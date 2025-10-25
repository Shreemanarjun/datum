import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:datum/datum.dart';
import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:rxdart/rxdart.dart' show MergeStream, Rx, SwitchMapExtension;

class MockLocalAdapter<T extends DatumEntityBase> implements LocalAdapter<T> {
  MockLocalAdapter({this.fromJson, this.relatedAdapters});

  final Map<String, Map<String, T>> _storage = {};
  final Map<String, Map<String, Map<String, dynamic>>> _rawStorage = {};
  final Map<String, List<DatumSyncOperation<T>>> _pendingOps = {};
  final _changeController = StreamController<DatumChangeDetail<T>>.broadcast();

  int _schemaVersion = 0;

  /// When true, prevents push/patch/delete from emitting changes.
  bool silent = false;

  /// A function to deserialize JSON into an entity of type T.
  final T Function(Map<String, dynamic>)? fromJson;

  /// A map of related adapters for testing relational queries.
  final Map<Type, LocalAdapter<DatumEntityBase>>? relatedAdapters;

  /// An external stream to drive reactive queries, typically from DatumManager.
  Stream<DataChangeEvent<T>>? externalChangeStream;

  final Map<String, DatumSyncMetadata?> _metadata = {}; // ignore: unused_field
  final Map<String, DatumSyncResult<T>?> _lastSyncResults = {};

  @override
  String get name => 'MockLocalAdapter';

  @override
  Future<void> initialize() async {
    // No-op for mock
  }

  @override
  Future<List<T>> readAll({String? userId}) async {
    if (userId != null) {
      return _storage[userId]?.values.toList() ?? [];
    }
    return _storage.values.expand((map) => map.values).toList();
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    if (userId != null) {
      return _storage[userId]?[id];
    }
    // If no userId is provided, search across all users.
    for (final userStorage in _storage.values) {
      if (userStorage.containsKey(id)) return userStorage[id];
    }
    return null;
  }

  @override
  Future<Map<String, T>> readByIds(
    List<String> ids, {
    required String userId,
  }) async {
    final userStorage = _storage[userId];
    if (userStorage == null) return {};

    final results = <String, T>{};
    for (final id in ids) {
      if (userStorage.containsKey(id)) results[id] = userStorage[id]!;
    }
    return results;
  }

  @override
  Future<void> create(T entity) async {
    // Delegate to the synchronized push method to ensure atomicity.
    await push(entity);
  }

  @override
  Future<void> update(T entity) async {
    // Delegate to the synchronized push method to ensure atomicity.
    await push(entity);
  }

  /// A custom method for tests that combines create/update logic.
  Future<void> push(T item) async {
    final bool exists = _storage[item.userId]?.containsKey(item.id) ?? false;
    // ignore: avoid_print
    print(
      '[MockLocalAdapter] push: id=${item.id}, userId=${item.userId}, exists: $exists',
    );
    _storage.putIfAbsent(item.userId, () => {})[item.id] = item; // This now correctly overwrites
    // Add a microtask delay BEFORE emitting the change to ensure the storage
    // update is settled. This helps prevent race conditions in reactive tests
    // where a stream might query the data before it's fully updated.
    await Future<void>.delayed(Duration.zero);
    if (!silent) {
      _changeController.add(
        DatumChangeDetail(
          entityId: item.id,
          userId: item.userId,
          type: exists ? DatumOperationType.update : DatumOperationType.create,
          timestamp: DateTime.now(),
          data: item,
        ),
      );
    }
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    if (fromJson == null) {
      throw StateError('MockLocalAdapter needs fromJson to handle patch.');
    }
    final existing = _storage[userId ?? '']?[id];
    if (existing == null) {
      throw Exception('Entity with id $id not found for user ${userId ?? ''}.');
    }

    final json = existing.toDatumMap()..addAll(delta);
    final patchedItem = fromJson!(json);
    // Delegate to the push method to ensure atomicity.
    await push(patchedItem);
    return patchedItem;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    // ignore: avoid_print
    print('[MockLocalAdapter] delete: id=$id, userId=${userId ?? 'null'}');
    final item = _storage[userId ?? '']?.remove(id);
    if (item != null) {
      // Add a microtask delay to ensure the storage update is settled before
      // the change event is broadcast. This helps prevent race conditions in
      // reactive tests.
      await Future<void>.delayed(Duration.zero);
      if (!silent) {
        _changeController.add(
          DatumChangeDetail(
            entityId: id,
            userId: userId ?? '',
            type: DatumOperationType.delete,
            timestamp: DateTime.now(),
          ),
        );
      }
      return true;
    }
    return false;
  }

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(
    String userId,
  ) async {
    return List.from(_pendingOps[userId] ?? []);
  }

