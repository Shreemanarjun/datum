import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';

/// Represents the outcome of a synchronization operation.
class DatumSyncResult<T extends DatumEntity> {
  /// The user ID for which the sync was performed.
  final String userId;

  /// The total time taken for the sync operation.
  final Duration duration;

  /// The number of local operations successfully pushed to the remote.
  final int syncedCount;

  /// The number of operations that failed permanently.
  final int failedCount;

  /// The number of conflicts that were detected and resolved.
  final int conflictsResolved;

  /// A list of operations that are still pending after the sync cycle.
  /// This includes operations that were not processed or failed with a retryable error.
  final List<DatumSyncOperation<T>> pendingOperations;

  /// A list of errors that occurred during the sync.
  final List<Object> errors;

  /// Whether the sync operation was successful (no permanent failures).
  /// Note: A sync can be successful even if there are pending operations (e.g., due to retryable network errors).
  final bool isSuccess;

  /// Whether the sync operation was skipped (e.g., due to being offline or another sync in progress).
  final bool wasSkipped;

  /// Whether the sync operation was cancelled mid-process (e.g., by disposing the manager).
  final bool wasCancelled;

  /// Creates a [DatumSyncResult].
  const DatumSyncResult({
    required this.userId,
    required this.syncedCount,
    required this.failedCount,
    required this.conflictsResolved,
    required this.pendingOperations,
    required this.duration,
    this.errors = const [],
    this.isSuccess = true,
    this.wasSkipped = false,
    this.wasCancelled = false,
  });

  /// Creates a result for a sync operation that was skipped.
  DatumSyncResult.skipped(this.userId, int pendingCount) // Removed const
    : duration = Duration.zero,
      syncedCount = 0,
      failedCount = 0,
      conflictsResolved = 0,
      pendingOperations = const [],
      errors = const [],
      isSuccess = true,
      wasSkipped = true,
      wasCancelled = false;

  /// Creates a result for a sync operation that was cancelled.
  DatumSyncResult.cancelled(this.userId, this.syncedCount) // Removed const
    : duration = Duration.zero,
      failedCount = 0,
      conflictsResolved = 0,
      pendingOperations = const [],
      errors = const [],
      isSuccess = true,
      wasSkipped = false,
      wasCancelled = true;

  @override
  String toString() {
    return 'DatumSyncResult('
        'userId: $userId, '
        'duration: $duration, '
        'synced: $syncedCount, '
        'failed: $failedCount, '
        'conflicts: $conflictsResolved, '
        'pending: ${pendingOperations.length}, '
        'success: $isSuccess, '
        'skipped: $wasSkipped, '
        'cancelled: $wasCancelled'
        ')';
  }
}
