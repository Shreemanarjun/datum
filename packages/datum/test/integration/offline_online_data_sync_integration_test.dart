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

  group('Offline/Online Data Synchronization Tests', () {
    test('works offline with existing local data and queues operations for later sync', () async {
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

    test('can access local data offline and sync when connectivity is restored', () async {
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

    test('maintains data consistency during offline/online transitions', () async {
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

    test('handles concurrent offline operations and online sync correctly', () async {
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

    test('Datum.instance provides offline/online functionality', () async {
      // Set up online connectivity that can be controlled
      final connectivityController = StreamController<bool>();
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => connectivityController.stream);

      // Start offline
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => false);

      // Initialize Datum using static initialize method
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

      // 1. OFFLINE: Work with data using Datum.instance
      final offlineEntity = TestEntity.create('instance-offline', userId, 'Created via Datum.instance');
      await Datum.manager<TestEntity>().push(item: offlineEntity, userId: userId);

      // Verify data is accessible offline via instance
      var localItems = await Datum.manager<TestEntity>().readAll(userId: userId);
      expect(localItems.length, 1);
      expect(localItems.first.id, 'instance-offline');

      // Verify operations are queued
      final pendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(pendingCount, 1);

      // 2. GO ONLINE: Connect and sync using instance
      remoteAdapter.isConnectedValue = true;
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      connectivityController.add(true);

      // Wait for auto-sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify data was synced to remote via instance
      final remoteItems = await remoteAdapter.readAll(userId: userId);
      expect(remoteItems.length, 1);
      expect(remoteItems.first.id, 'instance-offline');

      // Verify pending operations are cleared
      final finalPendingCount = await Datum.manager<TestEntity>().getPendingCount(userId);
      expect(finalPendingCount, 0);

      // Verify instance access works (Datum.instance is the singleton)
      expect(Datum.instance, isNotNull);
      expect(Datum.isInitialized, true);
    });
  });
}
