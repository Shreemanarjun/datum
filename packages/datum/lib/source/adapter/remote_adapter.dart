import 'package:datum/datum.dart';

/// Remote storage adapter abstraction for cloud data sources.
abstract class RemoteAdapter<T extends DatumEntityInterface> {
  /// A descriptive name for the adapter (e.g., "Firebase", "REST").
  String get name => runtimeType.toString();

  /// Initializes the remote service (e.g., authenticates, sets up listeners).
  Future<void> initialize();

  // --- Reactive Methods (Streams) ---

  /// Stream of changes that occur in the remote data source.
  /// Return null if the adapter doesn't support real-time change notifications.
  Stream<DatumChangeDetail<T>>? get changeStream;

  /// Unsubscribes from the change stream.
  Future<void> unsubscribeFromChanges() async {}

  /// Resubscribes to the change stream.
  Future<void> resubscribeToChanges() async {}

  /// Watch all items directly from the remote source.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<List<T>>? watchAll({String? userId, DatumSyncScope? scope}) => null;

  /// Watch a single item by its ID directly from the remote source.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<T?>? watchById(String id, {String? userId}) => null;

  /// Watch a subset of items matching a query from the remote source.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) => null;

  /// Watches the number of remote entities that match the given [query].
  ///
  /// Emits a new count whenever the remote data changes, if the backend
  /// supports realtime updates.
  ///
  /// Returns `null` if the remote adapter does not support watching counts.
  ///
  /// The optional [userId] can be used to scope the request to a specific
  /// user's data when supported by the backend.
  Stream<int>? watchCount({DatumQuery? query, String? userId}) => null;

  // --- One-time Read Methods ---

  /// Fetch all items, optionally filtered by a scope.
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope});

  /// Fetch a single item by its ID.
  Future<T?> read(String id, {String? userId});

  /// Executes a one-time query against the remote data source.
  ///
  /// This method should be implemented by adapters to translate a [DatumQuery]
  /// into a native query for the underlying service (e.g., a REST API call).
  Future<List<T>> query(DatumQuery query, {String? userId});

  /// Returns the number of remote entities that match the given [query].
  ///
  /// If [query] is null, all entities available from the remote data source
  /// will be counted.
  ///
  /// The optional [userId] can be used to scope the request to a specific
  /// user's data when supported by the backend.
  ///
  /// Implementations should override this method to perform an efficient
  /// remote count operation instead of fetching all records.
  Future<int> count({DatumQuery? query, String? userId}) async => 0;

  // --- Write Methods ---

  /// Create a new entity on the remote data source.
  Future<void> create(T entity);

  /// Update an existing entity on the remote data source.
  Future<void> update(T entity);

  /// Create multiple entities on the remote data source.
  Future<void> createAll(List<T> entities) async {
    for (final entity in entities) {
      await create(entity);
    }
  }

  /// Update multiple entities on the remote data source.
  Future<void> updateAll(List<T> entities) async {
    for (final entity in entities) {
      await update(entity);
    }
  }

  /// Apply a partial update ("patch") to an existing entity.
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  });

  /// Delete an entity from the remote data source.
  Future<bool> delete(String id, {String? userId});

  /// Delete multiple entities from the remote data source.
  Future<void> deleteAll(List<String> ids, {String? userId}) async {
    for (final id in ids) {
      await delete(id, userId: userId);
    }
  }

  // --- Sync & Metadata Methods ---

  /// Retrieve metadata describing the user's sync state from the remote.
  Future<DatumSyncMetadata?> getSyncMetadata(String userId);

  /// Persist updated sync state metadata to the remote.
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId);

  /// Check if the remote data source is currently reachable.
  Future<bool> isConnected();

  /// Fetches related entities based on the relationship definitions from the remote source.
  ///
  /// This is an optional method that adapters can implement if their backend
  /// supports efficient relational queries. If not implemented, it will throw
  /// an [UnimplementedError].
  Future<List<R>> fetchRelated<R extends DatumEntityInterface>(
    RelationalDatumEntity parent,
    String relationName,
    RemoteAdapter<R> relatedAdapter,
  ) {
    throw UnimplementedError(
      'fetchRelated is not implemented for this remote adapter.',
    );
  }

  /// Dispose of any resources used by the adapter (e.g., network connections).
  Future<void> dispose() async {}

  /// Checks the health of the remote adapter.
  ///
  /// Returns [AdapterHealthStatus.healthy] by default. Adapters should override
  /// this to provide a meaningful health check (e.g., ping a server endpoint).
  Future<AdapterHealthStatus> checkHealth() async => AdapterHealthStatus.healthy;
}
