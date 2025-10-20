import 'dart:async';

import 'package:datum/datum.dart';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:rxdart/rxdart.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';
import 'datum_config_test.dart';

class MockIsolateHelper extends Mock implements IsolateHelper {}

class MockLocalAdapter<T extends DatumEntity> extends Mock implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock implements RemoteAdapter<T> {}

class MockLogger extends Mock implements DatumLogger {}

void main() {
  group('DatumSyncEngine', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late QueueManager<TestEntity> queueManager;
    late MockConnectivityChecker connectivity;
    late StreamController<DatumSyncEvent<TestEntity>> eventController;
    late BehaviorSubject<DatumSyncStatusSnapshot> statusSubject;
    late BehaviorSubject<DatumSyncMetadata> metadataSubject;
    late MockIsolateHelper isolateHelper;
    late MockLogger logger;
    late DatumSyncEngine<TestEntity> syncEngine;

    setUpAll(() {
      registerFallbackValue(
        const DatumSyncMetadata(
          userId: 'fb',
          lastSyncTime: null,
          dataHash: 'fb',
        ),
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
      registerFallbackValue(
        DatumConflictContext(
          userId: 'fb',
          entityId: 'fb',
          type: DatumConflictType.bothModified,
          detectedAt: DateTime(0),
        ),
      );
    });
    setUp(() {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      final pendingOpsByUser = <String, List<DatumSyncOperation<TestEntity>>>{};
      final localItemsByUser = <String, List<TestEntity>>{};

      queueManager = QueueManager<TestEntity>(
        localAdapter: localAdapter,
        logger: DatumLogger(enabled: false),
      );
      connectivity = MockConnectivityChecker();
      eventController = StreamController<DatumSyncEvent<TestEntity>>.broadcast();
      statusSubject = BehaviorSubject<DatumSyncStatusSnapshot>.seeded(
        DatumSyncStatusSnapshot.initial(''),
      );
      logger = MockLogger();
      metadataSubject = BehaviorSubject<DatumSyncMetadata>();
      isolateHelper = MockIsolateHelper();

      syncEngine = DatumSyncEngine<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: LastWriteWinsResolver<TestEntity>(),
        queueManager: queueManager,
        conflictDetector: DatumConflictDetector<TestEntity>(),
        logger: logger,
        config: const DatumConfig(),
        connectivityChecker: connectivity,
        eventController: eventController,
        statusSubject: statusSubject,
        metadataSubject: metadataSubject,
        isolateHelper: isolateHelper,
      );

      // Add default stubs for methods called during sync
      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => logger.info(any())).thenAnswer((_) {});
      when(() => logger.warn(any())).thenAnswer((_) {});
      when(() => logger.debug(any())).thenAnswer((_) {});
      when(() => logger.error(any(), any())).thenAnswer((_) {});
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
      when(() => remoteAdapter.update(any())).thenAnswer((_) async {});
      when(
        () => remoteAdapter.delete(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});

      // Stateful mock for pending operations
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((
        inv,
      ) async {
        final userId = inv.positionalArguments.first as String;
        return pendingOpsByUser[userId] ?? [];
      });
      when(() => localAdapter.addPendingOperation(any(), any())).thenAnswer((
        inv,
      ) async {
        final userId = inv.positionalArguments[0] as String;
        final op = inv.positionalArguments[1] as DatumSyncOperation<TestEntity>;
        pendingOpsByUser.putIfAbsent(userId, () => []).add(op);
      });
      when(() => localAdapter.removePendingOperation(any())).thenAnswer((
        inv,
      ) async {
        final opId = inv.positionalArguments.first as String;
        for (final ops in pendingOpsByUser.values) {
          ops.removeWhere((op) => op.id == opId);
        }
      });

      when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer(
        (inv) async {
          final userId = inv.namedArguments[#userId] as String?;
          return localItemsByUser[userId] ?? [];
        },
      );
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.getLastSyncResult(any()),
      ).thenAnswer((_) async => null);
      when(() => localAdapter.update(any())).thenAnswer((_) async {});
      when(() => localAdapter.create(any())).thenAnswer((inv) async {
        final item = inv.positionalArguments.first as TestEntity;
        localItemsByUser.putIfAbsent(item.userId, () => []).add(item);
      });
      when(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async => TestEntity.create('e1', 'user-1', 'patched'));
    });

    tearDown(() async {
      await eventController.close();
      await statusSubject.close();
      await metadataSubject.close();
    });

    test(
      'does not push anything if remote is empty and there are no pending ops',
      () async {
        // Arrange: Local adapter has an item, but it's not in the pending queue.
        // Remote is empty.
        when(() => localAdapter.readAll(userId: 'user-1')).thenAnswer(
          (_) async => [TestEntity.create('e1', 'user-1', 'Local Only')],
        );

        // Act
        final (result, _) = await syncEngine.synchronize('user-1');

        // Assert: Nothing should be pushed because there are no pending operations.
        verifyNever(() => remoteAdapter.create(any()));

        // The sync should still be "successful" as it completed without errors.
        expect(result.failedCount, 0);
        expect(result.syncedCount, 0);
      },
    );

    test('pushes pending create operation to remote', () async {
      // Arrange: A new item is created, which should generate a pending operation.
      final newEntity = TestEntity.create('e1', 'user-1', 'New Item');
      final operation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user-1',
        entityId: newEntity.id,
        type: DatumOperationType.create,
        timestamp: DateTime.now(),
        data: newEntity,
      );
      await queueManager.enqueue(operation);

      // Act
      final (result, _) = await syncEngine.synchronize('user-1');

      // Assert: The new entity should be pushed to the remote.
      verify(() => remoteAdapter.create(newEntity)).called(1);

      // The operation should be marked as synced.
      expect(result.syncedCount, 1);
      expect(result.failedCount, 0);
      final pendingOps = await localAdapter.getPendingOperations('user-1');
      expect(pendingOps, isEmpty);
    });

    test('pushes pending update operation to remote', () async {
      // Arrange
      final updatedEntity = TestEntity.create('e1', 'user-1', 'Updated Item');
      final operation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user-1',
        entityId: updatedEntity.id,
        type: DatumOperationType.update,
        timestamp: DateTime.now(),
        data: updatedEntity,
        delta: const {'name': 'Updated Item'},
      );
      await queueManager.enqueue(operation);

      // Act
      final (result, _) = await syncEngine.synchronize('user-1');

      // Verify that patch was called because a delta was provided
      verify(
        () => remoteAdapter.patch(
          id: updatedEntity.id,
          delta: any(named: 'delta', that: isA<Map<String, dynamic>>()),
          userId: 'user-1',
        ),
      ).called(1);

      expect(result.syncedCount, 1);
      final pendingOps = await localAdapter.getPendingOperations('user-1');
      expect(pendingOps, isEmpty);
    });

    test('pushes pending update with full data when delta is null', () async {
      // Arrange
      final updatedEntity = TestEntity.create('e1', 'user-1', 'Updated Item');
      final operation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user-1',
        entityId: updatedEntity.id,
        type: DatumOperationType.update,
        timestamp: DateTime.now(),
        data: updatedEntity,
        delta: null, // No delta
      );
      await queueManager.enqueue(operation);

      // Act
      await syncEngine.synchronize('user-1');

      // Assert: The full update method should be called, not patch.
      verify(() => remoteAdapter.update(updatedEntity)).called(1);
      verifyNever(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
        ),
      );
    });

    test('pushes pending delete operation to remote', () async {
      // Arrange
      final operation = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'user-1',
        entityId: 'e1',
        type: DatumOperationType.delete,
        timestamp: DateTime.now(),
      );
      await queueManager.enqueue(operation);

      // Act
      final (result, _) = await syncEngine.synchronize('user-1');

      // Assert
      verify(() => remoteAdapter.delete('e1', userId: 'user-1')).called(1);
      expect(result.syncedCount, 1);
      final pendingOps = await localAdapter.getPendingOperations('user-1');
      expect(pendingOps, isEmpty);
    });

    test('skips sync when offline', () async {
      // Arrange
      when(() => connectivity.isConnected).thenAnswer((_) async => false);

      // Act
      final (result, _) = await syncEngine.synchronize('user-1');

      // Assert
      expect(result.wasSkipped, isTrue);
      expect(result.syncedCount, 0);

      // Verify no remote calls were made
      verifyNever(() => remoteAdapter.create(any()));
    });

    test(
      'synchronize still skips if force: true is used while a sync is in progress',
      () async {
        // Arrange
        final syncCompleter = Completer<List<TestEntity>>();
        // Make the first sync call hang by blocking the remote adapter
        when(
          () => remoteAdapter.readAll(
            userId: any(named: 'userId'),
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) => syncCompleter.future);

        // Act
        // Start the first sync, but don't await it
        final firstSyncFuture = syncEngine.synchronize('user-1');

        // Give it a moment to start and set the status to 'syncing'
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Start the second sync with force: true while the first is blocked
        final (secondSyncResult, _) = await syncEngine.synchronize(
          'user-1',
          force: true,
        );

        // Assert: The sync should still be skipped to prevent re-entrancy.
        expect(secondSyncResult.wasSkipped, isTrue);

        // Clean up
        syncCompleter.complete([]);
        await firstSyncFuture;
      },
    );

    test(
      'logs an error when a delete operation fails with EntityNotFoundException',
      () async {
        // Arrange
        final exception = EntityNotFoundException(
          'Entity e1 not found on remote.',
        );
        final operation = DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user-1',
          entityId: 'e1',
          type: DatumOperationType.delete,
          timestamp: DateTime.now(),
        );
        await queueManager.enqueue(operation);

        // Stub the remote delete to throw the exception
        when(
          () => remoteAdapter.delete('e1', userId: 'user-1'),
        ).thenThrow(exception);

        // Act & Assert
        // The synchronize call should re-throw the exception, wrapped in a SyncException.
        await expectLater(
          syncEngine.synchronize('user-1'),
          throwsA(
            isA<SyncExceptionWithEvents>().having(
              (e) => e.originalError,
              'originalError',
              exception,
            ),
          ),
        );

        // Verify that the specific error was logged.
        verify(
          () => logger.error('Operation op1 failed: $exception', any()),
        ).called(1);
      },
    );
    test('logs an error when metadata update fails', () async {
      // Arrange
      final exception = Exception('Failed to save metadata');
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenThrow(exception);

      // Act & Assert
      // The synchronize call should re-throw the exception from the metadata update.
      await expectLater(
        syncEngine.synchronize('user-1'),
        throwsA(
          isA<SyncExceptionWithEvents>().having(
            (e) => e.originalError,
            'originalError',
            exception,
          ),
        ),
      );

      // Verify that the specific error was logged.
      verify(
        () => logger.error(
          'Failed to update sync metadata for user user-1: $exception',
          any(),
        ),
      ).called(1);
    });
    group('Operation Data Validation', () {
      test('throws ArgumentError for create operation without data', () async {
        // Arrange
        final operation = DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user-1',
          entityId: 'e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: null, // Missing data
        );
        await queueManager.enqueue(operation);

        // Act & Assert
        expect(
          syncEngine.synchronize('user-1'),
          throwsA(
            isA<SyncExceptionWithEvents>().having(
              (e) => e.originalError,
              'originalError',
              isA<ArgumentError>(),
            ),
          ),
        );
      });

      test('throws ArgumentError for update operation without data', () async {
        // Arrange
        final operation = DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user-1',
          entityId: 'e1',
          type: DatumOperationType.update,
          timestamp: DateTime.now(),
          data: null, // Missing data
        );
        await queueManager.enqueue(operation);

        // Act & Assert
        expect(
          syncEngine.synchronize('user-1'),
          throwsA(
            isA<SyncExceptionWithEvents>().having(
              (e) => e.originalError,
              'originalError',
              isA<ArgumentError>(),
            ),
          ),
        );
      });
    });

    group('Conflict Resolution Logging', () {
      setUp(() {
        final remoteItem = TestEntity.create(
          'e1',
          'user-1',
          'Remote',
        ).copyWith(version: 2);
        final localItem = TestEntity.create(
          'e1',
          'user-1',
          'Local',
        ).copyWith(version: 1);

        when(
          () => remoteAdapter.readAll(userId: 'user-1'),
        ).thenAnswer((_) async => [remoteItem]);
        when(
          () => localAdapter.readByIds(['e1'], userId: 'user-1'),
        ).thenAnswer((_) async => {'e1': localItem});
      });

      test('logs a warning when conflict resolution is aborted', () async {
        // Arrange
        final resolver = MockConflictResolver<TestEntity>();
        when(
          () => resolver.resolve(
            local: any(named: 'local'),
            remote: any(named: 'remote'),
            context: any(named: 'context'),
          ),
        ).thenAnswer((_) async => const DatumConflictResolution.abort('Test'));

        final engineWithCustomResolver = DatumSyncEngine<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          conflictResolver: resolver, // Use the custom resolver
          queueManager: queueManager,
          conflictDetector: DatumConflictDetector<TestEntity>(),
          logger: logger,
          config: const DatumConfig(),
          connectivityChecker: connectivity,
          eventController: eventController,
          statusSubject: statusSubject,
          metadataSubject: metadataSubject,
          isolateHelper: isolateHelper,
        );

        // Act
        await engineWithCustomResolver.synchronize('user-1');

        // Assert
        verify(() => logger.warn(any(that: contains('aborted')))).called(1);
      });

      test(
        'logs a warning when conflict resolution requires user input',
        () async {
          // Arrange
          final resolver = MockConflictResolver<TestEntity>();
          when(
            () => resolver.resolve(
              local: any(named: 'local'),
              remote: any(named: 'remote'),
              context: any(named: 'context'),
            ),
          ).thenAnswer(
            (_) async => const DatumConflictResolution.requireUserInput('Needs user choice'),
          );

          final engineWithCustomResolver = DatumSyncEngine<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
            conflictResolver: resolver, // Use the custom resolver
            queueManager: queueManager,
            conflictDetector: DatumConflictDetector<TestEntity>(),
            logger: logger,
            config: const DatumConfig(),
            connectivityChecker: connectivity,
            eventController: eventController,
            statusSubject: statusSubject,
            metadataSubject: metadataSubject,
            isolateHelper: isolateHelper,
          );

          // Act
          await engineWithCustomResolver.synchronize('user-1');

          // Assert
          verify(
            () => logger.warn(any(that: contains('requires user input'))),
          ).called(1);
        },
      );

      test('throws StateError if merge resolution has no data', () async {
        // Arrange
        final resolver = MockConflictResolver<TestEntity>();
        when(
          () => resolver.resolve(
            local: any(named: 'local'),
            remote: any(named: 'remote'),
            context: any(named: 'context'),
          ),
        ).thenAnswer(
          // We can't call the private `_` constructor.
          // To test the StateError, we can simulate an invalid resolution
          // by using a valid constructor and then creating an invalid state.
          (_) async => DatumConflictResolution.merge(
            TestEntity.create('e1', 'user-1', 'Merged'),
          ).copyWith(setResolvedDataToNull: true),
        );

        final engineWithCustomResolver = DatumSyncEngine<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          conflictResolver: resolver,
          queueManager: queueManager,
          conflictDetector: DatumConflictDetector<TestEntity>(),
          logger: logger,
          config: const DatumConfig(),
          connectivityChecker: connectivity,
          eventController: eventController,
          statusSubject: statusSubject,
          metadataSubject: metadataSubject,
          isolateHelper: isolateHelper,
        );

        // Act & Assert
        await expectLater(
          engineWithCustomResolver.synchronize('user-1'),
          throwsA(
            isA<SyncExceptionWithEvents>().having(
              (e) => e.originalError,
              'originalError',
              isA<StateError>(),
            ),
          ),
        );
      });
    });

    test('emits DatumSyncMetadata on successful sync', () async {
      // Arrange
      when(() => localAdapter.readAll(userId: 'user-1')).thenAnswer(
        (_) async => [TestEntity.create('e1', 'user-1', 'Metadata Test')],
      );
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(() => localAdapter.create(any())).thenAnswer((_) async {});

      final futureMetadata = metadataSubject.stream.first;

      // Act
      await syncEngine.synchronize('user-1');

      // Assert
      final metadata = await futureMetadata;
      expect(metadata, isNotNull);
      expect(metadata.userId, 'user-1');
      expect(metadata.dataHash, 'testhash');

      final entityCounts = metadata.entityCounts;
      expect(entityCounts, isNotNull);
      expect(entityCounts, isNotEmpty);

      final testEntityDetails = entityCounts!['TestEntity'];
      expect(testEntityDetails, isNotNull);
      expect(
        testEntityDetails!.count,
        1,
        reason: 'Metadata should reflect the item count from localAdapter.readAll',
      );
      expect(
        testEntityDetails.hash,
        'testhash',
        reason: 'Entity-specific hash should be generated',
      );

      expect(
        metadata.lastSyncTime!.isAfter(
          DateTime.now().subtract(const Duration(seconds: 5)),
        ),
        isTrue,
        reason: 'lastSyncTime should be recent',
      );
    });

    test(
      'correctly updates DatumSyncMetadata after a pull operation',
      () async {
        // Arrange: Remote has one item, local has none.
        final remoteEntity = TestEntity.create('e1', 'user-1', 'Remote Item');
        when(
          () => remoteAdapter.readAll(userId: 'user-1'),
        ).thenAnswer((_) async => [remoteEntity]);

        // When create is called, update the state that readAll will use.
        final localItems = <TestEntity>[];
        when(() => localAdapter.create(any())).thenAnswer((inv) async {
          localItems.add(inv.positionalArguments.first as TestEntity);
        });
        when(
          () => localAdapter.readAll(userId: 'user-1'),
        ).thenAnswer((_) async => localItems);

        // Act
        await syncEngine.synchronize('user-1');

        // Assert: Check the captured metadata.
        // Capture the metadata that is saved to both local and remote adapters.
        final captured = verify(
          () => localAdapter.updateSyncMetadata(captureAny(), 'user-1'),
        ).captured;
        expect(captured, hasLength(1));
        final finalMetadata = captured.first as DatumSyncMetadata;

        expect(finalMetadata, isNotNull);

        // Use a local variable to help flow analysis
        final meta = finalMetadata;

        expect(meta.userId, 'user-1');
        expect(meta.entityCounts, isNotNull);

        final entityDetails = meta.entityCounts!['TestEntity'];
        expect(entityDetails, isNotNull);
        expect(
          entityDetails!.count,
          1,
          reason: 'Metadata count should be 1 after pulling one item.',
        );
        expect(
          entityDetails.hash,
          'testhash',
          reason: 'A new hash should be computed based on the new local state.',
        );
      },
    );
  });
}
