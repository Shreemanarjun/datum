import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

/// A resolver that accepts remote deletions (removes local when remote is gone),
/// otherwise last-write-wins.
class HonorRemoteDeletionResolver<T extends DatumEntityInterface> implements DatumConflictResolver<T> {
  @override
  String get name => 'HonorRemoteDeletion';

  @override
  FutureOr<DatumConflictResolution<T>> resolve({T? local, T? remote, required DatumConflictContext context}) {
    if (local != null && remote == null) {
      return DatumConflictResolution<T>.deleteLocal('remote deleted');
    }
    if (local == null && remote != null) return DatumConflictResolution.useRemote(remote);
    return DatumConflictResolution.useLocal(local as T);
  }
}

DatumManager<TestEntity> _manager({
  required MockLocalAdapter<TestEntity> local,
  required MockRemoteAdapter<TestEntity> remote,
  required DatumConfig<TestEntity> config,
}) {
  final connectivity = MockConnectivityChecker();
  when(() => connectivity.isConnected).thenAnswer((_) async => true);
  when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return DatumManager<TestEntity>(
    localAdapter: local,
    remoteAdapter: remote,
    connectivity: connectivity,
    datumConfig: config,
  );
}

TestEntity _e(String id) => TestEntity(
      id: id,
      userId: 'u1',
      name: 'name-$id',
      value: 0,
      modifiedAt: DateTime(2024),
      createdAt: DateTime(2024),
      version: 1,
    );

void main() {
  late MockLocalAdapter<TestEntity> local;
  late MockRemoteAdapter<TestEntity> remote;

  setUp(() {
    local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
  });

  test('remote deletion is detected and applied when opted in (#41)', () async {
    final manager = _manager(
      local: local,
      remote: remote,
      config: DatumConfig<TestEntity>(
        detectRemoteDeletions: true,
        defaultSyncDirection: SyncDirection.pullOnly,
        defaultConflictResolver: HonorRemoteDeletionResolver<TestEntity>(),
      ),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    // Local has e1 and e2; remote only has e1 (e2 was deleted remotely).
    local.addLocalItem('u1', _e('e1'));
    local.addLocalItem('u1', _e('e2'));
    remote.addRemoteItem('u1', _e('e1'));

    await manager.synchronize('u1');

    expect(await local.read('e1', userId: 'u1'), isNotNull, reason: 'e1 still on remote');
    expect(await local.read('e2', userId: 'u1'), isNull, reason: 'e2 deleted remotely → removed locally');
  });

  test('default last-write-wins keeps local on remote deletion (safe default)', () async {
    final manager = _manager(
      local: local,
      remote: remote,
      config: DatumConfig<TestEntity>(
        detectRemoteDeletions: true,
        defaultSyncDirection: SyncDirection.pullOnly,
        defaultConflictResolver: LastWriteWinsResolver<TestEntity>(),
      ),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    local.addLocalItem('u1', _e('e1'));
    local.addLocalItem('u1', _e('e2'));
    remote.addRemoteItem('u1', _e('e1'));

    await manager.synchronize('u1');

    expect(await local.read('e2', userId: 'u1'), isNotNull, reason: 'LWW keeps local');
  });

  test('detection is OFF by default — local kept', () async {
    final manager = _manager(
      local: local,
      remote: remote,
      config: DatumConfig<TestEntity>(
        defaultSyncDirection: SyncDirection.pullOnly,
        defaultConflictResolver: HonorRemoteDeletionResolver<TestEntity>(),
      ),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    local.addLocalItem('u1', _e('e1'));
    local.addLocalItem('u1', _e('e2'));
    remote.addRemoteItem('u1', _e('e1'));

    await manager.synchronize('u1');

    expect(await local.read('e2', userId: 'u1'), isNotNull, reason: 'no detection → kept');
  });

  test('entities with pending local operations are not treated as remote deletions', () async {
    final manager = _manager(
      local: local,
      remote: remote,
      config: DatumConfig<TestEntity>(
        detectRemoteDeletions: true,
        defaultSyncDirection: SyncDirection.pullOnly,
        defaultConflictResolver: HonorRemoteDeletionResolver<TestEntity>(),
      ),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    local.addLocalItem('u1', _e('e2'));
    // e2 has an unsynced local create pending → must be preserved.
    await local.addPendingOperation(
      'u1',
      DatumSyncOperation<TestEntity>(
        id: 'op-e2',
        userId: 'u1',
        entityId: 'e2',
        type: DatumOperationType.create,
        data: _e('e2'),
        timestamp: DateTime(2024),
      ),
    );

    await manager.synchronize('u1');

    expect(await local.read('e2', userId: 'u1'), isNotNull, reason: 'pending local op preserved');
  });
}
