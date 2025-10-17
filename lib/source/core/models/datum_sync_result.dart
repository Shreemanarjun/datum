import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:meta/meta.dart';

/// Represents the outcome of a synchronization cycle.
@immutable
class DatumSyncResult<T extends DatumEntity> {
  /// The user ID for which the sync was performed.
  final String userId;

  /// The total duration of the sync cycle.
  final Duration duration;

  /// The number of operations that were successfully synced.
  final int syncedCount;

  /// The number of operations that failed to sync.
  final int failedCount;

  /// The number of conflicts that were detected and resolved.
  final int conflictsResolved;

  /// A list of operations that are still pending after the sync cycle.
  final List<DatumSyncOperation<T>> pendingOperations;

  /// Whether the sync was skipped (e.g., due to being offline or another sync in progress).
  final bool wasSkipped;

  /// Whether the sync was cancelled (e.g., due to the manager being disposed).
  final bool wasCancelled;

  /// The error that caused the sync to fail, if any.
  final Object? error;

  /// Creates a new [DatumSyncResult].
  const DatumSyncResult({
    required this.userId,
    required this.duration,
    required this.syncedCount,
    required this.failedCount,
    required this.conflictsResolved,
    required this.pendingOperations,
    this.wasSkipped = false,
    this.wasCancelled = false,
    this.error,
  });

  /// Creates a result for a sync cycle that was skipped.
  const DatumSyncResult.skipped(this.userId, int pendingCount)
      : duration = Duration.zero,
        syncedCount = 0,
        failedCount = 0,
        conflictsResolved = 0,
        pendingOperations = const [],
        wasSkipped = true,
        wasCancelled = false,
        error = null;

  /// Creates a result for a sync cycle that was cancelled.
  const DatumSyncResult.cancelled(this.userId, this.syncedCount)
      : duration = Duration.zero,
        failedCount = 0,
        conflictsResolved = 0,
        pendingOperations = const [],
        wasSkipped = false,
        wasCancelled = true,
        error = null;

  /// Creates a result for a sync cycle that failed with an error.
  const DatumSyncResult.fromError(this.userId, this.error)
      : duration = Duration.zero,
        syncedCount = 0,
        failedCount = 1,
        conflictsResolved = 0,
        pendingOperations = const [],
        wasSkipped = false,
        wasCancelled = false;

  /// Whether the sync completed successfully without any failures.
  bool get isSuccess =>
      !wasSkipped && !wasCancelled && failedCount == 0 && error == null;

  @override
  String toString() {
    if (wasSkipped) return 'DatumSyncResult(userId: $userId, status: skipped)';
    if (wasCancelled) {
      return 'DatumSyncResult(userId: $userId, status: cancelled)';
    }
    return 'DatumSyncResult(userId: $userId, synced: $syncedCount, failed: $failedCount, conflicts: $conflictsResolved, duration: $duration)';
  }
}
