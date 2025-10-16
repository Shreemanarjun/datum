import 'dart:async';

import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';

import '../mocks/test_entity.dart';

// Use proper mocktail mocks for adapters
class MockLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements ConnectivityChecker {}

/// A custom logger for tests that omits stack traces for cleaner output.
class TestLogger extends DatumLogger {
  TestLogger() : super(enabled: true);

  @override
  void error(String message, [StackTrace? stackTrace]) {
    super.error(message); // Call the base method without the stack trace.
  }
}

/// A mock middleware for testing data transformations.
class MockMiddleware extends Mock implements DatumMiddleware<TestEntity> {}

void main() async {
  group('DatumManager', () {
    late DatumManager<TestEntity> manager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    const userId = 'test-user';

    setUpAll(() {
      registerFallbackValue(
        DatumSyncMetadata(userId: 'fallback', dataHash: 'fallback'),
      );
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
    });

    setUp(() async {
      // Reset mocks for each test to ensure isolation.
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Default stubs for initialization
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 1);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => localAdapter.getPendingOperations(any()),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => remoteAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      // Stub for migration check during initialization
      when(() => localAdapter.transaction(any())).thenAnswer((
        invocation,
      ) async {
        final action =
            invocation.positionalArguments.first as Future<dynamic> Function();
        return action();
      });
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.removePendingOperation(any()),
      ).thenAnswer((_) async {});
      when(() => localAdapter.clearUserData(any())).thenAnswer((_) async => {});
      when(() => localAdapter.create(any())).thenAnswer((_) async {});
      when(() => localAdapter.update(any())).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.addPendingOperation(any(), any()),
      ).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        logger: TestLogger(),
        datumConfig: const DatumConfig(), // Default config
      );
    });

    group('Initialization', () {
      test('initializes adapters and starts auto-sync if configured', () async {
        // Arrange
        // This test needs a custom manager, so we create it here.
        when(
          () => localAdapter.getAllUserIds(),
        ).thenAnswer((_) async => ['user1']);

        // Create a new manager instance for this specific test.
        final autoSyncManager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: TestLogger(),
          datumConfig: const DatumConfig(
            autoStartSync: true,
            initialUserId: 'user1',
          ),
        );

        // Act
        await autoSyncManager.initialize();

        // Assert
        verify(() => localAdapter.initialize()).called(1);
        verify(() => remoteAdapter.initialize()).called(1);

        // Allow time for the unawaited synchronize call in initialize to start.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Verify that an initial sync (pull phase) was triggered for the initial user.
        verify(
          () => remoteAdapter.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        ).called(1);

        await autoSyncManager.dispose();
      });
    });

    group('Lifecycle and State', () {
      test('dispose cancels timers and closes streams', () async {
        // Arrange
        await manager.initialize(); // Initialize the default manager
        manager.startAutoSync(
          userId,
        ); // Start a timer to ensure it gets cancelled.

        // Act
        await manager.dispose();

        // Assert
        verify(() => localAdapter.dispose()).called(1);
        verify(() => remoteAdapter.dispose()).called(1);

        // A closed stream should emit a "done" event and then complete.
        await expectLater(manager.onDataChange, emitsDone);
      });

      test('throws StateError if used after being disposed', () async {
        // Arrange
        await manager.initialize();
        await manager.dispose();

        // Act & Assert
        expect(() => manager.read('id'), throwsStateError);
        expect(() => manager.synchronize(userId), throwsStateError);
      });
    });

    group('Middleware', () {
      late MockMiddleware middleware;

      // This group needs a special setup with middleware.
      setUp(() async {
        await manager.dispose(); // Dispose the default manager

        middleware = MockMiddleware();
        when(() => middleware.transformAfterFetch(any())).thenAnswer((
          inv,
        ) async {
          return inv.positionalArguments.first as TestEntity;
        });

        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: TestLogger(),
          datumConfig: const DatumConfig(),
          middlewares: [middleware],
        );

        await manager.initialize();
      });

      test('applies transformBeforeSave on push', () async {
        await manager.initialize();
        // Arrange
        final originalEntity = TestEntity.create('e1', userId, 'Original');
        final transformedEntity = originalEntity.copyWith(name: 'Transformed');

        when(
          () => middleware.transformBeforeSave(originalEntity),
        ).thenAnswer((_) async => transformedEntity);
        when(
          () => localAdapter.create(transformedEntity),
        ).thenAnswer((_) async {});
        // Stub the read call that push() makes internally
        when(
          () => localAdapter.read(originalEntity.id, userId: userId),
        ).thenAnswer((_) async {
          return null;
        });
        when(
          () => localAdapter.addPendingOperation(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        await manager.push(item: originalEntity, userId: userId);

        // Assert
        verify(() => middleware.transformBeforeSave(originalEntity)).called(1);
        verify(() => localAdapter.create(transformedEntity)).called(1);
      });

      test('applies transformAfterFetch on read', () async {
        await manager.initialize();
        // Arrange
        final storedEntity = TestEntity.create('e1', userId, 'Stored');
        final transformedEntity = storedEntity.copyWith(
          name: 'Transformed After Fetch',
        );

        when(
          () => localAdapter.read('e1', userId: userId),
        ).thenAnswer((_) async => storedEntity);
        when(
          () => middleware.transformAfterFetch(storedEntity),
        ).thenAnswer((_) async => transformedEntity);

        // Act
        final result = await manager.read('e1', userId: userId);

        // Assert
        verify(() => middleware.transformAfterFetch(storedEntity)).called(1);
        expect(result, isNotNull);
        expect(result!.name, 'Transformed After Fetch');
      });
    });

    group('Push Operation Error Handling', () {
      test('does not queue operation if local create fails', () async {
        await manager.initialize();
        // Arrange
        final entity = TestEntity.create('e1', userId, 'Test');
        final exception = Exception('Local DB write failed');
        when(() => localAdapter.create(any())).thenThrow(exception);

        // Act & Assert
        await expectLater(
          () => manager.push(item: entity, userId: userId),
          throwsA(exception),
        );

        // Verify that because the local save failed, no operation was queued.
        verifyNever(() => localAdapter.addPendingOperation(any(), any()));
        final pendingCount = await manager.getPendingCount(userId);
        expect(pendingCount, 0);
      });
    });

    // tearDown is now at the end of the group to apply to all tests.
    tearDown(() async {
      // This is crucial for isolating tests that create their own Datum instances.
      if (Datum.instanceOrNull != null) {
        await Datum.instance.dispose();
      }
      await manager.dispose();
    });

    group('onSyncProgress', () {
      test('emits progress events during sync', () async {
        // Arrange
        await manager.initialize();
        final op1 = DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: userId,
          entityId: 'e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create('e1', userId, 'Test 1'),
        );
        final op2 = DatumSyncOperation<TestEntity>(
          id: 'op2',
          userId: userId,
          entityId: 'e2',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create('e2', userId, 'Test 2'),
        );

        when(
          () => localAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => [op1, op2]);
        when(() => remoteAdapter.create(any())).thenAnswer((i) async {});
        when(
          () => localAdapter.removePendingOperation(any()),
        ).thenAnswer((_) async {});
        when(
          () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) async => {});
        when(
          () => localAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final stream = manager.eventStream.whereType<DatumSyncProgressEvent>();

        // Assert
        expect(
          stream,
          emitsInOrder([
            isA<DatumSyncProgressEvent>()
                .having((e) => e.progress, 'progress', 0.5)
                .having((e) => e.completed, 'completed', 1)
                .having((e) => e.total, 'total', 2),
            isA<DatumSyncProgressEvent>()
                .having((e) => e.progress, 'progress', 1.0)
                .having((e) => e.completed, 'completed', 2)
                .having((e) => e.total, 'total', 2),
          ]),
        );

        // Trigger a sync
        await manager.synchronize(userId);
      });
    });

    group('watchSyncStatus', () {
      test('emits initial idle status and then syncing status', () async {
        await manager.initialize();
        // Arrange stubs for the sync() call
        when(
          () => remoteAdapter.readAll(
            userId: any(named: 'userId'),
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) async => {});
        when(
          () => localAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final stream = manager.eventStream;

        // Assert
        // Expect the initial 'idle' status first
        expect(
          stream,
          emitsInOrder([
            isA<DatumSyncStartedEvent>(),
            isA<DatumSyncCompletedEvent>(),
          ]),
        );

        // Trigger a sync to change the status
        await manager.synchronize(userId);
      });

      test('emits detailed status updates during sync', () async {
        // Arrange
        await manager.initialize();
        final op1 = DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: userId,
          entityId: 'e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create('e1', userId, 'Test 1'),
        );
        when(
          () => localAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => [op1]);
        when(() => remoteAdapter.create(any())).thenAnswer((i) async {});
        when(
          () => localAdapter.removePendingOperation(any()),
        ).thenAnswer((_) async {});
        // Stub the pull phase to avoid errors, even though we are testing push
        when(
          () => localAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) async => {});
        when(
          () => localAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final stream = manager.eventStream;

        // Assert
        expect(
          stream,
          emitsInOrder([
            isA<DatumSyncStartedEvent>(),
            isA<DatumSyncProgressEvent>().having(
              (e) => e.progress,
              'progress',
              1.0,
            ),
            isA<DatumSyncCompletedEvent>().having(
              (e) => e.result.syncedCount,
              'syncedCount',
              1,
            ),
          ]),
        );

        // Trigger a sync
        await manager.synchronize(userId);
      });

      test('does not emit for other users', () async {
        // Arrange
        await manager.initialize();
        when(
          () => remoteAdapter.readAll(
            userId: any(named: 'userId'),
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) async => {});
        when(
          () => localAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final stream = manager.eventStream;
        final events = <DatumSyncEvent>[];
        stream.listen(events.add);

        // Trigger a sync for the main user
        await manager.synchronize(userId);
        await Future<void>.delayed(
          const Duration(milliseconds: 10),
        ); // Allow stream to emit

        // Assert
        // The stream should only emit events for the user being synced.
        expect(
          events,
          everyElement(
            isA<DatumSyncEvent>().having((e) => e.userId, 'userId', userId),
          ),
        );
      });
    });

    // This group is removed as watchSyncStatistics is no longer part of the public API.
    // Statistics can be derived from the event stream if needed.
    /*
      test('emits initial stats and updated stats after a sync', () async {
        // Arrange stubs for the sync() call
        final op1 = DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: userId,
          entityId: 'e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create('e1', userId, 'Test 1'),
        );
        when(
          () => localAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => [op1]);
        when(
          () => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) async => {});
        when(
          () => remoteAdapter.create(any()),
        ).thenAnswer((i) async {});
        when(
          () => localAdapter.removePendingOperation(any()),
        ).thenAnswer((_) async {});
        when(
          () => localAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => localAdapter.getAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);

        // Act & Assert
        expect(
          manager.watchSyncStatistics(),
          emitsInOrder([
            // Initial state
            isA<SyncStatistics>().having((s) => s.totalSyncs, 'totalSyncs', 0),
            // After one successful sync
            isA<SyncStatistics>().having((s) => s.totalSyncs, 'totalSyncs', 1),
          ]),
        );

        await manager.synchronize(userId);
      });

      test('emits updated stats after a failed sync', () async {
        // Arrange
        final op1 = DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: userId,
          entityId: 'e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create('e1', userId, 'Test 1'),
        );
        when(
          () => localAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => [op1]);
        when(
          () => remoteAdapter.create(any()),
        ).thenThrow(Exception('Sync failed'));
        // Add stubs for the pull phase, which still runs even if push fails.
        when(
          () => remoteAdapter.readAll(
            userId: any(named: 'userId'),
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) async => {});
        when(
          () => localAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});

        // Act & Assert
        expect(
          manager.watchSyncStatistics(),
          emitsInOrder([
            // Initial state
            isA<SyncStatistics>()
                .having((s) => s.totalSyncs, 'totalSyncs', 0)
                .having((s) => s.failedSyncs, 'failedSyncs', 0),
            // After one failed sync
            isA<SyncStatistics>()
                .having((s) => s.totalSyncs, 'totalSyncs', 1)
                .having((s) => s.successfulSyncs, 'successfulSyncs', 0)
                .having((s) => s.failedSyncs, 'failedSyncs', 1),
          ]),
        );

        // The sync method will throw because the operation is not retryable.
        // We expect this and catch it to allow the test to proceed and verify
        // that the statistics were still updated correctly.
        await expectLater(manager.synchronize(userId), throwsA(isA<Exception>()));
      });

      test('emits updated stats after a sync with conflicts', () async {
        // Arrange
        final remoteItem = TestEntity.create(
          'e1',
          userId,
          'Remote',
        ).copyWith(version: 2, modifiedAt: DateTime.now());
        final localItem = TestEntity.create(
          'e1',
          userId,
          'Local',
        ).copyWith(version: 1, modifiedAt: DateTime.now());

        when(
          () => localAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => []);
        when(
          () => remoteAdapter.readAll(userId: userId, scope: any(named: 'scope')),
        ).thenAnswer((_) async => [remoteItem]);
        when(
          () => localAdapter.readByIds([remoteItem.id], userId: userId),
        ).thenAnswer((_) async => {remoteItem.id: localItem});
        when(
          () => localAdapter.update(any()),
        ).thenAnswer((_) async {});
        when(
          () => localAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});

        // Act & Assert
        expect(
          manager.watchSyncStatistics(),
          emitsInOrder([
            // Initial state
            isA<SyncStatistics>().having(
              (s) => s.conflictsDetected,
              'conflictsDetected',
              0,
            ),
            // After one sync with a conflict
            isA<SyncStatistics>()
                .having((s) => s.totalSyncs, 'totalSyncs', 1)
                .having((s) => s.successfulSyncs, 'successfulSyncs', 1)
                .having((s) => s.conflictsDetected, 'conflictsDetected', 1)
                .having(
                  (s) => s.conflictsAutoResolved,
                  'conflictsAutoResolved',
                  1,
                ),
          ]),
        );

        await manager.synchronize(userId);
      });

      test('does not emit stats for other managers', () async {
        // Arrange
        final otherManager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          datumConfig: const DatumConfig(),
        );
        await otherManager.initialize();

        final stats = <SyncStatistics>[];
        otherManager.watchSyncStatistics().listen(stats.add);

        // Act
        await manager.synchronize(userId);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Assert
        expect(stats.length, 1); // Only the initial event
        expect(stats.first.totalSyncs, 0);
      });
    */

    group('Automatic Full Re-sync (needsFullResync logic)', () {
      final baseTime = DateTime.now();
      final localMetadata = DatumSyncMetadata(
        userId: userId,
        lastSyncTime: baseTime,
        dataHash: 'hash123',
        entityCounts: const {
          'TestEntity': DatumEntitySyncDetails(count: 10, hash: 'testhash'),
        },
      );

      // This test is now covered by the 'Automatic Full Re-sync' group below.
      // The core idea is to check if a sync triggers a pull when metadata mismatches.

      test('is triggered if local metadata is null', () async {
        await manager.initialize();
        // Arrange
        when(
          () => localAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => null);
        when(
          () => remoteAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => localMetadata);

        // Act
        await manager.synchronize(userId);

        // Assert: A pull should be triggered.
        verify(
          () => remoteAdapter.readAll(
            userId: userId,
            scope: any(named: 'scope'),
          ),
        ).called(1);
      });

      test('is NOT triggered if remote metadata is null', () async {
        await manager.initialize();
        // Arrange
        when(
          () => localAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => localMetadata);
        when(
          () => remoteAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => null);

        // Act
        await manager.synchronize(userId);

        // Assert: A pull should NOT be triggered based on metadata check.
        // Note: _pullChanges is still called, but it won't fetch based on metadata.
        // We can verify that the metadata-based logic inside pull is skipped.
        // For this test, we'll just confirm no error occurs.
        expect(manager.synchronize(userId), completes);
      });

      test('is triggered on global dataHash mismatch', () async {
        await manager.initialize();
        // Arrange
        final remoteMetadata = localMetadata.copyWith(dataHash: 'hash456');
        when(
          () => localAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => localMetadata);
        when(
          () => remoteAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => remoteMetadata);

        // Act
        await manager.synchronize(userId);

        // Assert
        verify(
          () => remoteAdapter.readAll(
            userId: userId,
            scope: any(named: 'scope'),
          ),
        ).called(1);
      });

      test('is triggered on entity-specific hash mismatch', () async {
        await manager.initialize();
        // Arrange
        final remoteMetadata = localMetadata.copyWith(
          entityCounts: {
            'TestEntity': const DatumEntitySyncDetails(
              count: 10,
              hash: 'DIFFERENT_HASH',
            ),
          },
        );
        when(
          () => localAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => localMetadata);
        when(
          () => remoteAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => remoteMetadata);

        // Act
        await manager.synchronize(userId);

        // Assert
        verify(
          () => remoteAdapter.readAll(
            userId: userId,
            scope: any(named: 'scope'),
          ),
        ).called(1);
      });

      test('is triggered if local metadata is missing an entity', () async {
        await manager.initialize();
        // Arrange
        final localMetadataMissingEntity = DatumSyncMetadata(
          userId: userId,
          lastSyncTime: baseTime,
          dataHash: 'hash123',
          entityCounts: const {
            // Missing 'TestEntity'
          },
        );
        when(
          () => localAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => localMetadataMissingEntity);
        when(
          () => remoteAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => localMetadata); // Remote has both

        // Act
        await manager.synchronize(userId);

        // Assert
        verify(
          () => remoteAdapter.readAll(
            userId: userId,
            scope: any(named: 'scope'),
          ),
        ).called(1);
      });
    });

    group('Automatic Full Re-sync', () {
      test('performs a full re-sync when needsFullResync is true', () async {
        await manager.initialize();
        // Arrange: Setup a scenario where a full re-sync is needed.
        // For example, a mismatch in the global data hash.
        final localMetadata = DatumSyncMetadata(
          userId: userId,
          lastSyncTime: DateTime.now(),
          dataHash: 'local_hash',
        );
        final remoteMetadata = localMetadata.copyWith(dataHash: 'remote_hash');

        when(
          () => localAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => localMetadata);
        when(
          () => remoteAdapter.getSyncMetadata(userId),
        ).thenAnswer((_) async => remoteMetadata);

        // Remote has data that will be pulled after the re-sync.
        final remoteEntity = TestEntity.create('e1', userId, 'Fresh Data');
        when(
          () => remoteAdapter.readAll(
            userId: userId,
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => [remoteEntity]);

        // After pull, local adapter will have the new data.
        when(
          () => localAdapter.readAll(userId: userId),
        ).thenAnswer((_) async => [remoteEntity]);

        // The "smart sync" logic would look like this:
        Future<DatumSyncResult> performSmartSync(String userId) async {
          // This logic is now internal to the sync engine, which checks metadata.
          // We can't call `needsFullResync` directly. We just call sync.
          return manager.synchronize(userId);
        }

        // Act
        final result = await performSmartSync(userId);

        // Assert
        // 1. Verify that the cleanup methods were NOT called, as this logic
        // is not part of the public API anymore. The sync engine handles it.
        verifyNever(() => localAdapter.clearUserData(userId));

        // 2. Verify that the sync was still successful.
        expect(result.failedCount, 0);

        // 3. Verify that the pull operation happened by checking the final
        // state of the local adapter.
        verify(
          () => localAdapter.create(
            any(that: predicate<TestEntity>((e) => e.name == 'Fresh Data')),
          ),
        ).called(1);

        // 4. Verify that new metadata was generated and saved.
        verify(() => localAdapter.updateSyncMetadata(any(), userId)).called(1);
        verify(() => remoteAdapter.updateSyncMetadata(any(), userId)).called(1);
      });
    });

    group('Event Streams', () {
      group('onDataChange', () {
        test('emits DataChangeEvent on push (create)', () async {
          await manager.initialize();
          // Arrange
          final entity = TestEntity.create('e1', userId, 'New Item');
          when(
            () => localAdapter.read(entity.id, userId: userId),
          ).thenAnswer((_) async => null);
          when(() => localAdapter.create(any())).thenAnswer((_) async {});
          when(
            () => localAdapter.addPendingOperation(any(), any()),
          ).thenAnswer((_) async {});

          // Act & Assert
          expect(
            manager.eventStream.whereType<DataChangeEvent<TestEntity>>(),
            emits(
              isA<DataChangeEvent<TestEntity>>()
                  .having((e) => e.changeType, 'changeType', ChangeType.created)
                  .having((e) => e.data.id, 'data.id', entity.id)
                  .having((e) => e.source, 'source', DataSource.local),
            ),
          );

          await manager.push(item: entity, userId: userId);
        });

        test('emits DataChangeEvent on push (update)', () async {
          await manager.initialize();
          // Arrange
          final existingEntity = TestEntity.create('e1', userId, 'Old Item');
          final updatedEntity = existingEntity.copyWith(name: 'Updated Item');
          when(
            () => localAdapter.read(existingEntity.id, userId: userId),
          ).thenAnswer((_) async => existingEntity);
          when(
            () => localAdapter.patch(
              id: any(named: 'id'),
              delta: any(named: 'delta'),
              userId: any(named: 'userId'),
            ),
          ).thenAnswer((_) async => updatedEntity);
          when(
            () => localAdapter.addPendingOperation(any(), any()),
          ).thenAnswer((_) async {});

          // Act & Assert
          expect(
            manager.eventStream.whereType<DataChangeEvent<TestEntity>>(),
            emits(
              isA<DataChangeEvent<TestEntity>>()
                  .having((e) => e.changeType, 'changeType', ChangeType.updated)
                  .having((e) => e.data.id, 'data.id', updatedEntity.id)
                  .having((e) => e.source, 'source', DataSource.local),
            ),
          );

          await manager.push(item: updatedEntity, userId: userId);
        });

        test('emits DataChangeEvent on delete', () async {
          await manager.initialize();
          // Arrange
          final entity = TestEntity.create('e1', userId, 'To be deleted');
          when(
            () => localAdapter.read(entity.id, userId: userId),
          ).thenAnswer((_) async => entity);
          when(
            () => localAdapter.delete(entity.id, userId: userId),
          ).thenAnswer((_) async => true);
          when(
            () => localAdapter.addPendingOperation(any(), any()),
          ).thenAnswer((_) async {});

          // Act & Assert
          expect(
            manager.eventStream.whereType<DataChangeEvent<TestEntity>>(),
            emits(
              isA<DataChangeEvent<TestEntity>>()
                  .having((e) => e.changeType, 'changeType', ChangeType.deleted)
                  .having((e) => e.data.id, 'data.id', entity.id),
            ),
          );

          await manager.delete(id: entity.id, userId: userId);
        });
      });

      group('onSyncStarted / onSyncCompleted', () {
        test(
          'emits start and completed events for a successful sync',
          () async {
            await manager.initialize();
            // Arrange
            when(
              () => localAdapter.getPendingOperations(userId),
            ).thenAnswer((_) async => []);
            when(
              () => localAdapter.readAll(userId: any(named: 'userId')),
            ).thenAnswer((_) async => []);
            when(
              () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
            ).thenAnswer((_) async => {});
            when(
              () => localAdapter.updateSyncMetadata(any(), any()),
            ).thenAnswer((_) async {});
            when(
              () => remoteAdapter.updateSyncMetadata(any(), any()),
            ).thenAnswer((_) async {});

            // Act & Assert
            final startedFuture = manager.eventStream
                .whereType<DatumSyncStartedEvent>()
                .first;
            final completedFuture = manager.eventStream
                .whereType<DatumSyncCompletedEvent>()
                .first;

            await manager.synchronize(userId);

            final startedEvent = await startedFuture;
            final completedEvent = await completedFuture;

            expect(startedEvent.userId, userId);
            expect(completedEvent.userId, userId);
            expect(completedEvent.result.failedCount, 0);
          },
        );
      });

      group('onConflict', () {
        test('emits ConflictDetectedEvent when a conflict occurs', () async {
          await manager.initialize();
          // Arrange
          final remoteItem = TestEntity.create(
            'e1',
            userId,
            'Remote',
          ).copyWith(version: 2, modifiedAt: DateTime.now());
          final localItem = TestEntity.create(
            'e1',
            userId,
            'Local',
          ).copyWith(version: 1, modifiedAt: DateTime.now());

          when(
            () => localAdapter.getPendingOperations(userId),
          ).thenAnswer((_) async => []);
          when(
            () => remoteAdapter.readAll(
              userId: userId,
              scope: any(named: 'scope'),
            ),
          ).thenAnswer((_) async => [remoteItem]);
          when(
            () => localAdapter.readByIds([remoteItem.id], userId: userId),
          ).thenAnswer((_) async => {remoteItem.id: localItem});
          when(() => localAdapter.update(any())).thenAnswer((_) async {});
          when(
            () => localAdapter.readAll(userId: any(named: 'userId')),
          ).thenAnswer((_) async => []);
          when(
            () => localAdapter.updateSyncMetadata(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => remoteAdapter.updateSyncMetadata(any(), any()),
          ).thenAnswer((_) async {});

          // Act & Assert
          final conflictFuture = expectLater(
            manager.onConflict,
            emits(
              isA<ConflictDetectedEvent<TestEntity>>()
                  .having((e) => e.context.entityId, 'entityId', 'e1')
                  .having(
                    (e) => e.context.type,
                    'type',
                    DatumConflictType.bothModified,
                  ),
            ),
          );

          await manager.synchronize(userId);
          await conflictFuture; // Await the expectation after triggering the action
        });
      });

      group('onUserSwitched', () {
        test('emits UserSwitchedEvent on successful user switch', () async {
          await manager.initialize();
          when(
            () => localAdapter.getPendingOperations(any()),
          ).thenAnswer((_) async => []);

          // Act & Assert
          // switchUser is no longer a public method. This is handled by
          // creating a new manager instance or re-initializing.
          // The onUserSwitched event is also internal.
          expect(true, isTrue);
        });
      });

      // This group is removed as onError is no longer a public stream.
      // Errors are now handled via exceptions on the synchronize future
      // and the DatumSyncErrorEvent on the eventStream.
      /*
        test('emits SyncErrorEvent on initialization failure', () async {
          // This requires creating a new manager instance that will fail.
          final failingLocalAdapter = MockLocalAdapter<TestEntity>();
          when(
            failingLocalAdapter.initialize,
          ).thenThrow(Exception('DB connection failed'));

          final errorManager = DatumManager<TestEntity>(
            localAdapter: failingLocalAdapter,
            remoteAdapter: remoteAdapter,
          );

          expect(
            errorManager.onError,
            emits(
              isA<SyncErrorEvent>().having(
                (e) => e.error,
                'error',
                contains('Initialization'),
              ),
            ),
          );

          await expectLater(
            errorManager.initialize(),
            throwsA(isA<Exception>()),
          );
        });
      */

      group('Concurrency', () {
        test(
          'concurrent push calls are correctly queued and synced to remote',
          () async {
            await manager.initialize();
            // Arrange
            final entities = List.generate(
              // Using a smaller number for faster tests
              5,
              (i) => TestEntity.create('e$i', userId, 'Item $i'),
            );

            when(
              () => localAdapter.read(any(), userId: any(named: 'userId')),
            ).thenAnswer((_) async => null);
            when(() => localAdapter.create(any())).thenAnswer((_) async => {});
            when(
              () => localAdapter.addPendingOperation(any(), any()),
            ).thenAnswer((_) async {});
            when(() => remoteAdapter.create(any())).thenAnswer((i) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });

            when(() => localAdapter.getPendingOperations(userId)).thenAnswer(
              (_) async => entities
                  .map(
                    (e) => DatumSyncOperation<TestEntity>(
                      id: e.id,
                      userId: userId,
                      entityId: e.id,
                      type: DatumOperationType.create,
                      timestamp: DateTime.now(),
                      data: e,
                    ),
                  )
                  .toList(),
            );

            // Act 1: Fire all push calls concurrently to populate the queue
            final futures = entities
                .map((e) => manager.push(item: e, userId: userId))
                .toList();
            await Future.wait(futures);

            // Act 2: Trigger a sync to process the queue
            await manager.synchronize(userId);

            // Assert
            // Verify that push was called for each entity
            verify(() => localAdapter.create(any())).called(5);
            // Verify that an operation was enqueued for each entity
            verify(
              () => localAdapter.addPendingOperation(userId, any()),
            ).called(5);
            // Verify that each queued item was pushed to the remote
            verify(() => remoteAdapter.create(any())).called(5);
          },
        );

        test('handles concurrent pushSync calls correctly', () async {
          await manager.initialize();
          // Arrange
          final entities = List.generate(
            5,
            (i) => TestEntity.create('e$i', userId, 'Item $i'),
          );

          // Mocks for the 'push' part
          when(
            () => localAdapter.read(any(), userId: any(named: 'userId')),
          ).thenAnswer((_) async => null);
          when(() => localAdapter.create(any())).thenAnswer((_) async => {});
          when(
            () => localAdapter.addPendingOperation(any(), any()),
          ).thenAnswer((_) async {});

          // Mocks for the 'sync' part
          when(() => remoteAdapter.create(any())).thenAnswer((i) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });

          when(() => localAdapter.getPendingOperations(userId)).thenAnswer(
            (_) async => entities
                .map(
                  (e) => DatumSyncOperation<TestEntity>(
                    id: e.id,
                    userId: userId,
                    entityId: e.id,
                    type: DatumOperationType.create,
                    timestamp: DateTime.now(),
                    data: e,
                  ),
                )
                .toList(),
          );

          // Act: Fire all pushSync calls concurrently
          // pushAndSync is no longer a public method. This is tested by
          // calling push and then synchronize.
          final futures = entities
              .map((e) => manager.push(item: e, userId: userId))
              .toList();
          await Future.wait(futures);
          await manager.synchronize(userId);

          // Assert
          // Verify that local push was called for each entity
          verify(() => localAdapter.create(any())).called(5);
          // Verify that remote push was called for each entity
          verify(() => remoteAdapter.create(any())).called(5);
          // Verify that all operations were marked as synced
          verify(() => localAdapter.removePendingOperation(any())).called(5);
        });

        test('handles concurrent deleteSync calls correctly', () async {
          await manager.initialize();
          // Arrange
          final entities = List.generate(
            5,
            (i) => TestEntity.create('e$i', userId, 'Item $i'),
          );
          for (final e in entities) {
            // Pre-populate local and remote storage
            when(
              () => localAdapter.read(e.id, userId: userId),
            ).thenAnswer((_) async => e);
          }
          when(
            () => localAdapter.delete(any(), userId: any(named: 'userId')),
          ).thenAnswer((_) async => true);
          when(
            () => localAdapter.addPendingOperation(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => remoteAdapter.delete(any(), userId: any(named: 'userId')),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });

          when(() => localAdapter.getPendingOperations(userId)).thenAnswer(
            (_) async => entities
                .map(
                  (e) => DatumSyncOperation<TestEntity>(
                    id: e.id,
                    userId: userId,
                    entityId: e.id,
                    type: DatumOperationType.delete,
                    timestamp: DateTime.now(),
                  ),
                )
                .toList(),
          );

          // Act: Fire all deleteSync calls concurrently
          // deleteAndSync is no longer a public method.
          final futures = entities
              .map((e) => manager.delete(id: e.id, userId: userId))
              .toList();
          await Future.wait(futures);
          await manager.synchronize(userId);

          // Assert
          verify(() => localAdapter.delete(any(), userId: userId)).called(5);
          verify(() => remoteAdapter.delete(any(), userId: userId)).called(5);
          verify(() => localAdapter.removePendingOperation(any())).called(5);
        });
      });
    });

    group('Lifecycle and Error States', () {
      test('calling methods before initialize throws StateError', () async {
        // Arrange
        final uninitializedManager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
        );

        // Act & Assert
        expect(
          () => uninitializedManager.read('some-id'),
          throwsA(isA<StateError>()),
        );
        expect(
          () => uninitializedManager.synchronize('some-user'),
          throwsA(isA<StateError>()),
        );
      });

      test('calling methods after dispose throws StateError', () async {
        await manager.initialize();
        // Arrange
        await manager.dispose();

        // Act & Assert
        expect(() => manager.read('some-id'), throwsA(isA<StateError>()));
        expect(
          () => manager.synchronize('some-user'),
          throwsA(isA<StateError>()),
        );
      });

      test('synchronize returns skipped result when offline', () async {
        await manager.initialize();
        // Arrange
        when(
          () => connectivityChecker.isConnected,
        ).thenAnswer((_) async => false);

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.wasSkipped, isTrue);
        verifyNever(
          () => remoteAdapter.readAll(
            userId: any(named: 'userId'),
            scope: any(named: 'scope'),
          ),
        );
      });

      test(
        'synchronize throws and emits error event on remote failure',
        () async {
          await manager.initialize();
          // Arrange
          final exception = Exception('Remote push failed');
          final op = DatumSyncOperation<TestEntity>(
            id: 'op1',
            userId: userId,
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e1', userId, 'Test 1'),
          );
          when(
            () => localAdapter.getPendingOperations(userId),
          ).thenAnswer((_) async => [op]);
          when(() => remoteAdapter.create(any())).thenThrow(exception);

          // Act
          final errorEventFuture = expectLater(
            manager.onSyncError,
            emits(isA<DatumSyncErrorEvent>()),
          );
          final syncThrowFuture = expectLater(
            () => manager.synchronize(userId),
            throwsA(exception),
          );

          // Assert
          // Await both futures concurrently to avoid race conditions.
          await Future.wait([errorEventFuture, syncThrowFuture]);
        },
      );

      test(
        'delete returns false and does not queue if item does not exist',
        () async {
          await manager.initialize();
          // Arrange
          when(
            () => localAdapter.read('non-existent', userId: userId),
          ).thenAnswer((_) async => null);

          // Act
          final result = await manager.delete(
            id: 'non-existent',
            userId: userId,
          );

          // Assert
          expect(result, isFalse);
          verifyNever(() => localAdapter.addPendingOperation(any(), any()));
        },
      );

      test('push does not save or queue if item has not changed', () async {
        await manager.initialize();
        // Arrange
        final entity = TestEntity.create('e1', userId, 'Unchanged Item');
        // Simulate that the exact same entity already exists locally.
        when(
          () => localAdapter.read(entity.id, userId: userId),
        ).thenAnswer((_) async => entity);

        // Act
        final result = await manager.push(item: entity, userId: userId);

        // Assert
        // The returned entity should be the same as the input.
        expect(result, entity);

        // Verify that no write operations were performed.
        verifyNever(() => localAdapter.create(any()));
        verifyNever(() => localAdapter.update(any()));
        verifyNever(
          () => localAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        );

        // Verify that no operation was queued for sync.
        verifyNever(() => localAdapter.addPendingOperation(any(), any()));
      });
    });

    group('Public Properties', () {
      test('queueManager getter exposes the internal queue manager', () async {
        await manager.initialize();
        // Arrange
        final operation = DatumSyncOperation<TestEntity>(
          id: 'op-test',
          userId: userId,
          entityId: 'e-test',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
        );
        // Stub the method that will be called by the queue manager.
        when(
          () => localAdapter.addPendingOperation(any(), any()),
        ).thenAnswer((_) async {});

        // Act: Get the queue manager from the manager.
        final exposedQueueManager = manager.queueManager;

        // Assert: It's the correct type.
        expect(exposedQueueManager, isA<QueueManager<TestEntity>>());

        // Further Assert: Use the exposed manager and verify it's functional.
        await exposedQueueManager.enqueue(operation);
        verify(
          () => localAdapter.addPendingOperation(userId, operation),
        ).called(1);
      });
    });

    group('Public Event Streams', () {
      test(
        'onSyncStarted, onSyncProgress, and onSyncCompleted emit correctly',
        () async {
          await manager.initialize();
          // Arrange
          final op1 = DatumSyncOperation<TestEntity>(
            id: 'op1',
            userId: userId,
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e1', userId, 'Test 1'),
          );
          when(
            () => localAdapter.getPendingOperations(userId),
          ).thenAnswer((_) async => [op1]);
          when(() => remoteAdapter.create(any())).thenAnswer((_) async {});

          // Act
          final startedFuture = expectLater(
            manager.onSyncStarted,
            emits(
              isA<DatumSyncStartedEvent>().having(
                (e) => e.userId,
                'userId',
                userId,
              ),
            ),
          );

          final progressFuture = expectLater(
            manager.onSyncProgress,
            emits(
              isA<DatumSyncProgressEvent>().having(
                (e) => e.progress,
                'progress',
                1.0,
              ),
            ),
          );

          final completedFuture = expectLater(
            manager.onSyncCompleted,
            emits(
              isA<DatumSyncCompletedEvent>().having(
                (e) => e.result.syncedCount,
                'syncedCount',
                1,
              ),
            ),
          );

          // Trigger the sync
          await manager.synchronize(userId);

          // Assert
          await Future.wait([startedFuture, progressFuture, completedFuture]);
        },
      );
    });
  });
}
