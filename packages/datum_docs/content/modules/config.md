---
title: Configuration Module
---




The Configuration module provides comprehensive options for customizing Datum's behavior to match your application's requirements. Configuration affects everything from sync intervals to conflict resolution strategies.

<Info>
**Configuration Hierarchy**: Global config applies to all entities, but entity-specific configs override global settings for that entity type.
</Info>

## DatumConfig

The main configuration class that controls Datum's behavior globally and per-entity.

### Basic Configuration

```dart
final config = DatumConfig<Task>(
  // Logging and debugging
  enableLogging: true,
  logLevel: LogLevel.debug,

  // Auto-sync behavior
  autoStartSync: true,
  autoSyncInterval: Duration(minutes: 5),
  initialUserId: () async => 'user123',

  // Delete behavior
  deleteBehavior: DeleteBehavior.softDelete, // or hardDelete (default)

  // Sync behavior
  defaultSyncDirection: SyncDirection.pushThenPull,
  syncTimeout: Duration(seconds: 30),
  defaultSyncOptions: DatumSyncOptions<Task>(
    forceFullSync: false,
    resolveConflicts: true,
  ),

  // Schema management
  schemaVersion: 2,
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [ColumnOperation.add('priority', defaultValue: 0)],
    ),
  ],

  // Error handling
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    shouldRetry: (error) async => error is NetworkException && error.isRetryable,
    maxRetries: 3,
    backoffStrategy: const ExponentialBackoff(),
  ),

  // User switching
  defaultUserSwitchStrategy: UserSwitchStrategy.syncThenSwitch,

  // Performance tuning
  syncExecutionStrategy: const SequentialStrategy(),
  syncRequestStrategy: const SequentialRequestStrategy(),
  remoteEventDebounceTime: Duration(milliseconds: 100),
  changeCacheDuration: Duration(seconds: 30),

  // Performance tuning for sync operations
  remoteSyncBatchSize: 100,
  remoteStreamBatchSize: 50,
  progressEventFrequency: 50,

  // Cold start synchronization
  coldStartConfig: ColdStartConfig(
    strategy: ColdStartStrategy.adaptive,
    maxDuration: Duration(seconds: 15),
    syncThreshold: Duration(hours: 1),
    initialDelay: Duration(milliseconds: 500),
  ),
);
```

### Delete Behavior Configuration

Configure how delete operations are handled globally:

```dart
// Hard delete (the default): items are removed from local storage immediately
final hardDeleteConfig = DatumConfig<Task>(
  deleteBehavior: DeleteBehavior.hardDelete,
);

// Soft delete: items are marked as deleted locally and removed only after
// the delete operation has synced — recommended for offline-first apps
final softDeleteConfig = DatumConfig<Task>(
  deleteBehavior: DeleteBehavior.softDelete,
);
```

#### Delete Behavior Options

- **`DeleteBehavior.hardDelete`**: Immediately removes items from local storage (default)
- **`DeleteBehavior.softDelete`**: Marks items as deleted locally and queues the delete operation for synchronization

#### Hard Delete Behavior

```dart
// Items are immediately removed from local storage
await manager.delete(id: 'task123', userId: 'user1');
// Item is gone from local storage immediately
// Delete operation is queued for remote sync
```

#### Soft Delete Behavior

```dart
// Items are marked as deleted locally but remain in storage
await manager.delete(id: 'task123', userId: 'user1');
// Item remains in local storage with isDeleted = true
// Delete operation is queued for remote sync
// Item will be removed after successful sync
```

#### Per-Operation Override

Override the global delete behavior for specific operations:

```dart
// Override global config for specific delete operations
await manager.delete(
  id: 'task123',
  userId: 'user1',
  behavior: DeleteBehavior.softDelete, // Override global hardDelete setting
);

// Or use the sync method with behavior override
await manager.deleteAndSync(
  id: 'task123',
  userId: 'user1',
  behavior: DeleteBehavior.hardDelete, // Override global softDelete setting
);
```

