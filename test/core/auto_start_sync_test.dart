import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../integration/observer_integration_test.dart';
import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class MockLogger extends Mock implements DatumLogger {}

void main() {
  // Use late final to ensure mocks are created only once per test group
  late MockLocalAdapter<TestEntity> localAdapter;
  late MockRemoteAdapter<TestEntity> remoteAdapter;
  late MockConnectivityChecker connectivityChecker;

  // Helper to pre-populate data without a running manager.
  Future<void> setupInitialData(List<TestEntity> entities) async {
    // Directly add items and pending operations to the main test adapter.
    // This ensures the test starts with the correct state.
    for (final entity in entities) {
      localAdapter.addLocalItem(entity.userId, entity);
      await localAdapter.addPendingOperation(
        entity.userId,
        DatumSyncOperation(
          id: 'op-${entity.id}',
          userId: entity.userId,
          entityId: entity.id,
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: entity,
        ),
      );
    }
  }

  group('Auto-Start Sync', () {
    setUp(() {
      // Reset mocks before each test to ensure a clean state
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Default to being online for all tests unless overridden.
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
    });

    tearDown(() {
      // No-op, as mocks are re-created in setUp.
    });

    test(
      'auto-starts sync for all users with data on initialization',
      () async {
        final user1Entity = TestEntity(
          id: 'entity1',
          userId: 'user1',
          name: 'User 1 Item',
          value: 1,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        );
        final user2Entity = TestEntity(
          id: 'entity2',
          userId: 'user2',
          name: 'User 2 Item',
          value: 2,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        );

        await setupInitialData([user1Entity, user2Entity]);

        // Now create manager with autoStartSync
        final manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          datumConfig: const DatumConfig<TestEntity>(
            autoStartSync: true,
            schemaVersion: 0,
            autoSyncInterval: Duration(seconds: 1),
          ),
        );

        await manager.initialize();

        // Wait for auto-sync to trigger
        await Future<void>.delayed(const Duration(milliseconds: 1500));

        // Both users should have been synced
        final user1Pending = await manager.getPendingCount('user1');
        final user2Pending = await manager.getPendingCount('user2');

        expect(user1Pending, 0, reason: 'Auto-sync should have synced user1');
        expect(user2Pending, 0, reason: 'Auto-sync should have synced user2');

        await manager.dispose();
      },
    );

    test('does not auto-start sync when autoStartSync is false', () async {
      await setupInitialData([TestEntity.create('e1', 'user1', 'Item 1')]);

      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig<TestEntity>(
          schemaVersion: 0,
          autoSyncInterval: Duration(seconds: 1),
        ),
      );

      await manager.initialize();

      // Wait a bit
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // Should NOT be synced automatically
      final pendingCount = await manager.getPendingCount('user1');
      expect(
        pendingCount,
        1,
        reason: 'Auto-sync should NOT start automatically',
      );

      await manager.dispose();
    });

    test('handles multiple users with different data', () async {
      final entities = List.generate(3, (i) {
        final index = i + 1;
        return TestEntity(
          id: 'entity$index',
          userId: 'user$index',
          name: 'User $index Item',
          value: index,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        );
      });
      await setupInitialData(entities);

      // Now create manager with autoStartSync
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig<TestEntity>(
          autoStartSync: true,
          schemaVersion: 0,
          autoSyncInterval: Duration(seconds: 1),
        ),
      );

      await manager.initialize();

      // Wait for auto-sync
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // All users should have synced data
      for (var i = 1; i <= 3; i++) {
        final pendingCount = await manager.getPendingCount('user$i');
        expect(pendingCount, 0, reason: 'Auto-sync should work for user$i');
      }

      await manager.dispose();
    });

    test('ignores users with empty userId', () async {
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig<TestEntity>(
          autoStartSync: true,
          schemaVersion: 0,
        ),
      );

      await manager.initialize();

      // Should not throw or cause issues
      expect(manager.dispose, returnsNormally);

      await manager.dispose();
    });

    test('auto-starts sync only for initialUserId when provided', () async {
      await setupInitialData([
        TestEntity.create('e1', 'user1', 'Item 1'),
        TestEntity.create('e2', 'user2', 'Item 2'),
      ]);

      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig<TestEntity>(
          autoStartSync: true,
          initialUserId: 'user1', // Target only user1
          schemaVersion: 0,
          autoSyncInterval: Duration(seconds: 1),
        ),
      );

      await manager.initialize();

      // Wait for auto-sync to trigger
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // Only user1 should have been synced
      final user1Pending = await manager.getPendingCount('user1');
      final user2Pending = await manager.getPendingCount('user2');

      expect(
        user1Pending,
        0,
        reason: 'Auto-sync should have synced the initialUserId',
      );
      expect(
        user2Pending,
        1,
        reason: 'Auto-sync should NOT have synced other users',
      );

      await manager.dispose();
    });

    test(
      'does not auto-start for users created after initialization',
      () async {
        // Initialize manager with no initial user data
        final manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          datumConfig: const DatumConfig<TestEntity>(
            autoStartSync: true,
            schemaVersion: 0,
            autoSyncInterval: Duration(seconds: 1),
          ),
        );
        await manager.initialize();

        // Now, create data for a new user
        await manager.push(
          item: TestEntity.create('e1', 'user1', 'Item 1'),
          userId: 'user1',
        );

        // Wait to see if auto-sync triggers (it shouldn't)
        await Future<void>.delayed(const Duration(milliseconds: 1500));

        final pendingCount = await manager.getPendingCount('user1');
        expect(
          pendingCount,
          1,
          reason: 'Auto-sync should not start for users created post-init',
        );

        await manager.dispose();
      },
    );

    test('auto-sync retries after coming back online', () async {
      // Start offline
      when(
        () => connectivityChecker.isConnected,
      ).thenAnswer((_) async => false);
      await setupInitialData([TestEntity.create('e1', 'user1', 'Item 1')]);

      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig<TestEntity>(
          autoStartSync: true,
          schemaVersion: 0,
          autoSyncInterval: Duration(seconds: 1),
        ),
      );
      await manager.initialize();

      // Wait for the first sync attempt (which should fail)
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(
        await manager.getPendingCount('user1'),
        1,
        reason: 'Sync should fail while offline',
      );

      // Come back online
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      // Wait for the next sync interval
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // The next attempt should succeed
      expect(
        await manager.getPendingCount('user1'),
        0,
        reason: 'Sync should succeed after coming online',
      );

      await manager.dispose();
    });

    group('stopAutoSync', () {
      test('stops periodic sync for a specific user', () async {
        // Arrange
        registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));

        await setupInitialData([
          TestEntity.create('e1', 'user1', 'Item 1'),
          TestEntity.create('e2', 'user2', 'Item 2'),
        ]);

        final manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivityChecker,
          datumConfig: const DatumConfig<TestEntity>(
            autoStartSync: true,
            schemaVersion: 0,
            autoSyncInterval: Duration(milliseconds: 500),
          ),
        );
        await manager.initialize();

        // Wait for initial sync to complete for both users
        await Future<void>.delayed(const Duration(milliseconds: 750));
        expect(await manager.getPendingCount('user1'), 0);
        expect(await manager.getPendingCount('user2'), 0);

        // Act: Stop sync for user1, then create new data for both
        manager.stopAutoSync(userId: 'user1');

        await manager.push(
          item: TestEntity.create('e1-new', 'user1', 'New 1'),
          userId: 'user1',
        );
        await manager.push(
          item: TestEntity.create('e2-new', 'user2', 'New 2'),
          userId: 'user2',
        );

        // Wait for the next sync interval
        await Future<void>.delayed(const Duration(milliseconds: 750));

        // Assert
        // user1's sync was stopped, so their new item should still be pending.
        expect(await manager.getPendingCount('user1'), 1);
        // user2's sync is still active, so their new item should be synced.
        expect(await manager.getPendingCount('user2'), 0);

        await manager.dispose();
      });

      test(
        'stops periodic sync for all users if no userId is provided',
        () async {
          // Arrange
          registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));

          await setupInitialData([
            TestEntity.create('e1', 'user1', 'Item 1'),
            TestEntity.create('e2', 'user2', 'Item 2'),
          ]);

          final manager = DatumManager<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
            connectivity: connectivityChecker,
            datumConfig: const DatumConfig<TestEntity>(
              autoStartSync: true,
              schemaVersion: 0,
              autoSyncInterval: Duration(milliseconds: 500),
            ),
          );
          await manager.initialize();

          // Wait for initial sync to complete for both users
          await Future<void>.delayed(const Duration(milliseconds: 750));
          expect(await manager.getPendingCount('user1'), 0);
          expect(await manager.getPendingCount('user2'), 0);

          // Act: Stop all syncs, then create new data for both
          manager.stopAutoSync();

          await manager.push(
            item: TestEntity.create('e1-new', 'user1', 'New 1'),
            userId: 'user1',
          );
          await manager.push(
            item: TestEntity.create('e2-new', 'user2', 'New 2'),
            userId: 'user2',
          );

          // Wait for the next sync interval
          await Future<void>.delayed(const Duration(milliseconds: 750));

          // Assert: Both syncs were stopped, so both new items should be pending.
          expect(await manager.getPendingCount('user1'), 1);
          expect(await manager.getPendingCount('user2'), 1);

          await manager.dispose();
        },
      );
    });

    test('logs an error if auto-sync fails', () async {
      // Arrange
      final mockLogger = MockLogger();
      registerFallbackValue(StackTrace.empty);

      final exception = Exception('Auto-sync failed');
      await setupInitialData([TestEntity.create('e1', 'user1', 'Item 1')]);
      // Register fallback for this test's scope before using `any()`.
      registerFallbackValue(
        TestEntity.create('fallback', 'fallback', 'fallback'),
      );
      registerFallbackValue(
        const DatumSyncMetadata(userId: 'fb-user', dataHash: 'fb-hash'),
      );
      // Create a dedicated remote adapter for this test to stub its behavior.
      final failingRemoteAdapter = MockedRemoteAdapter<TestEntity>();
      when(() => failingRemoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => failingRemoteAdapter.initialize()).thenAnswer((_) async {});
      // Stub other methods that might be called during the sync process.
      when(
        () => failingRemoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => failingRemoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(() => failingRemoteAdapter.create(any())).thenThrow(exception);

      // Stub synchronize to always throw
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: failingRemoteAdapter,
        connectivity: connectivityChecker,
        logger: mockLogger,
        datumConfig: const DatumConfig<TestEntity>(
          // Disable initial auto-sync
          autoStartSync: false,
          autoSyncInterval: Duration(milliseconds: 100),
        ),
      );

      // Act
      await manager.initialize();

      // Manually start the periodic sync to isolate the behavior under test.
      manager.startAutoSync('user1');

      // Wait for the auto-sync timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Assert
      verify(
        () => mockLogger.error(
          'Auto-sync for user user1 failed: $exception',
          any(),
        ),
      ).called(1);

      await manager.dispose();
    });
  });
}
