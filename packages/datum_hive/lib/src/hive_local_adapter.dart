// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:datum/datum.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:meta/meta.dart';

class HiveLocalAdapter<T extends DatumEntityInterface> extends LocalAdapter<T> {
  /// The name of the Hive box where entities of type `T` will be stored.
  final String entityBoxName;

  /// A factory function to create an instance of `T` from a `Map<String, dynamic>`.
  final T Function(Map<String, dynamic> map) fromMap;

  /// The Hive box for storing entities (`Map<String, dynamic>`).
  @protected
  late final Box<Map<dynamic, dynamic>> entityBox;

  /// The Hive box for storing pending sync operations (`List<Map<String, dynamic>>`).
  @protected
  late final Box<List<dynamic>> pendingOpsBox;

  /// The Hive box for storing metadata (`Map<String, dynamic>`).
  @protected
  late final Box<Map<dynamic, dynamic>> metadataBox;

  int schemaVersion;
  HiveLocalAdapter({
    required this.entityBoxName,
    required this.fromMap,
    this.schemaVersion = 0,
  });

  @override
  Future<void> initialize() async {
    entityBox = await Hive.openBox<Map<dynamic, dynamic>>(entityBoxName);
    pendingOpsBox = await Hive.openBox<List<dynamic>>('${entityBoxName}_pending_ops');
    metadataBox = await Hive.openBox<Map<dynamic, dynamic>>('${entityBoxName}_metadata');
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      if (entityBox.isOpen) entityBox.close(),
      if (pendingOpsBox.isOpen) pendingOpsBox.close(),
      if (metadataBox.isOpen) metadataBox.close(),
    ]);
  }

  @override
  Stream<DatumChangeDetail<T>>? changeStream() {
    return entityBox.watch().map((event) {
      final entityMap = event.value;
      final entity = entityMap != null ? fromMap(_normalizeMap(entityMap)) : null;
      return DatumChangeDetail(
        entityId: event.key as String,
        userId: entity?.userId ?? '',
        type: event.deleted ? DatumOperationType.delete : DatumOperationType.update,
        timestamp: DateTime.now(),
        data: entity,
      );
    });
  }

  @override
  Future<void> create(T entity) {
    return entityBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final entityMap = entityBox.get(id);
    if (entityMap == null) return null;
    final entity = fromMap(_normalizeMap(entityMap));
    if (userId == null || entity.userId == userId) {
      return entity;
    }
    return null;
  }

  @override
  Future<List<T>> readAll({String? userId}) async {
    final maps = (entityBox.values).where((map) => userId == null || map['userId'] == userId);
    return maps.map((map) => fromMap(_normalizeMap(map))).toList();
  }

  @override
  Future<Map<String, T>> readByIds(List<String> ids, {required String userId}) async {
    final results = <String, T>{};
    for (final id in ids) {
      final entity = await read(id, userId: userId);
      if (entity != null) {
        results[id] = entity;
      }
    }
    return results;
  }

  @override
  Future<void> update(T entity) {
    return entityBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<T> patch({required String id, required Map<String, dynamic> delta, String? userId}) async {
    final existing = entityBox.get(id);
    if (existing == null) {
      throw EntityNotFoundException(message: 'Entity with id $id not found for patch.');
    }
    final json = _normalizeMap(existing)..addAll(delta);
    final patchedItem = fromMap(json);
    await update(patchedItem);
    return patchedItem;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    if (entityBox.containsKey(id)) {
      await entityBox.delete(id);
      return true;
    }
    return false;
  }

  @override
  Future<void> clear() => entityBox.clear();

  @override
  Future<void> clearUserData(String userId) async {
    // Collect the box KEYS (not the value maps) whose entity belongs to the
    // user — deleteAll takes keys.
    final keysToDelete = [
      for (final key in entityBox.keys)
        if (entityBox.get(key)?['userId'] == userId) key,
    ];
    await Future.wait([
      entityBox.deleteAll(keysToDelete),
      pendingOpsBox.delete(userId),
      metadataBox.delete(userId),
      metadataBox.delete('last_sync_result_$userId'),
    ]);
  }

  @override
  Future<void> addPendingOperation(String userId, DatumSyncOperation<T> operation) async {
    final opsList = (pendingOpsBox.get(userId) ?? []).cast<Map<dynamic, dynamic>>().toList();
    final existingIndex = opsList.indexWhere((map) => map['id'] == operation.id);

    if (existingIndex != -1) {
      opsList[existingIndex] = operation.toMap();
    } else {
      opsList.add(operation.toMap());
    }
    await pendingOpsBox.put(userId, opsList);
  }

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(String userId) async {
    final opsList = pendingOpsBox.get(userId);
    if (opsList == null) return [];
    return opsList.cast<Map<dynamic, dynamic>>().map((raw) {
      return DatumSyncOperation.fromMap(_normalizeMap(raw), fromMap);
    }).toList();
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    for (final userId in pendingOpsBox.keys) {
      final ops = (pendingOpsBox.get(userId))?.toList();
      if (ops == null) continue;

      final initialLength = ops.length;
      ops.removeWhere((op) => (op as Map)['id'] == operationId);

      if (ops.length < initialLength) {
        await pendingOpsBox.put(userId, ops);
        // Assuming operation IDs are unique across users, we can break.
        break;
      }
    }
  }

  @override
  Future<List<String>> getAllUserIds() async {
    return (entityBox.values).map((map) => map['userId'] as String).toSet().toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    final maps = (entityBox.values).where((map) => userId == null || map['userId'] == userId);
    return maps.map(_normalizeMap).toList();
  }

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) async {
    // If a userId is provided, we should only clear their data.
    if (userId != null) {
      await clearUserData(userId);
    } else {
      await clear();
    }
    // Store the raw maps as given (no entity round-trip): Hive is schemaless,
    // and migrations may add columns the current fromMap/toDatumMap do not
    // know about yet — a round-trip would silently drop them.
    final newEntities = <String, Map<dynamic, dynamic>>{};
    for (final rawItem in data) {
      final id = rawItem['id'] as String? ?? fromMap(rawItem).id;
      newEntities[id] = Map<String, dynamic>.from(rawItem);
    }
    await entityBox.putAll(newEntities);
  }

  /// Reserved metadata-box key persisting the schema version across launches.
  static const String schemaVersionKey = '__datum_schema_version__';

  @override
  Future<int> getStoredSchemaVersion() async {
    final stored = metadataBox.get(schemaVersionKey);
    if (stored != null) return stored['version'] as int? ?? schemaVersion;
    // Nothing persisted yet: fall back to the constructor-provided baseline.
    return schemaVersion;
  }

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    schemaVersion = version;
    await metadataBox.put(schemaVersionKey, {'version': version});
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    final map = metadataBox.get(userId);
    if (map == null) return null;
    return DatumSyncMetadata.fromMap(_normalizeMap(map));
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    return await metadataBox.put(userId, metadata.toMap());
  }

  @override
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) async {
    final map = metadataBox.get('last_sync_result_$userId');
    if (map == null) return null;
    return DatumSyncResult.fromMap(_normalizeMap(map));
  }

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<T> result) {
    return metadataBox.put('last_sync_result_$userId', result.toMap());
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    // Hive does not support true ACID transactions. This implementation
    // ensures atomicity at the application level but not full DB rollback.
    // For critical operations like migrations, a database with native
    // transaction support (like SQLite) is recommended.
    return action();
  }

  @override
  Future<int> getStorageSize({String? userId}) async {
    if (!entityBox.isOpen) return 0;
    final allData = await getAllRawData(userId: userId);
    // This is a simplified calculation. A more accurate way might be to
    // sum the size of the box file on disk, but that's more complex.
    return jsonEncode(allData).length;
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    return entityBox.isOpen && pendingOpsBox.isOpen && metadataBox.isOpen ? AdapterHealthStatus.healthy : AdapterHealthStatus.unhealthy;
  }

  // Helper to convert Map<dynamic, dynamic> from Hive to Map<String, dynamic>
  Map<String, dynamic> _normalizeMap(Map<dynamic, dynamic> maybeMap) {
    return Map.fromEntries(
      maybeMap.entries.map((entry) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          return MapEntry(key, _normalizeMap(value));
        } else if (value is List) {
          return MapEntry(key, value.map((item) => item is Map ? _normalizeMap(item) : item).toList());
        }
        return MapEntry(key, value);
      }),
    );
  }

  // --- Unimplemented Reactive/Paginated Methods ---
  // These can be implemented by extending this class if needed.

  @override
  Future<PaginatedResult<T>> readAllPaginated(PaginationConfig config, {String? userId}) async {
    final all = await readAll(userId: userId);
    final totalCount = all.length;
    final totalPages = config.pageSize == 0 ? 0 : (totalCount / config.pageSize).ceil();
    final currentPage = config.currentPage ?? 1;
    final start = (currentPage - 1) * config.pageSize;
    if (start >= totalCount) {
      return PaginatedResult(
        items: const [],
        totalCount: totalCount,
        currentPage: currentPage,
        totalPages: totalPages,
        hasMore: false,
      );
    }
    final end = (start + config.pageSize > totalCount) ? totalCount : start + config.pageSize;
    return PaginatedResult(
      items: all.sublist(start, end),
      totalCount: totalCount,
      currentPage: currentPage,
      totalPages: totalPages,
      hasMore: currentPage < totalPages,
    );
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    // Hive is a key-value store with no native query engine, so we read the
    // (user-scoped) box and evaluate the DatumQuery in memory. This honors
    // filters, sorting, and limit/offset — unlike the previous readAll fallback.
    final all = await readAll(userId: userId);
    return DatumQueryMatcher.apply(all, query);
  }

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) {
    return watchAll(userId: userId)?.map((items) => DatumQueryMatcher.apply(items, query));
  }

  @override
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) {
    final Stream<BoxEvent> eventMaps = entityBox.watch();

    return eventMaps.asyncExpand(
      (event) async* {
        // 1. Await the values from the box. Use a local variable for clarity.
        final allValues = entityBox.values;

        // 2. Filter the maps. The '?? []' handles the case where 'values' is null.
        final filteredMaps = (allValues).where(
          (map) => userId == null || map['userId'] == userId,
        );

        // 3. Transform the filtered maps into your entity objects.
        final entities = filteredMaps.map((map) => fromMap(_normalizeMap(map))).toList();

        // 4. Yield the complete list as a single event on the stream.
        yield entities;
      },
    );
  }
}