<Info>
**Delete Behavior Choice**: Use `hardDelete` for immediate local cleanup, `softDelete` for guaranteed sync of delete operations.
</Info>

### Default Sync Options

Configure default synchronization behavior that applies to all sync operations:

```dart
final config = DatumConfig<Task>(
  defaultSyncOptions: DatumSyncOptions<Task>(
    forceFullSync: false,        // Force full sync bypassing metadata comparison
    resolveConflicts: true,      // Whether to resolve conflicts during sync
    includeDeletes: true,        // Include delete operations in sync
    direction: SyncDirection.pushThenPull,  // Sync direction
    timeout: Duration(seconds: 30),         // Sync operation timeout
  ),
);
```

**Key Options:**
- **`forceFullSync`**: When `true`, forces a complete sync regardless of metadata comparison results
- **`resolveConflicts`**: Whether conflicts should be resolved during sync (default: `true`)
- **`includeDeletes`**: Whether delete operations should be included in sync (default: `true`)
- **`direction`**: The sync direction for this sync, overriding the config default
- **`timeout`**: Maximum time allowed for this sync, overriding the config default
- **`overrideBatchSize`**: A custom batch size for this sync
- **`conflictResolver`**: A conflict resolver overriding the default for this sync only
- **`query`**: A query used to filter the data fetched from the remote source

### Sync Direction Options

Control the order and type of synchronization:

- **`SyncDirection.pushThenPull`**: Push local changes first, then pull remote changes (default)
- **`SyncDirection.pullThenPush`**: Pull remote changes first, then push local changes
- **`SyncDirection.pushOnly`**: Only push local changes to remote
- **`SyncDirection.pullOnly`**: Only pull remote changes to local

### Execution Strategies

Control how sync operations are processed:

#### SequentialStrategy (Default)

```dart
final config = DatumConfig(
  syncExecutionStrategy: SequentialStrategy(),
);
```

Processes operations one by one. Reliable but potentially slower for large batches.

#### ParallelStrategy

```dart
final config = DatumConfig(
  syncExecutionStrategy: ParallelStrategy(
    batchSize: 10, // Process 10 operations concurrently
  ),
);
```

Processes multiple operations concurrently. Faster for large batches but uses more resources. Pass `failFast: false` to keep processing the remaining operations after the first error.

### Request Strategies

Handle concurrent synchronization requests:

#### SequentialRequestStrategy (Default)

```dart
final config = DatumConfig(
  syncRequestStrategy: SequentialRequestStrategy(),
);
```

Queues concurrent sync requests and processes them in order.

#### SkipConcurrentStrategy

```dart
final config = DatumConfig(
  syncRequestStrategy: SkipConcurrentStrategy(),
);
```

Skips new sync requests if a sync is already in progress.

### Error Recovery

Configure automatic retry behavior for failed operations. `shouldRetry` receives the `DatumException` and decides whether a retry is worthwhile:

```dart
final config = DatumConfig(
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    shouldRetry: (error) async => error is NetworkException && error.isRetryable,
    maxRetries: 3,
    backoffStrategy: ExponentialBackoff(
      baseDelay: Duration(seconds: 1),
      maxDelay: Duration(minutes: 5),
      multiplier: 2.0,
    ),
  ),
);
```

#### Built-in Backoff Strategies

- **`ExponentialBackoff`**: Exponential backoff with configurable `baseDelay`, `multiplier`, and `maxDelay`
- **`LinearBackoff`**: Delay increases by a fixed `increment` per attempt
- **`FixedBackoff`**: Fixed `delay` between retries
- **`CustomBackoff`**: Delay computed by a custom function of the attempt number

### User Switch Strategies

Control behavior when switching between users:

- **`UserSwitchStrategy.syncThenSwitch`**: Sync current user's data before switching
- **`UserSwitchStrategy.clearAndFetch`**: Clear new user's local data and fetch from remote
- **`UserSwitchStrategy.promptIfUnsyncedData`**: Fail switch if current user has unsynced data
- **`UserSwitchStrategy.keepLocal`**: Switch without any data modifications

### Conflict Resolution

