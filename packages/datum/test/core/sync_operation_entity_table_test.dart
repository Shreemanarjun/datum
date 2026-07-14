import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  group('DatumSyncOperation.entityTable (#16)', () {
    test('round-trips through toMap/fromMap', () {
      final op = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'u1',
        entityId: 'e1',
        entityTable: 'TestEntity',
        type: DatumOperationType.create,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final restored = DatumSyncOperation<TestEntity>.fromMap(op.toMap(), TestEntity.fromJson);
      expect(restored.entityTable, 'TestEntity');
      expect(restored, op);
    });

    test('is backward compatible with maps that lack the field', () {
      final legacy = {
        'id': 'op1',
        'userId': 'u1',
        'entityId': 'e1',
        'type': 'create',
        'timestamp': 1700000000000,
        'retryCount': 0,
        'sizeInBytes': 0,
      };
      final op = DatumSyncOperation<TestEntity>.fromMap(legacy, TestEntity.fromJson);
      expect(op.entityTable, isNull);
    });

    test('manager stamps pending operations with the entity type name', () async {
      final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final connectivity = MockConnectivityChecker();
      when(() => connectivity.isConnected).thenAnswer((_) async => false); // offline: keep the op pending
      when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());

      final manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: connectivity,
        datumConfig: const DatumConfig<TestEntity>(),
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      await manager.push(item: TestEntity.create('e1', 'u1', 'A'), userId: 'u1');

      final pending = await manager.getPendingOperations('u1');
      expect(pending, isNotEmpty);
      expect(pending.first.entityTable, 'TestEntity');
    });
  });
}
