/// Strategy for handling synchronization when the app is fully closed and reopened.
enum ColdStartStrategy {
  /// No automatic sync on cold start
  disabled,

  /// Re-read everything from the remote on cold start (`forceFullSync`).
  fullSync,

  /// Sync on cold start when the last cold-start sync is older than
  /// `syncThreshold`. The cycle is a normal one: skipped when nothing
  /// changed, incremental when the remote adapter supports it.
  adaptive,

  /// Only sync changes since last successful sync
  incremental,

  /// Sync critical/high-priority data first, then background sync remaining data
  priorityBased,
}

/// Configuration for cold start synchronization behavior.
class ColdStartConfig {
  /// The strategy to use for cold start synchronization
  final ColdStartStrategy strategy;

  /// Maximum duration allowed for cold start sync to prevent blocking UI
  final Duration maxDuration;

  /// Time threshold after which cold start sync is triggered
  final Duration syncThreshold;

  /// Delay before starting cold start sync to allow UI to load
  final Duration initialDelay;

  const ColdStartConfig({
    this.strategy = ColdStartStrategy.adaptive,
    this.maxDuration = const Duration(seconds: 15),
    this.syncThreshold = const Duration(hours: 1),
    this.initialDelay = const Duration(milliseconds: 500),
  });

  ColdStartConfig copyWith({
    ColdStartStrategy? strategy,
    Duration? maxDuration,
    Duration? syncThreshold,
    Duration? initialDelay,
  }) {
    return ColdStartConfig(
      strategy: strategy ?? this.strategy,
      maxDuration: maxDuration ?? this.maxDuration,
      syncThreshold: syncThreshold ?? this.syncThreshold,
      initialDelay: initialDelay ?? this.initialDelay,
    );
  }
}

/// Metrics collected during cold start sync operations
class ColdStartMetrics {
  final DateTime startTime;
  final DateTime? endTime;
  final int entitiesSynced;
  final int bytesTransferred;
  final Duration? duration;
  final bool completed;
  final String? failureReason;

  const ColdStartMetrics({
    required this.startTime,
    this.endTime,
    this.entitiesSynced = 0,
    this.bytesTransferred = 0,
    this.duration,
    this.completed = false,
    this.failureReason,
  });

  ColdStartMetrics copyWith({
    DateTime? endTime,
    int? entitiesSynced,
    int? bytesTransferred,
    Duration? duration,
    bool? completed,
    String? failureReason,
  }) {
    return ColdStartMetrics(
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      entitiesSynced: entitiesSynced ?? this.entitiesSynced,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      duration: duration ?? this.duration,
      completed: completed ?? this.completed,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  double get performanceScore {
    if (duration == null) return 0.0;
    // Score based on sync efficiency (entities per second)
    final entitiesPerSecond = entitiesSynced / duration!.inSeconds;
    // Normalize to 0-1 scale (assuming 50 entities/sec is excellent)
    return (entitiesPerSecond / 50.0).clamp(0.0, 1.0);
  }
}