Set the default conflict resolution strategy. If none is provided, `LastWriteWinsResolver` is used:

```dart
final config = DatumConfig<Task>(
  defaultConflictResolver: LastWriteWinsResolver<Task>(),
);
```

Other built-in resolvers are `LocalPriorityResolver`, `RemotePriorityResolver`, `MergeResolver`, and `UserPromptResolver`. Implement `DatumConflictResolver<T>` for custom resolution logic.

### Migration Configuration

Handle schema evolution declaratively with `SchemaMigration`:

```dart
final config = DatumConfig(
  schemaVersion: 2,
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [
        ColumnOperation.add('priority', defaultValue: 0),
        ColumnOperation.rename('description', to: 'content'),
      ],
    ),
  ],
  onMigrationError: (error, stack) async {
    // Handle migration failures (e.g. report and recover)
    print('Migration failed: $error');
  },
);
```

If `onMigrationError` is null, migration errors are rethrown so the app never runs against a corrupted store.

### Sync Optimization & Cache Flags

Newer `DatumConfig` fields fine-tune how much work a sync cycle does:

```dart
final config = DatumConfig(
  // Treat entities missing from a full remote pull as remote deletions and
  // route them through the conflict resolver (default: false)
  detectRemoteDeletions: false,

  // Cache local query() results (default: false — the local DB is already fast,
  // and cached shared instances can go stale)
  enableQueryCache: false,
  maxQueryCacheSize: 100,

  // Cache the per-user content hash used for sync metadata so idle cycles skip
  // an O(n) readAll + rehash (default: true)
  enableMetadataHashCache: true,

  // Allow incremental pulls when the remote adapter mixes in DeltaSyncCapable
  // or CursorSyncCapable (default: true)
  enableDeltaSync: true,
  // Clock-skew tolerance subtracted from the delta-sync watermark
  deltaSyncOverlap: Duration(minutes: 5),

  // Local-only/system user IDs that must never be auto-discovered or synced
  excludedSyncUserIds: {'automatic-system'},

  // Offload the entire sync cycle to a background isolate. Requires adapters
  // that can be sent to (or re-established in) another isolate.
  useIsolateSync: false,
);
```

**Key Flags:**
- **`detectRemoteDeletions`**: On a *full* pull, entities that exist locally but not remotely are surfaced as deletion conflicts. The default `LastWriteWinsResolver` keeps local data; use a remote-priority resolver to propagate deletions.
- **`enableQueryCache`** / **`maxQueryCacheSize`**: Opt-in caching for local `query()` calls.
- **`enableMetadataHashCache`**: Keeps sync-metadata hashing O(1) for idle cycles. Disable only if something writes to local storage completely out-of-band.
- **`enableDeltaSync`** / **`deltaSyncOverlap`**: Incremental pulls fetch only entities modified since the last sync watermark. First syncs and `detectRemoteDeletions` cycles still perform full pulls.
- **`excludedSyncUserIds`**: Explicit `synchronize(userId)` calls for excluded users are skipped too.
- **`useIsolateSync`**: Runs synchronization off the main isolate.

## Entity-Specific Configuration

Configure behavior per entity type:

```dart
final taskConfig = DatumConfig<Task>(
  // Task-specific settings
  autoSyncInterval: Duration(minutes: 2), // More frequent sync for tasks
  defaultConflictResolver: LocalPriorityResolver<Task>(), // Prefer local changes
  syncExecutionStrategy: ParallelStrategy(batchSize: 5),
);

final registration = DatumRegistration<Task>(
  localAdapter: localAdapter,
  remoteAdapter: remoteAdapter,
  config: taskConfig,
);
```

## Connectivity Configuration

Datum needs a `DatumConnectivityChecker` implementation, passed to `Datum.initialize` (not to `DatumConfig`):

```dart
class CustomConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async {
    // Custom connectivity logic (e.g. connectivity_plus, a ping, ...)
    return true;
  }

  @override
  Stream<bool> get onStatusChange {
    // Emit whenever connectivity changes
    return const Stream.empty();
  }
}
```

