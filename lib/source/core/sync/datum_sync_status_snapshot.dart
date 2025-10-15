import 'package:flutter/foundation.dart';
import 'package:datum/source/core/health/datum_health.dart';

/// High-level states for the synchronization process.
enum DatumSyncStatus {
  /// No sync currently running.
  idle,

  /// Sync is actively running.
  syncing,

  /// Sync was paused by the user.
  paused,

  /// Sync was cancelled by the user.
  cancelled,

  /// Sync failed with errors.
  failed,

  /// Sync completed successfully.
  completed,
}

/// An immutable snapshot describing the current sync state for a user.
@immutable
class DatumSyncStatusSnapshot {
  /// User ID for this snapshot.
  final String userId;

  /// Current high-level sync status.
  final DatumSyncStatus status;

  /// Number of operations waiting to sync.
  final int pendingOperations;

  /// Number of completed operations in the current cycle.
  final int completedOperations;

  /// Number of failed operations in the current cycle.
  final int failedOperations;

  /// Progress percentage (0.0 to 1.0) of the current cycle.
  final double progress;

  /// When the last sync started.
  final DateTime? lastStartedAt;

  /// When the last sync completed.
  final DateTime? lastCompletedAt;

  /// Errors encountered during the sync.
  final List<Object> errors;

  /// Number of successfully synced operations in the current cycle.
  final int syncedCount;

  /// Number of conflicts resolved in the current cycle.
  final int conflictsResolved;

  /// The current health status of this specific sync manager.
  final DatumHealth health;

  /// Whether there is unsynced data.
  bool get hasUnsyncedData => pendingOperations > 0;

  /// Whether there are any failures.
  bool get hasFailures => failedOperations > 0;

  /// Creates a sync status snapshot.
  const DatumSyncStatusSnapshot({
    required this.userId,
    required this.status,
    required this.pendingOperations,
    required this.completedOperations,
    required this.failedOperations,
    required this.progress,
    this.lastStartedAt,
    this.lastCompletedAt,
    this.errors = const [],
    this.syncedCount = 0,
    this.conflictsResolved = 0,
    this.health = const DatumHealth(status: DatumSyncHealth.healthy),
  });

  /// Creates an initial snapshot for a user.
  factory DatumSyncStatusSnapshot.initial(String userId) {
    return DatumSyncStatusSnapshot(
      userId: userId,
      status: DatumSyncStatus.idle,
      pendingOperations: 0,
      completedOperations: 0,
      failedOperations: 0,
      progress: 0,
      health: const DatumHealth(status: DatumSyncHealth.healthy),
    );
  }

  /// Creates a copy with modified fields.
  DatumSyncStatusSnapshot copyWith({
    DatumSyncStatus? status,
    int? pendingOperations,
    int? completedOperations,
    int? failedOperations,
    double? progress,
    DateTime? lastStartedAt,
    DateTime? lastCompletedAt,
    List<Object>? errors,
    int? syncedCount,
    int? conflictsResolved,
    DatumHealth? health,
  }) {
    return DatumSyncStatusSnapshot(
      userId: userId,
      status: status ?? this.status,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      completedOperations: completedOperations ?? this.completedOperations,
      failedOperations: failedOperations ?? this.failedOperations,
      progress: progress ?? this.progress,
      lastStartedAt: lastStartedAt ?? this.lastStartedAt,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      errors: errors ?? this.errors,
      syncedCount: syncedCount ?? this.syncedCount,
      conflictsResolved: conflictsResolved ?? this.conflictsResolved,
      health: health ?? this.health,
    );
  }
}
