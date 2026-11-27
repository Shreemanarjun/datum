import 'package:datum/datum.dart';

/// The shared store behind every [InMemoryRemoteAdapter] built over it — the
/// in-process stand-in for a backend that several devices talk to.
///
/// Rows are stored as serialized maps (never live entity objects), so two
/// adapters over one backend never alias each other's instances.
class InMemoryRemoteBackend {
  /// rows[userId][entityId] = remote map.
  final Map<String, Map<String, Map<String, dynamic>>> rows = {};

  /// Per-user sync metadata.
  final Map<String, DatumSyncMetadata> metadata = {};

  final Map<String, ({int status, int times})> _faults = {};

  /// Makes the next [times] writes (create/update/patch/delete) touching
  /// [entityId] fail with an HTTP-like [status], mapped onto Datum's exception
  /// taxonomy exactly like [HttpRemoteAdapter]: 404 → not found, 409 →
  /// conflict, 5xx → retryable network error, anything else → non-retryable.
  /// `times <= 0` disarms the fault.
  void failWrites(String entityId, {int status = 500, int times = 1}) {
    if (times <= 0) {
      _faults.remove(entityId);
    } else {
      _faults[entityId] = (status: status, times: times);
    }
  }

  /// Wipes rows, metadata and armed faults.
  void reset() {
    rows.clear();
    metadata.clear();
    _faults.clear();
  }

  void _maybeFail(String entityId) {
    final fault = _faults[entityId];
    if (fault == null) return;
    if (fault.times <= 1) {
      _faults.remove(entityId);
    } else {
      _faults[entityId] = (status: fault.status, times: fault.times - 1);
    }
    throw switch (fault.status) {
      404 => EntityNotFoundException(message: 'Entity $entityId not found'),
      401 => AuthenticationException(message: 'Injected 401 on $entityId'),
      409 => ConflictException(message: 'Injected conflict on $entityId'),
      final s => NetworkException(
        message: 'Injected status $s on $entityId',
        isRetryable: s >= 500 || s == 408 || s == 429,
      ),
    };
  }
}

/// A [RemoteAdapter] over an [InMemoryRemoteBackend]: full pulls only (no
/// delta/cursor capability), strict update/patch/delete (missing rows throw
/// [EntityNotFoundException], like a real REST backend's 404), and
/// create-as-upsert (an idempotent retry of a create never duplicates).
class InMemoryRemoteAdapter<T extends DatumEntityInterface>
    extends RemoteAdapter<T> {
  InMemoryRemoteAdapter({required this.backend, required this.fromMap});

  final InMemoryRemoteBackend backend;
  final T Function(Map<String, dynamic> map) fromMap;

  @override
  String get name => 'InMemoryRemoteAdapter';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<DatumChangeDetail<T>>? get changeStream => null;

  Map<String, dynamic>? _find(String id, String? userId) {
    if (userId != null) return backend.rows[userId]?[id];
    for (final byId in backend.rows.values) {
      if (byId[id] case final hit?) return hit;
    }
    return null;
  }

  T _decode(Map<String, dynamic> map) => fromMap(Map.of(map));

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    final maps = userId != null
        ? (backend.rows[userId]?.values ?? const <Map<String, dynamic>>[])
        : backend.rows.values.expand((m) => m.values);
    final items = maps.map(_decode).toList();
    return scope == null ? items : DatumQueryMatcher.apply(items, scope.query);
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final map = _find(id, userId);
    return map == null ? null : _decode(map);
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async =>
      DatumQueryMatcher.apply(await readAll(userId: userId), query);

  void _put(T entity) {
    (backend.rows[entity.userId] ??= {})[entity.id] = entity.toDatumMap(
      target: MapTarget.remote,
    );
  }

  @override
  Future<void> create(T entity) async {
    backend._maybeFail(entity.id);
    _put(entity);
  }

  @override
  Future<void> update(T entity) async {
    backend._maybeFail(entity.id);
    if (_find(entity.id, entity.userId) == null) {
      throw EntityNotFoundException(message: 'Entity ${entity.id} not found');
    }
    _put(entity);
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    backend._maybeFail(id);
    final existing = _find(id, userId);
    if (existing == null) {
      throw EntityNotFoundException(message: 'Entity $id not found');
    }
    existing.addAll(delta);
    return _decode(existing);
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    backend._maybeFail(id);
    final owner =
        userId ??
        backend.rows.keys.firstWhere(
          (u) => backend.rows[u]!.containsKey(id),
          orElse: () => '',
        );
    if (backend.rows[owner]?.remove(id) == null) {
      throw EntityNotFoundException(message: 'Entity $id not found');
    }
    return true;
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async =>
      backend.metadata[userId];

  @override
  Future<void> updateSyncMetadata(
    DatumSyncMetadata metadata,
    String userId,
  ) async => backend.metadata[userId] = metadata;

  @override
  Future<bool> isConnected() async => true;
}

/// An [InMemoryRemoteAdapter] that refuses an edit of a row that has moved
/// past the version the edit started from (see [GuardedWriteCapable]): the
/// in-process stand-in for a backend with `UPDATE ... WHERE version <= :base`.
class GuardedInMemoryRemoteAdapter<T extends DatumEntityInterface>
    extends InMemoryRemoteAdapter<T>
    with GuardedWriteCapable<T> {
  GuardedInMemoryRemoteAdapter({required super.backend, required super.fromMap});

  /// The stored row [id], checked against [baseVersion]. No await between
  /// this and the write that follows, so the two are one step.
  Map<String, dynamic> _unchanged(String id, int baseVersion, String? userId) {
    backend._maybeFail(id);
    final existing = _find(id, userId);
    if (existing == null) {
      throw EntityNotFoundException(message: 'Entity $id not found');
    }
    final version = _decode(existing).version;
    if (version > baseVersion) {
      throw ConflictException(
        message: 'Entity $id is at version $version, past $baseVersion',
      );
    }
    return existing;
  }

  @override
  Future<Set<String>> createAllIfAbsent(List<T> entities) async {
    final taken = <String>{};
    for (final entity in entities) {
      backend._maybeFail(entity.id);
      _find(entity.id, entity.userId) == null
          ? _put(entity)
          : taken.add(entity.id);
    }
    return taken;
  }

  @override
  Future<void> patchIfUnchanged({
    required String id,
    required Map<String, dynamic> delta,
    required int baseVersion,
    String? userId,
  }) async => _unchanged(id, baseVersion, userId).addAll(delta);

  @override
  Future<void> deleteIfUnchanged(
    String id, {
    required int baseVersion,
    String? userId,
  }) async {
    final row = _unchanged(id, baseVersion, userId);
    backend.rows[_decode(row).userId]?.remove(id);
  }
}
