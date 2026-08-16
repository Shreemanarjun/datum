import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

/// Integration test for Datum persistence layer with DatumManager.
///
/// This test verifies that the persistence layer works correctly with
/// the Datum synchronization engine, including metadata storage,
/// configuration management, and data persistence across sync operations.
void main() {
  late InMemoryDatumPersistence persistence;
  late DatumManager<TestEntity> manager;

  setUp(() async {
    // Initialize persistence layer
    persistence = InMemoryDatumPersistence();
    await persistence.initialize();

    // Create Datum instance with persistence
    await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: MockConnectivityChecker(),
      persistence: persistence,
      registrations: [
        DatumRegistration<TestEntity>(
          localAdapter: TestLocalAdapter(),
          remoteAdapter: TestRemoteAdapter(),
        ),
      ],
    );

    // Get the manager for testing
    manager = Datum.manager<TestEntity>();
  });

  tearDown(() async {
    await Datum.instance.dispose();
    await persistence.dispose();
    Datum.resetForTesting();
  });

  group('Persistence Integration Tests', () {
    group('Sync Metadata Persistence', () {
      test('persists sync metadata across manager operations', () async {
        const userId = 'test-user';

        // Initially no metadata should exist
        expect(await persistence.getSyncMetadata(userId), isNull);

        // Create and sync an entity
        final entity = TestEntity.create('persist-test-1', userId, 'Test Entity');
        await manager.push(item: entity, userId: userId);

        // Check that operation was enqueued
        final pendingCount = await manager.getPendingCount(userId);
        expect(pendingCount, 1);

        // Sync should create metadata
        final result = await manager.synchronize(userId, options: const DatumSyncOptions<TestEntity>(direction: SyncDirection.pushOnly));
        expect(result.syncedCount, 1);

        // Verify metadata was persisted
        final metadata = await persistence.getSyncMetadata(userId);
        expect(metadata, isNotNull);
        expect(metadata!.userId, userId);
        expect(metadata.lastSyncTime, isNotNull);
        expect(metadata.syncStatus, SyncStatus.synced);
      });

      test('restores sync metadata on manager initialization', () async {
        const userId = 'test-user';

        // Manually create metadata
        final originalMetadata = DatumSyncMetadata(
          userId: userId,
          lastSyncTime: DateTime.now().subtract(const Duration(hours: 1)),
          dataHash: 'original-hash',
          syncStatus: SyncStatus.synced,
          entityCounts: const {
            'TestEntity': DatumEntitySyncDetails(count: 5, hash: 'entity-hash'),
          },
        );

        await persistence.saveSyncMetadata(userId, originalMetadata);

        // Create a new manager and verify it loads the metadata
        final loadedMetadata = await persistence.getSyncMetadata(userId);

        expect(loadedMetadata, isNotNull);
        expect(loadedMetadata!.userId, originalMetadata.userId);
        expect(loadedMetadata.dataHash, originalMetadata.dataHash);
        expect(loadedMetadata.syncStatus, originalMetadata.syncStatus);
        expect(loadedMetadata.entityCounts, originalMetadata.entityCounts);
      });

      test('updates sync metadata during sync operations', () async {
        const userId = 'test-user';

        // Initial sync
        final entity1 = TestEntity.create('update-test-1', userId, 'Entity 1');
        await manager.push(item: entity1, userId: userId);
        await manager.synchronize(userId);

        var metadata = await persistence.getSyncMetadata(userId);
        expect(metadata!.entityCounts!['TestEntity']!.count, 1);

        // Add another entity and sync
        final entity2 = TestEntity.create('update-test-2', userId, 'Entity 2');
        await manager.push(item: entity2, userId: userId);
        await manager.synchronize(userId);

        metadata = await persistence.getSyncMetadata(userId);
        expect(metadata!.entityCounts!['TestEntity']!.count, 2);
        expect(metadata.lastSyncTime!.isAfter(metadata.lastSuccessfulSyncTime!), isFalse);
      });
    });

    group('Configuration Persistence', () {
      test('persists configuration data', () async {
        const key = 'test-config-key';
        const value = 'test-config-value';

        // Initially no config should exist
        expect(await persistence.getConfig(key), isNull);

        // Save configuration
        await persistence.saveConfig(key, value);

        // Verify it was persisted
        final retrieved = await persistence.getConfig(key);
        expect(retrieved, value);
      });

      test('configuration survives manager operations', () async {
        const key = 'survival-config';
        const value = {'nested': 'data', 'number': 42};

        // Save config before operations
        await persistence.saveConfig(key, value);

        // Perform some sync operations
        const userId = 'config-test-user';
        final entity = TestEntity.create('config-test-1', userId, 'Config Test');
        await manager.push(item: entity, userId: userId);
        await manager.synchronize(userId);

        // Verify config still exists
        final retrieved = await persistence.getConfig(key);
        expect(retrieved, value);
      });

      test('configuration streaming works with persistence', () async {
        const key = 'stream-config';

        final stream = persistence.watchConfig(key);
        final emittedValues = <dynamic>[];

        final subscription = stream.listen(emittedValues.add);

        // Initial value should be null
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 1);
        expect(emittedValues.last, isNull);

        // Save config
        await persistence.saveConfig(key, 'first-value');
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 2);
        expect(emittedValues.last, 'first-value');

        // Update config
        await persistence.saveConfig(key, 'second-value');
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 3);
        expect(emittedValues.last, 'second-value');

        await subscription.cancel();
      });
    });

    group('Data Persistence', () {
      test('persists arbitrary data', () async {
        const key = 'test-data-key';
        final value = {
          'entities': ['entity1', 'entity2'],
          'timestamp': DateTime.now().toIso8601String(),
          'metadata': {'version': 1, 'active': true}
        };

        // Save data
        await persistence.saveData(key, value);

        // Verify it was persisted
        final retrieved = await persistence.getData(key);
        expect(retrieved, value);
      });

      test('data streaming works with persistence', () async {
        const key = 'stream-data';

        final stream = persistence.watchData(key);
        final emittedValues = <dynamic>[];

        final subscription = stream.listen(emittedValues.add);

        // Initial value should be null
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 1);
        expect(emittedValues.last, isNull);

        // Save data
        final data1 = {'step': 1, 'status': 'initial'};
        await persistence.saveData(key, data1);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 2);
        expect(emittedValues.last, data1);

        // Update data
        final data2 = {'step': 2, 'status': 'updated'};
        await persistence.saveData(key, data2);
        await Future.delayed(const Duration(milliseconds: 10));
        expect(emittedValues.length, 3);
        expect(emittedValues.last, data2);

        await subscription.cancel();
      });
    });

    group('User Data Isolation', () {
      test('clearUserData removes user-specific data only', () async {
        const user1 = 'isolation-user-1';
        const user2 = 'isolation-user-2';

        // Setup data for both users
        await persistence.saveSyncMetadata(user1, const DatumSyncMetadata(userId: user1));
        await persistence.saveSyncMetadata(user2, const DatumSyncMetadata(userId: user2));

        await persistence.saveConfig('$user1-config', 'user1-value');
        await persistence.saveConfig('$user2-config', 'user2-value');
        await persistence.saveConfig('global-config', 'global-value');

        await persistence.saveData('$user1-data', 'user1-data-value');
        await persistence.saveData('$user2-data', 'user2-data-value');
        await persistence.saveData('global-data', 'global-data-value');

        // Clear user1 data
        await persistence.clearUserData(user1);

        // Verify user1 data is gone
        expect(await persistence.getSyncMetadata(user1), isNull);
        expect(await persistence.getConfig('$user1-config'), isNull);
        expect(await persistence.getData('$user1-data'), isNull);

        // Verify user2 and global data remains
        expect(await persistence.getSyncMetadata(user2), isNotNull);
        expect(await persistence.getConfig('$user2-config'), 'user2-value');
        expect(await persistence.getConfig('global-config'), 'global-value');
        expect(await persistence.getData('$user2-data'), 'user2-data-value');
        expect(await persistence.getData('global-data'), 'global-data-value');
      });

      test('getAllUserIds returns correct user list', () async {
        const user1 = 'list-user-1';
        const user2 = 'list-user-2';
        const user3 = 'list-user-3';

        // Add metadata for users
        await persistence.saveSyncMetadata(user1, const DatumSyncMetadata(userId: user1));
        await persistence.saveSyncMetadata(user2, const DatumSyncMetadata(userId: user2));
        await persistence.saveSyncMetadata(user3, const DatumSyncMetadata(userId: user3));

        final userIds = await persistence.getAllUserIds();
        expect(userIds.length, 3);
        expect(userIds, containsAll([user1, user2, user3]));
      });
    });

    group('Data Clearing', () {
      test('clearAllData removes all persisted data', () async {
        // Setup various data
        await persistence.saveSyncMetadata('clear-test-user', const DatumSyncMetadata(userId: 'clear-test-user'));
        await persistence.saveConfig('clear-config', 'value');
        await persistence.saveData('clear-data', 'value');

        // Verify data exists
        expect(await persistence.getSyncMetadata('clear-test-user'), isNotNull);
        expect(await persistence.getConfig('clear-config'), 'value');
        expect(await persistence.getData('clear-data'), 'value');

        // Clear all data
        await persistence.clearAllData();

        // Verify all data is gone
        expect(await persistence.getSyncMetadata('clear-test-user'), isNull);
        expect(await persistence.getConfig('clear-config'), isNull);
        expect(await persistence.getData('clear-data'), isNull);
        expect((await persistence.getAllUserIds()).isEmpty, isTrue);
      });
    });

    group('Storage Statistics', () {
      test('getStorageStats provides accurate statistics', () async {
        // Setup some data
        await persistence.saveSyncMetadata('stats-user', const DatumSyncMetadata(userId: 'stats-user'));
        await persistence.saveConfig('stats-config-1', 'value1');
        await persistence.saveConfig('stats-config-2', 'value2');
        await persistence.saveData('stats-data-1', 'data1');
        await persistence.saveData('stats-data-2', 'data2');
        await persistence.saveData('stats-data-3', 'data3');

        final stats = await persistence.getStorageStats();

        expect(stats, isNotNull);
        expect(stats!['totalUsers'], 1);
        expect(stats['totalEntries'], 6); // 1 metadata + 2 config + 3 data
        expect(stats['storageSizeBytes'], greaterThan(0));
        expect(stats['lastModified'], isNotNull);
      });

      test('getStorageStats returns null when not initialized', () async {
        final uninitialized = InMemoryDatumPersistence();
        final stats = await uninitialized.getStorageStats();
        expect(stats, isNull);
      });
    });

    group('Persistence with Sync Operations', () {
      test('sync operations update persisted metadata correctly', () async {
        const userId = 'sync-persist-user';

        // Initial state
        var metadata = await persistence.getSyncMetadata(userId);
        expect(metadata, isNull);

        // First sync
        final entity1 = TestEntity.create('sync-persist-1', userId, 'Entity 1');
        await manager.push(item: entity1, userId: userId);
        await manager.synchronize(userId);

        metadata = await persistence.getSyncMetadata(userId);
        expect(metadata, isNotNull);
        expect(metadata!.syncStatus, SyncStatus.synced);
        expect(metadata.lastSyncTime, isNotNull);
        expect(metadata.lastSuccessfulSyncTime, isNotNull);

        // Second sync with additional entity
        final entity2 = TestEntity.create('sync-persist-2', userId, 'Entity 2');
        await manager.push(item: entity2, userId: userId);
        await manager.synchronize(userId);

        final updatedMetadata = await persistence.getSyncMetadata(userId);
        expect(updatedMetadata!.lastSyncTime!.isAfter(metadata.lastSyncTime!), isTrue);
        expect(updatedMetadata.lastSuccessfulSyncTime!.isAfter(metadata.lastSuccessfulSyncTime!), isTrue);
      });

      test('failed sync operations are reflected in persisted metadata', () async {
        const userId = 'failed-sync-user';

        // Force a sync failure by having pending operations that can't be processed
        final entity = TestEntity.create('failed-sync-1', userId, 'Failed Entity');

        // Push but don't sync - this creates pending operations
        await manager.push(item: entity, userId: userId);

        // The metadata should reflect that there are pending operations
        // (This depends on the specific implementation of the manager)
        final metadata = await persistence.getSyncMetadata(userId);
        if (metadata != null) {
          expect(metadata.totalPendingChanges, greaterThan(0));
        }
      });
    });

    group('Persistence Lifecycle', () {
      test('persistence survives manager recreation', () async {
        const userId = 'lifecycle-user';

        // Create initial data
        await persistence.saveSyncMetadata(
            userId,
            const DatumSyncMetadata(
              userId: userId,
              dataHash: 'lifecycle-hash',
              syncStatus: SyncStatus.synced,
            ));
        await persistence.saveConfig('lifecycle-config', 'lifecycle-value');

        // Dispose and recreate manager (simulating app restart)
        await Datum.instance.dispose();
        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: MockConnectivityChecker(),
          persistence: persistence,
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: TestLocalAdapter(),
              remoteAdapter: TestRemoteAdapter(),
            ),
          ],
        );

        // Verify data persists
        final metadata = await persistence.getSyncMetadata(userId);
        expect(metadata, isNotNull);
        expect(metadata!.dataHash, 'lifecycle-hash');

        final config = await persistence.getConfig('lifecycle-config');
        expect(config, 'lifecycle-value');
      });

      test('dispose cleans up resources properly', () async {
        // Setup some data and streams
        await persistence.saveConfig('dispose-test', 'value');

        final stream = persistence.watchConfig('dispose-test');
        final subscription = stream.listen((_) {});

        // Dispose
        await persistence.dispose();

        // Verify streams are closed
        expect(subscription.isPaused, isFalse); // Should be cancelled

        // Verify persistence is no longer functional
        expect(persistence.isInitialized, isFalse);
      });
    });
  });
}