  /// Synchronously gets pending operations for a user. For testing only.
  List<DatumSyncOperation<T>> getPending(String userId) {
    return _pendingOps[userId] ?? [];
  }

  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<T> operation,
  ) async {
    final userOps = _pendingOps.putIfAbsent(userId, () => []);
    // Handle updates for retry logic by replacing if exists, otherwise add.
    final existingIndex = userOps.indexWhere((op) => op.id == operation.id);
    if (existingIndex != -1) {
      userOps[existingIndex] = operation;
    } else {
      userOps.add(operation);
    }
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    for (final ops in _pendingOps.values) {
      ops.removeWhere((op) => op.id == operationId);
    }
  }

  @override
  Future<void> clearUserData(String userId) async {
    _storage.remove(userId);
    _pendingOps.remove(userId);
    _metadata.remove(userId);
  }

  @override
  Future<void> initializeUserQueue(String userId) async {
    // For the mock, this ensures the list for the user exists.
    _pendingOps.putIfAbsent(userId, () => []);
  }

  @override
  Future<void> clear() async {
    // ignore: avoid_print
    print(
      '[MockLocalAdapter] clear: Wiping all storage, pending ops, and metadata.',
    );
    _storage.clear();
    _pendingOps.clear();
    _metadata.clear();
    _rawStorage.clear();
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    return _metadata[userId];
  }

  @override
  Future<void> updateSyncMetadata(
    DatumSyncMetadata metadata,
    String userId,
  ) async {
    _metadata[userId] = metadata;
  }

  @override
  Future<void> dispose() async {
    // In a test environment, we often want the data to persist across
    // manager instances. We only close the stream controller to prevent leaks.
    // The clear() method can be called manually in tests if needed. Add a check
    // to prevent closing an already closed controller.
    if (!_changeController.isClosed) await _changeController.close();
  }

  /// Helper to simulate an external change for testing.
  void emitChange(DatumChangeDetail<T> change) {
    _changeController.add(change);
  }

  @override
  Stream<DatumChangeDetail<T>>? changeStream() {
    return _changeController.stream;
  }

  @override
  Stream<int>? schemaVersionStream() {
    return null;
  }

  @override
  Stream<List<T>>? watchAll({String? userId, bool? includeInitialData}) {
    // Use the external stream if provided, otherwise fall back to the internal one.
    final stream = externalChangeStream;
    if (stream == null) return null;

    final updateStream = stream.where((event) => userId == null || event.userId == userId).asyncMap((_) => readAll(userId: userId));

    if (includeInitialData ?? true) {
      final initialDataStream = Stream.fromFuture(readAll(userId: userId));
      return Rx.merge([initialDataStream, updateStream]).asBroadcastStream();
    }
    return updateStream;
  }

  @override
  Stream<T?>? watchById(String id, {String? userId}) {
    final stream = externalChangeStream;
    if (stream == null) return null;

    final initialDataStream = Stream.fromFuture(read(id, userId: userId));
    final updateStream = stream
        .where(
          (event) => event.data?.id == id && (userId == null || event.userId == userId),
        )
        .asyncMap((_) => read(id, userId: userId));

    return MergeStream([initialDataStream, updateStream]).asBroadcastStream();
  }

  @override
  Future<PaginatedResult<T>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) async {
    final allItems = await readAll(userId: userId);
    final totalCount = allItems.length;
    final totalPages = (totalCount / config.pageSize).ceil();
    final currentPage = config.currentPage ?? 1;

    final startIndex = (currentPage - 1) * config.pageSize;
    if (startIndex >= totalCount) {
      return PaginatedResult(
        items: const [],
        totalCount: totalCount,
        currentPage: currentPage,
        totalPages: totalPages,
        hasMore: false,
      );
    }

    final endIndex = (startIndex + config.pageSize > totalCount) ? totalCount : startIndex + config.pageSize;
    final pageItems = allItems.sublist(startIndex, endIndex);

    return PaginatedResult(
      items: pageItems,
      totalCount: totalCount,
      currentPage: currentPage,
      totalPages: totalPages,
      hasMore: currentPage < totalPages,
    );
  }

  @override
  Stream<PaginatedResult<T>>? watchAllPaginated(
    PaginationConfig config, {
    String? userId, // ignore: avoid_unused_constructor_parameters
  }) {
    final stream = externalChangeStream;
    if (stream == null) return null;

    final initialDataStream = Stream.fromFuture(
      readAllPaginated(config, userId: userId),
    );
    final updateStream = stream.where((event) => userId == null || event.userId == userId).asyncMap((_) => readAllPaginated(config, userId: userId));

    return Rx.concat([initialDataStream, updateStream]);
  }

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) {
    final stream = externalChangeStream;
    if (stream == null) return null;

    // Helper to apply query
    Future<List<T>> getFiltered() async {
      return applyQuery(await readAll(userId: userId), query);
    }

    final initialDataStream = Stream.fromFuture(getFiltered());
    final updateStream = stream.where((event) => userId == null || event.userId == userId).asyncMap((_) => getFiltered());

    return Rx.concat([initialDataStream, updateStream]).asBroadcastStream();
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    // Simulate querying by fetching all and then applying the query logic.
    final allItems = await readAll(userId: userId);
    return applyQuery(allItems, query);
  }

  @override
  Stream<int>? watchCount({DatumQuery? query, String? userId}) {
    final sourceStream = query != null ? watchQuery(query, userId: userId) : watchAll(userId: userId);

    return sourceStream?.map((list) => list.length);
  }

  @override
  Stream<T?>? watchFirst({DatumQuery? query, String? userId}) {
    final sourceStream = query != null ? watchQuery(query, userId: userId) : watchAll(userId: userId);

    return sourceStream?.map((list) => list.isNotEmpty ? list.first : null);
  }

  /// Executes a block of code as a single, atomic operation.
  ///
  /// This is crucial for multi-step processes where all steps must succeed or
  /// fail together, ensuring the database is not left in an inconsistent state.
  /// A prime use case is schema migrations, where multiple data transformations
  /// must be applied atomically.
  ///
  /// This mock implementation achieves atomicity by:
  /// 1. Using a `synchronized` lock to prevent any other transactions from
  ///    running concurrently.
  /// 2. Creating a backup of the in-memory storage before executing the `action`.
  /// 3. If the `action` completes successfully, the changes are committed.
  /// 4. If the `action` throws an error, all changes are rolled back by
  ///    restoring the data from the backup.
  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    // This is a simplified mock transaction. It doesn't provide true rollback
    // for the in-memory map, but it allows testing the flow.
    // A real implementation (e.g., with semaphores or temporary state)
    // would be more complex.
    final backupStorage = _storage.map<String, Map<String, T>>(
      (key, value) => MapEntry(key, Map<String, T>.from(value)),
    );
    try {
      return await action();
    } catch (e) {
      // Restore from backup on error
      _storage
        ..clear()
        ..addAll(backupStorage);
      rethrow;
    }
  }

  /// Helper to directly add an item to the mock storage for test setup.
  void addLocalItem(String userId, T item) {
    _storage.putIfAbsent(userId, () => {})[item.id] = item;
  }

  @override
  Future<List<String>> getAllUserIds() async {
    return _storage.keys.toList();
  }

  @override
  Future<int> getStoredSchemaVersion() async {
    return _schemaVersion;
  }

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    _schemaVersion = version;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    // Prioritize raw storage if it has data, otherwise use regular storage.
    if (_rawStorage.isNotEmpty) {
      if (userId != null) {
        return _rawStorage[userId]?.values.toList() ?? [];
      }
      return _rawStorage.values.expand((map) => map.values).toList();
    }
    final items = await readAll(userId: userId);
    return items.map((item) => item.toDatumMap()).toList();
  }

  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) async {
    if (userId != null && userId.isNotEmpty) {
      _rawStorage[userId]?.clear();
    } else {
      _rawStorage.clear();
    }

    // For migration tests, store the raw data directly to avoid re-serialization
    // that could interfere with test assertions.
    for (final rawItem in data) {
      final itemUserId = rawItem['userId'] as String? ?? '';
      final itemId = rawItem['id'] as String? ?? '';
      _rawStorage.putIfAbsent(itemUserId, () => {})[itemId] = rawItem;
    }
  }

  @override
  Future<List<R>> fetchRelated<R extends DatumEntityBase>(
    RelationalDatumEntity parent,
    String relationName,
    LocalAdapter<R> relatedAdapter,
  ) async {
    final relation = parent.relations[relationName];
    if (relation == null) {
      throw Exception(
        'Relation "$relationName" not found on ${parent.runtimeType}.',
      );
    }

    switch (relation) {
      case BelongsTo():
        final foreignKeyField = relation.foreignKey;
        final parentMap = parent.toDatumMap();
        final foreignKeyValue = parentMap[foreignKeyField] as String?;

        if (foreignKeyValue == null) {
          return [];
        }

        // In a 'belongsTo' relationship, the foreign key on the parent
        // points to the primary key of the related entity.
        final relatedItem = await relatedAdapter.read(foreignKeyValue);
        return relatedItem != null ? [relatedItem] : [];
      case HasMany():
        final foreignKeyField = relation.foreignKey;
        final parentId = parent.id;
        final query = DatumQuery(
          filters: [Filter(foreignKeyField, FilterOperator.equals, parentId)],
        );
        return relatedAdapter.query(query);
      case ManyToMany():
        // 1. Get the manager for the pivot entity via the central Datum instance.
        final pivotAdapter = relatedAdapters?[relation.pivotEntity.runtimeType];
        if (pivotAdapter == null) {
          throw StateError(
            'MockLocalAdapter requires a related adapter for ${relation.pivotEntity.runtimeType} to be provided for ManyToMany relations.',
          );
        }

        // 2. Query the pivot table to find all entries matching the parent's local key.
        final pivotQuery = DatumQuery(
          filters: [
            Filter(
              relation.thisForeignKey,
              FilterOperator.equals,
              parent.toDatumMap()[relation.thisLocalKey],
            ),
          ],
        );
        final pivotEntries = await pivotAdapter.query(pivotQuery);

        if (pivotEntries.isEmpty) {
          return [];
        }

        // 3. Extract the IDs of the "other" side of the relationship.
        final otherIds = pivotEntries.map((e) => e.toDatumMap()[relation.otherForeignKey] as String).where((id) => id.isNotEmpty).toList();

        if (otherIds.isEmpty) return [];

        // 4. Fetch the related entities using the extracted IDs.
        return relatedAdapter.query(
          DatumQuery(
            filters: [
              Filter(relation.otherLocalKey, FilterOperator.isIn, otherIds),
            ],
          ),
          userId: parent.userId,
        );
      case HasOne():
        final foreignKeyField = relation.foreignKey;
        final localKeyValue = parent.toDatumMap()[relation.localKey];
        final query = DatumQuery(
          filters: [
            Filter(foreignKeyField, FilterOperator.equals, localKeyValue),
          ],
        );
        return relatedAdapter.query(query);
    }
  }

  @override
  Stream<List<R>>? watchRelated<R extends DatumEntityBase>(
    RelationalDatumEntity parent,
    String relationName,
    LocalAdapter<R> relatedAdapter,
  ) {
    final relation = parent.relations[relationName];
    if (relation == null) {
      throw Exception(
        'Relation "$relationName" not found on ${parent.runtimeType}.',
      );
    }

    switch (relation) {
      case BelongsTo():
        final foreignKeyField = relation.foreignKey;
        final parentMap = parent.toDatumMap();
        final foreignKeyValue = parentMap[foreignKeyField] as String?;

        if (foreignKeyValue == null) {
          return Stream.value([]);
        }
        return relatedAdapter.watchById(foreignKeyValue)?.map((item) => item != null ? [item] : []);
      case HasMany():
        final foreignKeyField = relation.foreignKey;
        final parentId = parent.id;
        final query = DatumQuery(
          filters: [Filter(foreignKeyField, FilterOperator.equals, parentId)],
        );
        return relatedAdapter.watchQuery(query);
      case ManyToMany():
        final pivotAdapter = relatedAdapters?[relation.pivotEntity.runtimeType];
        if (pivotAdapter == null) {
          throw StateError(
            'MockLocalAdapter requires a related adapter for ${relation.pivotEntity.runtimeType} to be provided for ManyToMany relations.',
          );
        }

        final pivotQuery = DatumQuery(
          filters: [
            Filter(
              relation.thisForeignKey,
              FilterOperator.equals,
              parent.toDatumMap()[relation.thisLocalKey],
            ),
          ],
        );

        return pivotAdapter.watchQuery(pivotQuery)?.switchMap((pivotEntries) {
          if (pivotEntries.isEmpty) return Stream.value([]);
          final otherIds = pivotEntries.map((e) => e.toDatumMap()[relation.otherForeignKey] as String?).where((id) => id != null && id.isNotEmpty).cast<String>().toList();
          if (otherIds.isEmpty) return Stream.value([]);
          final relatedQuery = DatumQuery(
            filters: [
              Filter(relation.otherLocalKey, FilterOperator.isIn, otherIds),
            ],
          );
          return relatedAdapter.watchQuery(relatedQuery) ?? Stream.value([]);
        });
      case HasOne():
        final foreignKeyField = relation.foreignKey;
        final localKeyValue = parent.toDatumMap()[relation.localKey];
        final query = DatumQuery(
          filters: [
            Filter(foreignKeyField, FilterOperator.equals, localKeyValue),
          ],
        );
        // Use watchFirst for a more direct 1-to-1 watch, which is less
        // prone to emitting intermediate empty lists during updates.
        return relatedAdapter.watchFirst(query: query)?.map((item) => item != null ? [item] : []);
    }
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    return AdapterHealthStatus.healthy;
  }

  @override
  Future<int> getStorageSize({String? userId}) async {
    // A simple mock implementation.
    // Can be made more sophisticated if tests require it.
    return 0;
  }

  @override
  Stream<int> watchStorageSize({String? userId}) {
    final changes = changeStream()?.where((event) => userId == null || event.userId == userId).asyncMap((_) => getStorageSize(userId: userId));

    if (changes == null) return Stream.value(0);

    // Use a transformer to emit the initial value first, then subsequent changes.
    return changes.transform(
      StreamTransformer.fromBind((stream) async* {
        yield await getStorageSize(userId: userId);
        yield* stream;
      }),
    );
  }

  @override
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) async {
    return _lastSyncResults[userId];
  }

  @override
  Future<void> saveLastSyncResult(
    String userId,
    DatumSyncResult<T> result,
  ) async {
    _lastSyncResults[userId] = result;
  }
}

