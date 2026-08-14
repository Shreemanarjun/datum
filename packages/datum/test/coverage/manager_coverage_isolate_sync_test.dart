import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart' show applyQuery;
import '../mocks/test_entity.dart';
import 'manager_coverage_helpers.dart' show OnlineConnectivity, makeEntity;

/// Coverage for the `useIsolateSync` path of DatumManager.synchronize, which
/// captures all dependencies into locals and offloads the sync to Isolate.run.
///
/// The adapters below are deliberately plain (no stream controllers, no
/// closures) so the whole object graph is sendable across the isolate
/// boundary.

class PlainLocalAdapter extends LocalAdapter<TestEntity> {
  final Map<String, Map<String, TestEntity>> store = {};
  final Map<String, List<DatumSyncOperation<TestEntity>>> pendingOps = {};
  final Map<String, DatumSyncMetadata> metadataByUser = {};
  final Map<String, DatumSyncResult<TestEntity>> lastResults = {};
  int schemaVersion = 0;

  @override
  Future<void> initialize() async {}

  @override
  Stream<DatumChangeDetail<TestEntity>>? changeStream() => null;

  @override
  Future<List<TestEntity>> readAll({String? userId}) async {
    if (userId != null) return store[userId]?.values.toList() ?? [];
    return store.values.expand((m) => m.values).toList();
  }

  @override
  Future<TestEntity?> read(String id, {String? userId}) async {
    if (userId != null) return store[userId]?[id];
    for (final userStore in store.values) {
      final found = userStore[id];
      if (found != null) return found;
    }
    return null;
  }

  @override
  Future<Map<String, TestEntity>> readByIds(List<String> ids, {required String userId}) async {
    final userStore = store[userId] ?? {};
    return {
      for (final id in ids)
        if (userStore.containsKey(id)) id: userStore[id]!,
    };
  }

  @override
  Future<List<String>> getAllUserIds() async => store.keys.toList();

  @override
  Future<PaginatedResult<TestEntity>> readAllPaginated(PaginationConfig config, {String? userId}) async {
    final items = await readAll(userId: userId);
    return PaginatedResult(
      items: items,
      totalCount: items.length,
      currentPage: 1,
      totalPages: 1,
      hasMore: false,
    );
  }

  @override
  Future<List<TestEntity>> query(DatumQuery query, {String? userId}) async => applyQuery(await readAll(userId: userId), query);

  @override
  Future<void> create(TestEntity entity) async {
    store.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
  }

  @override
  Future<void> update(TestEntity entity) async => create(entity);

  @override
  Future<TestEntity> patch({required String id, required Map<String, dynamic> delta, String? userId}) async {
    final existing = store[userId ?? '']?[id];
    if (existing == null) throw StateError('missing entity $id');
    final patched = TestEntity.fromJson(existing.toDatumMap()..addAll(delta));
    store.putIfAbsent(patched.userId, () => {})[id] = patched;
    return patched;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    return store[userId ?? '']?.remove(id) != null;
  }

  @override
  Future<void> clearUserData(String userId) async {
    store.remove(userId);
    pendingOps.remove(userId);
  }

  @override
  Future<void> clear() async {
    store.clear();
    pendingOps.clear();
    metadataByUser.clear();
  }

  @override
  Future<List<DatumSyncOperation<TestEntity>>> getPendingOperations(String userId) async => List.of(pendingOps[userId] ?? []);

  @override
  Future<void> addPendingOperation(String userId, DatumSyncOperation<TestEntity> operation) async {
    final ops = pendingOps.putIfAbsent(userId, () => []);
    final index = ops.indexWhere((op) => op.id == operation.id);
    if (index >= 0) {
      ops[index] = operation;
    } else {
      ops.add(operation);
    }
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    for (final ops in pendingOps.values) {
      ops.removeWhere((op) => op.id == operationId);
    }
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => metadataByUser[userId];

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    metadataByUser[userId] = metadata;
  }

