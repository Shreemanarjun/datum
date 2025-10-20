import 'dart:async';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/datum.dart';

import '../mocks/test_entity.dart';

class MockLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

typedef StreamControllers = ({
  StreamController<DatumChangeDetail<TestEntity>> local,
  StreamController<DatumChangeDetail<TestEntity>> remote,
});

class MockConnectivityChecker extends Mock
    implements DatumConnectivityChecker {}

void main() {
  group('DatumManager External Change Handling', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late DatumManager<TestEntity> manager;
    late MockConnectivityChecker connectivityChecker;

    const userId = 'user-1';
    final now = DateTime.now();
    final entity = TestEntity(
      id: 'entity-1',
      userId: userId,
      name: 'Initial',
      value: 1,
      modifiedAt: now,
      createdAt: now,
      version: 1,
    );

    setUpAll(() {
      // Register a fallback value for TestEntity to be used with `any()`
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

      // Register a fallback for DatumSyncOperation to use with `any()`
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fallback',
          userId: 'fallback',
          entityId: 'fallback',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );

      // Register a fallback for DatumSyncMetadata
      registerFallbackValue(
        const DatumSyncMetadata(userId: 'fallback', dataHash: 'fallback'),
      );

      // Add the missing fallback for DatumSyncResult<TestEntity>.
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

    setUp(() {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();
      final pendingOpsForUser = <DatumSyncOperation<TestEntity>>[];

      // Default stubs for mocktail mocks
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(() => localAdapter.create(any())).thenAnswer((_) async {});
      when(
        () => localAdapter.delete(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => true);
      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(() => localAdapter.update(any())).thenAnswer((_) async {});

      when(
        () => localAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((inv) async {
        // The first argument is the ID (String), the second is the delta (Map).
        // We simulate the patch by applying the delta to the original entity.
        final delta = inv.namedArguments[#delta] as Map<String, dynamic>;
        final originalMap = entity.toDatumMap();
        return TestEntity.fromJson(originalMap..addAll(delta));
      });

      when(() => localAdapter.addPendingOperation(any(), any())).thenAnswer((
        inv,
      ) async {
        pendingOpsForUser.add(
          inv.positionalArguments[1] as DatumSyncOperation<TestEntity>,
        );
      });
      when(
        () => localAdapter.getPendingOperations(any()),
      ).thenAnswer((_) async => pendingOpsForUser);
      when(
        () => localAdapter.getLastSyncResult(any()),
      ).thenAnswer((_) async => null);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig<TestEntity>(
          schemaVersion: 0, // Match the mock adapter's initial version
          remoteEventDebounceTime:
              Duration.zero, // Disable debouncing for most tests
        ),
      );

      // Register the mocktail fallback for ChangeDetail
      registerFallbackValue(
        DatumChangeDetail<TestEntity>(
          type: DatumOperationType.create,
          entityId: '',
          userId: '',
          timestamp: DateTime.now(),
        ),
      );
    });

    // Helper to set up stream controllers for tests.
    StreamControllers setupStreams() {
      final localSC =
          StreamController<DatumChangeDetail<TestEntity>>.broadcast();
      final remoteSC =
          StreamController<DatumChangeDetail<TestEntity>>.broadcast();
      when(localAdapter.changeStream).thenAnswer((_) => localSC.stream);
      when(() => remoteAdapter.changeStream).thenAnswer((_) => remoteSC.stream);
      return (local: localSC, remote: remoteSC);
    }

    tearDown(() async {
      await manager.dispose();
    });

    test(
      'remote create change is saved locally but NOT re-queued for remote push',
      () async {
        // Arrange: Set up the stream controller BEFORE initializing the manager.
        final (remote: remoteStreamController, local: _) = setupStreams();
        await manager.initialize();

        final remoteChange = DatumChangeDetail(
          // Use a fixed timestamp to ensure the changeKey is identical.
          timestamp: DateTime(2023),
          type: DatumOperationType.create,
          entityId: entity.id,
          userId: userId,
          data: entity,
        );

        // Act: Simulate a change from the remote adapter's stream
        remoteStreamController.add(remoteChange);
        await Future<void>.delayed(
          const Duration(milliseconds: 100),
        ); // Process stream

        // Assert: Verify it was saved locally by calling create
        verify(() => localAdapter.create(entity)).called(1);

        // Assert: Verify it was NOT added to the pending queue
        final pendingOps = await manager.getPendingCount(userId);
        expect(pendingOps, 0);
      },
    );

    test('remote delete change is applied locally but NOT re-queued', () async {
      // Arrange: Set up the stream controller and initial data state
      // BEFORE initializing the manager.
      final (remote: remoteStreamController, local: _) = setupStreams();
      when(
        () => localAdapter.read(entity.id, userId: userId),
      ).thenAnswer((_) async => entity);
      await manager.initialize();

      final deleteChange = DatumChangeDetail<TestEntity>(
        type: DatumOperationType.delete,
        entityId: entity.id,
        userId: userId,
        timestamp: DateTime.now(),
      );

      // Act: Simulate a delete event from remote
      remoteStreamController.add(deleteChange);
      await Future<void>.delayed(
        const Duration(milliseconds: 100),
      ); // Process stream

      // Assert: Verify it was deleted locally
      verify(() => localAdapter.delete(entity.id, userId: userId)).called(1);

      // Assert: Verify no delete operation was queued
      final pendingOps = await manager.getPendingCount(userId);
      expect(pendingOps, 0);
    });

    test('duplicate remote changes are ignored by the cache', () async {
      // Arrange
      final (remote: remoteStreamController, local: _) = setupStreams();
      await manager.initialize();

      final remoteChange = DatumChangeDetail(
        type: DatumOperationType.create,
        entityId: entity.id,
        userId: userId,
        timestamp: DateTime.now(),
        data: entity,
      );

      // Act: Simulate the exact same change arriving twice
      remoteStreamController.add(remoteChange);
      remoteStreamController.add(remoteChange);
      // Wait for the stream to be processed. Since debounce is zero, it's fast.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert: The create method should only be called ONCE due to the cache.
      verify(() => localAdapter.create(any())).called(1);
    });

    test(
      'a change is processed again if it arrives after cache duration expires',
      () async {
        // Arrange
        // Re-initialize manager with a very short cache duration for this test.
        await manager.dispose();
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          datumConfig: const DatumConfig<TestEntity>(
            schemaVersion: 0,
            remoteEventDebounceTime: Duration.zero,
            changeCacheDuration: Duration(milliseconds: 100),
          ),
        );

        final (remote: remoteStreamController, local: _) = setupStreams();
        await manager.initialize();

        final remoteChange = DatumChangeDetail(
          type: DatumOperationType.create,
          entityId: entity.id,
          userId: userId,
          timestamp: DateTime.now(),
          data: entity,
        );

        // Act:
        // 1. Send the first change.
        remoteStreamController.add(remoteChange);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 2. Wait for the cache to expire.
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // 3. Send the same change again.
        remoteStreamController.add(remoteChange);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Assert: The create method should have been called TWICE.
        verify(() => localAdapter.create(any())).called(2);
      },
    );

    test(
      'multiple remote changes are buffered and processed as a batch',
      () async {
        // Arrange
        // Re-initialize manager with a longer debounce time for this test.
        await manager.dispose();
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          datumConfig: const DatumConfig<TestEntity>(
            schemaVersion: 0,
            remoteEventDebounceTime: Duration(milliseconds: 200),
          ),
        );

        final (remote: remoteStreamController, local: _) = setupStreams();
        await manager.initialize();

        final change1 = DatumChangeDetail(
          type: DatumOperationType.create,
          entityId: 'entity-1',
          userId: userId,
          timestamp: DateTime.now(),
          data: entity.copyWith(id: 'entity-1'),
        );
        final change2 = DatumChangeDetail<TestEntity>(
          type: DatumOperationType.delete,
          entityId: 'entity-2',
          userId: userId,
          timestamp: DateTime.now(),
        );

        // Act: Fire both changes in quick succession, well within the debounce time.
        remoteStreamController.add(change1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        remoteStreamController.add(change2);

        // Wait for the debounce timer to fire and process the batch.
        await Future<void>.delayed(const Duration(milliseconds: 250));

        // Assert: Verify that both operations were processed.
        verify(
          () => localAdapter.create(
            any(that: predicate((e) => (e as TestEntity).id == 'entity-1')),
          ),
        ).called(1);
        verify(() => localAdapter.delete('entity-2', userId: userId)).called(1);
      },
    );

    test(
      'local adapter changes are processed and queued for remote push',
      () async {
        // Arrange: Set up the stream controller BEFORE initializing the manager.
        final (local: localStreamController, remote: _) = setupStreams();
        await manager.initialize();

        final localChange = DatumChangeDetail(
          type: DatumOperationType.create,
          entityId: entity.id,
          userId: userId,
          timestamp: DateTime.now(),
          data: entity,
        );

        // Act: Simulate a change from the local adapter's stream
        localStreamController.add(localChange);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Assert: Verify the change was queued for remote sync
        final pendingOps = await manager.getPendingCount(userId);
        expect(pendingOps, 1);
      },
    );

    test('local adapter update change is queued for remote push', () async {
      // Arrange: Start with an existing entity in the local adapter.
      final (local: localStreamController, remote: _) = setupStreams();
      when(
        () => localAdapter.read(entity.id, userId: userId),
      ).thenAnswer((_) async => entity);
      await manager.initialize();

      final updatedEntity = entity.copyWith(name: 'Locally Updated');
      final localChange = DatumChangeDetail(
        type: DatumOperationType.update,
        entityId: updatedEntity.id,
        userId: updatedEntity.userId,
        timestamp: DateTime.now(),
        data: updatedEntity,
      );

      // Act: Simulate an update from the local adapter's stream
      localStreamController.add(localChange);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Assert: Verify an 'update' operation was queued
      final pendingOps = await manager.getPendingCount(userId);
      expect(pendingOps, 1);

      // Optional: Deeper check on the operation type
      final ops = await localAdapter.getPendingOperations(userId);
      expect(ops.first.type, DatumOperationType.update);
    });

    test(
      'remote delete for a non-existent item is handled gracefully',
      () async {
        // Arrange: Ensure the item does not exist locally.
        // The default stub for `read` already returns null.
        final (remote: remoteStreamController, local: _) = setupStreams();
        await manager.initialize();

        final deleteChange = DatumChangeDetail<TestEntity>(
          type: DatumOperationType.delete,
          entityId: 'non-existent-id',
          userId: userId,
          timestamp: DateTime.now(),
        );

        // Act & Assert: The operation should complete without throwing an error.
        expect(() => remoteStreamController.add(deleteChange), returnsNormally);
      },
    );

    test(
      'local adapter update change with delta is queued for remote push',
      () async {
        // Arrange: Set up the stream controller and an existing entity.
        final (local: localStreamController, remote: _) = setupStreams();
        when(
          () => localAdapter.read(entity.id, userId: userId),
        ).thenAnswer((_) async => entity);
        await manager.initialize();

        // This is the updated version of the entity.
        final updatedEntity = entity.copyWith(name: 'Locally Updated');

        // This is the change event, as it would come from an external source
        // that modified the local DB directly (e.g., another process).
        final localChange = DatumChangeDetail(
          type: DatumOperationType.update,
          entityId: updatedEntity.id,
          userId: updatedEntity.userId,
          timestamp: DateTime.now(),
          data: updatedEntity,
        );

        // Act: Simulate an update from the local adapter's stream.
        localStreamController.add(localChange);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Assert: Verify an 'update' operation was queued.
        final pendingOps = await manager.getPendingCount(userId);
        expect(pendingOps, 1);

        // Capture the operation that was enqueued to inspect its contents.
        final capturedOp = verify(
          () => localAdapter.addPendingOperation(userId, captureAny()),
        ).captured.single as DatumSyncOperation<TestEntity>;

        // Assert that the operation is an 'update'.
        expect(capturedOp.type, DatumOperationType.update);

        // CRITICAL: Assert that the operation contains the delta, not the full data.
        // This confirms the delta-sync optimization is working for external changes.
        expect(capturedOp.delta, isNotNull);
        expect(capturedOp.delta, {'name': 'Locally Updated'});
      },
    );

    test(
        'handles external change arriving during a pull operation for the same entity',
        () async {
      // This test simulates a race condition: a sync starts, pulling v2 of an
      // entity. While the sync is running, a real-time event for v3 arrives.
      // The expected outcome is that v3, the latest version, should be the
      // final state in the local database.

      // ARRANGE
      // Create a completer to signal when the final patch operation is done.
      final patchCompleter = Completer<void>();

      final (remote: remoteStreamController, local: _) = setupStreams();
      await manager.initialize();

      final localV1 = entity.copyWith(version: 1, name: 'Version 1');
      final remoteV2 = entity.copyWith(version: 2, name: 'Version 2');
      final externalV3 = entity.copyWith(version: 3, name: 'Version 3');

      // The sync will pull remoteV2 and see localV1, creating a conflict.
      when(
        () => remoteAdapter.readAll(
          userId: userId,
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => [remoteV2]);
      when(
        () => localAdapter.readByIds([remoteV2.id], userId: userId),
      ).thenAnswer((_) async => {remoteV2.id: localV1});

      // When the external change handler calls `push`, it will read the entity
      // to determine if it's a create or update. We must stub this read to
      // return the version that the sync process just saved (v2), so that
      // the handler correctly performs a patch to get to v3.
      when(() => localAdapter.read(remoteV2.id, userId: userId))
          .thenAnswer((_) async => remoteV2);

      when(
        () => localAdapter.saveLastSyncResult(any(), any()),
      ).thenAnswer((_) async {});
      when(() => localAdapter.update(any())).thenAnswer((_) async {});

      // Stub metadata calls
      when(
        () => localAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});

      // Stub for the final metadata generation step after all writes are done.
      when(
        () => localAdapter.readAll(userId: userId),
      ).thenAnswer((_) async => [externalV3]);

      // When the final patch for v3 happens, complete the completer.
      when(
        () => localAdapter.patch(
          id: externalV3.id,
          delta: any(named: 'delta', that: equals({'name': 'Version 3'})),
          userId: userId,
        ),
      ).thenAnswer((_) async {
        if (!patchCompleter.isCompleted) {
          patchCompleter.complete();
        }
        // Return a simulated patched entity.
        return externalV3;
      });

      // ACT
      // Start the sync but don't await it yet.
      final syncFuture = manager.synchronize(userId);

      // Give the sync a moment to start its pull operation.
      // This ensures the race condition is more likely to occur as intended.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Immediately after, simulate the v3 external change arriving.
      remoteStreamController.add(
        DatumChangeDetail(
          type: DatumOperationType.update,
          entityId: externalV3.id,
          userId: userId,
          timestamp: DateTime.now(),
          data: externalV3,
        ),
      );

      // Await the completion of the sync.
      await syncFuture;

      // Explicitly wait for the patch operation to be called.
      await patchCompleter.future;

      // ASSERT
      // The sync engine will resolve the conflict and save remoteV2.
      // Then, the external change handler will process externalV3.
      // The final call should be a `patch` with the delta for v3.
      verify(
        () => localAdapter.patch(
          id: externalV3.id,
          delta: any(named: 'delta', that: equals({'name': 'Version 3'})),
          userId: userId,
        ),
      ).called(1);
    }, timeout: const Timeout(Duration(seconds: 2)));
  });
}
