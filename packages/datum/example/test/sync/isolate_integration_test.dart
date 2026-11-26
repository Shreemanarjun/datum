import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/models/datum_change_detail.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:datum/source/core/sync/datum_sync_execution_strategy.dart'
    hide IsolateStrategy;
import 'package:datum/source/utils/connectivity_checker.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:example/sync/isolate_stratergy.dart';
import 'package:example/sync/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// Use proper mocktail mocks for adapters
class MockLocalAdapter<T extends DatumEntityInterface> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock
    implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock
    implements DatumConnectivityChecker {}

/// A custom logger for tests that omits stack traces for cleaner output.
class TestLogger extends DatumLogger {
  TestLogger() : super(enabled: true);

  @override
  void error(String message, [StackTrace? stackTrace]) {
    super.error(message); // Call the base method without the stack trace.
  }
}

void main() {
  group('with IsolateStrategy', () {
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
      when(
        () => localAdapter.getLastSyncResult(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.saveLastSyncResult(any(), any()),
      ).thenAnswer((_) async {});
      when(() => localAdapter.getSyncMetadata(any()))
          .thenAnswer((_) async => null);
      when(() => remoteAdapter.getSyncMetadata(any()))
          .thenAnswer((_) async => null);

      // Default manager setup
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker, // Now required
        logger: logger,
        datumConfig: const DatumConfig(),
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });
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
        connectivity: connectivityChecker, // Now required
        logger: logger,
        datumConfig: const DatumConfig(
          syncExecutionStrategy: IsolateStrategy(SequentialStrategy()),
          remoteSyncBatchSize: 1,
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
      // Add the missing stubs for the sync lifecycle
      when(() => isolatedLocalAdapter.getLastSyncResult(any()))
          .thenAnswer((_) async => null);
      when(() => isolatedLocalAdapter.saveLastSyncResult(any(), any()))
          .thenAnswer((_) async {});
      when(() => isolatedLocalAdapter.getSyncMetadata(any()))
          .thenAnswer((_) async => null);
      when(() => isolatedRemoteAdapter.getSyncMetadata(any()))
          .thenAnswer((_) async => null);

      final exception = UnknownException(
        message: 'Isolate push failed',
      );
      final processedIds = <String>{};

      // Re-create manager for this specific strategy
      await manager.dispose();
      manager = DatumManager<TestEntity>(
        localAdapter: isolatedLocalAdapter,
        remoteAdapter: isolatedRemoteAdapter,
        connectivity: isolatedConnectivityChecker, // Now required
        logger: isolatedLogger,
        datumConfig: const DatumConfig(
          // Using a fail-fast strategy inside the isolate is the most
          // logical approach, as we want errors to propagate out immediately.
          syncExecutionStrategy: IsolateStrategy(
            ParallelStrategy(batchSize: 2, failFast: true),
          ),
          remoteSyncBatchSize: 1,
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
        () => isolatedLocalAdapter.addPendingOperation(any(), any()),
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

      // Assert
      // The future should complete with the error from the isolate.
      // We wrap the call in a closure `() => ...` so that `expectLater`
      // can correctly catch the asynchronous error. The sync engine wraps
      // the original exception, but the manager re-throws the original error.
      await expectLater(
        () => manager.synchronize(userId),
        // IMPORTANT: When testing exceptions that cross isolate boundaries,
        // do NOT use `throwsA(exceptionInstance)`.
        //
        // When an exception is passed from a worker isolate to the main
        // isolate, it is serialized and a *new* exception object is created
        // in the main isolate. This new object will have the same message,
        // but it will not be the same instance as the original.
        //
        // Therefore, we must check the exception's type and properties
        // (like its message via `toString()`) to ensure the test is robust.
        throwsA(isA<UnknownException>().having(
          (e) => e.message,
          'message',
          'Isolate push failed',
        )),
      );

      // Verify that operations in the successful batches were processed.
      expect(processedIds, {'e0', 'e1', 'e2'});

      // Successful operations are dequeued; the failed one is parked.
      verify(
        () => isolatedLocalAdapter.removePendingOperation('op0'),
      ).called(1);
      verify(
        () => isolatedLocalAdapter.removePendingOperation('op1'),
      ).called(1);
      verify(
        () => isolatedLocalAdapter.removePendingOperation('op2'),
      ).called(1);
      verifyNever(
        () => isolatedLocalAdapter.removePendingOperation('op3'),
      );
      final parked = verify(
        () => isolatedLocalAdapter.addPendingOperation(userId, captureAny()),
      ).captured.single as DatumSyncOperation;
      expect((parked.id, parked.isParked), ('op3', true));
    });

    test(
      'with forceIsolateInTest correctly processes operations in a real isolate',
      () async {
        // This test uses the special TestIsolateStrategy to bypass the `isTest`
        // check and test the actual isolate communication logic.

        // Arrange
        final processedInIsolate = <String>[]; // To track execution order

        // The `processOperation` function will be sent from the main isolate
        // to the worker isolate to be executed.

        // Use the test strategy to force isolate spawning.
        const strategy = IsolateStrategy(
          SequentialStrategy(),
          forceIsolateInTest: true,
        );

        // Act
        // We call the strategy directly, not through the manager, to test it in isolation.
        // The manager's mocks would be too complex to pass into a real isolate.
        // Awaiting the future returned by `execute` is cleaner than using a Completer.
        await strategy.execute<TestEntity>(
          operations,
          (op) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            processedInIsolate.add(op.id);
          },
          () => false, // isCancelled
          (completed, total) {}, // onProgress can be a no-op for this test
        );

        // Assert
        expect(
          processedInIsolate,
          ['op0', 'op1', 'op2', 'op3', 'op4'],
          reason: 'All operations should be processed in order.',
        );
      },
      // Isolates can be slow to spin up, so a longer timeout is safer.
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });
}
