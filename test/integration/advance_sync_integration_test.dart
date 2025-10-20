import 'dart:async';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/datum.dart';

import '../mocks/test_entity.dart';

// Use proper mocktail mocks for adapters
class MockLocalAdapter<T extends DatumEntity> extends Mock implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements DatumConnectivityChecker {}

void main() {
  group('Advanced Sync Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

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
        DatumSyncOperation<TestEntity>(
          id: 'fallback',
          userId: 'fallback',
          entityId: 'fallback',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        const DatumSyncMetadata(userId: 'fb', dataHash: 'fallback'),
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
    });

    setUp(() async {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig(),
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('cancels sync operation via strategy', () async {
      // Arrange
      // Re-initialize manager with a strategy that can be cancelled.
      await manager.dispose();
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        // Use a sequential strategy to demonstrate cancellation.
        datumConfig: const DatumConfig(
          syncExecutionStrategy: SequentialStrategy(),
        ),
      );

      await manager.initialize();

      // Stub getPendingOperations for the sync call
      when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
        (_) async => List.generate(
          10,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: 'user1',
            entityId: 'entity$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('entity$i', 'user1', 'Test Item $i'),
          ),
        ),
      );

      // Mock remote to be slow, giving us time to "cancel".
      // In the new API, cancellation is handled by the sync engine checking
      // its status. We can simulate this by having the sync complete
      // before all items are processed.
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      // Act
      // Start the sync but don't wait for it.
      final syncFuture = manager.synchronize('user1');

      // Wait a short time, then "cancel" by disposing the manager,
      // which will stop the sync process.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await manager.dispose();

      // The sync should complete, but not all items will have been processed.
      final result = await syncFuture;

      // Assert
      expect(
        result.wasCancelled,
        isTrue,
        reason: 'Sync should be marked as cancelled.',
      );
      expect(
        result.isSuccess,
        isFalse,
        reason: 'A cancelled sync is not a successful one.',
      );
      expect(result.syncedCount, lessThan(10));
    });

    test('sync with scope performs a partial sync', () async {
      final remoteEntity1 = TestEntity.create(
        'remote1',
        'user1',
        'Recent Item',
      );
      final remoteEntity2 = remoteEntity1.copyWith(
        id: 'remote2',
        modifiedAt: DateTime.now().subtract(const Duration(days: 40)),
      );
      when(
        () => remoteAdapter.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((inv) {
        // Simulate the remote adapter filtering based on the scope's query.
        final scope = inv.namedArguments[#scope] as DatumSyncScope?;
        final hasMinDateFilter = scope?.query.filters.any(
              (f) => (f as Filter).field == 'minModifiedDate',
            ) ??
            false;
        if (hasMinDateFilter) {
          return Future.value([remoteEntity1]);
        }
        return Future.value([remoteEntity1, remoteEntity2]);
      });
      final localOnlyEntity = TestEntity.create(
        'local-only',
        'user1',
        'Local Only Item',
      );
      // Stub the readAll for the final assertion
      when(
        () => localAdapter.readAll(userId: 'user1'),
      ).thenAnswer((_) async => [localOnlyEntity, remoteEntity1]);
      await manager.push(item: localOnlyEntity, userId: 'user1');

      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      // Create a query and pass it to the scope.
      final query = DatumQuery(
        filters: [
          Filter('minModifiedDate', FilterOperator.greaterThan, thirtyDaysAgo),
        ],
      );
      final scope = DatumSyncScope(query: query);
      await manager.synchronize('user1', scope: scope);

      final localItems = await manager.readAll(userId: 'user1');
      expect(localItems, hasLength(2));

      expect(localItems.any((item) => item.id == 'remote1'), isTrue);
      expect(localItems.any((item) => item.id == 'remote2'), isFalse);
      expect(localItems.any((item) => item.id == 'local-only'), isTrue);
    });

    test('per-operation retry logic increments retry count on failure', () async {
      // Re-initialize manager with retries enabled for this specific test.
      await manager.dispose();
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: LastWriteWinsResolver<TestEntity>(),
        connectivity: connectivityChecker,
        datumConfig: DatumConfig(
          errorRecoveryStrategy: DatumErrorRecoveryStrategy(
            maxRetries: 1,
            shouldRetry: (e) async => e is NetworkException,
          ),
        ),
      );

      await manager.initialize();

      final successEntity = TestEntity.create(
        'success1',
        'user1',
        'Will Succeed',
      );
      final failEntity = TestEntity.create('fail1', 'user1', 'Will Fail');

      // Make the remote adapter throw a retryable network exception for 'fail1'
      final retryableException = NetworkException(
        'Simulated network failure',
        isRetryable: true,
      );
      // Stub the successful create call
      when(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == 'success1')),
        ),
      ).thenAnswer((_) async {});
      // Stub the failing create call
      when(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == 'fail1')),
        ),
      ).thenThrow(retryableException);

      final successOp = DatumSyncOperation(
        id: 'op-s',
        userId: 'user1',
        entityId: 'success1',
        type: DatumOperationType.create,
        timestamp: DateTime.now(),
        data: successEntity,
      );
      final failOp = DatumSyncOperation(
        id: 'op-f',
        userId: 'user1',
        entityId: 'fail1',
        type: DatumOperationType.create,
        timestamp: DateTime.now(),
        data: failEntity,
        retryCount: 0,
      );

      final pendingOps = [successOp, failOp];

      // Stub getPendingOperations for the first sync call
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => pendingOps);
      // Stub the update call for the failed operation
      when(
        () => localAdapter.addPendingOperation(
          'user1',
          any(
            that: predicate(
              (op) => (op as DatumSyncOperation).entityId == 'fail1',
            ),
          ),
        ), // This is the 'update' call for the retry.
      ).thenAnswer((invocation) async {
        final updatedOp = invocation.positionalArguments[1] as DatumSyncOperation<TestEntity>;
        final index = pendingOps.indexWhere((op) => op.id == updatedOp.id);
        if (index != -1) {
          pendingOps[index] = updatedOp;
        }
      });
      when(() => localAdapter.removePendingOperation('op-s')).thenAnswer(
        (_) async => pendingOps.removeWhere((op) => op.id == 'op-s'),
      );
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);

      // Act 1: First sync attempt
      final result = await manager.synchronize('user1');

      // Assert 1
      expect(result.syncedCount, 1);
      expect(result.failedCount, 0, reason: 'Retryable ops are not failed');

      // The failed operation should still be in the queue with an incremented retry count.
      expect(result.pendingOperations, hasLength(1));
      expect(result.pendingOperations.first.entityId, 'fail1');
      expect(result.pendingOperations.first.retryCount, 1);

      // Debugging assertion to verify pendingOps after first sync
      expect(
        pendingOps.map((op) => op.id).toSet().length,
        pendingOps.length,
        reason: 'No duplicate operations should exist in pendingOps after first sync',
      );

      // Act 2: Second sync attempt. This time, the remote call will succeed.
      // We need to reset the mock to not throw the exception anymore.
      when(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == 'fail1')),
        ),
      ).thenAnswer((_) async {});
      // Re-stub for the second sync to only return the failing operation.
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => pendingOps);
      when(() => localAdapter.removePendingOperation('op-f')).thenAnswer(
        (_) async => pendingOps.removeWhere((op) => op.id == 'op-f'),
      );
      final secondResult = await manager.synchronize('user1');

      // Assert 2
      expect(secondResult.syncedCount, 1);
      expect(secondResult.pendingOperations, isEmpty);

      // Debugging assertion to verify pendingOps after second sync
      expect(
        pendingOps.map((op) => op.id).toSet().length,
        pendingOps.length,
        reason: 'No duplicate operations should exist in pendingOps after second sync',
      );

      // Verify both items are now on the remote.
      verify(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == 'success1')),
        ),
      ).called(1);
      verify(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == 'fail1')),
        ),
      ).called(2);
    });
  });
}

