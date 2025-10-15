import 'package:datum/source/core/health/datum_health.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';

/// Detailed status information for a specific `DatumManager`'s sync operations.
class DatumSyncStatus<T extends DatumEntity> {
  /// Creates a sync status details object.
  const DatumSyncStatus({
    required this.userId,
    required this.isSyncing,
    required this.pendingOperations,
    required this.failedOperations,
    required this.health,
    this.lastSyncTime,
    this.lastSuccessfulSync,
    this.currentBatch,
    this.progress,
  });

  /// The user ID this status pertains to.
  final String userId;

  /// Whether a sync cycle is currently in progress.
  final bool isSyncing;

  /// The timestamp of the last sync attempt (successful or not).
  final DateTime? lastSyncTime;

  /// The timestamp of the last successful sync.
  final DateTime? lastSuccessfulSync;

  /// The number of pending operations waiting to be synced.
  final int pendingOperations;

  /// The number of operations that have failed permanently.
  final int failedOperations;

  /// The current batch of operations being processed, if any.
  final List<DatumSyncOperation<T>>? currentBatch;

  /// The progress of the current sync cycle as a value between 0.0 and 1.0.
  final double? progress;

  /// The current health status of this specific sync manager.
  final DatumHealth health;

  /// A convenience getter to check for unsynced data.
  bool get hasUnsyncedData => pendingOperations > 0;

  /// A convenience getter to check for failed operations.
  bool get hasFailures => failedOperations > 0;

  /// The time elapsed since the last sync attempt.
  Duration? get timeSinceLastSync =>
      lastSyncTime != null ? DateTime.now().difference(lastSyncTime!) : null;
}
