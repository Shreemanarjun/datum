import 'dart:async';
import 'dart:convert';

import 'package:datum/datum.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:meta/meta.dart';

import 'hive_box_keys.dart';

/// A generic `LocalAdapter` for Hive.
///
/// This adapter provides a complete implementation for storing any `DatumEntity`
/// in Hive boxes. It stores entities as `Map<String, dynamic>` to avoid the
/// need for registering `TypeAdapter`s for each entity.
///
/// To use it, provide the `entityBoxName`, a `fromMap` factory, and a
/// `sampleInstance` of your entity.
class IsolatedHiveLocalAdapter<T extends DatumEntityInterface> extends LocalAdapter<T> with SchemaFingerprintCapable {
  /// The name of the Hive box where entities of type `T` will be stored.
  final String entityBoxName;

  /// A factory function to create an instance of `T` from a `Map<String, dynamic>`.
  final T Function(Map<String, dynamic> map) fromMap;

  /// The Hive box for storing entities (`Map<String, dynamic>`).
  @protected
  late final IsolatedBox<Map<dynamic, dynamic>> entityBox;

  /// The Hive box for storing pending sync operations (`List<Map<String, dynamic>>`).
  @protected
  late final IsolatedBox<List<dynamic>> pendingOpsBox;

  /// The Hive box for storing metadata (`Map<String, dynamic>`).
  @protected
  late final IsolatedBox<Map<dynamic, dynamic>> metadataBox;

  int schemaVersion;

  /// Creates a new `HiveLocalAdapter`.
  ///
  /// - [entityBoxName]: The name for the main Hive box (e.g., 'tasks', 'users').
  /// - [fromMap]: A function that can construct an entity `T` from a map.
  ///   purposes within the framework.
  IsolatedHiveLocalAdapter({
    required this.entityBoxName,
    required this.fromMap,
    this.schemaVersion = 0,
  });

  @override
  Future<void> initialize() async {
    entityBox = await IsolatedHive.openBox<Map<dynamic, dynamic>>(entityBoxName);
    pendingOpsBox = await IsolatedHive.openBox<List<dynamic>>('${entityBoxName}_pending_ops');
    metadataBox = await IsolatedHive.openBox<Map<dynamic, dynamic>>('${entityBoxName}_metadata');
    await _migrateLegacyKeys();
  }

