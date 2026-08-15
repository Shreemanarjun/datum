import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/test_entity.dart';

// Mock classes
class MockLocalAdapter<T extends DatumEntityInterface> extends Mock implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements DatumConnectivityChecker {}

/// A custom logger for tests that omits stack traces for cleaner output.
class TestLogger extends DatumLogger {
  TestLogger() : super(enabled: true);

  @override
  void error(String message, [StackTrace? stackTrace]) {
    super.error(message); // Call the base method without the stack trace.
  }
}

void main() {
  group('Batch Operations Edge Cases', () {
    late DatumManager<TestEntity> manager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late TestLogger logger;

    const userId = 'test-user';

    setUpAll(() {
      registerFallbackValue(
        TestEntity(
          id: 'fallback',
          userId: 'fallback',
          name: 'fallback',
          value: 0,
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
          version: 0,
        ),
      );
      registerFallbackValue(
        const DatumSyncMetadata(userId: 'fallback', dataHash: 'fallback'),
      );
      registerFallbackValue(
        const DatumSyncResult<TestEntity>(
          userId: 'fallback-user',
          duration: Duration.zero,
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        ),
      );
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fallback-op',
          userId: 'fallback-user',
          entityId: 'fallback-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
    });

    setUp(() async {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();
      logger = TestLogger();

      // Default stubs
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);
      when(() => localAdapter.changeStream()).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(() => remoteAdapter.changeStream).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => localAdapter.removePendingOperation(any())).thenAnswer((_) async {});
      when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {});
      when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => []);
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) => Future.value(null));
      when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) => Future.value(null));

      // Stub batch operations
      when(() => remoteAdapter.createAll(any())).thenAnswer((_) async {});
      when(() => remoteAdapter.updateAll(any())).thenAnswer(
        (inv) async => inv.positionalArguments.first as List<TestEntity>,
      );
      when(() => remoteAdapter.deleteAll(any(), userId: any(named: 'userId'))).thenAnswer((_) async {});

      // Stub individual operations (for single-item batches)
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
      when(() => remoteAdapter.update(any())).thenAnswer(
        (inv) async => inv.positionalArguments.first as TestEntity,
      );
      when(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async => TestEntity.create(
          inv.namedArguments[#id] as String,
          inv.namedArguments[#userId] as String,
          'Patched',
        ),
      );
      when(() => remoteAdapter.delete(any(), userId: any(named: 'userId'))).thenAnswer((_) async => true);
    });

    tearDown(() async {
      await manager.dispose();
    });

    group('Batch Size Configuration', () {
      test('batches operations when count equals batch size', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 5),
        );
        await manager.initialize();

        final operations = List.generate(
          5,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 5);
        expect(result.failedCount, 0);
        // Should call createAll once with all 5 entities
        verify(() => remoteAdapter.createAll(any())).called(1);
        verifyNever(() => remoteAdapter.create(any()));
      });

      test('creates multiple batches when operations exceed batch size', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 3),
        );
        await manager.initialize();

        final operations = List.generate(
          7,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 7);
        expect(result.failedCount, 0);
        // Should call createAll 2 times: [3 items], [3 items]
        // And create 1 time for the last single item
        verify(() => remoteAdapter.createAll(any())).called(2);
        verify(() => remoteAdapter.create(any())).called(1);
      });

      test('handles single operation as individual call when batch size is 1', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 1),
        );
        await manager.initialize();

        final operations = [
          DatumSyncOperation<TestEntity>(
            id: 'op1',
            userId: userId,
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e1', userId, 'Item 1'),
          ),
        ];

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);
        when(() => remoteAdapter.create(any())).thenAnswer((_) async {});

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 1);
        // With batch size 1, should call individual create, not createAll
        verify(() => remoteAdapter.create(any())).called(1);
        verifyNever(() => remoteAdapter.createAll(any()));
      });
    });

    group('Mixed Operation Types', () {
      test('groups operations by type into separate batches', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 10),
        );
        await manager.initialize();

        final operations = [
          // 3 creates
          DatumSyncOperation<TestEntity>(
            id: 'op1',
            userId: userId,
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e1', userId, 'Item 1'),
          ),
          DatumSyncOperation<TestEntity>(
            id: 'op2',
            userId: userId,
            entityId: 'e2',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e2', userId, 'Item 2'),
          ),
          DatumSyncOperation<TestEntity>(
            id: 'op3',
            userId: userId,
            entityId: 'e3',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e3', userId, 'Item 3'),
          ),
          // 2 updates
          DatumSyncOperation<TestEntity>(
            id: 'op4',
            userId: userId,
            entityId: 'e4',
            type: DatumOperationType.update,
            timestamp: DateTime.now(),
            data: TestEntity.create('e4', userId, 'Item 4'),
            delta: const {'name': 'Updated'},
          ),
          DatumSyncOperation<TestEntity>(
            id: 'op5',
            userId: userId,
            entityId: 'e5',
            type: DatumOperationType.update,
            timestamp: DateTime.now(),
            data: TestEntity.create('e5', userId, 'Item 5'),
            delta: const {'name': 'Updated'},
          ),
          // 1 delete
          DatumSyncOperation<TestEntity>(
            id: 'op6',
            userId: userId,
            entityId: 'e6',
            type: DatumOperationType.delete,
            timestamp: DateTime.now(),
          ),
        ];

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 6);
        expect(result.failedCount, 0);
        // Should call createAll for creates, patch for updates (with delta), delete for deletes
        verify(() => remoteAdapter.createAll(any())).called(1);
        verify(
          () => remoteAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        ).called(2); // 2 patch calls for the 2 update operations
        verify(() => remoteAdapter.delete(any(), userId: userId)).called(1);
      });

      test('handles alternating operation types correctly', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 5),
        );
        await manager.initialize();

        final operations = [
          DatumSyncOperation<TestEntity>(
            id: 'op1',
            userId: userId,
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e1', userId, 'Item 1'),
          ),
          DatumSyncOperation<TestEntity>(
            id: 'op2',
            userId: userId,
            entityId: 'e2',
            type: DatumOperationType.update,
            timestamp: DateTime.now(),
            data: TestEntity.create('e2', userId, 'Item 2'),
            delta: const {'name': 'Updated'},
          ),
          DatumSyncOperation<TestEntity>(
            id: 'op3',
            userId: userId,
            entityId: 'e3',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e3', userId, 'Item 3'),
          ),
          DatumSyncOperation<TestEntity>(
            id: 'op4',
            userId: userId,
            entityId: 'e4',
            type: DatumOperationType.delete,
            timestamp: DateTime.now(),
          ),
        ];

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 4);
        // Should create separate calls for each operation (alternating types)
        verify(() => remoteAdapter.create(any())).called(2); // op1, op3
        verify(
          () => remoteAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        ).called(1); // op2
        verify(() => remoteAdapter.delete(any(), userId: userId)).called(1); // op4
      });
    });

    group('Error Handling in Batches', () {
      test('handles partial batch failure correctly', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: DatumConfig(
            remoteSyncBatchSize: 5,
            errorRecoveryStrategy: DatumErrorRecoveryStrategy(
              maxRetries: 0,
              shouldRetry: (_) async => false,
            ),
          ),
        );
        await manager.initialize();

        final operations = List.generate(
          5,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);
        when(() => remoteAdapter.createAll(any())).thenThrow(const NetworkException(message: 'Batch failed'));

        // Act: the batch call fails, but the engine falls back to processing
        // each operation individually — none of the five siblings may be
        // discarded because of a batch-level rejection.
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 5);
        expect(result.failedCount, 0);
        verify(() => remoteAdapter.create(any())).called(5);
      });

      test('continues with next batch if one batch fails with failFast=false', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: DatumConfig(
            remoteSyncBatchSize: 2,
            syncExecutionStrategy: const ParallelStrategy(failFast: false),
            errorRecoveryStrategy: DatumErrorRecoveryStrategy(
              maxRetries: 0,
              shouldRetry: (_) async => false,
            ),
          ),
        );
        await manager.initialize();

        final operations = List.generate(
          6,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        var callCount = 0;
        when(() => remoteAdapter.createAll(any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 2) {
            // Fail the second batch
            throw const NetworkException(message: 'Second batch failed');
          }
        });

        // Act: the failing middle batch falls back to per-operation creates,
        // so every entity still reaches the remote.
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 6);
        expect(result.failedCount, 0);
        // All 3 batches attempted despite the middle failure...
        verify(() => remoteAdapter.createAll(any())).called(3);
        // ...and the failed batch's two operations were retried individually.
        verify(() => remoteAdapter.create(any())).called(2);
      });
    });

    group('Empty and Null Cases', () {
      test('handles empty operations list gracefully', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 10),
        );
        await manager.initialize();

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => []);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 0);
        expect(result.failedCount, 0);
        verifyNever(() => remoteAdapter.createAll(any()));
        verifyNever(() => remoteAdapter.updateAll(any()));
        verifyNever(() => remoteAdapter.deleteAll(any(), userId: any(named: 'userId')));
      });

      test('handles operations with null data for delete correctly', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 5),
        );
        await manager.initialize();

        final operations = List.generate(
          3,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.delete,
            timestamp: DateTime.now(),
            // data is null for delete operations
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 3);
        verify(() => remoteAdapter.deleteAll(any(), userId: userId)).called(1);
      });
    });

    group('Large Batch Scenarios', () {
      test('handles very large batch (100+ operations) efficiently', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 50),
        );
        await manager.initialize();

        final operations = List.generate(
          150,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 150);
        expect(result.failedCount, 0);
        // Should create 3 batches: [50], [50], [50]
        verify(() => remoteAdapter.createAll(any())).called(3);
      });

      test('handles maximum batch size (1000 operations)', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 1000),
        );
        await manager.initialize();

        final operations = List.generate(
          1000,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 1000);
        expect(result.failedCount, 0);
        // Should create 1 large batch
        verify(() => remoteAdapter.createAll(any())).called(1);
      });
    });

    group('Progress Events with Batching', () {
      test('emits correct progress events for batched operations', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 5),
        );
        await manager.initialize();

        final operations = List.generate(
          10,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        final progressEvents = <DatumSyncProgressEvent>[];
        manager.onSyncProgress.listen(progressEvents.add);

        // Act
        await manager.synchronize(userId);

        // Assert
        // Should emit progress events for each batch
        expect(progressEvents.isNotEmpty, isTrue);
        expect(progressEvents.every((e) => e.userId == userId), isTrue);
      });
    });

    group('Batch Size Edge Cases', () {
      test('handles batch size of 0 (should default to no batching)', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 0),
        );
        await manager.initialize();

        final operations = List.generate(
          3,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);
        when(() => remoteAdapter.create(any())).thenAnswer((_) async {});

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 3);
        // With batch size 0, should fall back to individual operations
        verify(() => remoteAdapter.create(any())).called(3);
      });

      test('handles very large batch size (larger than operation count)', () async {
        // Arrange
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(remoteSyncBatchSize: 10000),
        );
        await manager.initialize();

        final operations = List.generate(
          5,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e$i', userId, 'Item $i'),
          ),
        );

        when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => operations);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.syncedCount, 5);
        // Should create one batch with all operations
        verify(() => remoteAdapter.createAll(any())).called(1);
      });
    });
  });
}
