import 'package:equatable/equatable.dart';

/// Aggregated statistics about multiple sync cycles.
class DatumSyncStatistics extends Equatable {
  /// The total number of sync operations that have been initiated.
  final int totalSyncs;

  /// The number of syncs that completed successfully.
  final int successfulSyncs;

  /// The number of syncs that failed.
  final int failedSyncs;

  /// The total number of conflicts detected.
  final int conflictsDetected;

  /// The number of conflicts that were resolved automatically.
  final int conflictsAutoResolved;

  /// The number of conflicts that required user resolution.
  final int conflictsUserResolved;

  /// The running average duration of a sync operation.
  final Duration averageDuration;

  /// The total combined duration of all syncs.
  final Duration totalSyncDuration;

  /// Creates an instance of sync statistics.
  const DatumSyncStatistics({
    this.totalSyncs = 0,
    this.successfulSyncs = 0,
    this.failedSyncs = 0,
    this.conflictsDetected = 0,
    this.conflictsAutoResolved = 0,
    this.conflictsUserResolved = 0,
    this.averageDuration = Duration.zero,
    this.totalSyncDuration = Duration.zero,
  });

  /// Creates a copy of this object with modified fields.
  DatumSyncStatistics copyWith({
    int? totalSyncs,
    int? successfulSyncs,
    int? failedSyncs,
    int? conflictsDetected,
    int? conflictsAutoResolved,
    int? conflictsUserResolved,
    Duration? averageDuration,
    Duration? totalSyncDuration,
  }) {
    return DatumSyncStatistics(
      totalSyncs: totalSyncs ?? this.totalSyncs,
      successfulSyncs: successfulSyncs ?? this.successfulSyncs,
      failedSyncs: failedSyncs ?? this.failedSyncs,
      conflictsDetected: conflictsDetected ?? this.conflictsDetected,
      conflictsAutoResolved:
          conflictsAutoResolved ?? this.conflictsAutoResolved,
      conflictsUserResolved:
          conflictsUserResolved ?? this.conflictsUserResolved,
      averageDuration: averageDuration ?? this.averageDuration,
      totalSyncDuration: totalSyncDuration ?? this.totalSyncDuration,
    );
  }

  @override
  List<Object?> get props => [
    totalSyncs,
    successfulSyncs,
    failedSyncs,
    conflictsDetected,
    conflictsAutoResolved,
    conflictsUserResolved,
    averageDuration,
    totalSyncDuration,
  ];
}
