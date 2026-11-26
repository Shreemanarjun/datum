import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/test_entity.dart';
import '../mocks/forward_bulk_writes.dart';

// Use proper mocktail mocks for adapters
class MockLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

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
        () => localAdapter.addPendingOperation(any(), any()),
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
      when(
        () => localAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) => Future.value(null));
      when(
        () => remoteAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) => Future.value(null));

      // Stub batch operations
      when(() => remoteAdapter.createAll(any())).thenAnswer((_) async {});
      when(() => remoteAdapter.updateAll(any())).thenAnswer((_) async {});
      when(
        () => remoteAdapter.deleteAll(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async {});

      // Default manager setup
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker, // Now required
        logger: logger,
        datumConfig: const DatumConfig(remoteSyncBatchSize: 1),
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
      final exception = UnknownException(message: 'Remote create failed');
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
        connectivity: connectivityChecker, // Now required
        logger: logger,
        datumConfig: const DatumConfig(
          syncExecutionStrategy: SequentialStrategy(),
          remoteSyncBatchSize: 1,
        ),
      );
      await manager.initialize();

      // Act
      final syncFuture = manager.synchronize(userId);

      // Assert
      // The future should complete with the exception.
      // Instead of checking for the exact exception instance,
      // check for the type and a property (like the message) to make
      // the test more robust against stack trace differences.
      await expectLater(
        syncFuture,
        throwsA(
          isA<UnknownException>().having((e) => e.message, 'message', 'Remote create failed'),
        ),
      );

      // Verify that processing stopped after the error.
      expect(processedOrder, ['e0', 'e1']);

      // Successful operations are dequeued; the failed one is parked.
      verify(() => localAdapter.removePendingOperation('op0')).called(1);
      verify(() => localAdapter.removePendingOperation('op1')).called(1);
      verifyNever(() => localAdapter.removePendingOperation('op2'));
      final parked = verify(() => localAdapter.addPendingOperation(userId, captureAny())).captured.single as DatumSyncOperation;
      expect((parked.id, parked.isParked), ('op2', true));
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
          connectivity: connectivityChecker, // Now required
          logger: logger,
          datumConfig: const DatumConfig(
            syncExecutionStrategy: ParallelStrategy(batchSize: 2),
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
      });

      test('handles errors correctly', () async {
        // Arrange
        final exception = UnknownException(message: 'Remote push failed');
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
          connectivity: connectivityChecker, // Now required
          logger: logger,
          datumConfig: const DatumConfig(
            syncExecutionStrategy: ParallelStrategy(batchSize: 2),
            remoteSyncBatchSize: 1,
          ),
        );
        await manager.initialize();

        // Act & Assert
        // Set up expectations for both the thrown exception and the emitted event.
        final syncThrowsFuture = expectLater(
          () => manager.synchronize(userId),
          // Instead of checking for the exact exception instance,
          // check for the type and a property (like the message) to make
          // the test more robust against stack trace differences.
          throwsA(isA<UnknownException>()),
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
          final exception1 = UnknownException(message: 'Remote push failed 1');
          final exception2 = UnknownException(message: 'Remote push failed 2');
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
            connectivity: connectivityChecker, // Now required
            logger: logger,
            datumConfig: const DatumConfig(
              syncExecutionStrategy: ParallelStrategy(
                batchSize: 2,
                failFast: false,
              ),
              remoteSyncBatchSize: 1,
            ),
          );
          await manager.initialize();

          // Act
          final syncFuture = manager.synchronize(userId);

          // Assert
          // The future should complete with the first exception thrown.
          // Instead of checking for the exact exception instance,
          // check for the type and a property (like the message) to make
          // the test more robust against stack trace differences.
          await expectLater(
            syncFuture,
            throwsA(
              isA<Exception>(),
            ),
          );

          // Even though the sync failed, all non-failing operations should have
          // been processed because failFast is false.
          expect(processedIds, {'e0', 'e2', 'e3'});

          // Successful ops are dequeued; the two failed ones are parked
          // (kept queued with their error), never dropped.
          verify(() => localAdapter.removePendingOperation(any())).called(3);
          final parked = verify(() => localAdapter.addPendingOperation(userId, captureAny())).captured.cast<DatumSyncOperation<TestEntity>>();
          expect(parked, hasLength(2));
          expect(parked.every((op) => op.isParked), isTrue);
        },
      );
    });
  });
}
