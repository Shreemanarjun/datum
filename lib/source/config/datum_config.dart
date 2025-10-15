import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/migration/migration.dart';
import 'package:datum/source/core/models/user_switch_models.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/sync/datum_sync_execution_strategy.dart';

/// A handler for migration errors.
typedef MigrationErrorHandler =
    Future<void> Function(Object error, StackTrace stackTrace);

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

/// Configuration for the Datum engine and its managers.
class DatumConfig<T extends DatumEntity> {
  /// The interval for any automatic background synchronization.
  final Duration autoSyncInterval;

  /// Whether to automatically start auto-sync for all users with local data
  /// upon initialization.
  final bool autoStartSync;

  /// The maximum number of times a failed sync operation will be retried.
  final int maxRetries;

  /// The base delay before retrying a failed operation.
  final Duration retryDelay;

  /// The maximum duration for a single sync cycle before it times out.
  final Duration syncTimeout;

  /// The default conflict resolver to use if none is provided per-operation.
  /// If null, [LastWriteWinsResolver] is used.
  final DatumConflictResolver<T>? defaultConflictResolver;

  /// The default strategy to use when switching users.
  final UserSwitchStrategy defaultUserSwitchStrategy;

  /// The user ID to target for the initial auto-sync if [autoStartSync] is
  /// true. If null, DatumManager will discover all users with local data.
  final String? initialUserId;

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

  const DatumConfig({
    this.autoSyncInterval = const Duration(minutes: 15),
    this.autoStartSync = false,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 30),
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
  });

  /// A default configuration with sensible production values.
  factory DatumConfig.defaultConfig() => const DatumConfig();

  // In a full implementation, a `copyWith` method would be included here
  // to allow for easy modification of the configuration.

  DatumConfig<E> copyWith<E extends DatumEntity>({
    Duration? autoSyncInterval,
    bool? autoStartSync,
    int? maxRetries,
    Duration? retryDelay,
    Duration? syncTimeout,
    DatumConflictResolver<E>? defaultConflictResolver,
    UserSwitchStrategy? defaultUserSwitchStrategy,
    String? initialUserId,
    bool? enableLogging,
    SyncDirection? defaultSyncDirection,
    int? schemaVersion,
    List<Migration>? migrations,
    DatumSyncExecutionStrategy? syncExecutionStrategy,
    MigrationErrorHandler? onMigrationError,
  }) {
    return DatumConfig<E>(
      autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
      autoStartSync: autoStartSync ?? this.autoStartSync,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      syncTimeout: syncTimeout ?? this.syncTimeout,
      // Only copy the resolver if the new type E is assignable from the old type T.
      // This is safe when copyWith is called without a new generic type.
      defaultConflictResolver:
          defaultConflictResolver ??
          (this.defaultConflictResolver is DatumConflictResolver<E>
              ? this.defaultConflictResolver as DatumConflictResolver<E>
              : null),
      defaultUserSwitchStrategy:
          defaultUserSwitchStrategy ?? this.defaultUserSwitchStrategy,
      initialUserId: initialUserId ?? this.initialUserId,
      enableLogging: enableLogging ?? this.enableLogging,
      defaultSyncDirection: defaultSyncDirection ?? this.defaultSyncDirection,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      migrations: migrations ?? this.migrations,
      syncExecutionStrategy:
          syncExecutionStrategy ?? this.syncExecutionStrategy,
      onMigrationError: onMigrationError ?? this.onMigrationError,
    );
  }
}
