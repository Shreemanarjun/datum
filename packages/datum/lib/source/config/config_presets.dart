import 'datum_config.dart';
import '../utils/datum_logger.dart';

/// Configuration presets for common use cases.
///
/// These presets provide optimized configurations for different scenarios:
/// - [development]: Verbose logging, short timeouts, frequent cleanup
/// - [production]: Optimized performance, longer timeouts, minimal logging
/// - [highPerformance]: Maximum performance with large batches and minimal overhead
/// - [lowMemory]: Memory-efficient with small caches and frequent cleanup
/// - [testing]: Optimized for testing with minimal logging and fast timeouts
abstract class DatumConfigPresets {
  /// Configuration optimized for development environments.
  ///
  /// Features:
  /// - Verbose logging for debugging
  /// - Short timeouts for faster feedback
  /// - Frequent cache cleanup
  /// - Auto-sync enabled with short intervals
  static DatumConfig development() {
    return const DatumConfig(
      autoSyncInterval: Duration(minutes: 5),
      autoStartSync: true,
      syncTimeout: Duration(seconds: 30),
      enableLogging: true,
      logLevel: LogLevel.debug,
      enablePerformanceLogging: true,
      performanceLogThreshold: Duration(milliseconds: 50),
      changeCacheDuration: Duration(seconds: 10),
      maxChangeCacheSize: 500,
      changeCacheCleanupInterval: Duration(seconds: 15),
      remoteSyncBatchSize: 50,
      remoteStreamBatchSize: 25,
      progressEventFrequency: 25,
      remoteEventDebounceTime: Duration(milliseconds: 25),
    );
  }

  /// Configuration optimized for production environments.
  ///
  /// Features:
  /// - Minimal logging for performance
  /// - Longer timeouts for reliability
  /// - Optimized batch sizes
  /// - Auto-sync enabled with reasonable intervals
  static DatumConfig production() {
    return const DatumConfig(
      autoSyncInterval: Duration(minutes: 30),
      autoStartSync: true,
      syncTimeout: Duration(minutes: 5),
      enableLogging: true,
      logLevel: LogLevel.warn,
      enablePerformanceLogging: false,
      changeCacheDuration: Duration(minutes: 2),
      maxChangeCacheSize: 2000,
      changeCacheCleanupInterval: Duration(minutes: 5),
      remoteSyncBatchSize: 200,
      remoteStreamBatchSize: 100,
      progressEventFrequency: 100,
      remoteEventDebounceTime: Duration(milliseconds: 100),
    );
  }

  /// Configuration optimized for maximum performance.
  ///
  /// Features:
  /// - Minimal logging and overhead
  /// - Large batch sizes for efficiency
  /// - Extended cache durations
  /// - Auto-sync with longer intervals
  static DatumConfig highPerformance() {
    return const DatumConfig(
      autoSyncInterval: Duration(hours: 1),
      autoStartSync: true,
      syncTimeout: Duration(minutes: 10),
      enableLogging: false,
      logLevel: LogLevel.error,
      enablePerformanceLogging: false,
      changeCacheDuration: Duration(minutes: 5),
      maxChangeCacheSize: 5000,
      changeCacheCleanupInterval: Duration(minutes: 15),
      remoteSyncBatchSize: 500,
      remoteStreamBatchSize: 250,
      progressEventFrequency: 250,
      remoteEventDebounceTime: Duration(milliseconds: 200),
    );
  }

  /// Configuration optimized for low memory usage.
  ///
  /// Features:
  /// - Small cache sizes
  /// - Frequent cache cleanup
  /// - Minimal batch sizes
  /// - Auto-sync disabled by default
  static DatumConfig lowMemory() {
    return const DatumConfig(
      autoSyncInterval: Duration(hours: 2),
      autoStartSync: false,
      syncTimeout: Duration(minutes: 2),
      enableLogging: true,
      logLevel: LogLevel.info,
      enablePerformanceLogging: false,
      changeCacheDuration: Duration(seconds: 30),
      maxChangeCacheSize: 200,
      changeCacheCleanupInterval: Duration(seconds: 30),
      remoteSyncBatchSize: 25,
      remoteStreamBatchSize: 10,
      progressEventFrequency: 10,
      remoteEventDebounceTime: Duration(milliseconds: 10),
    );
  }

