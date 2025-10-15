import 'dart:async';

import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// Use mocktail mocks instead of hand-written ones for `when()` to work.
class MockLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

void main() {
  group('DatumMetrics Integration', () {
    // This needs to be defined at the top level for the fallback registration
    final now = DateTime.now();
    final baseEntity = TestEntity(
      id: 'conflict-entity',
      userId: 'user-metrics',
      name: 'Base',
      value: 1,
      modifiedAt: now,
      createdAt: now,
      version: 1,
    );

    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late Datum datum;

    const userId = 'user-metrics';

    setUpAll(() {
      // Register fallback values for any custom types used in `when()`
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fallback-op',
          userId: 'fallback-user',
          entityId: 'fallback-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(const DatumConfig());
      registerFallbackValue(
        const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'),
      );
      registerFallbackValue(
        DatumConflictContext(
          userId: 'fb',
          entityId: 'fb',
          type: DatumConflictType.bothModified,
          detectedAt: DateTime(0),
        ),
      );
      // Add the missing fallback value for TestEntity.
      registerFallbackValue(
        TestEntity(
          id: 'fb',
          userId: 'fb',
          name: 'fb',
          value: 0,
          modifiedAt: now,
          createdAt: now,
          version: 1,
        ),
      );
    });

    setUp(() async {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Add stubs for all methods that will be called during the test lifecycle.
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});

      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      // Stubbing a method call
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream.empty());
      // Stubbing a getter (no parentheses)
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => localAdapter.getPendingOperations(any()),
      ).thenAnswer((_) async => []);
      when(
        () => remoteAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});

      datum = await Datum.initialize(
        config: const DatumConfig(schemaVersion: 0),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );
    });

    tearDown(() async {
      await datum.dispose();
      Datum.resetForTesting();
    });

    test('totalSyncOperations increments on sync start', () async {
      expect(datum.currentMetrics.totalSyncOperations, 0);
      await datum.synchronize(userId);
      await Future.delayed(Duration.zero); // Allow event stream to process
      expect(datum.currentMetrics.totalSyncOperations, 1);
      await datum.synchronize(userId);
      await Future.delayed(Duration.zero); // Allow event stream to process
      expect(datum.currentMetrics.totalSyncOperations, 2);
    });

    test('successfulSyncs increments on successful completion', () async {
      expect(datum.currentMetrics.successfulSyncs, 0);
      await datum.synchronize(userId);
      await Future.delayed(Duration.zero); // Allow event stream to process
      expect(datum.currentMetrics.successfulSyncs, 1);
    });

    test('failedSyncs increments on sync error', () async {
      // Arrange
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenThrow(Exception('Remote fetch failed'));
      expect(datum.currentMetrics.failedSyncs, 0);

      // Act: The synchronize call will throw an exception.
      await expectLater(datum.synchronize(userId), throwsException);

      await Future.delayed(Duration.zero); // Allow event stream to process
      // Assert: The metric should be incremented before the exception is thrown.
      expect(datum.currentMetrics.failedSyncs, 1);
    });

    test('activeUsers tracks unique user IDs', () async {
      expect(datum.currentMetrics.activeUsers, isEmpty);
      await datum.synchronize('user-1');
      await Future.delayed(Duration.zero); // Allow event stream to process
      expect(datum.currentMetrics.activeUsers, {'user-1'});
      await datum.synchronize('user-2');
      await Future.delayed(Duration.zero); // Allow event stream to process
      expect(datum.currentMetrics.activeUsers, {'user-1', 'user-2'});
      await datum.synchronize('user-1');
      expect(datum.currentMetrics.activeUsers, {
        'user-1',
        'user-2',
      }); // Still the same set
    });

    test('userSwitchCount increments on user switch event', () async {
      expect(datum.currentMetrics.userSwitchCount, 0);

      // First, synchronize with one user to establish the "last active user".
      await datum.synchronize('user-A');
      await Future.delayed(Duration.zero); // Allow event stream to process
      expect(datum.currentMetrics.userSwitchCount, 0);

      // Now, synchronize with a different user. This will trigger the UserSwitchedEvent.
      await datum.synchronize('user-B');
      await Future.delayed(Duration.zero);

      expect(datum.currentMetrics.userSwitchCount, 1);
    });

    test(
      'conflictsDetected and conflictsResolvedAutomatically are updated on conflict',
      () async {
        // Arrange
        final localEntity = baseEntity.copyWith(
          name: 'Local Change',
          version: 2,
        );
        final remoteEntity = baseEntity.copyWith(
          name: 'Remote Change',
          version: 3,
        );

        // When pull happens, remote has a newer version.
        when(
          () => remoteAdapter.readAll(
            userId: any(named: 'userId'),
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => [remoteEntity]);

        // And local has an older, also modified version.
        when(
          () => localAdapter.readByIds(
            any(that: contains(remoteEntity.id)),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async => {remoteEntity.id: localEntity});

        // Stub the update that happens after conflict resolution.
        when(() => localAdapter.update(any())).thenAnswer((_) async {});

        expect(datum.currentMetrics.conflictsDetected, 0);
        expect(datum.currentMetrics.conflictsResolvedAutomatically, 0);

        // Act
        await datum.synchronize(userId);
        await Future.delayed(Duration.zero); // Allow event stream to process

        // Assert
        // The LastWriteWins resolver will automatically resolve the conflict.
        expect(
          datum.currentMetrics.conflictsDetected,
          1,
          reason: 'A conflict should have been detected.',
        );
        expect(
          datum.currentMetrics.conflictsResolvedAutomatically,
          1,
          reason: 'The conflict should have been resolved automatically.',
        );
      },
    );

    test('metrics stream emits new snapshots on change', () async {
      // Arrange
      final expectation = expectLater(
        datum.metrics,
        emitsInOrder([
          // Initial state
          isA<DatumMetrics>().having(
            (m) => m.totalSyncOperations,
            'totalSyncOperations',
            0,
          ),
          // After sync starts
          isA<DatumMetrics>()
              .having((m) => m.totalSyncOperations, 'totalSyncOperations', 1)
              .having((m) => m.successfulSyncs, 'successfulSyncs', 0),
          // After sync completes successfully
          isA<DatumMetrics>()
              .having((m) => m.totalSyncOperations, 'totalSyncOperations', 1)
              .having((m) => m.successfulSyncs, 'successfulSyncs', 1),
        ]),
      );

      // Act
      await datum.synchronize(userId);

      // Assert
      await expectation;
    });
  });

  group('DatumManager health stream', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late DatumManager<TestEntity> manager;
    const userId = 'health-test-user';

    setUp(() async {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => localAdapter.getPendingOperations(any()),
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
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('emits healthy -> syncing -> healthy on successful sync', () async {
      final expectation = expectLater(
        manager.health,
        emitsInOrder([
          isA<DatumHealth>().having(
            (h) => h.status,
            'status',
            DatumSyncHealth.healthy,
          ),
          isA<DatumHealth>().having(
            (h) => h.status,
            'status',
            DatumSyncHealth.syncing,
          ),
          isA<DatumHealth>().having(
            (h) => h.status,
            'status',
            DatumSyncHealth.healthy,
          ),
        ]),
      );

      await manager.synchronize(userId);
      await expectation;
    });

    test('emits healthy -> syncing -> error on failed sync', () async {
      final exception = Exception('Remote is down');
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenThrow(exception);

      final expectation = expectLater(
        manager.health,
        emitsInOrder([
          isA<DatumHealth>().having(
            (h) => h.status,
            'status',
            DatumSyncHealth.healthy,
          ),
          isA<DatumHealth>().having(
            (h) => h.status,
            'status',
            DatumSyncHealth.syncing,
          ),
          isA<DatumHealth>().having(
            (h) => h.status,
            'status',
            DatumSyncHealth.error,
          ),
        ]),
      );

      await expectLater(manager.synchronize(userId), throwsA(exception));
      await expectation;
    });

    test('remains healthy when offline and sync is skipped', () async {
      // Arrange
      when(
        () => connectivityChecker.isConnected,
      ).thenAnswer((_) async => false);

      final expectation = expectLater(
        manager.health,
        // It should only emit the initial 'healthy' state and nothing else,
        // because the sync is skipped before the state changes to 'syncing'.
        emits(
          isA<DatumHealth>().having(
            (h) => h.status,
            'status',
            DatumSyncHealth.healthy,
          ),
        ),
      );

      // Act
      final result = await manager.synchronize(userId);

      // Assert
      expect(result.wasSkipped, isTrue);
      // Close the stream to complete the expectation.
      await manager.dispose();
      await expectation;
    });

    test(
      'is healthy when there are pending operations but not syncing',
      () async {
        // Arrange: Simulate pending operations.
        when(() => localAdapter.getPendingOperations(any())).thenAnswer(
          (_) async => [
            DatumSyncOperation<TestEntity>(
              id: 'op1',
              userId: userId,
              entityId: 'e1',
              type: DatumOperationType.create,
              timestamp: DateTime.now(),
            ),
          ],
        );

        // Assert: The initial health state should still be healthy.
        expect(
          manager.health,
          emits(
            isA<DatumHealth>().having(
              (h) => h.status,
              'status',
              DatumSyncHealth.healthy,
            ),
          ),
        );
      },
    );
  });
}
