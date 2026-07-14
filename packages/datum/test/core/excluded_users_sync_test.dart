import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

DatumManager<TestEntity> _manager(MockLocalAdapter<TestEntity> local, MockRemoteAdapter<TestEntity> remote, DatumConfig<TestEntity> config) {
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

void main() {
  test('#32 synchronize() skips an excluded (system) user', () async {
    final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final manager = _manager(
      local,
      remote,
      const DatumConfig<TestEntity>(excludedSyncUserIds: {'automatic-system'}),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    // The system user has local data that must never reach the remote.
    local.addLocalItem('automatic-system', TestEntity.create('sys1', 'automatic-system', 'system'));

    final result = await manager.synchronize('automatic-system');
    expect(result.wasSkipped, isTrue);

    // A normal user syncs fine.
    local.addLocalItem('u1', TestEntity.create('e1', 'u1', 'real'));
    final ok = await manager.synchronize('u1');
    expect(ok.wasSkipped, isFalse);
  });

  test('#32 startAutoSync ignores an excluded user', () async {
    final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final manager = _manager(
      local,
      remote,
      const DatumConfig<TestEntity>(
        excludedSyncUserIds: {'automatic-system'},
        autoSyncInterval: Duration(minutes: 15),
      ),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    manager.startAutoSync('automatic-system');
    expect(await manager.getNextSyncTime(), isNull, reason: 'excluded user not scheduled');

    manager.startAutoSync('u1');
    expect(await manager.getNextSyncTime(), isNotNull, reason: 'normal user scheduled');
  });
}
