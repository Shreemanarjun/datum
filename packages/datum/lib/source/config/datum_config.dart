// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:equatable/equatable.dart';
import 'package:datum/source/core/migration/migration.dart';
import 'package:datum/source/utils/datum_logger.dart';

import 'package:datum/source/core/models/error_strategy.dart';
import 'package:datum/source/core/models/user_switch_models.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/sync/datum_sync_execution_strategy.dart';
import 'package:datum/source/core/manager/datum_sync_request_strategy.dart';
import 'package:datum/source/core/models/datum_sync_options.dart';
import 'package:datum/source/core/models/cold_start_strategy.dart';

import '../core/models/datum_entity.dart';

/// A handler for migration errors.
typedef MigrationErrorHandler = Future<void> Function(Object error, StackTrace stackTrace);

/// A callback that allows customizing the sync direction based on pending operations.
///
/// This callback is invoked before each sync operation to determine the optimal
/// sync direction. It receives the current pending operation count and the
/// default sync direction, and can return a custom direction.
///
/// Returns the sync direction to use for the operation. If null is returned,
/// the default direction will be used.
typedef SyncDirectionResolver = SyncDirection? Function(int pendingCount, SyncDirection defaultDirection);

/// Defines the direction of a synchronization operation.
/// Defines the order of operations during a synchronization cycle.
enum SyncDirection {
  /// Push local changes first, then pull remote changes. This is the default.
  pushThenPull,

  /// Pull remote changes first, then push local changes.
  pullThenPush,

  /// Only push local changes to the remote.
  pushOnly,

  /// Only pull remote changes to local.
  pullOnly,
}

/// Defines how delete operations are handled by the DatumManager.
enum DeleteBehavior {
  /// Marks items as deleted locally and queues a delete operation. The item is
  /// only removed from local storage after the delete is synced. This is the
  /// recommended approach for offline-first applications to ensure data
  /// consistency.
  softDelete,

  /// Immediately removes the item from local storage and queues a delete
  /// operation. This may lead to inconsistent states if the app is offline,
  /// as the local UI will reflect a deletion that has not yet been synced.
  hardDelete,
}

/// Configuration for the Datum engine and its managers.
class DatumConfig<T extends DatumEntityInterface> extends Equatable {
  /// The interval for any automatic background synchronization.
  final Duration autoSyncInterval;

  /// Whether to automatically start auto-sync for all users with local data
  /// upon initialization.
  final bool autoStartSync;

  /// The maximum duration for a single sync cycle before it times out.
  final Duration syncTimeout;

  /// The default conflict resolver to use if none is provided per-operation.
  /// If null, [LastWriteWinsResolver] is used.
  final DatumConflictResolver<T>? defaultConflictResolver;

  /// The default strategy to use when switching users.
  final UserSwitchStrategy defaultUserSwitchStrategy;

  /// The user ID to target for the initial auto-sync if [autoStartSync] is
  /// true. A function that returns a `Future<String?>` to get the current user ID.
  /// If the function returns null, DatumManager will discover all users with local data.
  /// If null, DatumManager will discover all users with local data.
  final Future<String?> Function()? initialUserId;

  /// Whether to enable detailed logging from the Datum engine.
  final bool enableLogging;

  /// The default direction for synchronization.
  final SyncDirection defaultSyncDirection;

  /// The current version of the data schema for migration purposes.
  final int schemaVersion;

  /// A list of [Migration] classes to be run when the [schemaVersion] is incremented.
  final List<Migration> migrations;

  /// The execution strategy for processing the sync queue.
  final DatumSyncExecutionStrategy syncExecutionStrategy;

  /// A callback to handle failures during schema migration.
  ///
  /// If a migration fails, this handler is invoked. If null, the error is
  /// rethrown, which will likely crash the application, preventing it from
  /// running with a corrupted database. You can provide a handler to
  /// implement a custom recovery strategy, like clearing all local data.
  final MigrationErrorHandler? onMigrationError;

  /// The strategy for handling errors and retries during synchronization.
  final DatumErrorRecoveryStrategy errorRecoveryStrategy;