```dart continue
await Datum.initialize(
  config: const DatumConfig(),
  connectivityChecker: CustomConnectivityChecker(),
);
```

## Observer Configuration

Add global and entity-specific observers:

```dart
// Entity-specific observer
class TaskAuditObserver extends DatumObserver<Task> {
  @override
  void onCreateEnd(Task item) => print('Task created: ${item.id}');
}

// Global observer (sees events for every entity type)
class MetricsObserver extends GlobalDatumObserver {
  @override
  void onSyncEnd(DatumSyncResult result) =>
      print('Sync finished: ${result.syncedCount} synced');
}
```

```dart continue
// Your app's connectivity checker (see the Utils module)
class AppConnectivity implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
```

Register both kinds during initialization:

```dart continue
await Datum.initialize(
  config: const DatumConfig(),
  connectivityChecker: AppConnectivity(),
  registrations: [
    DatumRegistration<Task>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
      observers: [TaskAuditObserver()], // entity-specific
    ),
  ],
  observers: [MetricsObserver()], // global
);
```

## Performance Tuning

### Debouncing Remote Events

Reduce the frequency of remote change processing:

```dart
final config = DatumConfig(
  remoteEventDebounceTime: Duration(milliseconds: 500), // Buffer events for 500ms
);
```

### Change Cache Duration

Control how long recent changes are cached to prevent duplicates:

```dart
final config = DatumConfig(
  changeCacheDuration: Duration(minutes: 1),        // Cache changes for 1 minute
  maxChangeCacheSize: 1000,                         // Bound the cache size
  changeCacheCleanupInterval: Duration(seconds: 30), // Periodic cleanup
);
```

### Sync Timeouts

Set timeouts for sync operations:

```dart
final config = DatumConfig(
  syncTimeout: Duration(minutes: 2), // 2 minute timeout
);
```

### Batch Processing

Configure batch sizes for memory-efficient sync operations:

```dart
final config = DatumConfig(
  remoteSyncBatchSize: 100,    // Process 100 remote items per batch
  remoteStreamBatchSize: 50,   // Stream 50 items at a time
  progressEventFrequency: 50,  // Emit progress events every 50 items
);
```

**Batch Processing Options:**
- **`remoteSyncBatchSize`**: Number of remote items processed together (default: 100)
- **`remoteStreamBatchSize`**: Number of items streamed at once for memory efficiency (default: 50)
- **`progressEventFrequency`**: How often progress events are emitted during sync (default: 50)

### Cold Start Configuration

Configure automatic synchronization behavior when the app is fully closed and reopened:

```dart
final config = DatumConfig(
  coldStartConfig: ColdStartConfig(
    strategy: ColdStartStrategy.adaptive,    // Sync strategy
    maxDuration: Duration(seconds: 15),      // Max sync time to prevent blocking UI
    syncThreshold: Duration(hours: 1),       // Minimum time between cold starts
    initialDelay: Duration(milliseconds: 500), // Delay before starting sync
  ),
);
```

#### Cold Start Strategies

- **`ColdStartStrategy.disabled`**: No automatic sync on cold start
- **`ColdStartStrategy.fullSync`**: Always perform full sync on cold start
- **`ColdStartStrategy.adaptive`**: Smart sync based on time since last sync and other factors (default)
- **`ColdStartStrategy.incremental`**: Only sync changes since last successful sync
- **`ColdStartStrategy.priorityBased`**: Sync critical/high-priority data first, then background sync remaining data

#### Cold Start Configuration Options

- **`strategy`**: The synchronization strategy to use (default: `adaptive`)
- **`maxDuration`**: Maximum duration allowed for cold start sync to prevent blocking UI (default: 15 seconds)
- **`syncThreshold`**: Time threshold after which cold start sync is triggered (default: 1 hour)
- **`initialDelay`**: Delay before starting cold start sync to allow UI to load (default: 500ms)

## Initialization Configuration

Configure Datum initialization behavior:

```dart
class MyConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true; // plug in connectivity_plus here
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
```