class MockRemoteAdapter<T extends DatumEntityBase> implements RemoteAdapter<T> {
  MockRemoteAdapter({this.fromJson});

  final Map<String, Map<String, T>> _remoteStorage = {};
  final Map<String, DatumSyncMetadata> _remoteMetadata = {};
  bool isConnectedValue = true;
  Duration _processingDelay = Duration.zero;
  final _changeController = StreamController<DatumChangeDetail<T>>.broadcast();
  final List<String> _failedIds = [];

  /// When true, prevents push/patch/delete from emitting changes.
  bool silent = false;

  /// A function to deserialize JSON into an entity of type T.
  final T Function(Map<String, dynamic>)? fromJson;

  @override
  String get name => 'MockRemoteAdapter';

  @override
  Future<void> initialize() async {
    // No-op for mock
  }

  void setFailedIds(List<String> ids) => _failedIds
    ..clear()
    ..addAll(ids);

  void setProcessingDelay(Duration delay) {
    _processingDelay = delay;
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    if (!isConnectedValue) throw Exception('No connection');
    var items = (userId != null ? _remoteStorage[userId]?.values.toList() : _remoteStorage.values.expand((map) => map.values).toList()) ?? [];
    if (scope != null) {
      // Find if a 'minModifiedDate' filter exists in the query.
      final minDateFilter = scope.query.filters.firstWhereOrNull(
        (f) => f is Filter && f.field == 'minModifiedDate',
      ) as Filter?;

      if (minDateFilter != null) {
        final minDate = DateTime.parse(minDateFilter.value as String);
        items = items.where((item) => item.modifiedAt.isAfter(minDate)).toList();
      }
    }
    return items;
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    if (!isConnectedValue) throw Exception('No connection');
    if (userId != null) {
      return _remoteStorage[userId]?[id];
    }
    for (final userStorage in _remoteStorage.values) {
      if (userStorage.containsKey(id)) return userStorage[id];
    }
    return null;
  }

