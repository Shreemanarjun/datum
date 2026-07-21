@TestOn('vm')
library;

import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../harness/http_remote_adapter.dart';
import '../harness/local_sync_server.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// ===========================================================================
// Production-stability checks against the real local HTTP server:
//  - multi-subscriber reactive streams staying consistent under live sync
//  - exact event delivery (no duplication/multiplication across subscribers)
//  - resource hygiene: timer leaks, listener accumulation across cycles,
//    cache boundedness, dispose closing streams and halting all activity,
//    and manager lifecycle churn.
// ===========================================================================

MockConnectivityChecker _connected() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}

void main() {
  late LocalSyncServer server;
  late DatumManager<TestEntity> manager;

  Future<DatumManager<TestEntity>> newDevice({DatumConfig<TestEntity>? config}) async {
    final m = DatumManager<TestEntity>(
      localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
      remoteAdapter: HttpRemoteAdapter<TestEntity>(baseUri: server.baseUri, fromMap: TestEntity.fromJson),
      connectivity: _connected(),
      datumConfig: config ?? const DatumConfig<TestEntity>(),
    );
    await m.initialize();
    return m;
  }

  setUp(() async {
    server = LocalSyncServer();
    await server.start();
    manager = await newDevice();
  });

  tearDown(() async {
    await manager.dispose();
    await server.stop();
  });

  group('multi-stream correctness under live sync', () {
    test('several concurrent watchers all converge on the synced state', () async {
      final aEmissions = <List<TestEntity>>[];
      final bEmissions = <List<TestEntity>>[];
      final queryEmissions = <List<TestEntity>>[];

      final subA = manager.watchAll(userId: 'u1').listen(aEmissions.add);
      final subB = manager.watchAll(userId: 'u1').listen(bEmissions.add);
      final subQ = manager
          .watchQuery(
            (DatumQueryBuilder<TestEntity>()..where('value', isGreaterThanOrEqualTo: 2)).build(),
            userId: 'u1',
          )
          .listen(queryEmissions.add);
      addTearDown(() async {
        await subA.cancel();
        await subB.cancel();
        await subQ.cancel();
      });

      // Data arrives from the server via a pull.
      for (var i = 1; i <= 3; i++) {
        server.seed('u1', TestEntity(id: 'e$i', userId: 'u1', name: 'n$i', value: i, modifiedAt: DateTime(2030, i), createdAt: DateTime(2024), version: 1).toDatumMap(target: MapTarget.remote));
      }
      await manager.synchronize('u1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(aEmissions.last, hasLength(3), reason: 'watcher A must see all pulled entities');
      expect(bEmissions.last, hasLength(3), reason: 'watcher B must see the same state');
      expect(aEmissions.last.map((e) => e.id).toSet(), bEmissions.last.map((e) => e.id).toSet());
      expect(queryEmissions.last.map((e) => e.value).toSet(), {2, 3}, reason: 'filtered watcher applies its query to the synced state');
    });

    test('cancelling one subscriber mid-sync does not disturb the others', () async {
      server.latency = const Duration(milliseconds: 100);
      server.seed('u1', TestEntity.create('e1', 'u1', 'late-arrival').toDatumMap(target: MapTarget.remote));

      final keptEmissions = <List<TestEntity>>[];
      var cancelledEmissionsAfterCancel = 0;
      var cancelled = false;

      final kept = manager.watchAll(userId: 'u1').listen(keptEmissions.add);
      final toCancel = manager.watchAll(userId: 'u1').listen((_) {
        if (cancelled) cancelledEmissionsAfterCancel++;
      });
      addTearDown(kept.cancel);

      final sync = manager.synchronize('u1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await toCancel.cancel();
      cancelled = true;
      await sync;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(keptEmissions.last.single.name, 'late-arrival', reason: 'surviving watcher still receives the pull');
      expect(cancelledEmissionsAfterCancel, 0, reason: 'a cancelled listener must never fire again');
    });

    test('event stream delivers exactly one started+completed pair per cycle per subscriber', () async {
      var completedA = 0, completedB = 0, startedA = 0;
      final subA = manager.eventStream.listen((e) {
        if (e is DatumSyncCompletedEvent<TestEntity>) completedA++;
        if (e is DatumSyncStartedEvent<TestEntity>) startedA++;
      });
      final subB = manager.eventStream.listen((e) {
        if (e is DatumSyncCompletedEvent<TestEntity>) completedB++;
      });
      addTearDown(() async {
        await subA.cancel();
        await subB.cancel();
      });

      for (var i = 0; i < 3; i++) {
        // An edit each round keeps the cycle from being metadata-skipped.
        await manager.push(item: TestEntity.create('cycle-$i', 'u1', 'edit $i'), userId: 'u1');
        await manager.synchronize('u1');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(startedA, 3, reason: 'one started event per cycle');
      expect(completedA, 3, reason: 'one completed event per cycle — no duplication across cycles');
      expect(completedB, 3, reason: 'every subscriber sees the same single event per cycle');
    });

    test('two devices: a pull on A fires A watchers with B-authored data', () async {
      final deviceB = await newDevice();
      addTearDown(deviceB.dispose);

      final emissions = <List<TestEntity>>[];
      final sub = manager.watchAll(userId: 'u1').listen(emissions.add);
      addTearDown(sub.cancel);

      await deviceB.push(item: TestEntity.create('remote-born', 'u1', 'authored-on-b'), userId: 'u1');
      await deviceB.synchronize('u1');
      await manager.synchronize('u1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions.last.single.name, 'authored-on-b', reason: "A's reactive UI updates from B's change without manual refresh");
    });
  });

  group('resource hygiene / leak detection', () {
    test('auto-sync timers stop firing after stopAutoSync (no leaked timers)', () async {
      manager.startAutoSync('u1', interval: const Duration(milliseconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(server.requestLog, isNotEmpty, reason: 'auto-sync must have hit the server while running');

      manager.stopAutoSync();
      // Let any in-flight cycle drain, then observe silence.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      server.requestLog.clear();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.requestLog, isEmpty, reason: 'a leaked timer would keep hitting the server after stop');
    });

    test('dispose closes the event stream and halts all server activity', () async {
      final disposable = await newDevice();
      var eventStreamDone = false;
      final sub = disposable.eventStream.listen((_) {}, onDone: () => eventStreamDone = true);
      addTearDown(sub.cancel);

      disposable.startAutoSync('u1', interval: const Duration(milliseconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await disposable.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      server.requestLog.clear();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(server.requestLog, isEmpty, reason: 'dispose must cancel timers and in-flight scheduling');
      expect(eventStreamDone, isTrue, reason: 'dispose must close the event controller so subscribers can release');
    });

    test('repeated subscribe/cancel churn leaves no stale listeners firing', () async {
      // 50 rounds of subscribe→cancel on the same stream surface.
      var staleFires = 0;
      for (var i = 0; i < 50; i++) {
        var active = true;
        final sub = manager.watchAll(userId: 'u1').listen((_) {
          if (!active) staleFires++;
        });
        await Future<void>.delayed(const Duration(milliseconds: 1));
        active = false;
        await sub.cancel();
      }

      // Trigger fresh emissions; none of the 50 cancelled listeners may fire.
      server.seed('u1', TestEntity.create('after-churn', 'u1', 'x').toDatumMap(target: MapTarget.remote));
      await manager.synchronize('u1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(staleFires, 0);

      // And a fresh subscriber still works normally after the churn.
      final emissions = <List<TestEntity>>[];
      final sub = manager.watchAll(userId: 'u1').listen(emissions.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.map((e) => e.id), contains('after-churn'));
    });

    test('soak: 30 sync cycles — stable per-cycle wire cost, drained queue, bounded caches', () async {
      final perCycleRequests = <int>[];
      for (var i = 0; i < 30; i++) {
        final before = server.requestLog.length;
        await manager.push(item: TestEntity.create('soak-$i', 'u1', 'v$i'), userId: 'u1');
        await manager.synchronize('u1');
        perCycleRequests.add(server.requestLog.length - before);
      }

      expect(await manager.getPendingCount('u1'), 0, reason: 'queue must drain every cycle');
      expect(await manager.count(userId: 'u1'), 30);

      // Listener/loop accumulation shows up as per-cycle request growth: the
      // last cycles must not cost more wire calls than the first ones.
      final firstAvg = perCycleRequests.take(5).reduce((a, b) => a + b) / 5;
      final lastAvg = perCycleRequests.skip(25).reduce((a, b) => a + b) / 5;
      expect(lastAvg, lessThanOrEqualTo(firstAvg + 1), reason: 'per-cycle request count grew across the soak: $perCycleRequests');

      final stats = manager.getCacheStats();
      expect(stats['entity_existence'], lessThanOrEqualTo(500), reason: 'existence cache must respect its configured bound');
      expect(stats['queries'], 0, reason: 'query cache is off by default and must stay empty');
    });

    test('caches respect their configured bounds under pressure', () async {
      final bounded = await newDevice(
        config: const DatumConfig<TestEntity>(
          maxEntityExistenceCacheSize: 20,
          enableQueryCache: true,
          maxQueryCacheSize: 5,
        ),
      );
      addTearDown(bounded.dispose);

      for (var i = 0; i < 60; i++) {
        server.seed('u1', TestEntity.create('c-$i', 'u1', 'item $i').toDatumMap(target: MapTarget.remote));
      }
      await bounded.synchronize('u1');

      // 60 distinct id reads through a 20-slot existence cache.
      for (var i = 0; i < 60; i++) {
        await bounded.read('c-$i', userId: 'u1');
      }
      // 20 distinct queries through a 5-slot query cache.
      for (var i = 0; i < 20; i++) {
        await bounded.query(
          (DatumQueryBuilder<TestEntity>()..where('name', isEqualTo: 'item $i')).build(),
          userId: 'u1',
        );
      }

      final stats = bounded.getCacheStats();
      expect(stats['entity_existence'], lessThanOrEqualTo(20), reason: 'LRU must evict, not grow unboundedly');
      expect(stats['queries'], lessThanOrEqualTo(5));
    });

    test('manager lifecycle churn: 12 create→sync→dispose rounds stay clean', () async {
      for (var i = 0; i < 12; i++) {
        final m = await newDevice();
        await m.push(item: TestEntity.create('life-$i', 'u1', 'round $i'), userId: 'u1');
        final result = await m.synchronize('u1');
        expect(result.failedCount, 0, reason: 'round $i must sync cleanly');
        await m.dispose();
      }

      // Every round's entity landed exactly once; the shared server saw a
      // consistent, non-duplicated history.
      expect(server.storage['u1']?.keys.where((k) => k.startsWith('life-')).length, 12);
      final posts = server.requestLog.where((r) => r.startsWith('POST /entities')).length;
      expect(posts, 12, reason: 'no round may re-deliver a previous round\'s operation');
    });
  });
}
