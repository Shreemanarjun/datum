import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/utils/datum_logger.dart';

/// Manages the queue of pending synchronization operations for a specific entity type [T].
///
/// This class acts as a high-level abstraction over the [LocalAdapter]'s
/// queueing mechanism. It provides a simple API to enqueue, dequeue, update,
/// and retrieve pending operations that are waiting to be synchronized with
/// a remote data source.
class QueueManager<T extends DatumEntityBase> {
  final LocalAdapter<T> localAdapter;
  final DatumLogger logger;

  /// Creates a new [QueueManager].
  ///
  /// Requires a [localAdapter] to persist the queue and a [logger] for output.
  QueueManager({required this.localAdapter, required this.logger});

  /// Adds a new synchronization [operation] to the queue for its user.
  Future<void> enqueue(DatumSyncOperation<T> operation) async {
    await localAdapter.addPendingOperation(operation.userId, operation);
  }

  /// Removes a synchronization operation from the queue by its [operationId].
  ///
  /// This is typically called after an operation has been successfully synced.
  Future<void> dequeue(String operationId) async {
    await localAdapter.removePendingOperation(operationId);
  }

  /// Updates an existing synchronization [operation] in the queue.
  ///
  /// This is useful for scenarios like incrementing a retry count on a failed
  /// operation. The underlying [LocalAdapter.addPendingOperation] is expected
  /// to handle replacement if an operation with the same ID already exists.
  Future<void> update(DatumSyncOperation<T> operation) async {
    // This assumes addPendingOperation handles replacement if the op exists
    await localAdapter.addPendingOperation(operation.userId, operation);
  }

  /// Retrieves a list of all pending synchronization operations for a given [userId].
  Future<List<DatumSyncOperation<T>>> getPending(String userId) async {
    return localAdapter.getPendingOperations(userId);
  }

  /// Returns the number of pending synchronization operations for a given [userId].
  Future<int> getPendingCount(String userId) async {
    final pending = await getPending(userId);
    return pending.length;
  }

  /// Clears all data for a specific [userId], including pending operations.
  ///
  /// This is a destructive action and should be used with care, for example,
  /// when a user logs out and their local data should be wiped.
  Future<void> clear(String userId) async {
    await localAdapter.clearUserData(userId);
  }

  /// Disposes of any resources held by the queue manager.
  ///
  /// Currently a no-op, but provided for API consistency and future use.
  Future<void> dispose() async {}
}
