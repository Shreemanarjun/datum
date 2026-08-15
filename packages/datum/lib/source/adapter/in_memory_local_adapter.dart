import 'dart:async';
import 'dart:convert';

import 'package:datum/datum.dart';

/// A complete, dependency-free **in-memory** [LocalAdapter] implementation.
///
/// Ship-ready for tests, prototypes, and as the reference minimal adapter:
/// everything is stored in `Map`s keyed by `userId` then entity `id`. It honors
/// [DatumQuery] via [DatumQueryMatcher], emits real change streams, and provides
/// transactional backup/rollback — so it advertises [WatchableAdapter],
/// [TransactionalAdapter], and [PaginatedAdapter].
///
/// Subclass it and override individual methods to build a persistent adapter
/// without rewriting the whole 28-method surface — the in-memory behavior acts
/// as a sane default ("Base with defaults").
///
/// ```dart
/// final adapter = InMemoryLocalAdapter<Task>(fromMap: Task.fromMap);
/// ```
class InMemoryLocalAdapter<T extends DatumEntityInterface> extends LocalAdapter<T> with WatchableAdapter, TransactionalAdapter, PaginatedAdapter {
  /// Creates an in-memory adapter. [fromMap] is required so [patch] and
  /// raw-data migration can rebuild entities from maps.
  InMemoryLocalAdapter({required this.fromMap, int schemaVersion = 0}) : _schemaVersion = schemaVersion;

  /// Deserializes a stored map back into an entity of type [T].
  final T Function(Map<String, dynamic> map) fromMap;

  final Map<String, Map<String, T>> _storage = {};
  final Map<String, List<DatumSyncOperation<T>>> _pendingOps = {};
  final Map<String, DatumSyncMetadata> _metadata = {};
  final Map<String, DatumSyncResult<T>> _lastSyncResults = {};
  final _changeController = StreamController<DatumChangeDetail<T>>.broadcast();
  int _schemaVersion;