/// Helper function to apply all default stubs to a set of mocks.
void _stubDefaultBehaviors(
  MockLocalAdapter<TestEntity> localAdapter,
  MockRemoteAdapter<TestEntity> remoteAdapter,
  MockConnectivityChecker connectivityChecker,
) {
  // Connectivity
  when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

  // Initialization
  when(() => localAdapter.initialize()).thenAnswer((_) async {});
  when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
  when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
  when(
    () => localAdapter.changeStream(),
  ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
  when(
    () => remoteAdapter.changeStream,
  ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());

  // Disposal
  when(() => localAdapter.dispose()).thenAnswer((_) async {});
  when(() => remoteAdapter.dispose()).thenAnswer((_) async {});

  // Core Operations
  when(() => localAdapter.create(any())).thenAnswer((_) async {});
  when(
    () => localAdapter.addPendingOperation(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => localAdapter.read(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => {});
  when(
    () => localAdapter.readAll(userId: any(named: 'userId')),
  ).thenAnswer((_) async => []);
  when(
    () => remoteAdapter.readAll(
      userId: any(named: 'userId'),
      scope: any(named: 'scope'),
    ),
  ).thenAnswer((_) async => []);

  // Sync-related Operations
  when(
    () => localAdapter.getPendingOperations(any()),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.removePendingOperation(any()),
  ).thenAnswer((_) async {});

  // Metadata
  when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
  when(
    () => remoteAdapter.getSyncMetadata(any()),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => remoteAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});
  // Add missing stub for getLastSyncResult
  when(
    () => localAdapter.getLastSyncResult(any()),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.saveLastSyncResult(any(), any()),
  ).thenAnswer((_) async {});
}
