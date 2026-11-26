import 'dart:async';
import 'dart:developer' show Service;
import 'dart:isolate' show Isolate;

import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart' show VmService;
import 'package:vm_service/vm_service_io.dart';

import 'conformance_entity.dart';
import 'http_remote_adapter.dart';
import 'local_sync_server.dart';
import 'sync_stack_conformance.dart' show TestConnectivityChecker;

const _u1 = 'u1';

/// Forces full GCs and reads heap usage through this isolate's VM service
/// (started on demand). JIT only: AOT has no VM service.
class _Heap {
  _Heap(this._vm, this._isolateId);

  final VmService _vm;
  final String _isolateId;

  static Future<_Heap?> connect() async {
    var info = await Service.getInfo();
    if (info.serverWebSocketUri == null) {
      info = await Service.controlWebServer(enable: true, silenceOutput: true);
    }
    final uri = info.serverWebSocketUri;
    final isolateId = Service.getIsolateId(Isolate.current);
    if (uri == null || isolateId == null) return null;
    return _Heap(await vmServiceConnectUri(uri.toString()), isolateId);
  }

  /// Heap bytes in use right after a full garbage collection.
  Future<int> usedAfterGc() async {
    final profile = await _vm.getAllocationProfile(_isolateId, gc: true);
    return profile.memoryUsage!.heapUsage!;
  }

  Future<void> dispose() => _vm.dispose();
}

/// One manager over [local] and an HTTP remote on [server].
Future<DatumManager<ConformanceEntity>> _boot(LocalAdapter<ConformanceEntity> local, LocalSyncServer server, {DatumConfig<ConformanceEntity> config = const DatumConfig<ConformanceEntity>(enableLogging: false)}) async {
  final manager = DatumManager<ConformanceEntity>(
    localAdapter: local,
    remoteAdapter: HttpRemoteAdapter<ConformanceEntity>(baseUri: server.baseUri, fromMap: ConformanceEntity.fromMap),
    connectivity: TestConnectivityChecker(),
    datumConfig: config,
  );
  await manager.initialize();
  return manager;
}

ConformanceEntity _item(String id, {String name = 'v1', int version = 1}) => ConformanceEntity.make(id, userId: _u1, name: name, version: version, modifiedAt: DateTime.now());

Future<void> _pushAll(DatumManager<ConformanceEntity> m, Iterable<ConformanceEntity> items) async {
  for (final item in items) {
    await m.push(item: item);
  }
}

/// Runs the Datum **resource conformance suite** for one local adapter,
/// against a real HTTP remote ([LocalSyncServer]):
///
/// - **Leaks:** a disposed manager — after syncing, watching, auto-sync and
///   event subscriptions — is garbage-collectable; no timer stays alive.
/// - **Memory:** the heap stays flat across many edit/sync cycles.
/// - **Storage:** repeated edits of the same rows don't grow the row count,
///   the pending queue or the stored size.
/// - **Network:** an idle sync, a push and a pull each stay within a fixed
///   request budget (no per-item round-trips, no N+1 reads).
/// - **Responsiveness:** a large pull never blocks the event loop for long.
///
/// [createLocal] must return a fresh, initialized, EMPTY adapter each call.
void runResourceConformanceTests({required String name, required Future<LocalAdapter<ConformanceEntity>> Function() createLocal}) {
  group('$name resource conformance', () {
    final server = LocalSyncServer();
    setUpAll(server.start);
    tearDownAll(server.stop);
    setUp(() {
      server
        ..storage.clear()
        ..metadata.clear()
        ..requestLog.clear()
        ..requestUris.clear();
    });

    _leakTests(server, createLocal);
    _memoryAndStorageTests(server, createLocal);
    _networkAndLoopTests(server, createLocal);
  });
}

