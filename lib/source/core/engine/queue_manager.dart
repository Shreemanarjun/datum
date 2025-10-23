import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/utils/datum_logger.dart';

/// Manages the queue of pending synchronization operations.
class QueueManager<T extends DatumEntityBase> {
  final LocalAdapter<T> localAdapter;
  final DatumLogger logger;

  QueueManager({required this.localAdapter, required this.logger});

  Future<void> enqueue(DatumSyncOperation<T> operation) async {
    await localAdapter.addPendingOperation(operation.userId, operation);
  }

  Future<void> dequeue(String operationId) async {
    await localAdapter.removePendingOperation(operationId);
  }

  Future<void> update(DatumSyncOperation<T> operation) async {
    // This assumes addPendingOperation handles replacement if the op exists
    await localAdapter.addPendingOperation(operation.userId, operation);
  }

  Future<List<DatumSyncOperation<T>>> getPending(String userId) async {
    return localAdapter.getPendingOperations(userId);
  }

  Future<int> getPendingCount(String userId) async {
    final pending = await getPending(userId);
    return pending.length;
  }

  Future<void> initializeUser(String userId) async {}

  Future<void> clear(String userId) async {
    await localAdapter.clearUserData(userId);
  }

  Future<void> dispose() async {}
}
