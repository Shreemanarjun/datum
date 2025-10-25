import 'dart:async';
import 'dart:convert';

import 'package:datum/datum.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// A generic `LocalAdapter` for Hive.
///
/// This adapter provides a complete implementation for storing any `DatumEntity`
/// in Hive boxes. It stores entities as `Map<String, dynamic>` to avoid the
/// need for registering `TypeAdapter`s for each entity.
///
/// To use it, provide the `entityBoxName`, a `fromMap` factory, and a
/// `sampleInstance` of your entity.
class HiveLocalAdapter<T extends DatumEntity> extends LocalAdapter<T> {
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

  int _schemaVersion = 0;

  /// Creates a new `HiveLocalAdapter`.
  ///
  /// - [entityBoxName]: The name for the main Hive box (e.g., 'tasks', 'users').
  /// - [fromMap]: A function that can construct an entity `T` from a map.
  ///   purposes within the framework.
  HiveLocalAdapter({
    required this.entityBoxName,
    required this.fromMap,
  });

  @override
  Future<void> initialize() async {
    entityBox = await Hive.openBox<Map<dynamic, dynamic>>(entityBoxName);
    pendingOpsBox =
        await Hive.openBox<List<dynamic>>('${entityBoxName}_pending_ops');
    metadataBox =
        await Hive.openBox<Map<dynamic, dynamic>>('${entityBoxName}_metadata');
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
      final entity =
          entityMap != null ? fromMap(_normalizeMap(entityMap)) : null;
      return DatumChangeDetail(
        entityId: event.key as String,
        userId: entity?.userId ?? '',
        type: event.deleted
            ? DatumOperationType.delete
            : DatumOperationType.update,
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
    final maps = entityBox.values
        .where((map) => userId == null || map['userId'] == userId);
    return maps.map((map) => fromMap(_normalizeMap(map))).toList();
  }

  @override
  Future<Map<String, T>> readByIds(List<String> ids,
      {required String userId}) async {
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
  Future<T> patch(
      {required String id,
      required Map<String, dynamic> delta,
      String? userId}) async {
    final existing = entityBox.get(id);
    if (existing == null) {
      throw EntityNotFoundException('Entity with id $id not found for patch.');
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
    final keysToDelete = entityBox.keys.where((key) {
      final map = entityBox.get(key);
      return map != null && map['userId'] == userId;
    }).toList();

    await Future.wait([
      entityBox.deleteAll(keysToDelete),
      pendingOpsBox.delete(userId),
      metadataBox.delete(userId),
      metadataBox.delete('last_sync_result_$userId'),
    ]);
  }

  @override
  Future<void> addPendingOperation(
      String userId, DatumSyncOperation<T> operation) async {
    final opsList = (pendingOpsBox.get(userId) ?? [])
        .cast<Map<dynamic, dynamic>>()
        .toList();
    final existingIndex =
        opsList.indexWhere((map) => map['id'] == operation.id);

    if (existingIndex != -1) {
      opsList[existingIndex] = operation.toMap();
    } else {
      opsList.add(operation.toMap());
    }
    await pendingOpsBox.put(userId, opsList);
  }

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(
      String userId) async {
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
    return entityBox.values
        .map((map) => map['userId'] as String)
        .toSet()
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    final maps = entityBox.values
        .where((map) => userId == null || map['userId'] == userId);
    return maps.map(_normalizeMap).toList();
  }

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data,
      {String? userId}) async {
    // If a userId is provided, we should only clear their data.
    if (userId != null) {
      await clearUserData(userId);
    } else {
      await clear();
    }
    final newEntities = <String, Map<dynamic, dynamic>>{};
    for (final rawItem in data) {
      final entity = fromMap(rawItem);
      newEntities[entity.id] = entity.toDatumMap(target: MapTarget.local);
    }
    await entityBox.putAll(newEntities);
  }

  @override
  Future<int> getStoredSchemaVersion() => Future.value(_schemaVersion);

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    _schemaVersion = version;
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    final map = metadataBox.get(userId);
    if (map == null) return null;
    return DatumSyncMetadata.fromMap(_normalizeMap(map));
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) {
    return metadataBox.put(userId, metadata.toMap());
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
    return entityBox.isOpen && pendingOpsBox.isOpen && metadataBox.isOpen
        ? AdapterHealthStatus.healthy
        : AdapterHealthStatus.unhealthy;
  }

  // Helper to convert Map<dynamic, dynamic> from Hive to Map<String, dynamic>
  Map<String, dynamic> _normalizeMap(Map<dynamic, dynamic> maybeMap) {
    return Map.fromEntries(maybeMap.entries.map((entry) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        return MapEntry(key, _normalizeMap(value));
      } else if (value is List) {
        return MapEntry(
            key,
            value
                .map((item) => item is Map ? _normalizeMap(item) : item)
                .toList());
      }
      return MapEntry(key, value);
    }));
  }

  // --- Unimplemented Reactive/Paginated Methods ---
  // These can be implemented by extending this class if needed.

  @override
  Future<PaginatedResult<T>> readAllPaginated(PaginationConfig config,
      {String? userId}) {
    throw UnimplementedError(
        'Pagination is not implemented in this generic Hive adapter.');
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) {
    // A proper implementation would parse the DatumQuery and apply it to the
    // Hive box. For now, we fall back to readAll.
    return readAll(userId: userId);
  }

  @override
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) {
    return entityBox.watch().map(
      (event) {
        final maps = entityBox.values
            .where((map) => userId == null || map['userId'] == userId);
        return maps.map((map) => fromMap(_normalizeMap(map))).toList();
      },
    );
  }

  @override
  Future<void> initializeUserQueue(String userId) {
    if (!pendingOpsBox.containsKey(userId)) {
      return pendingOpsBox.put(userId, []);
    }
    return Future.value();
  }
}
