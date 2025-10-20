import 'dart:async';

import 'package:datum/datum.dart';
import 'package:meta/meta.dart';

/// Local storage adapter abstraction that provides access to offline data.
abstract class LocalAdapter<T extends DatumEntity> {
  /// A descriptive name for the adapter (e.g., "Hive", "SQLite").
  String get name => runtimeType.toString();

  /// Initializes the local storage (e.g., opens databases/boxes).
  Future<void> initialize();

  // --- Reactive Methods (Streams) ---

  /// Stream of changes that occur in the local storage.
  /// Return null if the adapter doesn't support change notifications.
  Stream<DatumChangeDetail<T>>? changeStream();

  /// A stream that emits when the schema version changes.
  Stream<int>? schemaVersionStream() => null;

  /// Watch all items, emitting a new list on any change.
  ///
  /// The [includeInitialData] parameter controls whether the stream should
  /// immediately emit the current list of all items. Defaults to `true`.
  /// If `false`, the stream will only emit when a change occurs.
  /// Return `null` if the adapter doesn't support reactive queries.
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) =>
      null;

  /// Watch a single item by its ID, emitting the item on change or null if deleted.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<T?>? watchById(String id, {String? userId}) => null;

  /// Watch a paginated list of items.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<PaginatedResult<T>>? watchAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) =>
      null;

  /// Watch a subset of items matching a query.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) => null;

  /// Watch the total count of entities, optionally matching a query.
  /// Return null if the adapter does not support this feature.
  Stream<int>? watchCount({DatumQuery? query, String? userId}) => null;

  /// Watch the first entity matching a query, optionally sorted.
  /// Return null if the adapter does not support this feature.
  Stream<T?>? watchFirst({DatumQuery? query, String? userId}) => null;

  // --- One-time Read Methods ---

  /// Fetch all items.
  Future<List<T>> readAll({String? userId});

  /// Fetch a single item by its ID.
  Future<T?> read(String id, {String? userId});

  /// Fetch multiple items by their IDs.
  Future<Map<String, T>> readByIds(List<String> ids, {required String userId});

  /// Fetch all unique user IDs that have data stored locally.
  Future<List<String>> getAllUserIds();

  /// Fetch a paginated list of items.
  Future<PaginatedResult<T>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  });

  /// Executes a one-time query against the local data source.
  ///
  /// This method should be implemented by adapters to translate a [DatumQuery]
  /// into a native query for the underlying database (e.g., SQL).
  Future<List<T>> query(DatumQuery query, {String? userId});

  // --- Write Methods ---

  /// Create a new entity.
  Future<void> create(T entity);

  /// Update an existing entity.
  Future<void> update(T entity);

  /// Apply a partial update ("patch") to an existing entity.
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  });

  /// Remove an entity. Returns `true` if an item was deleted.
  Future<bool> delete(String id, {String? userId});

  /// Remove all data for a specific user.
  Future<void> clearUserData(String userId);

  /// Remove all data from the adapter.
  Future<void> clear();

  // --- Sync & Migration Methods ---

  /// Get all pending sync operations.
  Future<List<DatumSyncOperation<T>>> getPendingOperations(String userId);

  /// Add a new pending operation to the queue.
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<T> operation,
  );

  /// Remove a pending operation from the queue after it has been synced.
  Future<void> removePendingOperation(String operationId);

  /// Retrieve metadata about the user's sync state.
  Future<DatumSyncMetadata?> getSyncMetadata(String userId);

  /// Persist updated sync state metadata.
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId);

  /// Retrieve the schema version stored in the database. Should return 0 if none.
  Future<int> getStoredSchemaVersion();

  /// Persist the new schema version to the database.
  Future<void> setStoredSchemaVersion(int version);

  /// Fetch all data for a user as a list of raw maps.
  /// This is used during schema migrations to avoid deserialization issues.
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId});

  /// Overwrite all existing data with a new set of raw data maps.
  /// This is used during schema migrations after transforming the data.
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  });

  /// Fetches related entities based on the relationship definitions from the local source.
  ///
  /// This is an optional method that adapters can implement if their backend
  /// supports efficient relational queries (e.g., via joins in SQL).
  /// If not implemented, it will throw an [UnimplementedError].
  Future<List<R>> fetchRelated<R extends DatumEntity>(
    RelationalDatumEntity parent,
    String relationName,
    LocalAdapter<R> relatedAdapter,
  ) {
    throw UnimplementedError(
      'fetchRelated is not implemented for this local adapter.',
    );
  }

  /// Reactively watches related entities.
  ///
  /// This is an optional method that adapters can implement to provide
  /// reactive streams for relational data. If not implemented, it will
  /// throw an [UnimplementedError].
  Stream<List<R>>? watchRelated<R extends DatumEntity>(
    RelationalDatumEntity parent,
    String relationName,
    LocalAdapter<R> relatedAdapter,
  ) {
    throw UnimplementedError(
      'watchRelated is not implemented for this local adapter.',
    );
  }

  /// Executes a block of code within a single atomic transaction.
  ///
  /// This is crucial for multi-step processes where all steps must succeed or
  /// fail together, ensuring the database is not left in an inconsistent state.
  /// A prime use case is schema migrations, where multiple data transformations
  /// must be applied atomically.
  ///
  /// Implementations of this method should ensure that if the `action`
  /// throws an error, any changes made within the transaction are rolled back,
  /// preserving data integrity (ACID principles). For adapters on top of
  /// databases that support native transactions (like SQLite), this should
  /// wrap the action in a database transaction. For others, it may require
  /// manual locking and state backup/restore logic.
  ///
  /// ### Example with `synchronized`
  ///
  /// For adapters without native transaction support (like an in-memory or
  /// simple file-based adapter), you can use the `synchronized` package to
  /// ensure atomicity:
  ///
  /// ```dart
  /// import 'package:synchronized/synchronized.dart';
  ///
  /// class MyInMemoryAdapter<T extends DatumEntity> extends LocalAdapter<T> {
  ///   final _transactionLock = Lock();
  ///   final Map<String, T> _storage = {};
  ///
  ///   @override
  ///   Future<R> transaction<R>(Future<R> Function() action) async {
  ///     return _transactionLock.synchronized(() async {
  ///       // 1. Backup state before the transaction.
  ///       final backup = Map<String, T>.from(_storage);
  ///       try {
  ///         // 2. Execute the action.
  ///         return await action();
  ///       } catch (e) {
  ///         // 3. On error, restore from backup (rollback).
  ///         _storage..clear()..addAll(backup);
  ///         rethrow;
  ///       }
  ///     });
  ///   }
  ///   // ... other adapter methods
  /// }
  /// ```
  Future<R> transaction<R>(Future<R> Function() action);

  /// Dispose of underlying resources (e.g., close database connections).
  Future<void> dispose();

  /// Provides a sample, empty, or dummy instance of the entity.
  /// This is used for reflection-like purposes, such as logging.
  T get sampleInstance {
    throw UnimplementedError(
        'sampleInstance getter is not implemented for this adapter.');
  }

  /// Checks the health of the local adapter.
  ///
  /// Returns [AdapterHealthStatus.ok] by default. Adapters should override
  /// this to provide a meaningful health check (e.g., check if a database
  /// file is accessible).
  Future<AdapterHealthStatus> checkHealth() async => AdapterHealthStatus.ok;

  /// Returns the storage size in bytes for a given user.
  Future<int> getStorageSize({String? userId});

  /// Reactively watches the storage size in bytes for a given user.
  ///
  /// Emits the current size immediately and then a new size whenever the
  /// underlying data changes. Adapters can override this for a more efficient
  /// implementation if their storage engine supports it. The default implementation
  /// is also available as a static method for testing purposes.
  @visibleForTesting
  static Stream<int> defaultWatchStorageSize<T extends DatumEntity>(
      LocalAdapter<T> adapter,
      {String? userId}) {
    final changes = adapter
        .changeStream()
        // Filter changes to only include the relevant user.
        ?.where((event) => userId == null || event.userId == userId)
        // When a change occurs, recalculate the size.
        .asyncMap((_) => adapter.getStorageSize(userId: userId));

    if (changes == null) return Stream.value(0);

    // Use a transformer to emit the initial value first, then subsequent changes.
    return changes.transform(
      StreamTransformer.fromBind((stream) async* {
        yield await adapter.getStorageSize(userId: userId);
        yield* stream;
      }),
    );
  }

  Stream<int> watchStorageSize({String? userId}) {
    return LocalAdapter.defaultWatchStorageSize(this, userId: userId);
  }

  /// Saves the result of the last synchronization for a user.
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<T> result);

  /// Retrieves the result of the last synchronization for a user.
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId);
}