  @override
  Future<void> create(T entity) async {
    await _push(entity);
  }

  @override
  Future<void> update(T entity) async {
    await _push(entity);
  }

  Future<void> _push(T item) async {
    if (!isConnectedValue) {
      throw NetworkException('No connection', isRetryable: true);
    }
    await Future<void>.delayed(_processingDelay);
    if (_failedIds.contains(item.id)) {
      throw NetworkException('Simulated push failure for ${item.id}');
    }
    final bool exists = _remoteStorage[item.userId]?.containsKey(item.id) ?? false;
    _remoteStorage.putIfAbsent(item.userId, () => {})[item.id] = item;
    if (!silent) {
      _changeController.add(
        DatumChangeDetail(
          entityId: item.id,
          userId: item.userId,
          type: exists ? DatumOperationType.update : DatumOperationType.create,
          timestamp: DateTime.now(),
          data: item,
        ),
      );
    }
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    if (!isConnectedValue) throw NetworkException('No connection');
    await Future<void>.delayed(_processingDelay);
    if (_failedIds.contains(id)) {
      throw NetworkException('Simulated patch failure for $id');
    }
    if (fromJson == null) {
      throw StateError(
        'MockRemoteAdapter needs a fromJson constructor to handle patch.',
      );
    }

    final existing = _remoteStorage[userId ?? '']?[id];
    if (existing == null) {
      throw Exception('Entity not found for patching in mock remote adapter.');
    }

    final json = existing.toDatumMap()..addAll(delta);
    final patchedItem = fromJson!(json);
    _remoteStorage.putIfAbsent(userId ?? '', () => {})[id] = patchedItem;
    return patchedItem;
  }