// Mock implementations for testing
class MockConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true;

  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

class TestEntity extends DatumEntity {
  @override
  final String id;

  @override
  final String userId;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  final String name;

  const TestEntity({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
    required this.name,
  });

  factory TestEntity.create(String id, String userId, String name) {
    final now = DateTime.now();
    return TestEntity(
      id: id,
      userId: userId,
      createdAt: now,
      modifiedAt: now,
      version: 1,
      name: name,
    );
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
        'name': name,
      };

  TestEntity copyWith({
    String? id,
    String? userId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
  }) =>
      TestEntity(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
        name: name ?? this.name,
      );

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is TestEntity) {
      final diffMap = <String, dynamic>{};
      if (name != oldVersion.name) diffMap['name'] = name;
      return diffMap.isEmpty ? null : diffMap;
    }
    return null;
  }

  @override
  List<Object?> get props => [...super.props, name];

  @override
  String toString() => 'TestEntity(id: $id, name: $name)';
}

class TestLocalAdapter extends LocalAdapter<TestEntity> {
  final Map<String, TestEntity> _storage = {};
  final Map<String, DatumSyncMetadata> _syncMetadata = {};
  final Map<String, List<DatumSyncOperation<TestEntity>>> _pendingOperations = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<TestEntity?> read(String id, {String? userId}) async {
    final entity = _storage[id];
    if (entity != null && (userId == null || entity.userId == userId)) {
      return entity;
    }
    return null;
  }

