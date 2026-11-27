import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

/// The engine's state is held in signals. These tests read it the way an app
/// would: in effects and computeds, next to the stream views of the same state.
// Scenarios: state.signals (packages/datum/doc/SYNC_SCENARIOS.md)
void main() {
  MockConnectivityChecker online() {
    final checker = MockConnectivityChecker();
    when(() => checker.isConnected).thenAnswer((_) async => true);
    when(() => checker.onStatusChange).thenAnswer((_) => const Stream.empty());
    return checker;
  }

  test('the status, health, metadata and next sync time of a manager are signals that follow the engine', () async {
    final manager = DatumManager<TestEntity>(
      localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
      remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
      connectivity: online(),
      datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
    );
    await manager.initialize();

    final statuses = <DatumSyncStatus>[];
    final healths = <DatumSyncHealth>[];
    // Derived state: recomputed only when what it reads changes.
    final busy = Computed(() => manager.statusSignal.value.status == DatumSyncStatus.syncing);
    final busyChanges = <bool>[];
    final stops = [
      effect(() => statuses.add(manager.statusSignal.value.status)),
      effect(() => healths.add(manager.healthSignal.value.status)),
      effect(() => busyChanges.add(busy.value)),
    ];
    expect(statuses, [DatumSyncStatus.idle], reason: 'an effect starts with the current value');
    expect(manager.metadataSignal.value, isNull, reason: 'nothing has synced yet');

    await manager.push(item: TestEntity.create('e1', 'u1', 'one'), userId: 'u1');
    await manager.synchronize('u1');
    expect(statuses, containsAllInOrder([DatumSyncStatus.idle, DatumSyncStatus.syncing, DatumSyncStatus.idle]));
    expect(busyChanges, [false, true, false], reason: 'the many status writes of one cycle are two changes of "busy"');
    expect(healths.toSet(), containsAll([DatumSyncHealth.healthy, DatumSyncHealth.syncing]));
    expect(manager.metadataSignal.value?.userId, 'u1');
    expect(manager.statusSignal.value.syncedCount, 1);

    // The stream getters are views of the same state.
    expect(await manager.statusStream.first, manager.statusSignal.value);
    expect(await manager.health.first, manager.healthSignal.value);

    manager.pauseSync();
    expect(manager.statusSignal.value.status, DatumSyncStatus.paused);
    expect(manager.currentStatus.status, DatumSyncStatus.paused);
    manager.resumeSync();
    expect(statuses.last, DatumSyncStatus.idle);

    expect(manager.nextSyncTimeSignal.value, isNull);
    manager.startAutoSync('u1');
    expect(manager.nextSyncTimeSignal.value, isNotNull);
    expect(await manager.watchNextSyncTime.first, manager.nextSyncTimeSignal.value);
    manager.stopAutoSync(userId: 'u1');
    expect(manager.nextSyncTimeSignal.value, isNull);

    // Calling into the manager from an effect does not subscribe that effect
    // to the engine's state behind its back: only signals it reads itself.
    var runs = 0;
    stops.add(effect(() {
      runs++;
      manager.currentStatus;
      manager.autoSyncUserIds;
    }));
    manager.pauseSync();
    manager.resumeSync();
    expect(runs, 1);

    // Disposing the manager disposes its state; the stream views end.
    final ended = manager.statusStream.toList();
    for (final stop in stops) {
      stop();
    }
    await manager.dispose();
    expect(manager.statusSignal.disposed, isTrue);
    expect((await ended).last.status, DatumSyncStatus.idle);
  });

  test('Datum exposes its metrics, the statuses of its users and the health of every manager as signals', () async {
    Datum.resetForTesting();
    final datum = (await Datum.initialize(
      config: const DatumConfig(enableLogging: false, autoStartSync: false),
      connectivityChecker: online(),
      registrations: [
        DatumRegistration<TestEntity>(
          localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
          remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        ),
      ],
    ))
        .fold((error, _) => throw error, (datum) => datum);
    addTearDown(() async {
      await datum.dispose();
      Datum.resetForTesting();
    });

    expect(datum.healthsSignal.value.keys, [TestEntity]);
    expect(datum.healthsSignal.value[TestEntity]?.status, DatumSyncHealth.healthy);
    expect(datum.statusesSignal.value, isEmpty);
    final syncs = <int>[];
    final stop = effect(() => syncs.add(datum.metricsSignal.value.totalSyncOperations));
    addTearDown(stop);

    await Datum.manager<TestEntity>().push(item: TestEntity.create('e1', 'u1', 'one'), userId: 'u1');
    await datum.synchronize('u1');
    await Future<void>.delayed(Duration.zero);

    expect(syncs.last, greaterThan(0));
    expect(datum.currentMetrics, datum.metricsSignal.value);
    expect(datum.statusesSignal.value['u1']?.status, DatumSyncStatus.completed);
    expect(await datum.statusForUser('u1').first, datum.statusesSignal.value['u1']);
    expect(await datum.allHealths.first, datum.healthsSignal.value);
  });
}
