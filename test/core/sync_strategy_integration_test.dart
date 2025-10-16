import 'dart:async';

import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

void main() {
  group('SyncExecutionStrategy Integration', () {
    late DatumManager<TestEntity> manager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late TestLogger logger;
    late List<DatumSyncOperation<TestEntity>> operations;

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
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 1);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      operations = List.generate(
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

      // Stub basic sync dependencies
      when(
        () => localAdapter.getPendingOperations(userId),
      ).thenAnswer((_) async => operations);
      when(
        () => localAdapter.removePendingOperation(any()),
      ).thenAnswer((_) async {});
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
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);

      // Default manager setup
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        logger: logger,
        datumConfig: const DatumConfig(),
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('with SequentialStrategy processes operations in order', () async {
      // Arrange
      final processedOrder = <String>[];
      when(() => remoteAdapter.create(any())).thenAnswer((inv) async {
        final entity = inv.positionalArguments.first as TestEntity;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        processedOrder.add(entity.id);
      });

      // Act
      final result = await manager.synchronize(userId);

      // Assert
      expect(result.failedCount, 0);
      expect(result.syncedCount, 5);
      expect(processedOrder, ['e0', 'e1', 'e2', 'e3', 'e4']);
    });

    test('with SequentialStrategy stops on error', () async {
      // Arrange
      final processedOrder = <String>[];
      final exception = Exception('Remote create failed');
      when(() => remoteAdapter.create(any())).thenAnswer((inv) async {
        final entity = inv.positionalArguments.first as TestEntity;
        if (entity.id == 'e2') throw exception;
        processedOrder.add(entity.id);
      });

      // Re-create manager for this specific strategy
      await manager.dispose();
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        logger: logger,
        datumConfig: const DatumConfig(
          syncExecutionStrategy: SequentialStrategy(),
        ),
      );
      await manager.initialize();

      // Act
      final syncFuture = manager.synchronize(userId);

      // Assert
      // The future should complete with the exception.
      await expectLater(syncFuture, throwsA(exception));

      // Verify that processing stopped after the error.
      expect(processedOrder, ['e0', 'e1']);

      // Verify that successful operations AND the failed one were dequeued.
      // The failed one is removed to prevent it from blocking the queue.
      verify(() => localAdapter.removePendingOperation('op0')).called(1);
      verify(() => localAdapter.removePendingOperation('op1')).called(1);
      verify(() => localAdapter.removePendingOperation('op2')).called(1);
    });

    group('with ParallelStrategy', () {
      test('processes all operations', () async {
        // Arrange
        final processedIds = <String>{};
        when(() => remoteAdapter.create(any())).thenAnswer((inv) async {
          final entity = inv.positionalArguments.first as TestEntity;
          // Simulate variable network delay
          await Future<void>.delayed(
            Duration(milliseconds: 10 + entity.id.hashCode % 10),
          );
          processedIds.add(entity.id);
        });

        // Re-create manager for this specific strategy
        await manager.dispose();
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(
            syncExecutionStrategy: ParallelStrategy(batchSize: 2),
          ),
        );
        await manager.initialize();

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.failedCount, 0);
        expect(result.syncedCount, 5);
        expect(processedIds, {'e0', 'e1', 'e2', 'e3', 'e4'});
      });

      test('handles errors correctly', () async {
        // Arrange
        final exception = Exception('Remote push failed');
        when(() => remoteAdapter.create(any())).thenAnswer((inv) async {
          final entity = inv.positionalArguments.first as TestEntity;
          if (entity.id == 'e2') throw exception;
          // For other entities, complete successfully.
        });

        // Re-create manager for this specific strategy
        await manager.dispose();
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(
            syncExecutionStrategy: ParallelStrategy(batchSize: 2),
          ),
        );
        await manager.initialize();

        // Act & Assert
        // Set up expectations for both the thrown exception and the emitted event.
        final syncThrowsFuture = expectLater(
          () => manager.synchronize(userId),
          throwsA(exception),
        );
        final errorEventFuture = expectLater(
          manager.onSyncError,
          emits(isA<DatumSyncErrorEvent>()),
        );

        // Await both futures concurrently to avoid a race condition where the
        // event is emitted before the test awaits it.
        await Future.wait([syncThrowsFuture, errorEventFuture]);
      });

      test(
        'with failFast: false processes all operations despite errors',
        () async {
          // Arrange
          final exception1 = Exception('Remote push failed 1');
          final exception2 = Exception('Remote push failed 2');
          final processedIds = <String>{};

          when(() => remoteAdapter.create(any())).thenAnswer((inv) async {
            final entity = inv.positionalArguments.first as TestEntity;
            if (entity.id == 'e1') throw exception1;
            if (entity.id == 'e4') throw exception2;
            processedIds.add(entity.id);
          });

          // Re-create manager for this specific strategy
          await manager.dispose();
          manager = DatumManager<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
            connectivity: connectivityChecker,
            logger: logger,
            datumConfig: const DatumConfig(
              syncExecutionStrategy: ParallelStrategy(
                batchSize: 2,
                failFast: false,
              ),
            ),
          );
          await manager.initialize();

          // Act
          final syncFuture = manager.synchronize(userId);

          // Assert
          // The future should complete with the first exception thrown.
          await expectLater(syncFuture, throwsA(exception1));

          // Even though the sync failed, all non-failing operations should have
          // been processed because failFast is false.
          expect(processedIds, {'e0', 'e2', 'e3'});

          // Verify that the local queue manager removed ALL operations.
          // Successful ones are dequeued on success, and failed ones are
          // dequeued to prevent blocking the queue.
          verify(() => localAdapter.removePendingOperation(any())).called(5);
        },
      );
    });

    group('with IsolateStrategy', () {
      test('processes all operations successfully', () async {
        // Arrange
        final processedIds = <String>{};
        when(() => remoteAdapter.create(any())).thenAnswer((inv) async {
          final entity = inv.positionalArguments.first as TestEntity;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          processedIds.add(entity.id);
        });

        // Re-create manager for this specific strategy
        await manager.dispose();
        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          logger: logger,
          datumConfig: const DatumConfig(
            syncExecutionStrategy: IsolateStrategy(SequentialStrategy()),
          ),
        );
        await manager.initialize();

        // Act
        final result = await manager.synchronize(userId);

        // Assert
        expect(result.failedCount, 0);
        expect(result.syncedCount, 5);
        expect(processedIds, {'e0', 'e1', 'e2', 'e3', 'e4'});
        verify(() => localAdapter.removePendingOperation(any())).called(5);
      });

      test('handles errors correctly', () async {
        // Arrange
        // Isolate this test's mocks to prevent interference from the group's setUp.
        final isolatedLocalAdapter = MockLocalAdapter<TestEntity>();
        final isolatedRemoteAdapter = MockRemoteAdapter<TestEntity>();
        final isolatedConnectivityChecker = MockConnectivityChecker();
        final isolatedLogger = TestLogger();

        // Default stubs for this test's mocks
        when(isolatedLocalAdapter.initialize).thenAnswer((_) async {});
        when(() => isolatedRemoteAdapter.initialize()).thenAnswer((_) async {});
        when(() => isolatedLocalAdapter.dispose()).thenAnswer((_) async {});
        when(() => isolatedRemoteAdapter.dispose()).thenAnswer((_) async {});
        when(
          () => isolatedLocalAdapter.getStoredSchemaVersion(),
        ).thenAnswer((_) async => 1);
        when(() => isolatedLocalAdapter.changeStream()).thenAnswer(
          (_) => const Stream<DatumChangeDetail<TestEntity>>.empty(),
        );
        when(() => isolatedRemoteAdapter.changeStream).thenAnswer(
          (_) => const Stream<DatumChangeDetail<TestEntity>>.empty(),
        );
        when(
          () => isolatedConnectivityChecker.isConnected,
        ).thenAnswer((_) async => true);

        final exception = Exception('Isolate push failed');
        final processedIds = <String>{};

        // Re-create manager for this specific strategy
        await manager.dispose();
        manager = DatumManager<TestEntity>(
          localAdapter: isolatedLocalAdapter,
          remoteAdapter: isolatedRemoteAdapter,
          connectivity: isolatedConnectivityChecker,
          logger: isolatedLogger,
          datumConfig: DatumConfig(
            // Using a fail-fast strategy inside the isolate is the most
            // logical approach, as we want errors to propagate out immediately.
            syncExecutionStrategy: IsolateStrategy(
              const ParallelStrategy(batchSize: 2, failFast: true),
            ),
          ),
        );
        await manager.initialize();

        // Stub the behavior for this specific test
        when(() => isolatedRemoteAdapter.create(any())).thenAnswer((inv) async {
          final entity = inv.positionalArguments.first as TestEntity;
          if (entity.id == 'e3') throw exception;
          processedIds.add(entity.id);
        });
        when(
          () => isolatedLocalAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => operations);
        when(
          () => isolatedLocalAdapter.removePendingOperation(any()),
        ).thenAnswer((_) async {});
        when(
          () => isolatedLocalAdapter.readAll(userId: any(named: 'userId')),
        ).thenAnswer((_) async => []);
        when(
          () => isolatedLocalAdapter.readByIds(
            any(),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async => {});
        when(
          () => isolatedLocalAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => remoteAdapter.updateSyncMetadata(any(), any()),
        ).thenAnswer((_) async {});

        // Act
        final syncFuture = manager.synchronize(userId);

        // Assert
        // The future should complete with the error from the isolate.
        // We use `expectLater` with `throwsA` to correctly handle the
        // asynchronous error propagation from the sync engine.
        await expectLater(syncFuture, throwsA(exception));

        // Verify that operations in the successful batches were processed.
        expect(processedIds, {'e0', 'e1', 'e2'});

        // Verify that successful operations and the failed one were dequeued.
        verify(
          () => isolatedLocalAdapter.removePendingOperation('op0'),
        ).called(1);
        verify(
          () => isolatedLocalAdapter.removePendingOperation('op1'),
        ).called(1);
        verify(
          () => isolatedLocalAdapter.removePendingOperation('op2'),
        ).called(1);
        verify(
          () => isolatedLocalAdapter.removePendingOperation('op3'),
        ).called(1);
      });

      test(
        'with forceIsolateInTest correctly processes operations in a real isolate',
        () async {
          // This test uses the special TestIsolateStrategy to bypass the `isTest`
          // check and test the actual isolate communication logic.

          // Arrange
          final processedInIsolate = <String>[];
          final progressUpdates = <(int, int)>[];
          final completer = Completer<void>();

          // The `processOperation` function will be sent from the main isolate
          // to the worker isolate to be executed.
          Future<void> processOp(DatumSyncOperation<TestEntity> op) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            processedInIsolate.add(op.id);
          }

          void onProgress(int completed, int total) {
            progressUpdates.add((completed, total));
            if (completed == operations.length) {
              completer.complete();
            }
          }

          // Use the test strategy to force isolate spawning.
          const strategy = IsolateStrategy(
            SequentialStrategy(),
            forceIsolateInTest: true,
          );

          // Act
          // We call the strategy directly, not through the manager, to test it in isolation.
          // The manager's mocks would be too complex to pass into a real isolate.
          strategy.execute<TestEntity>(
            operations,
            processOp,
            () => false, // isCancelled
            onProgress,
          );

          // Assert
          // Wait for the completer, which is triggered when the last progress update is received.
          await completer.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('Isolate test timed out'),
          );

          expect(
            processedInIsolate,
            ['op0', 'op1', 'op2', 'op3', 'op4'],
            reason: 'All operations should be processed in order.',
          );
          expect(
            progressUpdates,
            [(1, 5), (2, 5), (3, 5), (4, 5), (5, 5)],
            reason: 'Progress should be reported for each completed operation.',
          );
        },
        // Isolates can be slow to spin up, so a longer timeout is safer.
        timeout: const Timeout(Duration(seconds: 5)),
      );
    });
  });
}