void _leakTests(LocalSyncServer server, Future<LocalAdapter<ConformanceEntity>> Function() createLocal) {
  test('a disposed manager is garbage-collectable after sync, watchers, auto-sync and events', () async {
    final heap = await _Heap.connect();
    if (heap == null) return markTestSkipped('no VM service (AOT)');
    addTearDown(heap.dispose);

    // Everything strong stays inside this closure's frame, which is gone
    // once it returns; only weak references escape.
    Future<List<WeakReference<Object>>> useAndDispose() async {
      final local = await createLocal();
      final manager = await _boot(local, server);
      await _pushAll(manager, [for (var i = 0; i < 50; i++) _item('e$i')]);
      final subscriptions = [manager.watchAll(userId: _u1).listen((_) {}), manager.watchById('e1', userId: _u1).listen((_) {}), manager.onDataChange.listen((_) {}), manager.onSyncProgress.listen((_) {})];
      expect((await manager.synchronize(_u1)).failedCount, 0);
      manager.startAutoSync(_u1, interval: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final pulled = await manager.read('e1', userId: _u1);
      for (final s in subscriptions) {
        await s.cancel();
      }
      await manager.dispose();
      // The adapter itself is caller-owned (harnesses may keep it), so check
      // what the manager owns: itself and the entities it handed out.
      return [WeakReference(manager), WeakReference(pulled!)];
    }

    final refs = await useAndDispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await heap.usedAfterGc();
    expect([for (final r in refs) r.target?.runtimeType], everyElement(isNull), reason: 'manager and entities must be collectable after dispose (nothing — e.g. an adapter listener — may still reference them)');
  });

  test('no timer outlives dispose, including an in-flight auto-sync schedule', () async {
    final timers = <Timer>[];
    await runZoned(
      () async {
        final manager = await _boot(await createLocal(), server);
        await _pushAll(manager, [for (var i = 0; i < 20; i++) _item('t$i')]);
        manager.startAutoSync(_u1, interval: const Duration(milliseconds: 10));
        await manager.synchronize(_u1);
        manager.watchAll(userId: _u1).listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await manager.dispose();
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, f) => parent.createTimer(zone, duration, f)..let(timers.add),
        createPeriodicTimer: (self, parent, zone, period, f) => parent.createPeriodicTimer(zone, period, f)..let(timers.add),
      ),
    );
    final logged = server.requestLog.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(timers, isNotEmpty, reason: 'the zone must have observed the engine timers');
    expect(timers.where((t) => t.isActive), isEmpty, reason: 'every timer is cancelled or fired after dispose');
    expect(server.requestLog.length, logged, reason: 'nothing hits the network after dispose: ${server.requestLog.skip(logged)}');
  });
}