```dart continue
await Datum.initialize(
  config: const DatumConfig(
    // Global config applied to all entities
    enableLogging: true,
    autoStartSync: true,
  ),
  connectivityChecker: MyConnectivityChecker(),
  registrations: [
    // Entity-specific configs override globals
    DatumRegistration<Task>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
      config: DatumConfig<Task>(
        autoSyncInterval: Duration(minutes: 1), // Override global setting
      ),
    ),
  ],
);
```

<Warning>
**Critical Settings**: Always test configuration changes in development first. Settings like `syncExecutionStrategy` and `defaultConflictResolver` can significantly impact performance and data integrity.
</Warning>

## Configuration Best Practices

### Development vs Production

```dart
DatumConfig getConfig(String environment) {
  switch (environment) {
    case 'development':
      return DatumConfig(
        enableLogging: true,
        logLevel: LogLevel.debug,
        autoSyncInterval: Duration(seconds: 30), // Frequent sync for testing
        errorRecoveryStrategy: DatumErrorRecoveryStrategy(
          shouldRetry: (error) async => false, // Fail fast in development
          maxRetries: 1,
        ),
      );

    case 'production':
      return DatumConfig(
        enableLogging: false,
        autoSyncInterval: Duration(minutes: 5),
        errorRecoveryStrategy: DatumErrorRecoveryStrategy(
          shouldRetry: (error) async => error is NetworkException && error.isRetryable,
          maxRetries: 5, // More retries in production
        ),
      );

    default:
      return DatumConfig();
  }
}
```

### Feature Flags

Use configuration for feature toggles:

```dart
class FeatureConfig {
  final bool enableOfflineSync;
  final bool enableConflictResolution;
  final bool enableMetrics;

  const FeatureConfig({
    this.enableOfflineSync = true,
    this.enableConflictResolution = true,
    this.enableMetrics = false,
  });

  DatumConfig toDatumConfig() {
    return DatumConfig(
      autoStartSync: enableOfflineSync,
      defaultConflictResolver: enableConflictResolution
          ? LastWriteWinsResolver()
          : null,
      // Configure metrics collection
    );
  }
}
```

### Environment-Specific Settings

```dart
import 'dart:io';

DatumConfig getEnvironmentConfig() {
  final environment = Platform.environment['ENVIRONMENT'] ?? 'development';

  return DatumConfig(
    // Adjust settings based on environment
    enableLogging: environment == 'development',
    autoSyncInterval: environment == 'production'
        ? Duration(minutes: 5)
        : Duration(seconds: 30),
    syncTimeout: environment == 'production'
        ? Duration(minutes: 5)
        : Duration(seconds: 10),
  );
}
```

## Monitoring Configuration

Performance logging and runtime monitoring are configured through `DatumConfig` and observed through the manager and `Datum` streams:

```dart
final config = DatumConfig(
  // Log operations that exceed the threshold
  enablePerformanceLogging: true,
  performanceLogThreshold: Duration(milliseconds: 100),
);
```

```dart
// Observe global metrics
datum.metrics.listen((m) {
  print('Syncs: ${m.totalSyncOperations} '
      '(ok: ${m.successfulSyncs}, failed: ${m.failedSyncs})');
});

// Run a health check on demand
final health = await manager.checkHealth();
print(health.describe());
```

## Migration Strategies

### Schema Versioning

```dart
class AppMigrations {
  static const currentVersion = 3;

  static List<Migration> get all => [
        SchemaMigration(
          fromVersion: 1,
          toVersion: 2,
          operations: [
            ColumnOperation.add('priority', defaultValue: 'medium'),
          ],
        ),
        SchemaMigration(
          fromVersion: 2,
          toVersion: 3,
          operations: [
            ColumnOperation.rename('description', to: 'content'),
          ],
        ),
      ];
}
```

Use in configuration:

```dart continue
final config = DatumConfig(
  schemaVersion: AppMigrations.currentVersion,
  migrations: AppMigrations.all,
);
```

## Configuration Recipes

`DatumConfig`'s defaults are production-safe. These recipes show complete configurations tuned for common scenarios — start from the one closest to your use case and adjust.