  @override
  Future<void> delete(String id, {String? userId}) async {
    if (!isConnectedValue) throw NetworkException('No connection');
    await Future<void>.delayed(_processingDelay);
    final item = _remoteStorage[userId ?? '']?.remove(id);
    if (item != null) {
      if (!silent) {
        _changeController.add(
          DatumChangeDetail(
            entityId: id,
            userId: userId ?? '',
            type: DatumOperationType.delete,
            timestamp: DateTime.now(),
          ),
        );
      }
    }
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    return _remoteMetadata[userId];
  }

  @override
  Future<void> updateSyncMetadata(
    DatumSyncMetadata metadata,
    String userId,
  ) async {
    _remoteMetadata[userId] = metadata;
  }

  DatumSyncMetadata? metadataFor(String userId) => _remoteMetadata[userId];

  @override
  Future<bool> isConnected() async => isConnectedValue;

  void addRemoteItem(String userId, T item) {
    _remoteStorage.putIfAbsent(item.userId, () => {})[item.id] = item;
  }

  void setRemoteMetadata(String userId, DatumSyncMetadata metadata) {
    _remoteMetadata[userId] = metadata;
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    if (!isConnectedValue) throw NetworkException('No connection');
    // Pass the userId to readAll. If it's null, readAll will correctly
    // fetch from all users, which is the desired behavior for relational queries.
    final allItems = await readAll(userId: userId);
    return applyQuery(allItems, query);
  }