void _memoryAndStorageTests(LocalSyncServer server, Future<LocalAdapter<ConformanceEntity>> Function() createLocal) {
  test('heap stays flat across 180 edit/sync cycles of 40 writes', () async {
    final heap = await _Heap.connect();
    if (heap == null) return markTestSkipped('no VM service (AOT)');
    addTearDown(heap.dispose);
    // A short echo-cache window so time-bounded caches can't mask a leak.
    final manager = await _boot(await createLocal(), server, config: const DatumConfig<ConformanceEntity>(enableLogging: false, changeCacheDuration: Duration(milliseconds: 50)));
    addTearDown(manager.dispose);
    final watch = manager.watchAll(userId: _u1).listen((_) {});
    addTearDown(watch.cancel);

    var version = 1;
    Future<void> cycles(int n) async {
      for (var c = 0; c < n; c++) {
        version++;
        await _pushAll(manager, [for (var i = 0; i < 40; i++) _item('m$i', name: 'v$version', version: version)]);
        expect((await manager.synchronize(_u1)).failedCount, 0);
        server // the harness's own request log is not the engine's memory
          ..requestLog.clear()
          ..requestUris.clear();
      }
    }

    await cycles(60); // warm-up: caches, JIT-compiled code, first allocations
    final h0 = await heap.usedAfterGc();
    await cycles(60);
    final h1 = await heap.usedAfterGc();
    await cycles(60);
    final h2 = await heap.usedAfterGc();
    final (first, second) = ((h1 - h0) ~/ 1024, (h2 - h1) ~/ 1024);

    // A leak grows the same every window (2,400 writes each); the JIT's own
    // code metadata tapers off. ~0.2 KB retained per write crosses this.
    expect(second, lessThan(512), reason: 'heap grew $first KB, then $second KB per 60 cycles');
  });

  test('repeated edits of the same rows do not grow rows, queue or stored size', () async {
    final manager = await _boot(await createLocal(), server);
    addTearDown(manager.dispose);
    final ids = [for (var i = 0; i < 25; i++) 's$i'];

    Future<(int, int, int)> footprint() async => ((await manager.readAll(userId: _u1, includeDeleted: true)).length, await manager.getPendingCount(_u1), await manager.getStorageSize(userId: _u1));

    await _pushAll(manager, [for (final id in ids) _item(id)]);
    await manager.synchronize(_u1);
    final (rows0, pending0, size0) = await footprint();
    expect((rows0, pending0), (25, 0));

    for (var v = 2; v <= 20; v++) {
      await _pushAll(manager, [for (final id in ids) _item(id, name: 'v$v', version: v)]);
      await manager.synchronize(_u1);
    }
    final (rows, pending, size) = await footprint();

    expect(rows, rows0, reason: 'updates must not add rows');
    expect(pending, 0, reason: 'every synced op is dequeued');
    expect(server.storage[_u1], hasLength(25));
    if (size0 > 0) {
      expect(size, lessThan(size0 * 2), reason: 'stored size tracks live data, not edit history ($size0 → $size bytes)');
    }
  });
}

void _networkAndLoopTests(LocalSyncServer server, Future<LocalAdapter<ConformanceEntity>> Function() createLocal) {
  test('request budget: push is O(items), pull reads in bulk, idle sync is cheap', () async {
    final writer = await _boot(await createLocal(), server);
    addTearDown(writer.dispose);
    await _pushAll(writer, [for (var i = 0; i < 100; i++) _item('n$i')]);

    server.requestLog.clear();
    expect((await writer.synchronize(_u1)).failedCount, 0);
    final pushWrites = server.requestLog.where((r) => !r.startsWith('GET')).length;
    expect(pushWrites, inInclusiveRange(1, 100 + 3), reason: 'at most one write per item plus metadata');

    server.requestLog.clear();
    await writer.synchronize(_u1);
    expect(server.requestLog.length, lessThanOrEqualTo(4), reason: 'an idle sync only checks metadata: ${server.requestLog}');

    final reader = await _boot(await createLocal(), server);
    addTearDown(reader.dispose);
    server.requestLog.clear();
    expect((await reader.synchronize(_u1)).failedCount, 0);
    expect(await reader.readAll(userId: _u1), hasLength(100));
    expect(server.requestLog.where((r) => r.startsWith('GET /entities/')), isEmpty, reason: 'pull must not read entities one by one');
    expect(server.requestLog.length, lessThanOrEqualTo(6), reason: 'pull: ${server.requestLog}');
  });

  test('a 2,000-row pull never blocks the event loop for long', () async {
    for (var i = 0; i < 2000; i++) {
      server.seed(_u1, _item('p$i').toDatumMap(target: MapTarget.remote));
    }
    final manager = await _boot(await createLocal(), server);
    addTearDown(manager.dispose);

    final watch = Stopwatch()..start();
    var last = Duration.zero;
    var maxGap = Duration.zero;
    final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final gap = watch.elapsed - last;
      if (gap > maxGap) maxGap = gap;
      last = watch.elapsed;
    });
    expect((await manager.synchronize(_u1)).failedCount, 0);
    ticker.cancel();

    expect(await manager.readAll(userId: _u1), hasLength(2000));
    // ponytail: generous bound for noisy CI; catches multi-second blocking
    // (per-row sync I/O, giant synchronous loops), not frame-level jank.
    expect(maxGap, lessThan(const Duration(milliseconds: 500)), reason: 'longest event-loop stall: ${maxGap.inMilliseconds} ms');
  });
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