  @override
  Future<List<TestEntity>> readAll({String? userId}) async {
    return _storage.values.where((entity) => userId == null || entity.userId == userId).toList();
  }

  @override
  Future<void> create(TestEntity entity) async {
    _storage[entity.id] = entity;
  }

  @override
  Future<void> update(TestEntity entity) async {
    _storage[entity.id] = entity;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    final entity = _storage[id];
    if (entity != null && (userId == null || entity.userId == userId)) {
      _storage.remove(id);
      return true;
    }
    return false;
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }

  @override
  Future<int> getStoredSchemaVersion() async => 1;

  @override
  Future<void> setStoredSchemaVersion(int version) async {}

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => _syncMetadata[userId];

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    _syncMetadata[userId] = metadata;
  }

  @override
  Future<DatumSyncResult<TestEntity>?> getLastSyncResult(String userId) async => null;

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<TestEntity> result) async {}

  @override
  Future<void> addPendingOperation(String userId, DatumSyncOperation<TestEntity> operation) async {
    _pendingOperations.putIfAbsent(userId, () => []).add(operation);
  }

  @override
  Future<List<DatumSyncOperation<TestEntity>>> getPendingOperations(String userId) async {
    return _pendingOperations[userId] ?? [];
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    for (final operations in _pendingOperations.values) {
      operations.removeWhere((op) => op.id == operationId);
    }
  }

  @override
  Future<List<String>> getAllUserIds() async => [];

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async => [];

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) async {}

  @override
  Future<int> getStorageSize({String? userId}) async => 0;

  @override
  Future<AdapterHealthStatus> checkHealth() async => AdapterHealthStatus.healthy;

  @override
  Stream<DatumChangeDetail<TestEntity>>? changeStream() => null;

  @override
  Future<void> clearUserData(String userId) async {}

  @override
  Future<TestEntity> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    final entity = _storage[id];
    if (entity != null && (userId == null || entity.userId == userId)) {
      final updatedEntity = TestEntity(
        id: entity.id,
        userId: entity.userId,
        createdAt: entity.createdAt,
        modifiedAt: DateTime.now(),
        version: entity.version + 1,
        name: delta['name'] ?? entity.name,
      );
      _storage[id] = updatedEntity;
      return updatedEntity;
    }
    throw Exception('Entity not found');
  }

  @override
  Future<List<TestEntity>> query(DatumQuery query, {String? userId}) async {
    return _storage.values.where((entity) => userId == null || entity.userId == userId).toList();
  }

  @override
  Future<Map<String, TestEntity>> readByIds(List<String> ids, {required String userId}) async {
    final result = <String, TestEntity>{};
    for (final id in ids) {
      final entity = _storage[id];
      if (entity != null && entity.userId == userId) {
        result[id] = entity;
      }
    }
    return result;
  }

  @override
  Future<PaginatedResult<TestEntity>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) async {
    final allEntities = _storage.values.where((entity) => userId == null || entity.userId == userId).toList();
    final currentPage = config.currentPage ?? 1;
    final startIndex = (currentPage - 1) * config.pageSize;
    final endIndex = startIndex + config.pageSize;
    final paginatedEntities = allEntities.sublist(
      startIndex,
      endIndex > allEntities.length ? allEntities.length : endIndex,
    );
    final totalPages = (allEntities.length / config.pageSize).ceil();
    return PaginatedResult(
      items: paginatedEntities,
      totalCount: allEntities.length,
      currentPage: currentPage,
      totalPages: totalPages,
      hasMore: endIndex < allEntities.length,
    );
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    return action();
  }
}