  @override
  Stream<DatumChangeDetail<T>>? get changeStream => _changeController.stream;

  /// Helper to simulate an external change for testing.
  void emitChange(DatumChangeDetail<T> change) {
    _changeController.add(change);
  }

  /// Closes the stream controller. Call this in test tearDown.
  @override
  Future<void> dispose() async {
    if (!_changeController.isClosed) await _changeController.close();
  }

  @override
  Stream<List<T>>? watchAll({String? userId, DatumSyncScope? scope}) {
    final initialDataStream = Stream.fromFuture(
      readAll(userId: userId, scope: scope),
    );
    final updateStream = changeStream!.where((event) => userId == null || event.userId == userId).asyncMap((_) => readAll(userId: userId, scope: scope));

    return Rx.concat([initialDataStream, updateStream]);
  }

  @override
  Stream<T?>? watchById(String id, {String? userId}) {
    final initialDataStream = Stream.fromFuture(read(id, userId: userId));
    final updateStream = changeStream!
        .where(
          (event) => event.userId == (userId ?? '') && event.entityId == id,
        )
        .asyncMap((_) => read(id, userId: userId));

    return Rx.concat([initialDataStream, updateStream]);
  }

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) {
    // This mock remote adapter doesn't have a local query engine,
    // so we'll apply the query logic after fetching all items.
    // This simulates how a simple REST API adapter might work with client-side filtering.
    Future<List<T>> getFiltered() async {
      final allItems = await readAll(userId: userId);
      // We can use the query logic from the MockLocalAdapter for this.
      // In a real remote adapter (e.g., Firestore), this logic would be
      // translated into a server-side query.
      return applyQuery(allItems, query);
    }

    final initialDataStream = Stream.fromFuture(getFiltered());
    final updateStream = changeStream!.where((event) => userId == null || event.userId == userId).asyncMap((_) => getFiltered());

    return Rx.concat([initialDataStream, updateStream]);
  }

  @override
  Future<List<R>> fetchRelated<R extends DatumEntityBase>(
    RelationalDatumEntity parent,
    String relationName,
    RemoteAdapter<R> relatedAdapter,
  ) async {
    final relation = parent.relations[relationName];
    if (relation == null) {
      throw Exception(
        'Relation "$relationName" not found on ${parent.runtimeType}.',
      );
    }

    switch (relation) {
      case BelongsTo():
        final foreignKeyField = relation.foreignKey;
        final parentMap = parent.toDatumMap();
        final foreignKeyValue = parentMap[foreignKeyField] as String?;

        if (foreignKeyValue == null) {
          return [];
        }

        final relatedItem = await relatedAdapter.read(foreignKeyValue);
        return relatedItem != null ? [relatedItem] : [];
      case HasMany():
        final foreignKeyField = relation.foreignKey;
        final parentId = parent.id;
        final query = DatumQuery(
          filters: [Filter(foreignKeyField, FilterOperator.equals, parentId)],
        );
        return relatedAdapter.query(query);
      case ManyToMany():
        // 1. Get the manager for the pivot entity.
        final pivotManager = Datum.managerByType(
          relation.pivotEntity.runtimeType,
        );
        // 2. Query the pivot table to find all entries matching the parent's local key.
        final pivotQuery = DatumQuery(
          filters: [
            Filter(
              relation.thisForeignKey,
              FilterOperator.equals,
              parent.toDatumMap()[relation.thisLocalKey],
            ),
          ],
        );
        final pivotEntries = await pivotManager.remoteAdapter.query(pivotQuery);

        if (pivotEntries.isEmpty) {
          return [];
        }

        // 3. Extract the IDs of the "other" side of the relationship.
        final otherIds = pivotEntries.map((e) => e.toDatumMap()[relation.otherForeignKey] as String?).where((id) => id != null && id.isNotEmpty).cast<String>().toList();

        if (otherIds.isEmpty) return [];

        // 4. Fetch the related entities using the extracted IDs.
        return relatedAdapter.query(
          DatumQuery(
            filters: [
              Filter(relation.otherLocalKey, FilterOperator.isIn, otherIds),
            ],
          ),
        );
      case HasOne():
        final foreignKeyField = relation.foreignKey;
        final localKeyValue = parent.toDatumMap()[relation.localKey];
        final query = DatumQuery(
          filters: [
            Filter(foreignKeyField, FilterOperator.equals, localKeyValue),
          ],
        );
        return relatedAdapter.query(query);
    }
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    return AdapterHealthStatus.healthy;
  }
}

