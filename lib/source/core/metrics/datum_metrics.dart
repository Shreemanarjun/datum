/// Tracks a collection of metrics and statistics for sync operations.
class DatumMetrics {
  /// Creates an instance of sync metrics, usually with initial zero values.
  DatumMetrics({
    this.totalSyncOperations = 0,
    this.successfulSyncs = 0,
    this.failedSyncs = 0,
    this.averageSyncDuration = Duration.zero,
    this.conflictsDetected = 0,
    this.conflictsResolvedAutomatically = 0,
    this.bytesUploaded = 0,
    this.bytesDownloaded = 0,
    Set<String>? activeUsers,
    this.userSwitchCount = 0,
  }) : activeUsers = activeUsers ?? <String>{};

  /// The total number of sync cycles initiated.
  int totalSyncOperations;

  /// The number of sync cycles that completed without any errors.
  int successfulSyncs;

  /// The number of sync cycles that failed.
  int failedSyncs;

  /// The running average duration of a sync cycle.
  Duration averageSyncDuration;

  /// The total number of data conflicts detected.
  int conflictsDetected;

  /// The number of conflicts that were resolved automatically by a resolver.
  int conflictsResolvedAutomatically;

  /// The total bytes uploaded to the remote data source.
  int bytesUploaded;

  /// The total bytes downloaded from the remote data source.
  int bytesDownloaded;

  /// A set of unique user IDs that have been active.
  final Set<String> activeUsers;

  /// The number of times the active user has been switched.
  int userSwitchCount;

  /// Converts the metrics object to a map for serialization or logging.
  Map<String, dynamic> toMap() => {
    'total_sync_operations': totalSyncOperations,
    'successful_syncs': successfulSyncs,
    'failed_syncs': failedSyncs,
    'average_sync_duration_ms': averageSyncDuration.inMilliseconds,
    'conflicts_detected': conflictsDetected,
    'conflicts_resolved_automatically': conflictsResolvedAutomatically,
    'bytes_uploaded': bytesUploaded,
    'bytes_downloaded': bytesDownloaded,
    'active_users_count': activeUsers.length,
    'user_switch_count': userSwitchCount,
  };
}