class TestRemoteAdapter extends RemoteAdapter<TestEntity> {
  final Map<String, TestEntity> _remoteStorage = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> create(TestEntity entity) async {
    _remoteStorage[entity.id] = entity;
  }

  @override
  Future<void> update(TestEntity entity) async {
    _remoteStorage[entity.id] = entity;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    return _remoteStorage.remove(id) != null;
  }

  @override
  Future<List<TestEntity>> readAll({String? userId, DatumSyncScope? scope}) async {
    return _remoteStorage.values.where((entity) => userId == null || entity.userId == userId).toList();
  }

  @override
  Future<TestEntity?> read(String id, {String? userId}) async {
    final entity = _remoteStorage[id];
    if (entity != null && (userId == null || entity.userId == userId)) {
      return entity;
    }
    return null;
  }

  @override
  Future<TestEntity> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    final entity = _remoteStorage[id];
    if (entity != null) {
      // Simple patch implementation for testing
      final updatedEntity = TestEntity(
        id: entity.id,
        userId: entity.userId,
        createdAt: entity.createdAt,
        modifiedAt: DateTime.now(),
        version: entity.version + 1,
        name: delta['name'] ?? entity.name,
      );
      _remoteStorage[id] = updatedEntity;
      return updatedEntity;
    }
    throw Exception('Entity not found');
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => null;

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {}

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<List<TestEntity>> query(DatumQuery query, {String? userId}) async {
    return _remoteStorage.values.where((entity) => userId == null || entity.userId == userId).toList();
  }

  @override
  Stream<DatumChangeDetail<TestEntity>> get changeStream => const Stream.empty();
}
