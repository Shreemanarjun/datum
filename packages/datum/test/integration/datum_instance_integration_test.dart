import 'dart:async';

import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/engine/datum_core.dart';
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

    // Set up default config for testing - disable auto sync to control when sync happens
    config = const DatumConfig(
      enableLogging: false,
      autoStartSync: false, // Disable auto sync
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

  group('Datum.instance Integration Tests', () {
    test('Datum.instance provides singleton access to the engine', () async {
      // Initially not initialized
      expect(Datum.isInitialized, false);
      expect(Datum.instanceOrNull, null);

      // Initialize using static method
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
      expect(Datum.isInitialized, true);
      expect(Datum.instance, isNotNull);
      expect(Datum.instanceOrNull, isNotNull);
      expect(Datum.instance, same(Datum.instance)); // Same instance
    });

    test('Datum.instance throws error when not initialized', () {
      expect(Datum.isInitialized, false);
      expect(() => Datum.instance, throwsStateError);
    });

    test('Datum.instance provides access to core engine properties', () async {
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

      // Test that instance provides access to core properties
      expect(Datum.instance.config, same(config));
      expect(Datum.instance.connectivityChecker, same(connectivityChecker));
      expect(Datum.instance.events, isNotNull);
      expect(Datum.instance.metrics, isNotNull);
      expect(Datum.instance.userChangeStream, isNotNull);
      expect(Datum.instance.currentMetrics, isNotNull);
    });

    test('Datum.instance provides sync functionality', () async {
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

      // Create some data via manager
      final entity = TestEntity.create('sync-test', userId, 'Test for sync');
      await Datum.manager<TestEntity>().push(item: entity, userId: userId);

      // Test global sync via instance
      final syncResult = await Datum.instance.synchronize(userId);
      expect(syncResult.failedCount, 0);
      expect(syncResult, isNotNull);
    });

    test('Datum.instance provides pause/resume functionality', () async {
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

      // Test pause/resume
      Datum.instance.pauseSync();
      Datum.instance.resumeSync();

      // Should not throw any errors
    });

    test('Datum.instance works offline with existing local data and queues operations for later sync', () async {
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

      // 1. OFFLINE PHASE: Work with existing local data
      // Simulate existing data in local database (pre-existing data)
      final existingEntity1 = TestEntity.create('existing-1', userId, 'Existing Item 1');
      final existingEntity2 = TestEntity.create('existing-2', userId, 'Existing Item 2');
      localAdapter.addLocalItem(userId, existingEntity1);
      localAdapter.addLocalItem(userId, existingEntity2);

      // Verify we can read existing data while offline
      final offlineItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(offlineItems.length, 2);
      expect(offlineItems.any((item) => item.id == 'existing-1'), true);
      expect(offlineItems.any((item) => item.id == 'existing-2'), true);

      // Perform operations while offline (create, update, delete)
      final newEntity = TestEntity.create('new-offline', userId, 'New Item Created Offline');
      await Datum.manager<TestEntity>().push(item: newEntity, userId: userId);

      final updatedEntity = existingEntity1.copyWith(name: 'Updated Offline');
      await Datum.manager<TestEntity>().push(item: updatedEntity, userId: userId);

      await Datum.manager<TestEntity>().delete(id: existingEntity2.id, userId: userId, behavior: DeleteBehavior.softDelete);

      // Verify local state after offline operations: the tombstone is hidden
      // from default reads but retained underneath for sync.
      final localItemsAfterOps = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItemsAfterOps.length, 2); // 1 updated existing + 1 new

      // Check the new item exists
      final newItem = localItemsAfterOps.firstWhere((item) => item.id == 'new-offline');
      expect(newItem.name, 'New Item Created Offline');

      // Check the updated item
      final updatedItem = localItemsAfterOps.firstWhere((item) => item.id == 'existing-1');
      expect(updatedItem.name, 'Updated Offline');

      // Check the deleted item is marked as deleted (visible only on request)
      final withTombstones = await Datum.manager<TestEntity>().readAll(userId: userId, includeDeleted: true);
      expect(withTombstones.length, 3);
      final deletedItem = withTombstones.firstWhere((item) => item.id == 'existing-2');
      expect(deletedItem.isDeleted, true);

      // Verify operations are queued for sync
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 3); // create, update, delete

      // 2. ONLINE PHASE: Connect and sync operations
      // Set remote adapter to online
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      // Emit connectivity restoration event
      connectivityController.add(true);

      // Wait for auto-sync to complete (pushes local changes)
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify that local operations were synced to remote
      final remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.isNotEmpty, true); // At least some items were synced

      // Verify pending operations are cleared after sync
      final finalPendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(finalPendingCount, 0);
    });

    test('Datum.instance can access local data offline and sync when connectivity is restored', () async {
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

      // 1. OFFLINE: Add some local data
      final localEntity1 = TestEntity.create('local-1', userId, 'Local Item 1');
      final localEntity2 = TestEntity.create('local-2', userId, 'Local Item 2');
      await Datum.manager<TestEntity>().push(item: localEntity1, userId: userId);
      await Datum.manager<TestEntity>().push(item: localEntity2, userId: userId);

      // Verify data is accessible offline
      var localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 2);

      // 2. REMAIN OFFLINE: Try to access data - should still work
      localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 2);

      // 3. GO ONLINE: Connect and sync
      // Connect to network
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);

      // Wait for auto-sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify local items were synced to remote
      final remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 2);
      expect(remoteItems.any((item) => item.id == 'local-1'), true);
      expect(remoteItems.any((item) => item.id == 'local-2'), true);

      // Verify pending operations are cleared
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 0);
    });

    test('Datum.instance maintains data consistency during offline/online transitions', () async {
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

      // 1. OFFLINE: Create initial data
      final entity = TestEntity.create('consistency-test', userId, 'Initial State');
      await Datum.manager<TestEntity>().push(item: entity, userId: userId);

      // 2. GO ONLINE: Sync initial data
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify initial sync
      var remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 1);
      expect(remoteItems.first.name, 'Initial State');

      // 3. GO OFFLINE: Make changes
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => false);
      connectivityController.add(false);
      await Future.delayed(const Duration(milliseconds: 50));

      // Update the entity offline
      final updatedEntity = entity.copyWith(name: 'Updated Offline');
      await Datum.manager<TestEntity>().push(item: updatedEntity, userId: userId);

      // Verify local change
      var localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 1);
      expect(localItems.first.name, 'Updated Offline');

      // 4. GO ONLINE AGAIN: Sync changes
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify final state is consistent
      remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 1);
      expect(remoteItems.first.name, 'Updated Offline');

      localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 1);
      expect(localItems.first.name, 'Updated Offline');

      // Verify no pending operations remain
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 0);
    });

    test('Datum.instance handles concurrent offline operations and online sync correctly', () async {
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

      // 1. OFFLINE: Perform multiple operations concurrently
      final futures = <Future>[];

      // Create multiple items
      for (int i = 0; i < 5; i++) {
        final entity = TestEntity.create('concurrent-$i', userId, 'Concurrent Item $i');
        futures.add(Datum.manager<TestEntity>().push(item: entity, userId: userId));
      }

      // Wait for all operations to complete
      await Future.wait(futures);

      // Verify all items are stored locally
      var localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 5);

      // Verify operations are queued
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 5);

      // 2. GO ONLINE: Sync all operations
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);

      // Wait for sync to complete
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify all items were synced to remote
      final remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 5);

      // Verify local state still has all items
      localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 5);

      // Verify no pending operations remain
      final finalPendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(finalPendingCount, 0);

      // Verify all concurrent items are present
      for (int i = 0; i < 5; i++) {
        expect(localItems.any((item) => item.id == 'concurrent-$i'), true);
        expect(remoteItems.any((item) => item.id == 'concurrent-$i'), true);
      }
    });

    test('Datum.instance handles offline sync with remote data deletion scenario', () async {
      // This test demonstrates the scenario where:
      // 1. Local has data that was previously synced
      // 2. Remote data gets deleted (simulating external changes)
      // 3. Local adds new data
      // 4. When syncing, operations on deleted remote data fail, but new data syncs

      // Set up online connectivity that can be controlled
      final connectivityController = StreamController<bool>();
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => connectivityController.stream);

      // Start online
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

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

      // 1. ONLINE: Create and sync 2 items
      final item1 = TestEntity.create('item-1', userId, 'Item 1');
      final item2 = TestEntity.create('item-2', userId, 'Item 2');

      await Datum.manager<TestEntity>().push(item: item1, userId: userId);
      await Datum.manager<TestEntity>().push(item: item2, userId: userId);
      await Datum.instance.synchronize(userId);

      // Verify data exists
      var localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 2);

      // 2. SIMULATE REMOTE DATA BEING DELETED (external change)
      remoteAdapter.clearAllData();

      // 3. OFFLINE: Add new data
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => false);
      final item3 = TestEntity.create('item-3', userId, 'Item 3');
      await Datum.manager<TestEntity>().push(item: item3, userId: userId);

      // Verify local has 3 items now
      localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 3);

      // 4. GO ONLINE: Attempt to sync
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);

      await Future.delayed(const Duration(milliseconds: 200));

      // 5. VERIFY RESULTS: Only the new item should sync successfully
      final remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 1);
      expect(remoteItems.first.id, 'item-3');

      // Local data should reflect successful sync (may be updated based on sync behavior)
      final finalLocalItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(finalLocalItems, isNotEmpty);
      // The exact local state depends on sync implementation, but operations should be processed
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 0); // All operations should be processed (success or failure)
    });
  });
}
