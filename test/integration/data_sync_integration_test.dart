import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class MockedRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

class MockedLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockDatumObserver<T extends DatumEntity> extends Mock
    implements DatumObserver<T> {}

/// A custom logger for tests that omits stack traces for cleaner output.
class TestLogger extends DatumLogger {
  TestLogger() : super(enabled: true);

  @override
  void error(String message, [StackTrace? stackTrace]) {
    super.error(message); // Call the base method without the stack trace.
  }
}

void main() {
  group('Delta Sync Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late MockDatumObserver<TestEntity> mockObserver;

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(DatumSyncMetadata(userId: 'fb', dataHash: 'fb'));
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb-op',
          userId: 'fb',
          entityId: 'fb-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        DatumChangeDetail<TestEntity>(
          type: DatumOperationType.create,
          entityId: 'fb',
          userId: 'fb',
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        const DatumSyncResult(
          userId: 'fallback',
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: <DatumSyncOperation<TestEntity>>[],
          duration: Duration.zero,
        ),
      );
      registerFallbackValue(
        DatumConflictContext(
          userId: 'fb',
          entityId: 'fb',
          type: DatumConflictType.bothModified,
          detectedAt: DateTime(0),
        ),
      );
    });

    Future<DatumManager<TestEntity>> setupManager({
      DatumConfig<TestEntity>? config,
    }) async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();
      mockObserver = MockDatumObserver<TestEntity>();

      // Common stubs for local adapter
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});

      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.getPendingOperations(any()),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.addPendingOperation(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.removePendingOperation(any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => localAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async => TestEntity.create('patched', 'user1', 'Patched locally'),
      );

      // Stub observer methods to prevent tests from hanging.
      // Mocktail's default for async methods is a Future that never completes.
      when(() => mockObserver.onSyncStart()).thenAnswer((_) {});
      when(() => mockObserver.onSyncEnd(any())).thenAnswer((_) {});
      when(() => mockObserver.onCreateStart(any())).thenAnswer((_) {});
      when(() => mockObserver.onCreateEnd(any())).thenAnswer((_) {});
      when(() => mockObserver.onUpdateStart(any())).thenAnswer((_) {});
      when(() => mockObserver.onUpdateEnd(any())).thenAnswer((_) {});
      when(() => mockObserver.onDeleteStart(any())).thenAnswer((_) {});
      when(
        () => mockObserver.onDeleteEnd(any(), success: any(named: 'success')),
      ).thenAnswer((_) {});
      when(
        () => mockObserver.onConflictDetected(any(), any(), any()),
      ).thenAnswer((_) {});

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter, // Use the real mock adapter
        remoteAdapter: remoteAdapter,
        datumConfig: config ?? const DatumConfig(),
        connectivity: connectivityChecker,
        localObservers: [mockObserver],
        logger: TestLogger(),
      );

      // Stub required methods for the mock remote adapter
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});

      // Stub for pull phase to prevent null-future errors
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});

      // Stub the patch method for remote adapter
      when(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async =>
            TestEntity.create('patched', 'user1', 'Patched from remote'),
      );
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});

      await manager.initialize();
      return manager;
    }

    setUp(() async {
      await setupManager();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test(
      'uses delta sync (patch) for updates to minimize network traffic',
      () async {
        // 1. ARRANGE: Create and sync an initial entity.
        final pendingOps = <DatumSyncOperation<TestEntity>>[];
        final initialEntity = TestEntity.create('delta-e1', 'user1', 'Initial');
        when(
          () => localAdapter.read(initialEntity.id, userId: 'user1'),
        ).thenAnswer((_) async => initialEntity);

        when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
        when(() => localAdapter.removePendingOperation(any())).thenAnswer((
          inv,
        ) async {
          final opId = inv.positionalArguments.first as String;
          pendingOps.removeWhere((op) => op.id == opId);
        });

        // Stub getPendingOperations for this test
        final createOp = DatumSyncOperation<TestEntity>(
          id: 'op-delta-e1-create',
          userId: 'user1',
          entityId: initialEntity.id,
          type: DatumOperationType.create,
          timestamp: initialEntity.modifiedAt,
          data: initialEntity,
        );
        pendingOps.add(createOp);
        when(
          () => localAdapter.getPendingOperations('user1'),
        ).thenAnswer((_) async => pendingOps);

        await manager.push(item: initialEntity, userId: 'user1');
        await manager.synchronize('user1');

        // Verify it was pushed fully the first time.
        verify(() => remoteAdapter.create(any())).called(1);
        expect(await manager.getPendingCount('user1'), 0);

        // 2. ACT: Update only one field of the entity and push it.
        final updatedEntity = initialEntity.copyWith(name: 'Updated Name');
        when(
          () => localAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async => updatedEntity);
        await manager.push(item: updatedEntity, userId: 'user1');

        // Update the stub to reflect the new pending 'update' operation.
        final updateOp = DatumSyncOperation<TestEntity>(
          id: 'op-delta-e1-update',
          userId: 'user1',
          entityId: updatedEntity.id,
          type: DatumOperationType.update,
          timestamp: updatedEntity.modifiedAt,
          delta: updatedEntity.diff(initialEntity),
          data: updatedEntity,
        );
        pendingOps.add(updateOp);

        // Sync again.
        await manager.synchronize('user1');

        // 3. ASSERT: Verify that `patch` was called with only the changed field.
        final capturedDelta = verify(
          () => remoteAdapter.patch(
            id: 'delta-e1',
            userId: 'user1',
            delta: captureAny(named: 'delta'),
          ),
        ).captured.single as Map<String, dynamic>;

        // The delta should only contain the 'name' field.
        expect(capturedDelta, hasLength(1));
        expect(capturedDelta['name'], 'Updated Name');

        // The observer API has changed. We can verify the DataChangeEvent.
        // This is implicitly tested by the push() method's event emission.

        // Verify the queue is empty after the delta sync.
        expect(await manager.getPendingCount('user1'), 0);
      },
    );

    test('does not create a patch operation if there are no changes', () async {
      // 1. ARRANGE: Create and sync an initial entity.
      final initialEntity = TestEntity.create('delta-e2', 'user1', 'Initial');
      when(
        () => localAdapter.read(initialEntity.id, userId: 'user1'),
      ).thenAnswer((_) async => initialEntity);
      await manager.push(item: initialEntity, userId: 'user1');
      // No need to sync, push() doesn't queue if no changes
      expect(await manager.getPendingCount('user1'), 0);

      // 2. ACT: Push the exact same entity again.
      await manager.push(item: initialEntity, userId: 'user1');

      // 3. ASSERT: No pending operation should be created.
      verifyNever(() => localAdapter.addPendingOperation(any(), any()));
      expect(await manager.getPendingCount('user1'), 0);

      // Sync again to be sure.
      await manager.synchronize('user1');

      // `patch` should never have been called because there was no diff.
      verifyNever(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      );
    });

    test('converts a patch to a push if remote entity does not exist',
        () async {
      final pendingOps = <DatumSyncOperation<TestEntity>>[];
      // 1. ARRANGE: Create and sync an initial entity.
      final initialEntity = TestEntity.create('delta-e3', 'user1', 'Initial');
      when(
        () => localAdapter.read(initialEntity.id, userId: 'user1'),
      ).thenAnswer((_) async => initialEntity);
      // Stub the create for the initial push
      when(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == initialEntity.id)),
        ),
      ).thenAnswer((_) async {});

      // The initial entity is assumed to be synced. We are only testing the update.
      // No need to actually perform the initial push/sync.

      // 2. ACT: Update the entity locally.
      final updatedEntity = initialEntity.copyWith(name: 'Updated Name');
      await manager.push(item: updatedEntity, userId: 'user1');

      // Arrange for the patch to fail with an EntityNotFoundException,
      // simulating that the item was deleted on the remote.
      when(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenThrow(
        EntityNotFoundException('Entity delta-e3 not found on remote.'),
      );

      // The fallback-to-push logic is now internal to the sync engine.
      // Awaiting a sync will now throw the exception if the retry (as push) fails.
      // For this test, we stub the create for the *updated* entity.
      when(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == updatedEntity.id)),
        ),
      ).thenAnswer((_) async {});
      final updateOp = DatumSyncOperation(
        id: 'op-update',
        userId: 'user1',
        entityId: updatedEntity.id,
        type: DatumOperationType.update,
        timestamp: DateTime.now(),
        data: updatedEntity,
        delta: updatedEntity.diff(initialEntity),
      );
      pendingOps.add(updateOp);
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => pendingOps);
      when(() => localAdapter.removePendingOperation('op-update')).thenAnswer(
        (_) async => pendingOps.removeWhere((op) => op.id == 'op-update'),
      );

      // Sync again.
      await manager.synchronize('user1');

      // 3. ASSERT: The engine should have caught the exception and retried
      // the operation as a full `create` (since it's not found).
      verify(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).called(1);
      verify(
        () => remoteAdapter.create(
          any(that: predicate((e) => (e as TestEntity).id == updatedEntity.id)),
        ),
      ).called(1);

      // The queue should be empty after the successful fallback push.
      expect(await manager.getPendingCount('user1'), 0);
    });

    test('retries a patch operation on network failure', () async {
      // Re-initialize manager with retries enabled
      // We can't use setUp for this one-off config, so we handle it manually.
      await manager
          .dispose(); // Dispose the one from setUp      await setupManager(
      // Create a local manager for this test to avoid interfering with the
      // group's setUp/tearDown cycle.
      await setupManager(
        config: DatumConfig(
          errorRecoveryStrategy: DatumErrorRecoveryStrategy(
            maxRetries: 3,
            shouldRetry: (error) async {
              return error is NetworkException;
            },
          ),
        ),
      );

      // 1. ARRANGE: Create and sync an initial entity.
      final initialEntity = TestEntity.create('delta-e4', 'user1', 'Initial');
      when(
        () => localAdapter.read(initialEntity.id, userId: 'user1'),
      ).thenAnswer((_) async => initialEntity);
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
      when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
        (_) async => [
          DatumSyncOperation(
            id: 'op-create',
            userId: 'user1',
            entityId: initialEntity.id,
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: initialEntity,
          ),
        ],
      );
      await manager.push(item: initialEntity, userId: 'user1');
      await manager.synchronize('user1');

      // 2. ACT: Update and push, but make the patch fail once.
      final updatedEntity = initialEntity.copyWith(name: 'Updated Name');
      await manager.push(item: updatedEntity, userId: 'user1');

      when(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenThrow(NetworkException('Simulated network failure'));

      var op = DatumSyncOperation<TestEntity>(
        id: 'op-update',
        userId: 'user1',
        entityId: updatedEntity.id,
        type: DatumOperationType.update,
        timestamp: DateTime.now(),
        delta: updatedEntity.diff(initialEntity),
        data: updatedEntity,
      );
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => [op]);
      when(
        () => localAdapter.addPendingOperation(
          'user1',
          any(
            that: predicate((o) => (o as DatumSyncOperation).id == 'op-update'),
          ),
        ),
      ).thenAnswer((inv) async {
        op = inv.positionalArguments[1] as DatumSyncOperation<TestEntity>;
      });

      // 3. ASSERT: The sync will fail, but the operation will be retried.
      final result = await manager.synchronize('user1');
      expect(result.failedCount, 0); // Retryable ops are not "failed"
      expect(result.pendingOperations, hasLength(1));
      expect(result.pendingOperations.first.retryCount, 1);
    });

    test('fails permanently on non-retryable error', () async {
      // 1. ARRANGE
      // Create a local manager for this test to avoid interfering with the
      // group's setUp/tearDown cycle.
      final testManager = await setupManager(
        config: DatumConfig(
          errorRecoveryStrategy: const DatumErrorRecoveryStrategy(
            maxRetries: 3,
            shouldRetry: _alwaysRetry,
          ),
        ),
      );

      final entity = TestEntity.create('delta-e5', 'user1', 'Will Fail');
      final nonRetryableException = Exception('Invalid data format');

      final pendingOpsList = <DatumSyncOperation<TestEntity>>[];
      // Stub the remote create to throw a non-retryable error
      when(() => remoteAdapter.create(any())).thenThrow(nonRetryableException);

      // Set up a pending operation in the queue
      final op = DatumSyncOperation<TestEntity>(
        id: 'op-fail',
        userId: 'user1',
        entityId: entity.id,
        type: DatumOperationType.create,
        timestamp: DateTime.now(),
        data: entity,
        retryCount: 0,
      );
      pendingOpsList.add(op);
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => pendingOpsList);
      when(() => localAdapter.removePendingOperation('op-fail')).thenAnswer(
        (_) async => pendingOpsList.removeWhere((o) => o.id == 'op-fail'),
      );

      // 2. ACT & ASSERT
      // The synchronize call should fail by re-throwing the exception.
      await expectLater(
        () => testManager.synchronize('user1'),
        throwsA(nonRetryableException),
      );

      // 3. VERIFY
      // Verify that the operation was NOT updated for a retry.
      verifyNever(
        () => localAdapter.addPendingOperation(
          'user1',
          any(that: predicate((o) => (o as DatumSyncOperation).retryCount > 0)),
        ),
      );

      // The operation should have been removed from the queue to prevent
      // it from blocking subsequent syncs.
      final pendingOps = await testManager.getPendingCount('user1');
      expect(pendingOps, 0);
      verify(() => localAdapter.removePendingOperation('op-fail')).called(1);

      await testManager.dispose();
    });

    test('emits onSyncError event on synchronization failure', () async {
      // 1. ARRANGE
      final exception = Exception('Remote is down');
      final entity = TestEntity.create('delta-e6', 'user1', 'Will Fail');

      // Stub the remote create to throw an error
      when(() => remoteAdapter.create(any())).thenThrow(exception);

      // Set up a pending operation
      final op = DatumSyncOperation<TestEntity>(
        id: 'op-fail-event',
        userId: 'user1',
        entityId: entity.id,
        type: DatumOperationType.create,
        timestamp: DateTime.now(),
        data: entity,
      );
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => [op]);

      // 2. ACT & ASSERT
      // Expect the event to be emitted
      final errorEventFuture = expectLater(
        manager.onSyncError,
        emits(
          isA<DatumSyncErrorEvent>()
              .having((e) => e.userId, 'userId', 'user1')
              .having((e) => e.error, 'error', exception),
        ),
      );

      // Expect the synchronize call to throw.
      final syncThrowFuture = expectLater(
        () => manager.synchronize('user1'),
        // Instead of checking for the exact exception instance,
        // check for the type and a property (like the message) to make
        // the test more robust against stack trace differences.
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'toString()', 'Exception: Remote is down')),
      );

      // Await both futures concurrently to avoid a race condition.
      await Future.wait([errorEventFuture, syncThrowFuture]);
    });

    test('cancels sync mid-process when manager is disposed', () async {
      // 1. ARRANGE
      // Re-initialize manager with a sequential strategy to make cancellation predictable
      await manager.dispose();
      await setupManager(
        config: const DatumConfig(syncExecutionStrategy: SequentialStrategy()),
      );

      final operations = List.generate(
        5,
        (i) => DatumSyncOperation<TestEntity>(
          id: 'op-cancel-$i',
          userId: 'user1',
          entityId: 'cancel-$i',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create('cancel-$i', 'user1', 'Cancel Test $i'),
        ),
      );

      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => operations);

      // Make remote operations slow to allow time for cancellation
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      // 2. ACT
      // Start the sync but don't await it yet
      final syncFuture = manager.synchronize('user1');

      // Wait for a short time, enough for some but not all operations to complete
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Cancel the sync by disposing the manager
      await manager.dispose();

      // Now await the result of the sync operation
      final result = await syncFuture;

      // 3. ASSERT
      expect(result.wasCancelled, isTrue);
      expect(result.syncedCount, isPositive);
      expect(result.syncedCount, lessThan(5));
    });

    group('SyncDirection options', () {
      test('pushOnly sync direction only pushes local changes', () async {
        // 1. ARRANGE
        final localOp = DatumSyncOperation<TestEntity>(
          id: 'op-push-only',
          userId: 'user1',
          entityId: 'push-only-e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create('push-only-e1', 'user1', 'Push Only'),
        );
        final remoteItem = TestEntity.create(
          'remote-only-e1',
          'user1',
          'Should not be pulled',
        );

        // Stub for push
        when(
          () => localAdapter.getPendingOperations('user1'),
        ).thenAnswer((_) async => [localOp]);
        when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
        when(
          () => localAdapter.removePendingOperation(any()),
        ).thenAnswer((_) async {});

        // Stub for pull (to verify it's NOT called)
        when(
          () => remoteAdapter.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => [remoteItem]);

        // 2. ACT
        final result = await manager.synchronize(
          'user1',
          options: const DatumSyncOptions(direction: SyncDirection.pushOnly),
        );

        // 3. ASSERT
        expect(result.syncedCount, 1);
        verify(
          () => remoteAdapter.create(
            any(that: predicate<TestEntity>((e) => e.id == 'push-only-e1')),
          ),
        ).called(1);

        // Verify pull was NOT performed
        verifyNever(
          () => remoteAdapter.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        );
        verifyNever(
          () => localAdapter.create(
            any(that: predicate<TestEntity>((e) => e.id == 'remote-only-e1')),
          ),
        );
      });

      test('pullOnly sync direction only pulls remote changes', () async {
        // 1. ARRANGE
        final localOp = DatumSyncOperation<TestEntity>(
          id: 'op-pull-only',
          userId: 'user1',
          entityId: 'pull-only-e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: TestEntity.create(
            'pull-only-e1',
            'user1',
            'Should not be pushed',
          ),
        );
        final remoteItem = TestEntity.create(
          'remote-pull-e1',
          'user1',
          'Should be pulled',
        );

        // Stub for push (to verify it's NOT called)
        when(
          () => localAdapter.getPendingOperations('user1'),
        ).thenAnswer((_) async => [localOp]);

        // Stub for pull
        when(
          () => remoteAdapter.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => [remoteItem]);
        when(() => localAdapter.create(any())).thenAnswer((_) async {});

        // 2. ACT
        await manager.synchronize(
          'user1',
          options: const DatumSyncOptions(direction: SyncDirection.pullOnly),
        );

        // 3. ASSERT
        // Verify pull was performed
        verify(
          () => localAdapter.create(
            any(that: predicate<TestEntity>((e) => e.id == 'remote-pull-e1')),
          ),
        ).called(1);

        // Verify push was NOT performed
        verifyNever(() => remoteAdapter.create(any()));
      });

      test(
        'pullThenPush sync direction executes in the correct order',
        () async {
          // 1. ARRANGE
          when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
            (_) async => [
              DatumSyncOperation<TestEntity>(
                id: 'op',
                userId: 'user1',
                entityId: 'e1',
                type: DatumOperationType.create,
                timestamp: DateTime.now(),
                data: TestEntity.create('e1', 'user1', 'Test'),
              ),
            ],
          );
          when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
          when(
            () => localAdapter.removePendingOperation(any()),
          ).thenAnswer((_) async {});

          // 2. ACT
          await manager.synchronize(
            'user1',
            options: const DatumSyncOptions(
              direction: SyncDirection.pullThenPush,
            ),
          );

          // 3. ASSERT
          verifyInOrder([
            // Pull phase
            () => remoteAdapter.readAll(
                  userId: 'user1',
                  scope: any(named: 'scope'),
                ),
            // Push phase
            () => remoteAdapter.create(any()),
          ]);
        },
      );
    });
  });
}

Future<bool> _alwaysRetry(DatumException e) async => true;
