import 'package:datum/source/core/models/datum_change_detail.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_pagination.dart';
import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:datum/source/core/query/datum_query.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';

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
  /// Return null if the adapter doesn't support reactive queries.
  Stream<List<T>>? watchAll({String? userId}) => null;

  /// Watch a single item by its ID, emitting the item on change or null if deleted.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<T?>? watchById(String id, {String? userId}) => null;

  /// Watch a paginated list of items.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<PaginatedResult<T>>? watchAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) => null;

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
  Future<R> transaction<R>(Future<R> Function() action);

  /// Dispose of underlying resources (e.g., close database connections).
  Future<void> dispose();
}
