import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryDatumPersistence persistence;

  setUp(() async {
    persistence = InMemoryDatumPersistence();
    await persistence.initialize();
  });

  tearDown(() async {
    await persistence.dispose();
  });

  group('InMemoryDatumPersistence', () {
    group('Initialization', () {
      test('isInitialized returns true after initialize', () async {
        expect(persistence.isInitialized, isTrue);
      });

      test('isInitialized returns false before initialize', () async {
        final uninitialized = InMemoryDatumPersistence();
        expect(uninitialized.isInitialized, isFalse);
      });

      test('initialize can be called multiple times', () async {
        await persistence.initialize();
        expect(persistence.isInitialized, isTrue);
      });
    });

    group('Sync Metadata Operations', () {
      final metadata = DatumSyncMetadata(
        userId: 'test-user',
        lastSyncTime: DateTime.now(),
        dataHash: 'test-hash',
        syncStatus: SyncStatus.synced,
      );

      test('saveSyncMetadata stores metadata correctly', () async {
        await persistence.saveSyncMetadata('test-user', metadata);

        final retrieved = await persistence.getSyncMetadata('test-user');
        expect(retrieved, isNotNull);
        expect(retrieved!.userId, metadata.userId);
        expect(retrieved.dataHash, metadata.dataHash);
        expect(retrieved.syncStatus, metadata.syncStatus);
      });

      test('getSyncMetadata returns null for non-existent user', () async {
        final retrieved = await persistence.getSyncMetadata('non-existent');
        expect(retrieved, isNull);
      });

      test('deleteSyncMetadata removes metadata correctly', () async {
        await persistence.saveSyncMetadata('test-user', metadata);
        expect(await persistence.getSyncMetadata('test-user'), isNotNull);

        await persistence.deleteSyncMetadata('test-user');
        expect(await persistence.getSyncMetadata('test-user'), isNull);
      });

      test('getAllUserIds returns all stored user IDs', () async {
        final metadata1 = DatumSyncMetadata(
          userId: 'user1',
          lastSyncTime: DateTime.now(),
          dataHash: 'test-hash-1',
          syncStatus: SyncStatus.synced,
        );
        final metadata2 = DatumSyncMetadata(
          userId: 'user2',
          lastSyncTime: DateTime.now(),
          dataHash: 'test-hash-2',
          syncStatus: SyncStatus.synced,
        );

        await persistence.saveSyncMetadata('user1', metadata1);
        await persistence.saveSyncMetadata('user2', metadata2);

        final userIds = await persistence.getAllUserIds();
        expect(userIds, containsAll(['user1', 'user2']));
        expect(userIds.length, 2);
      });
    });

    group('Configuration Operations', () {
      test('saveConfig stores configuration correctly', () async {
        await persistence.saveConfig('test-key', 'test-value');

        final retrieved = await persistence.getConfig('test-key');
        expect(retrieved, 'test-value');
      });

      test('getConfig returns null for non-existent key', () async {
        final retrieved = await persistence.getConfig('non-existent');
        expect(retrieved, isNull);
      });

      test('deleteConfig removes configuration correctly', () async {
        await persistence.saveConfig('test-key', 'test-value');
        expect(await persistence.getConfig('test-key'), 'test-value');

        await persistence.deleteConfig('test-key');
        expect(await persistence.getConfig('test-key'), isNull);
      });

      test('saveConfig supports various data types', () async {
        await persistence.saveConfig('string', 'value');
        await persistence.saveConfig('int', 42);
        await persistence.saveConfig('bool', true);
        await persistence.saveConfig('list', [1, 2, 3]);
        await persistence.saveConfig('map', {'key': 'value'});

        expect(await persistence.getConfig('string'), 'value');
        expect(await persistence.getConfig('int'), 42);
        expect(await persistence.getConfig('bool'), true);
        expect(await persistence.getConfig('list'), [1, 2, 3]);
        expect(await persistence.getConfig('map'), {'key': 'value'});
      });
    });

    group('Data Operations', () {
      test('saveData stores data correctly', () async {
        await persistence.saveData('test-key', 'test-value');

        final retrieved = await persistence.getData('test-key');
        expect(retrieved, 'test-value');
      });

      test('getData returns null for non-existent key', () async {
        final retrieved = await persistence.getData('non-existent');
        expect(retrieved, isNull);
      });

      test('deleteData removes data correctly', () async {
        await persistence.saveData('test-key', 'test-value');
        expect(await persistence.getData('test-key'), 'test-value');

        await persistence.deleteData('test-key');
        expect(await persistence.getData('test-key'), isNull);
      });
    });

    group('Streaming Operations', () {
      test('watchSyncMetadata emits current value immediately', () async {
        const metadata = DatumSyncMetadata(
          userId: 'test-user',
          syncStatus: SyncStatus.synced,
        );

        await persistence.saveSyncMetadata('test-user', metadata);

        final stream = persistence.watchSyncMetadata('test-user');
        final emittedValues = <DatumSyncMetadata?>[];

        final subscription = stream.listen(emittedValues.add);

        // Wait for the stream to emit
        await Future.delayed(const Duration(milliseconds: 10));
        await subscription.cancel();

        expect(emittedValues.length, 1);
        expect(emittedValues.first!.userId, 'test-user');
      });

      test('watchSyncMetadata emits updates when metadata changes', () async {
        final stream = persistence.watchSyncMetadata('test-user');
        final emittedValues = <DatumSyncMetadata?>[];

        final subscription = stream.listen(emittedValues.add);

        // Initial value should be null
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 1);
        expect(emittedValues.last, isNull);

        // Save metadata
        const metadata = DatumSyncMetadata(
          userId: 'test-user',
          syncStatus: SyncStatus.synced,
        );
        await persistence.saveSyncMetadata('test-user', metadata);

        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 2);
        expect(emittedValues.last!.userId, 'test-user');

        // Update metadata
        final updatedMetadata = metadata.copyWith(syncStatus: SyncStatus.failed);
        await persistence.saveSyncMetadata('test-user', updatedMetadata);

        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 3);
        expect(emittedValues.last!.syncStatus, SyncStatus.failed);

        await subscription.cancel();
      });

      test('watchConfig emits current value immediately', () async {
        await persistence.saveConfig('test-key', 'test-value');

        final stream = persistence.watchConfig('test-key');
        final emittedValues = <dynamic>[];

        final subscription = stream.listen(emittedValues.add);

        await Future.delayed(const Duration(milliseconds: 10));
        await subscription.cancel();

        expect(emittedValues.length, 1);
        expect(emittedValues.first, 'test-value');
      });

      test('watchData emits current value immediately', () async {
        await persistence.saveData('test-key', 'test-value');

        final stream = persistence.watchData('test-key');
        final emittedValues = <dynamic>[];

        final subscription = stream.listen(emittedValues.add);

        await Future.delayed(const Duration(milliseconds: 10));
        await subscription.cancel();

        expect(emittedValues.length, 1);
        expect(emittedValues.first, 'test-value');
      });
    });

    group('User Data Management', () {
      test('clearUserData removes all user-specific data', () async {
        // Setup data for user1 and user2
        await persistence.saveSyncMetadata('user1', const DatumSyncMetadata(userId: 'user1'));
        await persistence.saveSyncMetadata('user2', const DatumSyncMetadata(userId: 'user2'));

        await persistence.saveConfig('user1_pref', 'value1');
        await persistence.saveConfig('user2_pref', 'value2');
        await persistence.saveConfig('global_pref', 'global');

        await persistence.saveData('user1_data', 'data1');
        await persistence.saveData('user2_data', 'data2');
        await persistence.saveData('global_data', 'global');

        // Clear user1 data
        await persistence.clearUserData('user1');

        // Verify user1 data is gone
        expect(await persistence.getSyncMetadata('user1'), isNull);
        expect(await persistence.getConfig('user1_pref'), isNull);
        expect(await persistence.getData('user1_data'), isNull);

        // Verify user2 and global data remains
        expect(await persistence.getSyncMetadata('user2'), isNotNull);
        expect(await persistence.getConfig('user2_pref'), 'value2');
        expect(await persistence.getConfig('global_pref'), 'global');
        expect(await persistence.getData('user2_data'), 'data2');
        expect(await persistence.getData('global_data'), 'global');
      });
    });

    group('Data Clearing', () {
      test('clearAllData removes all stored data', () async {
        // Setup data
        await persistence.saveSyncMetadata('user1', const DatumSyncMetadata(userId: 'user1'));
        await persistence.saveConfig('config-key', 'config-value');
        await persistence.saveData('data-key', 'data-value');

        // Verify data exists
        expect(await persistence.getSyncMetadata('user1'), isNotNull);
        expect(await persistence.getConfig('config-key'), 'config-value');
        expect(await persistence.getData('data-key'), 'data-value');

        // Clear all data
        await persistence.clearAllData();

        // Verify all data is gone
        expect(await persistence.getSyncMetadata('user1'), isNull);
        expect(await persistence.getConfig('config-key'), isNull);
        expect(await persistence.getData('data-key'), isNull);
        expect((await persistence.getAllUserIds()).isEmpty, isTrue);
      });
    });

    group('Storage Statistics', () {
      test('getStorageStats returns correct statistics', () async {
        // Setup some data
        await persistence.saveSyncMetadata('user1', const DatumSyncMetadata(userId: 'user1'));
        await persistence.saveConfig('config1', 'value1');
        await persistence.saveData('data1', 'value1');

        final stats = await persistence.getStorageStats();

        expect(stats, isNotNull);
        expect(stats!['totalUsers'], 1);
        expect(stats['totalEntries'], greaterThan(0));
        expect(stats['storageSizeBytes'], greaterThan(0));
        expect(stats['lastModified'], isNotNull);
      });

      test('getStorageStats returns null when not initialized', () async {
        final uninitialized = InMemoryDatumPersistence();
        final stats = await uninitialized.getStorageStats();
        expect(stats, isNull);
      });
    });

    group('Error Handling', () {
      test('throws StateError when operations called before initialize', () async {
        final uninitialized = InMemoryDatumPersistence();

        expect(
          () => uninitialized.saveSyncMetadata('user', const DatumSyncMetadata(userId: 'user')),
          throwsA(isA<StateError>()),
        );

        expect(
          () => uninitialized.getSyncMetadata('user'),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