  @override
  Future<int> getStoredSchemaVersion() async => schemaVersion;

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    schemaVersion = version;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async => (await readAll(userId: userId)).map((e) => e.toDatumMap()).toList();

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) async {}

  @override
  Future<R> transaction<R>(Future<R> Function() action) => action();

  @override
  Future<void> dispose() async {}

  @override
  Future<int> getStorageSize({String? userId}) async => 0;

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<TestEntity> result) async {
    lastResults[userId] = result;
  }

  @override
  Future<DatumSyncResult<TestEntity>?> getLastSyncResult(String userId) async => lastResults[userId];
}

class PlainRemoteAdapter extends RemoteAdapter<TestEntity> {
  final Map<String, Map<String, TestEntity>> store = {};
  final Map<String, DatumSyncMetadata> metadataByUser = {};

  @override
  Future<void> initialize() async {}

  @override
  Stream<DatumChangeDetail<TestEntity>>? get changeStream => null;

  @override
  Future<List<TestEntity>> readAll({String? userId, DatumSyncScope? scope}) async {
    if (userId != null) return store[userId]?.values.toList() ?? [];
    return store.values.expand((m) => m.values).toList();
  }

  @override
  Future<TestEntity?> read(String id, {String? userId}) async => store[userId ?? '']?[id];

  @override
  Future<List<TestEntity>> query(DatumQuery query, {String? userId}) async => applyQuery(await readAll(userId: userId), query);

  @override
  Future<void> create(TestEntity entity) async {
    store.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
  }

  @override
  Future<void> update(TestEntity entity) async => create(entity);

  @override
  Future<TestEntity> patch({required String id, required Map<String, dynamic> delta, String? userId}) async {
    final existing = store[userId ?? '']?[id];
    if (existing == null) throw StateError('missing remote entity $id');
    final patched = TestEntity.fromJson(existing.toDatumMap()..addAll(delta));
    store.putIfAbsent(patched.userId, () => {})[id] = patched;
    return patched;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async => store[userId ?? '']?.remove(id) != null;

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => metadataByUser[userId];

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    metadataByUser[userId] = metadata;
  }

  @override
  Future<bool> isConnected() async => true;
}

void main() {
  group('useIsolateSync', () {
    // The isolate spawn goes through a top-level trampoline whose own type
    // parameter carries T; a closure built inside DatumManager would
    // reference the CLASS type parameter, and Dart closures capture `this`
    // to reach instance type arguments — which used to drag the manager
    // (unsendable stream controllers included) into the isolate send and
    // fail every isolate sync with an ArgumentError.
    test('synchronize completes a pull cycle inside the isolate', () async {
      final localAdapter = PlainLocalAdapter();
      final remoteAdapter = PlainRemoteAdapter();
      // Data the pull phase processes inside the isolate.
      remoteAdapter.store['u1'] = {'r1': makeEntity('r1', name: 'remote-item')};

      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(
          enableLogging: false,
          useIsolateSync: true,
        ),
      );
      await manager.initialize();

      final result = await manager.synchronize('u1');

      expect(result.userId, 'u1');
      expect(result.failedCount, 0);

      // Isolate.run deep-copies the adapters, so an IN-MEMORY store's side
      // effects stay inside the isolate — only the returned result crosses
      // back. Real adapters (Hive/SQLite/network) share their storage, so
      // their writes persist. Pinned here so the copy semantics are explicit.
      expect(localAdapter.store['u1'], isNull);

      await manager.dispose();
    });

    test('trySynchronize returns success through the isolate path', () async {
      final manager = DatumManager<TestEntity>(
        localAdapter: PlainLocalAdapter(),
        remoteAdapter: PlainRemoteAdapter(),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(
          enableLogging: false,
          useIsolateSync: true,
        ),
      );
      await manager.initialize();

      final result = await manager.trySynchronize('u1');
      expect(result.isSuccess(), isTrue, reason: '${result.failure}');

      await manager.dispose();
    });
  });
}