/// A helper function to apply query filters and sorting to a list of items.
List<T> applyQuery<T extends DatumEntityBase>(List<T> items, DatumQuery query) {
  var filteredItems = items.where((item) {
    final json = item.toDatumMap();
    if (query.logicalOperator == LogicalOperator.and) {
      return query.filters.every((filter) => _matches(json, filter));
    } else {
      return query.filters.any((filter) => _matches(json, filter));
    }
  }).toList();

  if (query.sorting.isNotEmpty) {
    filteredItems.sort((a, b) {
      for (final sort in query.sorting) {
        final valA = a.toDatumMap()[sort.field];
        final valB = b.toDatumMap()[sort.field];

        if (valA == null && valB == null) continue;
        if (valA == null) {
          return sort.nullSortOrder == NullSortOrder.first ? -1 : 1;
        }
        if (valB == null) {
          return sort.nullSortOrder == NullSortOrder.first ? 1 : -1;
        }

        if (valA is Comparable && valB is Comparable) {
          final comparison = valA.compareTo(valB);
          if (comparison != 0) {
            return sort.descending ? -comparison : comparison;
          }
        }
      }
      return 0;
    });
  }

  if (query.offset != null) {
    filteredItems = filteredItems.skip(query.offset!).toList();
  }
  if (query.limit != null) {
    filteredItems = filteredItems.take(query.limit!).toList();
  }

  return filteredItems;
}