  @override
  String get name => 'InMemoryLocalAdapter';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    if (!_changeController.isClosed) await _changeController.close();
  }

  void _emit(String id, String userId, DatumOperationType type, [T? data]) {
    if (_changeController.isClosed) return;
    _changeController.add(DatumChangeDetail(
      entityId: id,
      userId: userId,
      type: type,
      timestamp: DateTime.now(),
      data: data,
    ));
  }

  @override
  Stream<DatumChangeDetail<T>>? changeStream() => _changeController.stream;

  // --- Reads ---------------------------------------------------------------

  /// Reads hand out FRESH instances (a serialize/deserialize round-trip), so
  /// callers can never mutate the stored copy through shared state — eager
  /// relation stitching writes `relations` state into the returned entity,
  /// and memoized relation caches must not outlive a single read.
  T _fresh(T entity) => fromMap(entity.toDatumMap(target: MapTarget.local));

  @override
  Future<List<T>> readAll({String? userId}) async {
    if (userId != null) return _storage[userId]?.values.map(_fresh).toList() ?? [];
    return _storage.values.expand((m) => m.values).map(_fresh).toList();
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    if (userId != null) {
      final found = _storage[userId]?[id];
      return found == null ? null : _fresh(found);
    }
    for (final byId in _storage.values) {
      final found = byId[id];
      if (found != null) return _fresh(found);
    }
    return null;
  }

  @override
  Future<Map<String, T>> readByIds(List<String> ids, {required String userId}) async {
    final byId = _storage[userId];
    if (byId == null) return {};
    return {
      for (final id in ids)
        if (byId.containsKey(id)) id: _fresh(byId[id]!),
    };
  }

  @override
  Future<List<String>> getAllUserIds() async => _storage.keys.toList();

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    return DatumQueryMatcher.apply(await readAll(userId: userId), query);
  }

  @override
  Future<PaginatedResult<T>> readAllPaginated(PaginationConfig config, {String? userId}) async {
    final all = await readAll(userId: userId);
    final totalCount = all.length;
    final totalPages = config.pageSize == 0 ? 0 : (totalCount / config.pageSize).ceil();
    final currentPage = config.currentPage ?? 1;
    final start = (currentPage - 1) * config.pageSize;
    if (start >= totalCount) {
      return PaginatedResult(items: const [], totalCount: totalCount, currentPage: currentPage, totalPages: totalPages, hasMore: false);
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

  // --- Writes --------------------------------------------------------------

  @override
  Future<void> create(T entity) async {
    final existed = _storage[entity.userId]?.containsKey(entity.id) ?? false;
    _storage.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
    _emit(entity.id, entity.userId, existed ? DatumOperationType.update : DatumOperationType.create, entity);
  }

  @override
  Future<void> update(T entity) async {
    _storage.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
    _emit(entity.id, entity.userId, DatumOperationType.update, entity);
  }

  @override
  Future<T> patch({required String id, required Map<String, dynamic> delta, String? userId}) async {
    final existing = _storage[userId ?? '']?[id];
    if (existing == null) {
      throw EntityNotFoundException(message: 'Entity $id not found for user ${userId ?? ''}.');
    }
    final patched = fromMap(existing.toDatumMap()..addAll(delta));
    await update(patched);
    return patched;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    final removed = _storage[userId ?? '']?.remove(id);
    if (removed != null) {
      _emit(id, userId ?? '', DatumOperationType.delete);
      return true;
    }
    return false;
  }

  @override
  Future<void> clearUserData(String userId) async {
    _storage.remove(userId);
    _pendingOps.remove(userId);
    _metadata.remove(userId);
    _lastSyncResults.remove(userId);
  }

  @override
  Future<void> clear() async {
    _storage.clear();
    _pendingOps.clear();
    _metadata.clear();
    _lastSyncResults.clear();
  }

  // --- Reactive ------------------------------------------------------------

  Stream<S> _watch<S>(Future<S> Function() read, {String? userId, bool includeInitialData = true}) {
    // Stream.multi runs this setup for EVERY listener, so each one gets its
    // own change subscription and its own initial snapshot — a broadcast
    // controller's onListen only fires for the first listener, leaving later
    // concurrent listeners silent until the next write.
    return Stream<S>.multi((controller) {
      // Attach the change subscription SYNCHRONOUSLY before the (async)
      // initial read — a write landing between listen and the first emission
      // must not be missed. Every emission re-reads current state, so an
      // out-of-order initial emission is harmless (at worst a duplicate).
      final sub = _changeController.stream.where((e) => userId == null || e.userId == userId).listen((_) async {
        if (!controller.isClosed) controller.add(await read());
      });
      if (includeInitialData) {
        unawaited(read().then((initial) {
          if (!controller.isClosed) controller.add(initial);
        }));
      }
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) => _watch(() => readAll(userId: userId), userId: userId, includeInitialData: includeInitialData);

  @override
  Stream<T?>? watchById(String id, {String? userId}) => _watch(() => read(id, userId: userId), userId: userId);

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) => _watch(() => this.query(query, userId: userId), userId: userId);

  @override
  Stream<PaginatedResult<T>>? watchAllPaginated(PaginationConfig config, {String? userId}) => _watch(() => readAllPaginated(config, userId: userId), userId: userId);

  @override
  Stream<int>? watchCount({DatumQuery? query, String? userId}) {
    return _watch(() async => query != null ? (await this.query(query, userId: userId)).length : (await readAll(userId: userId)).length, userId: userId);
  }

  @override
  Stream<T?>? watchFirst({DatumQuery? query, String? userId}) {
    return _watch(() async {
      final items = query != null ? await this.query(query, userId: userId) : await readAll(userId: userId);
      return items.isEmpty ? null : items.first;
    }, userId: userId);
  }

  // --- Pending operations / metadata / schema ------------------------------

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(String userId) async => List.of(_pendingOps[userId] ?? const []);

  @override
  Future<void> addPendingOperation(String userId, DatumSyncOperation<T> operation) async {
    final ops = _pendingOps.putIfAbsent(userId, () => []);
    final i = ops.indexWhere((o) => o.id == operation.id);
    if (i != -1) {
      ops[i] = operation;
    } else {
      ops.add(operation);
    }
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    for (final ops in _pendingOps.values) {
      ops.removeWhere((o) => o.id == operationId);
    }
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => _metadata[userId];

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async => _metadata[userId] = metadata;

  @override
  Future<int> getStoredSchemaVersion() async => _schemaVersion;

  @override
  Future<void> setStoredSchemaVersion(int version) async => _schemaVersion = version;

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    final items = await readAll(userId: userId);
    return items.map((e) => e.toDatumMap()).toList();
  }

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) async {
    if (userId != null && userId.isNotEmpty) {
      _storage.remove(userId);
    } else {
      _storage.clear();
    }
    for (final raw in data) {
      final entity = fromMap(raw);
      _storage.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
    }
  }

  // --- Transactions / health / size / last result -------------------------

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    final backup = _storage.map((k, v) => MapEntry(k, Map<String, T>.from(v)));
    try {
      return await action();
    } catch (_) {
      _storage
        ..clear()
        ..addAll(backup);
      rethrow;
    }
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async => AdapterHealthStatus.healthy;

  @override
  Future<int> getStorageSize({String? userId}) async {
    final items = await readAll(userId: userId);
    if (items.isEmpty) return 0;
    return utf8.encode(jsonEncode(items.map((e) => e.toDatumMap()).toList())).length;
  }

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<T> result) async => _lastSyncResults[userId] = result;

  @override
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) async => _lastSyncResults[userId];
}