  /// The duration to buffer remote changes before processing a batch.
  /// Helps to group rapid-fire updates from a server push into a single operation.
  final Duration remoteEventDebounceTime;

  /// The strategy for handling concurrent calls to the `synchronize` method.
  /// Defaults to [SequentialRequestStrategy].
  final DatumSyncRequestStrategy syncRequestStrategy;

  /// The duration to keep a change ID in the cache to prevent duplicate processing.
  ///
  /// This should be long enough to account for network latency and potential
  /// delivery of the same event via multiple channels (e.g., WebSocket + Push),
  /// but short enough not to consume excessive memory.
  final Duration changeCacheDuration;

  /// Default sync options to use when none are provided to synchronize().
  /// These options will be merged with any options passed to individual sync calls.
  final DatumSyncOptions<T>? defaultSyncOptions;

  /// The maximum number of entries to keep in the change cache.
  /// When exceeded, older entries are removed to prevent unbounded memory growth.
  final int maxChangeCacheSize;

  /// The interval for periodic cleanup of the change cache.
  /// This is in addition to the immediate cleanup based on changeCacheDuration.
  final Duration changeCacheCleanupInterval;

  /// The batch size for processing remote changes during sync operations.
  /// Larger batches reduce memory overhead but may increase latency.
  final int remoteSyncBatchSize;

  /// The batch size for streaming remote items from adapters.
  /// Smaller batches reduce memory usage but may increase processing overhead.
  final int remoteStreamBatchSize;

  /// The frequency of progress event emissions during sync operations.
  /// Progress events are emitted every N items processed.
  final int progressEventFrequency;

  /// The minimum log level for logging output.
  final LogLevel logLevel;

  /// Whether to enable performance logging for operations exceeding thresholds.
  final bool enablePerformanceLogging;

  /// The duration threshold for performance logging.
  final Duration performanceLogThreshold;

  /// Sampling strategies for high-frequency log operations.
  final Map<String, LogSampler> logSamplers;

  /// A callback that allows customizing the sync direction based on pending operations.
  ///
  /// This callback is invoked before each sync operation to determine the optimal
  /// sync direction. It receives the current pending operation count and the
  /// default sync direction, and can return a custom direction.
  ///
  /// If null, the default sync direction logic will be used.
  final SyncDirectionResolver? syncDirectionResolver;

  /// Configuration for cold start synchronization behavior.
  /// Determines how the system handles sync when the app is fully closed and reopened.
  final ColdStartConfig coldStartConfig;

  /// Defines the behavior for delete operations. Defaults to [DeleteBehavior.hardDelete].
  final DeleteBehavior deleteBehavior;

  /// The maximum size of the query cache.
  final int maxQueryCacheSize;

  /// The maximum size of the relationship query cache.
  final int maxRelationshipQueryCacheSize;

  /// The maximum size of the entity existence cache.
  final int maxEntityExistenceCacheSize;

  /// Whether to offload the entire synchronization process to a background isolate.
  ///
  /// Requires that [LocalAdapter] and [RemoteAdapter] be sendable to an isolate.
  /// This usually means they cannot hold open database connections or other
  /// non-sendable resources directly, or they must be able to re-establish
  /// connections in the new isolate.
  final bool useIsolateSync;

