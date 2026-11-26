import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:datum/datum.dart';
import 'package:hive_ce/hive_ce.dart';
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

  /// Pending sync operations keyed by operation id, each stored as
  /// `{...op.toMap(), '_owner': userId, '_seq': int}`: add/replace/remove
  /// are single-key writes; reads filter by owner and order by `_seq`.
  @protected
  late final IsolatedBox<Map<dynamic, dynamic>> pendingOpsBox;

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

  bool _initialized = false;

  /// Opens the boxes. Idempotent: [DatumManager.initialize] initializes its
  /// adapter even when the caller already did.
  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    entityBox = await IsolatedHive.openBox<Map<dynamic, dynamic>>(entityBoxName);
    pendingOpsBox = await IsolatedHive.openBox<Map<dynamic, dynamic>>('${entityBoxName}_pending_queue');
    await _migrateLegacyPendingOps();
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
      final entity = fromMap(_normalizeMap(value));
      final (userId, id) = (entity.userId, entity.id);
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
    // ponytail: parses every row to read its owner (map key names vary, e.g.
    // generated entities store `user_id`); index by box-key prefix if huge.
    final all = (await entityBox.values).map((map) => fromMap(_normalizeMap(map)));
    return [for (final e in all) if (userId == null || e.userId == userId) e];
  }

  @override
  Future<Map<String, T>> readByIds(List<String> ids, {required String userId}) async {
    // Issue every isolate round-trip at once instead of one after another.
    final entities = await Future.wait([for (final id in ids) read(id, userId: userId)]);
    return {
      for (var i = 0; i < ids.length; i++)
        if (entities[i] != null) ids[i]: entities[i]!,
    };
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
        if (_ownerOf(await entityBox.get(key)) == userId) key,
    ];
    await Future.wait([
      entityBox.deleteAll(keysToDelete),
      pendingOpsBox.deleteAll([for (final row in await pendingOpsBox.values) if (row[_ownerKey] == userId) row['id']]),
      metadataBox.delete(userId),
      metadataBox.delete('last_sync_result_$userId'),
    ]);
  }

  static const _ownerKey = '_owner';
  static const _seqKey = '_seq';
  int _lastSeq = 0;

  /// Queue position: wall-clock micros (so order survives restarts), bumped
  /// on ties so it is strictly increasing within this instance.
  int _nextSeq() => _lastSeq = max(_lastSeq + 1, DateTime.now().microsecondsSinceEpoch);

  /// The queue used to be one `List` per user in `<box>_pending_ops`, so every
  /// enqueue/dequeue rewrote the whole list (O(n²) for n queued ops). Move any
  /// such ops, in order, into the keyed queue and drop the legacy box.
  Future<void> _migrateLegacyPendingOps() async {
    final legacyName = '${entityBoxName}_pending_ops';
    if (!await IsolatedHive.boxExists(legacyName)) return;
    final legacy = await IsolatedHive.openBox<List<dynamic>>(legacyName);
    final moved = <dynamic, Map<dynamic, dynamic>>{
      for (final userId in await legacy.keys)
        for (final raw in await legacy.get(userId) ?? const [])
          (raw as Map)['id']: {...raw, _ownerKey: userId, _seqKey: _nextSeq()},
    };
    if (moved.isNotEmpty) await pendingOpsBox.putAll(moved);
    await legacy.deleteFromDisk();
  }

  @override
  Future<void> addPendingOperation(String userId, DatumSyncOperation<T> operation) async {
    // A re-queued op (e.g. a retry) keeps its original position.
    final existing = await pendingOpsBox.get(operation.id);
    await pendingOpsBox.put(operation.id, {
      ...operation.toMap(),
      _ownerKey: userId,
      _seqKey: existing?[_seqKey] ?? _nextSeq(),
    });
  }

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(String userId) async {
    final rows = (await pendingOpsBox.values).where((row) => row[_ownerKey] == userId).toList()
      ..sort((a, b) => (a[_seqKey] as int).compareTo(b[_seqKey] as int));
    return [for (final row in rows) DatumSyncOperation.fromMap(_normalizeMap(row), fromMap)];
  }

  @override
  Future<void> removePendingOperation(String operationId) => pendingOpsBox.delete(operationId);

  @override
  Future<List<String>> getAllUserIds() async {
    return (await entityBox.values).map(_ownerOf).nonNulls.toSet().toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    final maps = (await entityBox.values).where((map) => userId == null || _ownerOf(map) == userId);
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
      final entity = fromMap(rawItem);
      final (owner, id) = (entity.userId, entity.id);
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

  /// Reserved metadata-box key persisting the migration history.
  static const String migrationHistoryKey = '__datum_migrations__';

  @override
  Future<List<MigrationRecord>> getMigrationHistory() async {
    final stored = await metadataBox.get(migrationHistoryKey);
    final rows = stored?['records'] as List? ?? const [];
    return [for (final row in rows) MigrationRecord.fromMap(_normalizeMap(row as Map))];
  }

  @override
  Future<void> recordMigration(MigrationRecord record) async {
    final history = await getMigrationHistory();
    await metadataBox.put(migrationHistoryKey, {
      'records': [for (final r in [...history, record]) r.toMap()],
    });
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
  /// The owning user of a stored row, read through [fromMap] so it works
  /// whatever key the entity uses (`userId`, `user_id`, …).
  String? _ownerOf(Map<dynamic, dynamic>? map) => map == null ? null : fromMap(_normalizeMap(map)).userId;

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
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) => rereadingWatch(
        entityBox.watch().where((e) => userId == null || decodeHiveBoxKey(e.key as String)?.userId == userId),
        () => readAll(userId: userId),
        includeInitialData: includeInitialData,
      );

  @override
  Stream<T?>? watchById(String id, {String? userId}) => rereadingWatch(
        entityBox.watch().where((e) => (decodeHiveBoxKey(e.key as String)?.id ?? e.key) == id),
        () => read(id, userId: userId),
      );
}