  /// Configuration optimized for testing environments.
  ///
  /// Features:
  /// - Minimal logging
  /// - Very short timeouts
  /// - Small caches for fast cleanup
  /// - Auto-sync disabled
  static DatumConfig testing() {
    return const DatumConfig(
      autoSyncInterval: Duration(hours: 1),
      autoStartSync: false,
      syncTimeout: Duration(seconds: 10),
      enableLogging: false,
      logLevel: LogLevel.error,
      enablePerformanceLogging: false,
      changeCacheDuration: Duration(seconds: 5),
      maxChangeCacheSize: 50,
      changeCacheCleanupInterval: Duration(seconds: 5),
      remoteSyncBatchSize: 10,
      remoteStreamBatchSize: 5,
      progressEventFrequency: 5,
      remoteEventDebounceTime: Duration(milliseconds: 1),
    );
  }

  /// Configuration for offline-first applications.
  ///
  /// Features:
  /// - Extended cache durations
  /// - Auto-sync enabled with moderate intervals
  /// - Larger batch sizes for efficiency
  /// - Moderate logging
  static DatumConfig offlineFirst() {
    return const DatumConfig(
      autoSyncInterval: Duration(minutes: 15),
      autoStartSync: true,
      syncTimeout: Duration(minutes: 3),
      enableLogging: true,
      logLevel: LogLevel.info,
      enablePerformanceLogging: false,
      changeCacheDuration: Duration(minutes: 10),
      maxChangeCacheSize: 1000,
      changeCacheCleanupInterval: Duration(minutes: 10),
      remoteSyncBatchSize: 100,
      remoteStreamBatchSize: 50,
      progressEventFrequency: 50,
      remoteEventDebounceTime: Duration(milliseconds: 50),
    );
  }

  /// Configuration for real-time applications.
  ///
  /// Features:
  /// - Very short debounce times
  /// - Frequent auto-sync
  /// - Small batch sizes for responsiveness
  /// - Minimal caching
  static DatumConfig realTime() {
    return const DatumConfig(
      autoSyncInterval: Duration(seconds: 30),
      autoStartSync: true,
      syncTimeout: Duration(seconds: 30),
      enableLogging: true,
      logLevel: LogLevel.warn,
      enablePerformanceLogging: false,
      changeCacheDuration: Duration(seconds: 10),
      maxChangeCacheSize: 100,
      changeCacheCleanupInterval: Duration(seconds: 10),
      remoteSyncBatchSize: 20,
      remoteStreamBatchSize: 10,
      progressEventFrequency: 10,
      remoteEventDebounceTime: Duration(milliseconds: 10),
    );
  }

  /// Creates a custom configuration by extending an existing preset.
  ///
  /// This allows you to start with a preset and customize specific values.
  static DatumConfig custom({
    required DatumConfig base,
    Duration? autoSyncInterval,
    bool? autoStartSync,
    Duration? syncTimeout,
    bool? enableLogging,
    LogLevel? logLevel,
    bool? enablePerformanceLogging,
    Duration? performanceLogThreshold,
    Duration? changeCacheDuration,
    int? maxChangeCacheSize,
    Duration? changeCacheCleanupInterval,
    int? remoteSyncBatchSize,
    int? remoteStreamBatchSize,
    int? progressEventFrequency,
    Duration? remoteEventDebounceTime,
    bool? enableQueryCache,
    bool? detectRemoteDeletions,
    Set<String>? excludedSyncUserIds,
  }) {
    return base.copyWith(
      autoSyncInterval: autoSyncInterval,
      autoStartSync: autoStartSync,
      syncTimeout: syncTimeout,
      enableLogging: enableLogging,
      logLevel: logLevel,
      enablePerformanceLogging: enablePerformanceLogging,
      performanceLogThreshold: performanceLogThreshold,
      changeCacheDuration: changeCacheDuration,
      maxChangeCacheSize: maxChangeCacheSize,
      changeCacheCleanupInterval: changeCacheCleanupInterval,
      remoteSyncBatchSize: remoteSyncBatchSize,
      remoteStreamBatchSize: remoteStreamBatchSize,
      progressEventFrequency: progressEventFrequency,
      remoteEventDebounceTime: remoteEventDebounceTime,
      enableQueryCache: enableQueryCache,
      detectRemoteDeletions: detectRemoteDeletions,
      excludedSyncUserIds: excludedSyncUserIds,
    );
  }
}
