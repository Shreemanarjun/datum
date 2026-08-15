import 'dart:async';

import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/engine/datum_core.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_registration.dart';
import 'package:datum/source/core/sync/datum_sync_execution_strategy.dart';
import 'package:datum/source/core/manager/datum_sync_request_strategy.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  late MockConnectivityChecker connectivityChecker;
  late MockLocalAdapter<TestEntity> localAdapter;
  late MockRemoteAdapter<TestEntity> remoteAdapter;
  late DatumConfig config;

  setUp(() async {
    // Reset Datum for clean state
    Datum.resetForTesting();

    // Set up mocks
    connectivityChecker = MockConnectivityChecker();
    localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    remoteAdapter = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);

    // Set up default config for testing
    config = const DatumConfig(
      enableLogging: false,
      autoStartSync: true,
      autoSyncInterval: Duration(seconds: 30),
      syncExecutionStrategy: ParallelStrategy(),
      syncRequestStrategy: SequentialRequestStrategy(),
    );

    // Set up default connectivity state (offline)
    when(() => connectivityChecker.isConnected).thenAnswer((_) async => false);
    when(() => connectivityChecker.onStatusChange).thenAnswer((_) => Stream.value(false));
  });

  tearDown(() async {
    // Dispose of any active subscriptions
    await Datum.instanceOrNull?.dispose();
    // Reset for next test
    Datum.resetForTesting();
  });

  group('Connectivity-Based Auto-Sync Tests', () {
    test('queue is maintained offline - operations are queued when offline', () async {
      // Initialize Datum with offline connectivity
      final result = await Datum.initialize(
        config: config,
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      expect(result.isSuccess(), true);

      // Create some test data offline
      const userId = 'user1';
      final entity = TestEntity.create('test-entity-1', userId, 'Test Item');
      final entity2 = TestEntity.create('test-entity-2', userId, 'Test Item 2');

      // Perform operations while offline - these should be queued
      await Datum.manager<TestEntity>().push(item: entity, userId: userId);
      await Datum.manager<TestEntity>().push(item: entity2, userId: userId);

      // Verify items are stored locally
      final localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 2);
      expect(localItems.any((item) => item.id == 'test-entity-1'), true);
      expect(localItems.any((item) => item.id == 'test-entity-2'), true);

      // Verify operations are queued (pending count > 0)
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, greaterThan(0));

      // Get pending operations
      final pendingOps = await Datum.manager<TestEntity>().getPendingOperations(userId);
      expect(pendingOps.length, 2);
      expect(pendingOps.every((op) => op.userId == userId), true);
    });

    test('queue is maintained offline - delete operations are queued', () async {
      // Initialize Datum with offline connectivity
      final result = await Datum.initialize(
        config: config,
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      expect(result.isSuccess(), true);

      const userId = 'user1';
      final entity = TestEntity.create('delete-test-entity', userId, 'Item to Delete');

      // First create the item (this will be stored locally)
      await Datum.manager<TestEntity>().push(item: entity, userId: userId);

      // Verify item exists locally
      var localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 1);
      expect(localItems.first.id, 'delete-test-entity');

      // Delete while offline - this should be queued
      final deleted = await Datum.manager<TestEntity>().delete(id: entity.id, userId: userId, behavior: DeleteBehavior.softDelete);
      expect(deleted, true);

      // The tombstone is invisible to the app by default...
      localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems, isEmpty);
      // ...but still exists underneath so it can sync.
      localItems = await Datum.manager<TestEntity>().readAll(userId: userId, includeDeleted: true);
      expect(localItems.length, 1);
      expect(localItems.first.id, 'delete-test-entity');
      expect(localItems.first.isDeleted, true);

      // Verify delete operation is queued
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 2); // One create, one delete

      final pendingOps = await Datum.manager<TestEntity>().getPendingOperations(userId);
      expect(pendingOps.length, 2);
      expect(pendingOps.any((op) => op.type == DatumOperationType.delete), true);
    });

    test('syncs successfully when online - connectivity restoration triggers sync', () async {
      // Set up online connectivity that can be controlled
      final connectivityController = StreamController<bool>();
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => connectivityController.stream);

      // Start offline
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => false);

      // Initialize Datum
      final result = await Datum.initialize(
        config: config,
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      expect(result.isSuccess(), true);

      const userId = 'user1';
      final entity = TestEntity.create('sync-test-entity', userId, 'Item to Sync');
      final entity2 = TestEntity.create('sync-test-entity-2', userId, 'Item to Sync 2');

      // Perform operations while offline
      await Datum.manager<TestEntity>().push(item: entity, userId: userId);
      await Datum.manager<TestEntity>().push(item: entity2, userId: userId);

      // Verify operations are queued
      var pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 2);

      // Now simulate connectivity restoration - set remote adapter to online
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      // Emit connectivity restoration event
      connectivityController.add(true);

      // Wait for auto-sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify items are now synced to remote
      final remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 2);
      expect(remoteItems.any((item) => item.id == 'sync-test-entity'), true);
      expect(remoteItems.any((item) => item.id == 'sync-test-entity-2'), true);

      // Verify pending operations are cleared
      pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 0);
    });

    test('syncs successfully when online - multiple users with pending operations', () async {
      // Set up online connectivity that can be controlled
      final connectivityController = StreamController<bool>();
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => connectivityController.stream);

      // Start offline
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => false);

      // Initialize Datum
      final result = await Datum.initialize(
        config: config,
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      expect(result.isSuccess(), true);

      const userId1 = 'user1';
      const userId2 = 'user2';

      // Create operations for multiple users while offline
      final entity1 = TestEntity.create('user1-entity', userId1, 'User1 Item');
      final entity2 = TestEntity.create('user2-entity', userId2, 'User2 Item');

      await Datum.manager<TestEntity>().push(item: entity1, userId: userId1);
      await Datum.manager<TestEntity>().push(item: entity2, userId: userId2);

      // Verify both users have pending operations
      var pendingCount1 = await Datum.manager<TestEntity>().getPendingCount(userId1);
      var pendingCount2 = await Datum.manager<TestEntity>().getPendingCount(userId2);
      expect(pendingCount1, 1);
      expect(pendingCount2, 1);

      // Now simulate connectivity restoration
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);

      // Wait for auto-sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify both users' data is synced
      final remoteItemsUser1 = await remoteAdapter.readAll(userId: userId1);
      final remoteItemsUser2 = await remoteAdapter.readAll(userId: userId2);

      expect(remoteItemsUser1.length, 1);
      expect(remoteItemsUser1.first.id, 'user1-entity');
      expect(remoteItemsUser2.length, 1);
      expect(remoteItemsUser2.first.id, 'user2-entity');

      // Verify pending operations are cleared for both users
      pendingCount1 = await Datum.manager<TestEntity>().getPendingCount(userId1);
      pendingCount2 = await Datum.manager<TestEntity>().getPendingCount(userId2);
      expect(pendingCount1, 0);
      expect(pendingCount2, 0);
    });

    test('syncs successfully when online - handles mixed create/update/delete operations', () async {
      // Set up online connectivity that can be controlled
      final connectivityController = StreamController<bool>();
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => connectivityController.stream);

      // Start offline
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => false);

      // Initialize Datum
      final result = await Datum.initialize(
        config: config,
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      expect(result.isSuccess(), true);

      const userId = 'user1';

      // Create an initial item while offline
      final entity = TestEntity.create('mixed-test-entity', userId, 'Initial Name');
      await Datum.manager<TestEntity>().push(item: entity, userId: userId);

      // Update the item while offline (will create another operation)
      final updatedEntity = entity.copyWith(name: 'Updated Name');
      await Datum.manager<TestEntity>().push(item: updatedEntity, userId: userId);

      // Create another item while offline
      final entity2 = TestEntity.create('mixed-test-entity-2', userId, 'Second Item');
      await Datum.manager<TestEntity>().push(item: entity2, userId: userId);

      // Delete the second item while offline
      await Datum.manager<TestEntity>().delete(id: entity2.id, userId: userId, behavior: DeleteBehavior.softDelete);

      // Verify we have pending operations (create, update, create, delete = 4 operations)
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 4);

      // Now simulate connectivity restoration
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);

      // Wait for auto-sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify final state: first item should be synced with updates, second item should not exist
      // Only the live item is visible by default; the tombstone stays hidden.
      final localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 1);

      // First item should not be deleted (only second was)
      final firstLocalItem = localItems.firstWhere((item) => item.id == 'mixed-test-entity');
      expect(firstLocalItem.name, 'Updated Name');
      expect(firstLocalItem.isDeleted, false);

      // After the remote confirmed the deletion (via its change stream), the
      // local tombstone is cleaned up too — the entity is gone everywhere.
      final withTombstones = await Datum.manager<TestEntity>().readAll(userId: userId, includeDeleted: true);
      expect(withTombstones.length, 1);
      expect(withTombstones.single.id, 'mixed-test-entity');

      // Verify remote state matches the intended operations
      final remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 1); // Only the first item should be on remote
      expect(remoteItems.first.id, 'mixed-test-entity');
      expect(remoteItems.first.name, 'Updated Name');
      expect(remoteItems.first.isDeleted, false);

      // Verify pending operations are cleared
      final finalPendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(finalPendingCount, 0);
    });
  });
}
