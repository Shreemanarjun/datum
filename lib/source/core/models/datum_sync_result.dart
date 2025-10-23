import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/utils/duration_formatter.dart';
import 'package:meta/meta.dart';

/// Represents the outcome of a synchronization cycle.
@immutable
class DatumSyncResult<T extends DatumEntityBase> {
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

  /// The total cumulative number of bytes pushed to the remote for this user.
  final int totalBytesPushed;

  /// The total cumulative number of bytes pulled from the remote for this user.
  final int totalBytesPulled;

  /// The number of bytes pushed to the remote in just this sync cycle.
  final int bytesPushedInCycle;

  /// The number of bytes pulled from the remote in just this sync cycle.
  final int bytesPulledInCycle;

  /// Whether the sync was skipped (e.g., due to being offline or another sync in progress).
  final bool wasSkipped;

  /// Whether the sync was cancelled (e.g., due to the manager being disposed).
  final bool wasCancelled;

  /// The error that caused the sync to fail, if any.
  final Object? error;

  /// A reason why the sync was skipped, if applicable.
  final String? skipReason;

  /// Creates a new [DatumSyncResult].
  const DatumSyncResult({
    required this.userId,
    required this.duration,
    required this.syncedCount,
    required this.failedCount,
    required this.conflictsResolved,
    required this.pendingOperations,
    this.totalBytesPushed = 0,
    this.totalBytesPulled = 0,
    this.bytesPushedInCycle = 0,
    this.bytesPulledInCycle = 0,
    this.wasSkipped = false,
    this.wasCancelled = false,
    this.error,
    this.skipReason,
  });

  /// Creates a result for a sync cycle that was skipped.
  factory DatumSyncResult.skipped(
    String userId,
    int pendingCount, {
    String? reason,
  }) {
    return DatumSyncResult<T>(
      userId: userId,
      duration: Duration.zero,
      syncedCount: 0,
      failedCount: 0,
      conflictsResolved: 0,
      pendingOperations: const [],
      wasSkipped: true,
      skipReason: reason,
    );
  }

  /// Creates a result for a sync cycle that was cancelled.
  const DatumSyncResult.cancelled(this.userId, this.syncedCount)
      : duration = Duration.zero,
        failedCount = 0,
        conflictsResolved = 0,
        pendingOperations = const [],
        totalBytesPushed = 0,
        totalBytesPulled = 0,
        bytesPushedInCycle = 0,
        bytesPulledInCycle = 0,
        wasSkipped = false,
        wasCancelled = true,
        error = null,
        skipReason = null;

  /// Creates a result for a sync cycle that failed with an error.
  const DatumSyncResult.fromError(this.userId, this.error)
      : duration = Duration.zero,
        syncedCount = 0,
        failedCount = 1,
        conflictsResolved = 0,
        pendingOperations = const [],
        totalBytesPushed = 0,
        totalBytesPulled = 0,
        bytesPushedInCycle = 0,
        bytesPulledInCycle = 0,
        wasSkipped = false,
        wasCancelled = false,
        skipReason = null;

  /// Whether the sync completed successfully without any failures.
  bool get isSuccess => !wasSkipped && !wasCancelled && failedCount == 0 && error == null;

  /// The total number of operations processed in this sync cycle.
  int get totalOperations => syncedCount + failedCount;

  /// The success rate of the sync cycle as a percentage (0.0 to 100.0).
  double get successPercentage {
    if (totalOperations == 0) return 100.0;
    return (syncedCount / totalOperations) * 100.0;
  }

  @override
  String toString() {
    if (wasSkipped) {
      return 'DatumSyncResult(userId: $userId, status: skipped, reason: $skipReason)';
    }
    if (wasCancelled) {
      return 'DatumSyncResult(userId: $userId, status: cancelled)';
    }
    final successRate = successPercentage.toStringAsFixed(1);
    return 'DatumSyncResult(userId: $userId, synced: $syncedCount/$totalOperations ($successRate%), failed: $failedCount, conflicts: $conflictsResolved, pushed: $bytesPushedInCycle bytes, pulled: $bytesPulledInCycle bytes, duration: ${formatDuration(duration)})';
  }

  /// Converts the result to a map for serialization.
  ///
  /// Note: `pendingOperations` and `error` are not serialized.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'userId': userId,
      'duration': duration.inMilliseconds,
      'syncedCount': syncedCount,
      'failedCount': failedCount,
      'conflictsResolved': conflictsResolved,
      'totalBytesPushed': totalBytesPushed,
      'totalBytesPulled': totalBytesPulled,
      'bytesPushedInCycle': bytesPushedInCycle,
      'bytesPulledInCycle': bytesPulledInCycle,
      'wasSkipped': wasSkipped,
      'wasCancelled': wasCancelled,
      'skipReason': skipReason,
    };
  }

  /// Creates a [DatumSyncResult] from a map.
  ///
  /// Since `pendingOperations` and `error` are not stored, they are initialized
  /// to their default empty/null values.
  factory DatumSyncResult.fromMap(Map<String, dynamic> map) {
    return DatumSyncResult<T>(
      userId: map['userId'] as String,
      duration: Duration(milliseconds: map['duration'] as int),
      syncedCount: map['syncedCount'] as int,
      failedCount: map['failedCount'] as int,
      conflictsResolved: map['conflictsResolved'] as int,
      pendingOperations: const [], // Not persisted
      totalBytesPushed: map['totalBytesPushed'] as int? ?? 0,
      totalBytesPulled: map['totalBytesPulled'] as int? ?? 0,
      bytesPushedInCycle: map['bytesPushedInCycle'] as int? ?? 0,
      bytesPulledInCycle: map['bytesPulledInCycle'] as int? ?? 0,
      wasSkipped: map['wasSkipped'] as bool,
      wasCancelled: map['wasCancelled'] as bool,
      error: null, // Not persisted
      skipReason: map['skipReason'] as String?,
    );
  }
}
