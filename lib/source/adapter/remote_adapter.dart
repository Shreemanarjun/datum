import 'package:datum/source/core/models/datum_change_detail.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_scope.dart';

/// Remote storage adapter abstraction for cloud data sources.
abstract class RemoteAdapter<T extends DatumEntity> {
  /// A descriptive name for the adapter (e.g., "Firebase", "REST").
  String get name => runtimeType.toString();

  /// Initializes the remote service (e.g., authenticates, sets up listeners).
  Future<void> initialize();

  // --- Reactive Methods (Streams) ---

  /// Stream of changes that occur in the remote data source.
  /// Return null if the adapter doesn't support real-time change notifications.
  Stream<DatumChangeDetail<T>>? get changeStream;

  /// Watch all items directly from the remote source.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<List<T>>? watchAll({String? userId, DatumSyncScope? scope}) => null;

  /// Watch a single item by its ID directly from the remote source.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<T?>? watchById(String id, {String? userId}) => null;

  /// Watch a subset of items matching a query directly from the remote source.
  /// Return null if the adapter doesn't support reactive queries.
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) => null;

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

  // --- Write Methods ---

  /// Create a new entity on the remote data source.
  Future<void> create(T entity);

  /// Update an existing entity on the remote data source.
  Future<void> update(T entity);

  /// Apply a partial update ("patch") to an existing entity.
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  });

  /// Delete an entity from the remote data source.
  Future<void> delete(String id, {String? userId});

  // --- Sync & Metadata Methods ---

  /// Retrieve metadata describing the user's sync state from the remote.
  Future<DatumSyncMetadata?> getSyncMetadata(String userId);

  /// Persist updated sync state metadata to the remote.
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId);

  /// Check if the remote data source is currently reachable.
  Future<bool> isConnected();

  /// Dispose of any resources used by the adapter (e.g., network connections).
  Future<void> dispose() async {}
}
