// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// An immutable snapshot of the synchronization metrics for the entire Datum instance.
@immutable
class DatumMetrics extends Equatable {
  /// The total number of synchronization cycles that have been started.
  final int totalSyncOperations;

  /// The number of synchronization cycles that completed without any failed operations.
  final int successfulSyncs;

  /// The number of synchronization cycles that failed or completed with at least one failed operation.
  final int failedSyncs;

  /// The total number of conflicts detected during pull operations.
  final int conflictsDetected;

  /// The number of conflicts that were resolved automatically by a resolver.
  final int conflictsResolvedAutomatically;

  /// The number of times the active user has been switched.
  final int userSwitchCount;

  /// A set of unique user IDs that have been active during the session.
  final Set<String> activeUsers;

  /// Creates a new instance of [DatumMetrics].
  const DatumMetrics({
    this.totalSyncOperations = 0,
    this.successfulSyncs = 0,
    this.failedSyncs = 0,
    this.conflictsDetected = 0,
    this.conflictsResolvedAutomatically = 0,
    this.userSwitchCount = 0,
    this.activeUsers = const {},
  });

  /// Creates a copy of this [DatumMetrics] instance with the given fields replaced.
  DatumMetrics copyWith({
    int? totalSyncOperations,
    int? successfulSyncs,
    int? failedSyncs,
    int? conflictsDetected,
    int? conflictsResolvedAutomatically,
    int? userSwitchCount,
    Set<String>? activeUsers,
  }) {
    return DatumMetrics(
      totalSyncOperations: totalSyncOperations ?? this.totalSyncOperations,
      successfulSyncs: successfulSyncs ?? this.successfulSyncs,
      failedSyncs: failedSyncs ?? this.failedSyncs,
      conflictsDetected: conflictsDetected ?? this.conflictsDetected,
      conflictsResolvedAutomatically:
          conflictsResolvedAutomatically ?? this.conflictsResolvedAutomatically,
      userSwitchCount: userSwitchCount ?? this.userSwitchCount,
      activeUsers: activeUsers ?? this.activeUsers,
    );
  }

  @override
  String toString() {
    return 'DatumMetrics(totalSyncs: $totalSyncOperations, successful: $successfulSyncs, failed: $failedSyncs, conflicts: $conflictsDetected)';
  }

  @override
  List<Object?> get props => [
        totalSyncOperations,
        successfulSyncs,
        failedSyncs,
        conflictsDetected,
        conflictsResolvedAutomatically,
        userSwitchCount,
        activeUsers,
      ];
}