  /// Rows written before composite keying were keyed by bare entity id, so
  /// two users could not own the same id (one silently clobbered the other).
  /// Re-key any such row as `(userId, id)` on open.
  Future<void> _migrateLegacyKeys() async {
    final rekeyed = <String, Map<dynamic, dynamic>>{};
    final staleKeys = <dynamic>[];
    for (final key in await entityBox.keys) {
      final value = await entityBox.get(key);
      if (value == null) continue;
      final userId = value['userId'] as String? ?? '';
      final id = value['id'] as String? ?? key.toString();
      final expected = hiveBoxKey(userId, id);
      if (key != expected) {
        rekeyed[expected] = value;
        staleKeys.add(key);
      }
    }
    if (rekeyed.isEmpty) return;
    await entityBox.putAll(rekeyed);
    await entityBox.deleteAll(staleKeys);
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
      // The composite key carries (userId, id) even for delete events,
      // where the value is already gone.
      final decoded = decodeHiveBoxKey(event.key as String);
      return DatumChangeDetail(
        entityId: decoded?.id ?? event.key as String,
        userId: entity?.userId ?? decoded?.userId ?? '',
        type: event.deleted ? DatumOperationType.delete : DatumOperationType.update,
        timestamp: DateTime.now(),
        data: entity,
      );
    });
  }

  @override
  Future<void> create(T entity) {
    return entityBox.put(hiveBoxKey(entity.userId, entity.id), entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    if (userId != null) {
      final entityMap = await entityBox.get(hiveBoxKey(userId, id));
      return entityMap == null ? null : fromMap(_normalizeMap(entityMap));
    }
    // Unscoped read: any user's row with this entity id.
    for (final map in await entityBox.values) {
      if (map['id'] == id) return fromMap(_normalizeMap(map));
    }
    return null;
  }

  @override
  Future<List<T>> readAll({String? userId}) async {
    final maps = (await entityBox.values).where((map) => userId == null || map['userId'] == userId);
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
    return entityBox.put(hiveBoxKey(entity.userId, entity.id), entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<T> patch({required String id, required Map<String, dynamic> delta, String? userId}) async {
    final existing = userId != null ? await entityBox.get(hiveBoxKey(userId, id)) : (await read(id))?.toDatumMap(target: MapTarget.local);
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
    if (userId != null) {
      final key = hiveBoxKey(userId, id);
      if (!await entityBox.containsKey(key)) return false;
      await entityBox.delete(key);
      return true;
    }
    // Unscoped delete: remove the id for every user that owns it.
    final keys = <dynamic>[];
    for (final key in await entityBox.keys) {
      if ((await entityBox.get(key))?['id'] == id) keys.add(key);
    }
    if (keys.isEmpty) return false;
    await entityBox.deleteAll(keys);
    return true;
  }

  @override
  Future<void> clear() => entityBox.clear();

  @override
  Future<void> clearUserData(String userId) async {
    // Collect the box KEYS (not the value maps) whose entity belongs to the
    // user — deleteAll takes keys.
    final keysToDelete = [
      for (final key in await entityBox.keys)
        if ((await entityBox.get(key))?['userId'] == userId) key,
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
    final opsList = (await pendingOpsBox.get(userId) ?? []).cast<Map<dynamic, dynamic>>().toList();
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
    final opsList = await pendingOpsBox.get(userId);
    if (opsList == null) return [];
    return opsList.cast<Map<dynamic, dynamic>>().map((raw) {
      return DatumSyncOperation.fromMap(_normalizeMap(raw), fromMap);
    }).toList();
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    for (final userId in await pendingOpsBox.keys) {
      final ops = (await pendingOpsBox.get(userId))?.toList();
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
    return (await entityBox.values).map((map) => map['userId'] as String).toSet().toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    final maps = (await entityBox.values).where((map) => userId == null || map['userId'] == userId);
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
      final owner = rawItem['userId'] as String? ?? fromMap(rawItem).userId;
      newEntities[hiveBoxKey(owner, id)] = Map<String, dynamic>.from(rawItem);
    }
    await entityBox.putAll(newEntities);
  }

  /// Reserved metadata-box key persisting the schema version across launches.
  static const String schemaVersionKey = '__datum_schema_version__';

  @override
  Future<int> getStoredSchemaVersion() async {
    final stored = await metadataBox.get(schemaVersionKey);
    if (stored != null) return stored['version'] as int? ?? schemaVersion;
    // Nothing persisted yet: fall back to the constructor-provided baseline.
    return schemaVersion;
  }

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    schemaVersion = version;
    await metadataBox.put(schemaVersionKey, {'version': version});
  }

  /// Reserved metadata-box key persisting the auto-migration fingerprint.
  static const String schemaFingerprintKey = '__datum_schema_fingerprint__';

  @override
  Future<String?> getStoredSchemaFingerprint() async {
    final stored = await metadataBox.get(schemaFingerprintKey);
    return stored?['fingerprint'] as String?;
  }

  @override
  Future<void> setStoredSchemaFingerprint(String fingerprint) async {
    await metadataBox.put(schemaFingerprintKey, {'fingerprint': fingerprint});
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    final map = await metadataBox.get(userId);
    if (map == null) return null;
    return DatumSyncMetadata.fromMap(_normalizeMap(map));
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    return await metadataBox.put(userId, metadata.toMap());
  }

  @override
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) async {
    final map = await metadataBox.get('last_sync_result_$userId');
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
    // Evaluate the DatumQuery in memory over the user-scoped box contents.
    final all = await readAll(userId: userId);
    return DatumQueryMatcher.apply(all, query);
  }

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) {
    return watchAll(userId: userId)?.map((items) => DatumQueryMatcher.apply(items, query));
  }

  @override
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) {
    // Stream.multi: every listener gets its own box subscription AND its own
    // initial snapshot (the previous single-subscription pipeline broke on a
    // second listener and starved snapshots).
    return Stream<List<T>>.multi((controller) {
      final sub = entityBox.watch().listen((_) async {
        if (!controller.isClosed) controller.add(await readAll(userId: userId));
      });
      if (includeInitialData) {
        unawaited(
          readAll(userId: userId).then((initial) {
            if (!controller.isClosed) controller.add(initial);
          }),
        );
      }
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<T?>? watchById(String id, {String? userId}) {
    return Stream<T?>.multi((controller) {
      final sub = entityBox.watch().listen((event) async {
        final decoded = decodeHiveBoxKey(event.key as String);
        final changedId = decoded?.id ?? event.key as String;
        if (changedId != id) return;
        if (!controller.isClosed) controller.add(await read(id, userId: userId));
      });
      unawaited(
        read(id, userId: userId).then((initial) {
          if (!controller.isClosed) controller.add(initial);
        }),
      );
      controller.onCancel = sub.cancel;
    });
  }
}