  const DatumConfig({
    this.autoSyncInterval = const Duration(minutes: 15),
    this.autoStartSync = false,
    this.syncTimeout = const Duration(minutes: 2),
    this.defaultConflictResolver,
    this.defaultUserSwitchStrategy = UserSwitchStrategy.syncThenSwitch,
    this.initialUserId,
    this.enableLogging = true,
    this.defaultSyncDirection = SyncDirection.pushThenPull,
    this.schemaVersion = 0,
    this.migrations = const [],
    this.syncExecutionStrategy = const SequentialStrategy(),
    this.onMigrationError,
    this.syncRequestStrategy = const SequentialRequestStrategy(),
    this.errorRecoveryStrategy = const DatumErrorRecoveryStrategy(
      shouldRetry: _defaultShouldRetry,
      maxRetries: 3,
      backoffStrategy: ExponentialBackoff(),
    ),
    this.remoteEventDebounceTime = const Duration(milliseconds: 50),
    this.changeCacheDuration = const Duration(seconds: 5),
    this.defaultSyncOptions,
    this.maxChangeCacheSize = 1000,
    this.changeCacheCleanupInterval = const Duration(seconds: 30),
    this.remoteSyncBatchSize = 100,
    this.remoteStreamBatchSize = 50,
    this.progressEventFrequency = 50,
    this.logLevel = LogLevel.info,
    this.enablePerformanceLogging = false,
    this.performanceLogThreshold = const Duration(milliseconds: 100),
    this.logSamplers = const {},
    this.syncDirectionResolver,
    this.coldStartConfig = const ColdStartConfig(),
    this.deleteBehavior = DeleteBehavior.hardDelete,
    this.maxQueryCacheSize = 100,
    this.maxRelationshipQueryCacheSize = 200,
    this.maxEntityExistenceCacheSize = 500,
    this.useIsolateSync = false,
  });

  /// A default configuration with sensible production values.
  factory DatumConfig.defaultConfig() => const DatumConfig();

  // In a full implementation, a `copyWith` method would be included here
  // to allow for easy modification of the configuration.

  DatumConfig<E> copyWith<E extends DatumEntityInterface>({
    Duration? autoSyncInterval,
    bool? autoStartSync,
    Duration? syncTimeout,
    DatumConflictResolver<E>? defaultConflictResolver,
    UserSwitchStrategy? defaultUserSwitchStrategy,
    Future<String?> Function()? initialUserId,
    bool? enableLogging,
    SyncDirection? defaultSyncDirection,
    int? schemaVersion,
    List<Migration>? migrations,
    DatumSyncExecutionStrategy? syncExecutionStrategy,
    MigrationErrorHandler? onMigrationError,
    DatumSyncRequestStrategy? syncRequestStrategy,
    DatumErrorRecoveryStrategy? errorRecoveryStrategy,
    Duration? remoteEventDebounceTime,
    Duration? changeCacheDuration,
    DatumSyncOptions<E>? defaultSyncOptions,
    int? maxChangeCacheSize,
    Duration? changeCacheCleanupInterval,
    int? remoteSyncBatchSize,
    int? remoteStreamBatchSize,
    int? progressEventFrequency,
    LogLevel? logLevel,
    bool? enablePerformanceLogging,
    Duration? performanceLogThreshold,
    Map<String, LogSampler>? logSamplers,
    SyncDirectionResolver? syncDirectionResolver,
    ColdStartConfig? coldStartConfig,
    DeleteBehavior? deleteBehavior,
    int? maxQueryCacheSize,
    int? maxRelationshipQueryCacheSize,
    int? maxEntityExistenceCacheSize,
    bool? useIsolateSync,
  }) {
    return DatumConfig<E>(
      autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
      autoStartSync: autoStartSync ?? this.autoStartSync,
      syncTimeout: syncTimeout ?? this.syncTimeout,
      // Only copy the resolver if the new type E is assignable from the old type T.
      // This is safe when copyWith is called without a new generic type.
      defaultConflictResolver: defaultConflictResolver ?? (this.defaultConflictResolver is DatumConflictResolver<E> ? this.defaultConflictResolver as DatumConflictResolver<E> : null),
      defaultUserSwitchStrategy: defaultUserSwitchStrategy ?? this.defaultUserSwitchStrategy,
      initialUserId: initialUserId ?? this.initialUserId,
      enableLogging: enableLogging ?? this.enableLogging,
      defaultSyncDirection: defaultSyncDirection ?? this.defaultSyncDirection,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      migrations: migrations ?? this.migrations,
      syncExecutionStrategy: syncExecutionStrategy ?? this.syncExecutionStrategy,
      onMigrationError: onMigrationError ?? this.onMigrationError,
      syncRequestStrategy: syncRequestStrategy ?? this.syncRequestStrategy,
      errorRecoveryStrategy: errorRecoveryStrategy ?? this.errorRecoveryStrategy,
      remoteEventDebounceTime: remoteEventDebounceTime ?? this.remoteEventDebounceTime,
      changeCacheDuration: changeCacheDuration ?? this.changeCacheDuration,
      defaultSyncOptions: defaultSyncOptions ?? (this.defaultSyncOptions is DatumSyncOptions<E> ? this.defaultSyncOptions as DatumSyncOptions<E> : null),
      maxChangeCacheSize: maxChangeCacheSize ?? this.maxChangeCacheSize,
      changeCacheCleanupInterval: changeCacheCleanupInterval ?? this.changeCacheCleanupInterval,
      remoteSyncBatchSize: remoteSyncBatchSize ?? this.remoteSyncBatchSize,
      remoteStreamBatchSize: remoteStreamBatchSize ?? this.remoteStreamBatchSize,
      progressEventFrequency: progressEventFrequency ?? this.progressEventFrequency,
      logLevel: logLevel ?? this.logLevel,
      enablePerformanceLogging: enablePerformanceLogging ?? this.enablePerformanceLogging,
      performanceLogThreshold: performanceLogThreshold ?? this.performanceLogThreshold,
      logSamplers: logSamplers ?? this.logSamplers,
      syncDirectionResolver: syncDirectionResolver ?? this.syncDirectionResolver,
      coldStartConfig: coldStartConfig ?? this.coldStartConfig,
      deleteBehavior: deleteBehavior ?? this.deleteBehavior,
      maxQueryCacheSize: maxQueryCacheSize ?? this.maxQueryCacheSize,
      maxRelationshipQueryCacheSize: maxRelationshipQueryCacheSize ?? this.maxRelationshipQueryCacheSize,
      maxEntityExistenceCacheSize: maxEntityExistenceCacheSize ?? this.maxEntityExistenceCacheSize,
      useIsolateSync: useIsolateSync ?? this.useIsolateSync,
    );
  }

