import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// An immutable snapshot of key synchronization statistics.
@immutable
class DatumMetrics extends Equatable {
  /// Total number of sync cycles started.
  final int totalSyncOperations;

  /// Sync cycles that completed without any failed operations.
  final int successfulSyncs;

  /// Sync cycles that had at least one failed operation or ended in an error.
  final int failedSyncs;

  /// Total number of data conflicts detected across all syncs.
  final int conflictsDetected;

  /// Total number of conflicts resolved automatically by a resolver.
  final int conflictsResolvedAutomatically;

  /// Total number of times the active user was switched.
  final int userSwitchCount;

  /// The set of unique user IDs that have been active during the app's lifetime.
  final Set<String> activeUsers;

  /// The total cumulative number of bytes pushed to the remote across all users.
  final int totalBytesPushed;

  /// The total cumulative number of bytes pulled from the remote across all users.
  final int totalBytesPulled;

  /// Creates a [DatumMetrics] snapshot.
  const DatumMetrics({
    this.totalSyncOperations = 0,
    this.successfulSyncs = 0,
    this.failedSyncs = 0,
    this.conflictsDetected = 0,
    this.conflictsResolvedAutomatically = 0,
    this.userSwitchCount = 0,
    this.activeUsers = const {},
    this.totalBytesPushed = 0,
    this.totalBytesPulled = 0,
  });

  /// Creates a copy of this metrics object with updated values.
  DatumMetrics copyWith({
    int? totalSyncOperations,
    int? successfulSyncs,
    int? failedSyncs,
    int? conflictsDetected,
    int? conflictsResolvedAutomatically,
    int? userSwitchCount,
    Set<String>? activeUsers,
    int? totalBytesPushed,
    int? totalBytesPulled,
  }) {
    return DatumMetrics(
      totalSyncOperations: totalSyncOperations ?? this.totalSyncOperations,
      successfulSyncs: successfulSyncs ?? this.successfulSyncs,
      failedSyncs: failedSyncs ?? this.failedSyncs,
      conflictsDetected: conflictsDetected ?? this.conflictsDetected,
      conflictsResolvedAutomatically: conflictsResolvedAutomatically ?? this.conflictsResolvedAutomatically,
      userSwitchCount: userSwitchCount ?? this.userSwitchCount,
      activeUsers: activeUsers ?? this.activeUsers,
      totalBytesPushed: totalBytesPushed ?? this.totalBytesPushed,
      totalBytesPulled: totalBytesPulled ?? this.totalBytesPulled,
    );
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
        totalBytesPushed,
        totalBytesPulled,
      ];

  @override
  String toString() {
    return 'DatumMetrics('
        'Syncs: $totalSyncOperations, '
        '✅: $successfulSyncs, '
        '❌: $failedSyncs, '
        'Conflicts: $conflictsDetected, '
        'Resolved: $conflictsResolvedAutomatically, '
        'Users: ${activeUsers.length}, '
        'Switches: $userSwitchCount, '
        'Pushed: ${(totalBytesPushed / 1024).toStringAsFixed(2)} KB, '
        'Pulled: ${(totalBytesPulled / 1024).toStringAsFixed(2)} KB'
        ')';
  }
}