bool _matches(Map<String, dynamic> json, FilterCondition condition) {
  if (condition is Filter) {
    final value = json[condition.field];
    if (value == null && condition.operator != FilterOperator.isNull && condition.operator != FilterOperator.isNotNull) {
      return false;
    }

    switch (condition.operator) {
      case FilterOperator.equals:
        return value == condition.value;
      case FilterOperator.notEquals:
        return value != condition.value;
      case FilterOperator.greaterThan:
        return value is Comparable && value.compareTo(condition.value) > 0;
      case FilterOperator.greaterThanOrEqual:
        return value is Comparable && value.compareTo(condition.value) >= 0;
      case FilterOperator.lessThan:
        return value is Comparable && value.compareTo(condition.value) < 0;
      case FilterOperator.lessThanOrEqual:
        return value is Comparable && value.compareTo(condition.value) <= 0;
      case FilterOperator.contains:
        return value is String && value.contains(condition.value as String);
      case FilterOperator.isIn:
        return condition.value is List && (condition.value as List).contains(value);
      case FilterOperator.isNotIn:
        return condition.value is List && !(condition.value as List).contains(value);
      case FilterOperator.isNull:
        return value == null;
      case FilterOperator.isNotNull:
        return value != null;
      case FilterOperator.containsIgnoreCase:
        return value is String &&
            condition.value is String &&
            value.toLowerCase().contains(
                  (condition.value as String).toLowerCase(),
                );
      case FilterOperator.startsWith:
        return value is String && condition.value is String && value.startsWith(condition.value as String);
      case FilterOperator.endsWith:
        return value is String && condition.value is String && value.endsWith(condition.value as String);
      case FilterOperator.arrayContains:
        return value is List && value.contains(condition.value);
      case FilterOperator.arrayContainsAny:
        if (value is! List || condition.value is! List) return false;
        final valueSet = value.toSet();
        return (condition.value as List).any(valueSet.contains);
      case FilterOperator.matches:
        return value is String && condition.value is String && RegExp(condition.value as String).hasMatch(value);
      case FilterOperator.withinDistance:
        if (value is! Map || condition.value is! Map) return false;
        final point = value as Map<String, dynamic>;
        final params = condition.value as Map<String, dynamic>;
        final center = params['center'] as Map<String, double>?;
        final radius = params['radius'] as double?;
        if (point['latitude'] == null || point['longitude'] == null || center == null || radius == null) {
          return false;
        }
        final distance = _haversineDistance(
          point['latitude'] as double,
          point['longitude'] as double,
          center['latitude']!,
          center['longitude']!,
        );
        return distance <= radius;
      case FilterOperator.between:
        if (value is! Comparable || condition.value is! List) return false;
        final bounds = condition.value as List;
        if (bounds.length != 2) return false;
        return value.compareTo(bounds[0]) >= 0 && value.compareTo(bounds[1]) <= 0;
    }
  } else if (condition is CompositeFilter) {
    if (condition.operator == LogicalOperator.and) {
      return condition.conditions.every((c) => _matches(json, c));
    } else {
      return condition.conditions.any((c) => _matches(json, c));
    }
  }
  return false;
}

double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371e3; // Earth's radius in metres
  final phi1 = lat1 * pi / 180;
  final phi2 = lat2 * pi / 180;
  final deltaPhi = (lat2 - lat1) * pi / 180;
  final deltaLambda = (lon2 - lon1) * pi / 180;

  final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}
