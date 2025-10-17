import 'package:datum/source/core/engine/queue_manager.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';

void main() {
  group('QueueManager', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late DatumLogger logger;
    late QueueManager<TestEntity> queueManager;

    setUp(() {
      localAdapter = MockLocalAdapter<TestEntity>();
      logger = DatumLogger(enabled: false); // Disable logs for tests
      queueManager = QueueManager<TestEntity>(
        localAdapter: localAdapter,
        logger: logger,
      );
    });

    tearDown(() async {
      await localAdapter.clear();
    });

    test('getPending retrieves operations from the local adapter', () async {
      final operation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user1',
        type: DatumOperationType.create,
        entityId: 'entity1',
        timestamp: DateTime.now(),
        data: TestEntity(
          id: 'entity1',
          userId: 'user1',
          name: 'Test',
          value: 42,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        ),
      );

      await localAdapter.addPendingOperation('user1', operation);

      final pending = await queueManager.getPending('user1');
      expect(pending, hasLength(1));
      expect(pending.first.id, 'op1');
    });

    test('enqueue adds an operation to the local adapter', () async {
      final operation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user1',
        type: DatumOperationType.create,
        entityId: 'entity1',
        timestamp: DateTime.now(),
        data: TestEntity(
          id: 'entity1',
          userId: 'user1',
          name: 'Test',
          value: 42,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        ),
      );

      await queueManager.enqueue(operation);

      final pending = await localAdapter.getPendingOperations('user1');
      expect(pending, hasLength(1));
      expect(pending.first.id, 'op1');
    });

    test('dequeue removes an operation from the local adapter', () async {
      final operation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user1',
        type: DatumOperationType.create,
        entityId: 'entity1',
        timestamp: DateTime.now(),
      );

      await queueManager.enqueue(operation);

      expect(await queueManager.getPending('user1'), hasLength(1));

      await queueManager.dequeue('op1');

      expect(await queueManager.getPending('user1'), isEmpty);
    });

    test('clears user queue', () async {
      await queueManager.enqueue(
        DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user1',
          type: DatumOperationType.create,
          entityId: 'entity1',
          timestamp: DateTime.now(),
        ),
      );

      await queueManager.clear('user1');

      expect(await queueManager.getPending('user1'), isEmpty);
    });

    test('handles multiple users independently', () async {
      await queueManager.enqueue(
        DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user1',
          type: DatumOperationType.create,
          entityId: 'entity1',
          timestamp: DateTime.now(),
        ),
      );

      await queueManager.enqueue(
        DatumSyncOperation<TestEntity>(
          id: 'op2',
          userId: 'user2',
          type: DatumOperationType.update,
          entityId: 'entity2',
          timestamp: DateTime.now(),
        ),
      );

      final pending1 = await queueManager.getPending('user1');
      final pending2 = await queueManager.getPending('user2');

      expect(pending1, hasLength(1));
      expect(pending2, hasLength(1));
      expect(pending1.first.id, 'op1');
      expect(pending2.first.id, 'op2');
    });

    test('update replaces an existing operation in the queue', () async {
      final initialOperation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user1',
        type: DatumOperationType.create,
        entityId: 'entity1',
        timestamp: DateTime.now(),
        retryCount: 0,
      );
      await queueManager.enqueue(initialOperation);

      final updatedOperation = initialOperation.copyWith(retryCount: 1);
      await queueManager.update(updatedOperation);

      final pending = await queueManager.getPending('user1');
      expect(pending, hasLength(1));
      expect(pending.first.id, 'op1');
      expect(pending.first.retryCount, 1);
    });

    test('getPendingCount returns the correct number of operations', () async {
      await queueManager.enqueue(
        DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user1',
          type: DatumOperationType.create,
          entityId: 'e1',
          timestamp: DateTime.now(),
        ),
      );
      await queueManager.enqueue(
        DatumSyncOperation<TestEntity>(
          id: 'op2',
          userId: 'user1',
          type: DatumOperationType.create,
          entityId: 'e2',
          timestamp: DateTime.now(),
        ),
      );

      final count = await queueManager.getPendingCount('user1');
      expect(count, 2);
    });

    test('getPending returns an empty list for a user with no operations',
        () async {
      final pending = await queueManager.getPending('non_existent_user');
      expect(pending, isEmpty);
    });

    test('getPendingCount returns 0 for a user with no operations', () async {
      final count = await queueManager.getPendingCount('non_existent_user');
      expect(count, 0);
    });

    test('dequeueing a non-existent operation does not throw an error',
        () async {
      await expectLater(queueManager.dequeue('non_existent_op'), completes);
    });
  });
}