  @override
  String toString() {
    return 'DatumConfig(autoSyncInterval: $autoSyncInterval, autoStartSync: $autoStartSync, syncTimeout: $syncTimeout, defaultConflictResolver: $defaultConflictResolver, defaultUserSwitchStrategy: $defaultUserSwitchStrategy, initialUserId: $initialUserId, enableLogging: $enableLogging, defaultSyncDirection: $defaultSyncDirection, schemaVersion: $schemaVersion, migrations: $migrations, syncExecutionStrategy: $syncExecutionStrategy, onMigrationError: $onMigrationError, syncRequestStrategy: $syncRequestStrategy, errorRecoveryStrategy: $errorRecoveryStrategy, remoteEventDebounceTime: $remoteEventDebounceTime, changeCacheDuration: $changeCacheDuration)';
  }

  @override
  List<Object?> get props {
    return [
      autoSyncInterval,
      autoStartSync,
      syncTimeout,
      defaultConflictResolver,
      defaultUserSwitchStrategy,
      initialUserId,
      enableLogging,
      defaultSyncDirection,
      schemaVersion,
      migrations,
      syncExecutionStrategy,
      onMigrationError,
      syncRequestStrategy,
      errorRecoveryStrategy,
      remoteEventDebounceTime,
      changeCacheDuration,
      defaultSyncOptions,
      maxChangeCacheSize,
      changeCacheCleanupInterval,
      remoteSyncBatchSize,
      remoteStreamBatchSize,
      progressEventFrequency,
      logLevel,
      enablePerformanceLogging,
      performanceLogThreshold,
      logSamplers,
      syncDirectionResolver,
      coldStartConfig,
      deleteBehavior,
      maxQueryCacheSize,
      maxRelationshipQueryCacheSize,
      maxEntityExistenceCacheSize,
      useIsolateSync,
    ];
  }
}

/// The default retry condition: only retry on a retryable NetworkException.
Future<bool> _defaultShouldRetry(DatumException error) async {
  return Future.value(error is NetworkException && (error).isRetryable);
}