### Development

Verbose logging, fast feedback, fail-fast retries:

```dart
final developmentConfig = DatumConfig(
  enableLogging: true,
  logLevel: LogLevel.debug,
  enablePerformanceLogging: true,
  performanceLogThreshold: Duration(milliseconds: 50),
  autoStartSync: true,
  autoSyncInterval: Duration(minutes: 5),
  syncTimeout: Duration(seconds: 30),
  changeCacheDuration: Duration(seconds: 10),
  maxChangeCacheSize: 500,
  remoteSyncBatchSize: 50,
  remoteStreamBatchSize: 25,
  progressEventFrequency: 25,
  remoteEventDebounceTime: Duration(milliseconds: 25),
);
```

### Production

Minimal logging, longer timeouts, larger batches:

```dart
final productionConfig = DatumConfig(
  enableLogging: true,
  logLevel: LogLevel.warn,
  autoStartSync: true,
  autoSyncInterval: Duration(minutes: 30),
  syncTimeout: Duration(minutes: 5),
  changeCacheDuration: Duration(minutes: 2),
  maxChangeCacheSize: 2000,
  changeCacheCleanupInterval: Duration(minutes: 5),
  remoteSyncBatchSize: 200,
  remoteStreamBatchSize: 100,
  progressEventFrequency: 100,
  remoteEventDebounceTime: Duration(milliseconds: 100),
);
```

### Low Memory

Small caches, small batches, sync on demand:

```dart
final lowMemoryConfig = DatumConfig(
  autoStartSync: false,
  syncTimeout: Duration(minutes: 2),
  changeCacheDuration: Duration(seconds: 30),
  maxChangeCacheSize: 200,
  changeCacheCleanupInterval: Duration(seconds: 30),
  remoteSyncBatchSize: 25,
  remoteStreamBatchSize: 10,
  progressEventFrequency: 10,
);
```

### Testing

No auto-sync, tiny caches, immediate event processing:

```dart
final testingConfig = DatumConfig(
  enableLogging: false,
  autoStartSync: false,
  syncTimeout: Duration(seconds: 10),
  changeCacheDuration: Duration(seconds: 5),
  maxChangeCacheSize: 50,
  remoteSyncBatchSize: 10,
  remoteStreamBatchSize: 5,
  progressEventFrequency: 5,
  remoteEventDebounceTime: Duration(milliseconds: 1),
);
```

### Real-Time

Frequent sync, short debounce, delta pulls:

```dart
final realTimeConfig = DatumConfig(
  autoStartSync: true,
  autoSyncInterval: Duration(seconds: 30),
  syncTimeout: Duration(seconds: 30),
  enableDeltaSync: true,
  remoteSyncBatchSize: 20,
  remoteStreamBatchSize: 10,
  remoteEventDebounceTime: Duration(milliseconds: 10),
);
```

### Recipe Selection Guide

| Recipe | Environment | Use Case |
|--------|-------------|----------|
| Development | Development | Fast feedback, debugging, testing |
| Production | Production | Balanced performance and reliability |
| Low Memory | Memory-constrained | Mobile apps, embedded systems |
| Testing | Automated testing | Fast test execution, minimal overhead |
| Real-Time | Live collaboration | Real-time sync, instant updates |

### Environment-Based Configuration

```dart
import 'dart:io';

DatumConfig configForEnvironment() {
  final environment = Platform.environment['ENVIRONMENT'] ?? 'development';
  switch (environment) {
    case 'production':
      return DatumConfig(logLevel: LogLevel.warn, autoSyncInterval: Duration(minutes: 30));
    case 'staging':
      return DatumConfig(logLevel: LogLevel.debug, autoSyncInterval: Duration(minutes: 30));
    case 'testing':
      return DatumConfig(enableLogging: false, autoStartSync: false);
    default:
      return DatumConfig(logLevel: LogLevel.debug, autoSyncInterval: Duration(seconds: 30));
  }
}
```

This configuration system provides extensive control over Datum's behavior while maintaining sensible defaults for most use cases.
