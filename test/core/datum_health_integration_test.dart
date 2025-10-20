import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/engine/datum_core.dart';
import 'package:datum/source/core/health/datum_health.dart';
import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_registration.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';
import 'datum_metrics_test.dart';

void main() {
  group('DatumManager health stream', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late DatumManager<TestEntity> manager;
    const userId = 'health-test-user';
    // This needs to be defined at the top level for the fallback registration
    final now = DateTime.now();

    late Datum datum;

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
      // Add the missing fallback for DatumSyncMetadata.
      registerFallbackValue(
        const DatumSyncMetadata(
            userId: 'fallback-user', dataHash: 'fallback-hash'),
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
      when(
        () => localAdapter.getLastSyncResult(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.saveLastSyncResult(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.getAllUserIds(),
      ).thenAnswer((_) async => []);

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
      manager = Datum.manager<TestEntity>();
    });

    tearDown(() async {
      await datum.dispose();
      Datum.resetForTesting();
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
      // The expectation is for a single event, so we can complete the test
      // without disposing the manager, which was causing the stream error.
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
