import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class _BatchRecordingRemote extends MockRemoteAdapter<TestEntity> {
  _BatchRecordingRemote() : super(fromJson: TestEntity.fromJson);

  final batchSizes = <int>[];

  @override
  Future<void> createAll(List<TestEntity> entities) {
    batchSizes.add(entities.length);
    return super.createAll(entities);
  }
}

void main() {
  test('cancelSync interrupts the running cycle, keeps the rest queued, and later syncs run', () async {
    final online = MockConnectivityChecker();
    when(() => online.isConnected).thenAnswer((_) async => true);
    when(() => online.onStatusChange).thenAnswer((_) => const Stream.empty());
    final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson)..setProcessingDelay(const Duration(milliseconds: 40));
    final manager = DatumManager<TestEntity>(
      localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
      remoteAdapter: remote,
      connectivity: online,
      // One operation per batch, so there are gaps to cancel in.
      datumConfig: const DatumConfig<TestEntity>(enableLogging: false, remoteSyncBatchSize: 1),
    );
    await manager.initialize();
    addTearDown(manager.dispose);
    for (var i = 0; i < 8; i++) {
      await manager.push(item: TestEntity.create('c$i', 'u1', 'n'), userId: 'u1');
    }

    manager.cancelSync(); // nothing running: a no-op
    final running = manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));
    await manager.statusStream.firstWhere((s) => s.status == DatumSyncStatus.syncing);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    manager.cancelSync();
    final cancelled = await running;

    expect(cancelled.wasCancelled, isTrue);
    final left = await manager.getPendingCount('u1');
    expect(left, inExclusiveRange(0, 8), reason: 'some were sent, the rest stay queued');

    remote.setProcessingDelay(Duration.zero);
    final next = await manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));
    expect(next.wasCancelled, isFalse);
    expect(await manager.getPendingCount('u1'), 0);
  });

  test('overrideBatchSize replaces remoteSyncBatchSize for one cycle only', () async {
    final online = MockConnectivityChecker();
    when(() => online.isConnected).thenAnswer((_) async => true);
    when(() => online.onStatusChange).thenAnswer((_) => const Stream.empty());
    final remote = _BatchRecordingRemote();
    final manager = DatumManager<TestEntity>(
      localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
      remoteAdapter: remote,
      connectivity: online,
      datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    Future<void> pushSix(String prefix, DatumSyncOptions<TestEntity> options) async {
      for (var i = 0; i < 6; i++) {
        await manager.push(item: TestEntity.create('$prefix$i', 'u1', 'n'), userId: 'u1');
      }
      remote.batchSizes.clear();
      await manager.synchronize('u1', options: options);
      expect(await manager.getPendingCount('u1'), 0);
    }

    await pushSix('a', const DatumSyncOptions(direction: SyncDirection.pushOnly, overrideBatchSize: 2));
    expect(remote.batchSizes, [2, 2, 2]);

    await pushSix('b', const DatumSyncOptions(direction: SyncDirection.pushOnly));
    expect(remote.batchSizes, [6], reason: 'back to the configured batch size');
  });
}
