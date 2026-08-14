---
title: Advanced Synchronization Patterns
---




This guide covers advanced synchronization patterns, monitoring, and control features in Datum. These patterns help you build robust, production-ready applications with sophisticated data synchronization requirements.

## Sync Strategies and Execution

<Info>
**Pro Tip**: Choose sync direction based on your app's needs. `pushThenPull` is recommended for most applications as it ensures local changes are sent first.
</Info>

### Sync Direction Control

Datum supports different synchronization directions to control the flow of data:

```dart
// Push local changes to remote, then pull remote changes
final pushThenPullResult = await manager.synchronize(
  'user123',
  options: DatumSyncOptions(direction: SyncDirection.pushThenPull),
);

// Pull remote changes first, then push local changes
final pullThenPushResult = await manager.synchronize(
  'user123',
  options: DatumSyncOptions(direction: SyncDirection.pullThenPush),
);

// Only push local changes (useful for one-way sync)
final pushOnlyResult = await manager.synchronize(
  'user123',
  options: DatumSyncOptions(direction: SyncDirection.pushOnly),
);

// Only pull remote changes (useful for read-only data)
final pullOnlyResult = await manager.synchronize(
  'user123',
  options: DatumSyncOptions(direction: SyncDirection.pullOnly),
);
```

### Execution Strategies

Control how sync operations are processed:

```dart
// Sequential processing (default) - process operations one by one
final sequentialConfig = DatumConfig(
  syncExecutionStrategy: SequentialStrategy(),
);

// Parallel processing - process multiple operations concurrently
final parallelConfig = DatumConfig(
  syncExecutionStrategy: ParallelStrategy(batchSize: 10),
);

// Background isolate processing - run sync in separate thread to avoid UI blocking
final isolateConfig = DatumConfig(
  syncExecutionStrategy: IsolateStrategy(SequentialStrategy()),
);

// Parallel processing in background isolate
final parallelIsolateConfig = DatumConfig(
  syncExecutionStrategy: IsolateStrategy(
    ParallelStrategy(batchSize: 5, failFast: true),
  ),
);
```

<Info>
**Performance Tip**: Use `IsolateStrategy` for heavy sync operations to prevent UI freezing. Combine with `ParallelStrategy` for maximum throughput on multi-core devices.
</Info>

### Request Strategies

Control how concurrent synchronization requests are handled:

```dart
// Queue concurrent requests with retry (default)
final queuedConfig = DatumConfig(
  syncRequestStrategy: SequentialRequestStrategy(retryCount: 3),
);

// Skip concurrent requests if sync is already running
final skipConfig = DatumConfig(
  syncRequestStrategy: SkipConcurrentStrategy(),
);
```

<Info>
**Strategy Selection**: Use `SequentialRequestStrategy` for data consistency when multiple sync triggers occur. Use `SkipConcurrentStrategy` for performance-critical scenarios where duplicate syncs are acceptable.
</Info>

#### Sequential Request Strategy

Ensures all sync requests are processed in order, preventing lost updates:

```dart
// Custom retry configuration
final config = DatumConfig(
  syncRequestStrategy: SequentialRequestStrategy(retryCount: 5),
);
```

```dart
// Handle rapid user interactions
class TaskManagerService {
  TaskManagerService(this.manager, this.currentUserId);

  final DatumManager<Task> manager;
  final String currentUserId;

  Future<void> saveAndSync(Task task) async {
    await manager.push(item: task, userId: currentUserId);
    await manager.synchronize(currentUserId); // Queued if another sync is running
  }
}
```

```dart continue
// Multiple rapid calls are queued and processed sequentially
final taskManager = TaskManagerService(manager, userId);
await Future.wait([
  taskManager.saveAndSync(task),
  taskManager.saveAndSync(task.copyWith(title: 'Second')),
  taskManager.saveAndSync(task.copyWith(title: 'Third')),
]);
```

#### Skip Concurrent Strategy

Prevents resource waste from overlapping sync operations:

```dart
final config = DatumConfig(
  syncRequestStrategy: SkipConcurrentStrategy(),
);

// Auto-sync triggers won't overlap
manager.startAutoSync('user123', interval: Duration(minutes: 2));

// Manual sync calls during auto-sync are skipped
final result = await manager.synchronize('user123');
if (result.wasSkipped) {
  print('Sync was skipped - another sync is already in progress');
}
```

<Warning>
**Data Loss Risk**: `SkipConcurrentStrategy` may result in lost updates if important changes are skipped. Use only when sync operations are idempotent.
</Warning>

## Conflict Resolution

### Built-in Resolvers

Datum provides several conflict resolution strategies:

```dart
// Last write wins - choose the most recently modified version
final lwwConfig = DatumConfig<Task>(
  defaultConflictResolver: LastWriteWinsResolver<Task>(),
);

// Local priority - always prefer local changes
final localWinsConfig = DatumConfig<Task>(
  defaultConflictResolver: LocalPriorityResolver<Task>(),
);

// Remote priority - always prefer remote changes
final remoteWinsConfig = DatumConfig<Task>(
  defaultConflictResolver: RemotePriorityResolver<Task>(),
);

// Intelligent merging - attempt to merge conflicting changes
final mergeConfig = DatumConfig<Task>(
  defaultConflictResolver: MergeResolver<Task>(
    onMerge: (local, remote, context) {
      // Custom merge logic
      return local.copyWith(
        title: local.title, // Keep local title
        description: remote.description, // Take remote description
      );
    },
  ),
);
```

<Warning>
**Important**: Custom conflict resolvers run on the main thread. For complex resolution logic, consider offloading to background isolates to avoid blocking the UI.
</Warning>

### Custom Conflict Resolvers

Implement custom resolution logic:

```dart
class CustomResolver extends DatumConflictResolver<Task> {
  @override
  String get name => 'CustomResolver';

  @override
  Future<DatumConflictResolution<Task>> resolve({
    Task? local,
    Task? remote,
    required DatumConflictContext context,
  }) async {
    if (local == null || remote == null) {
      // One side is missing (e.g. a deletion conflict) - keep whichever exists
      final survivor = local ?? remote;
      return survivor == null
          ? const DatumConflictResolution.abort('Nothing to resolve')
          : DatumConflictResolution.merge(survivor);
    }

    // Custom logic: prefer local for titles, remote for other fields
    if (local.title != remote.title) {
      final resolved = remote.copyWith(title: local.title);
      return DatumConflictResolution.merge(resolved);
    }

    // No conflict in the title - keep the local version
    return DatumConflictResolution.useLocal(local);
  }
}
```

### Conflict Monitoring

Monitor and handle conflicts reactively:

```dart
// Listen for conflict events
manager.onConflict.listen((event) {
  print('Conflict detected for ${event.context.entityId}');
  print('local: ${event.localData}, remote: ${event.remoteData}');
  // Handle conflict resolution UI
});

// Listen for resolution events
manager.eventStream
    .where((event) => event is ConflictResolvedEvent<Task>)
    .cast<ConflictResolvedEvent<Task>>()
    .listen((event) {
  print('Conflict resolved: ${event.resolution.strategy.name}');
});
```

## User Switching

### User Switch Strategies

Handle user switching with different strategies:

```dart
// Sync current user before switching
final result1 = await manager.switchUser(
  oldUserId: 'user1',
  newUserId: 'user2',
  strategy: UserSwitchStrategy.syncThenSwitch,
);

// Clear new user's data and fetch from remote
final result2 = await manager.switchUser(
  oldUserId: 'user1',
  newUserId: 'user2',
  strategy: UserSwitchStrategy.clearAndFetch,
);

// Fail if current user has unsynced data
final result3 = await manager.switchUser(
  oldUserId: 'user1',
  newUserId: 'user2',
  strategy: UserSwitchStrategy.promptIfUnsyncedData,
);

// Switch without any data modifications
final result4 = await manager.switchUser(
  oldUserId: 'user1',
  newUserId: 'user2',
  strategy: UserSwitchStrategy.keepLocal,
);
```

### User Switch Monitoring

```dart
// Listen for user switch events
manager.onUserSwitched.listen((event) {
  print('Switched from ${event.previousUserId} to ${event.newUserId}');
  print('Had unsynced data: ${event.hadUnsyncedData}');
});
```

## Connectivity Monitoring and Auto-Sync

### Automatic Sync on Connectivity Restoration

Datum can automatically monitor device connectivity and trigger synchronization when the device regains network access. This ensures that any pending operations queued while offline are automatically synchronized once connectivity is restored.

```dart
// The connectivity checker is provided to Datum.initialize (its required
// `connectivityChecker` parameter — see the custom checker below). Once
// configured, the system will automatically:
// 1. Monitor connectivity status changes
// 2. Queue sync operations while offline
// 3. Automatically trigger sync when connectivity is restored
// 4. Handle network failures gracefully with retry logic
final online = await Datum.instance.connectivityChecker.isConnected;
print(online ? 'Online' : 'Offline - operations will be queued');
```

### Custom Connectivity Checker

Implement custom connectivity monitoring logic:

```dart
class CustomConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async {
    // Implement your connectivity check logic, e.g. with connectivity_plus:
    //   final result = await Connectivity().checkConnectivity();
    //   return !result.contains(ConnectivityResult.none);
    return true;
  }

  @override
  Stream<bool> get onStatusChange {
    // Return a stream that emits connectivity status changes, e.g.:
    //   return Connectivity().onConnectivityChanged
    //       .map((result) => !result.contains(ConnectivityResult.none));
    return const Stream<bool>.empty();
  }
}
```

```dart continue
// Use the custom checker at initialization time
final either = await Datum.initialize(
  config: DatumConfig(),
  connectivityChecker: CustomConnectivityChecker(),
);
```

<Info>
**Network Optimization**: Connectivity monitoring helps reduce unnecessary sync attempts when offline and ensures data consistency when connectivity is restored.
</Info>

## Auto-Sync Management

### Periodic Auto-Sync

Configure automatic synchronization:

```dart
// Start auto-sync with default interval
manager.startAutoSync('user123');

// Start auto-sync with custom interval
manager.startAutoSync('user123', interval: Duration(minutes: 10));

// Stop auto-sync for specific user
manager.stopAutoSync(userId: 'user123');

// Stop auto-sync for all users
manager.stopAutoSync();
```

### Auto-Sync Monitoring

```dart
// Monitor next sync time
manager.watchNextSyncTime.listen((nextTime) {
  if (nextTime != null) {
    print('Next sync at: $nextTime');
  } else {
    print('Auto-sync disabled');
  }
});

// Monitor time until next sync
manager.watchNextSyncDuration.listen((duration) {
  if (duration != null) {
    print('Next sync in: ${duration.inMinutes} minutes');
  }
});
```

## Global Sync Control

### Pause/Resume Sync

Control synchronization across all managers:

```dart
// Pause all sync operations
Datum.instance.pauseSync();

// Resume all sync operations
Datum.instance.resumeSync();

// Check if a manager's sync is paused
final isPaused = manager.currentStatus.status == DatumSyncStatus.paused;
```

### Remote Change Subscriptions

Manage remote change listening:

```dart
// Temporarily stop listening to remote changes
await manager.unsubscribeFromRemoteChanges();

// Resume listening to remote changes
await manager.resubscribeToRemoteChanges();

// Global control
await Datum.instance.unsubscribeAllFromRemoteChanges();
await Datum.instance.resubscribeAllToRemoteChanges();
```

### Stream Management

#### Refreshing Streams

Force all reactive streams to re-evaluate their data when external state changes require cache invalidation:

```dart
// Refresh all streams for a specific manager
await manager.refreshStreams();

// This will:
// - Clear internal caches (query, relationship, entity existence)
// - Force reactive streams to emit fresh data
// - Ensure streams show the most current data after state changes
```

#### Use Cases

- **User Switching**: When switching between users, refresh streams to clear user-specific caches
- **External Data Changes**: When external systems modify data that Datum isn't aware of
- **Cache Invalidation**: When you need to ensure all streams have the latest data
- **Testing**: In test scenarios where you need to reset stream state

#### Automatic Refresh

Streams are automatically refreshed in certain scenarios:
- When users switch (via `onUserChanged` streams)
- After certain sync operations
- When the system detects state inconsistencies

#### Cache Management

```dart
// Clear specific caches
manager.clearCaches(); // Clear all caches
manager.clearRelationshipCacheForType(Task); // Clear relationship caches for Task type

// Get cache statistics
final stats = manager.getCacheStats();
print('Query cache size: ${stats['queries']}');
print('Relationship cache size: ${stats['relationship_queries']}');
```

<Warning>
**Performance Consideration**: `refreshStreams()` clears all internal caches, which may impact performance. Use sparingly and only when necessary.
</Warning>

## Monitoring and Observers

### Global Observers

Add observers for cross-cutting concerns:

```dart
class AuditObserver extends GlobalDatumObserver {
  @override
  void onSyncStart() {
    print('Global sync started');
  }

  @override
  void onSyncEnd(DatumSyncResult result) {
    print('Global sync completed: ${result.syncedCount} items');
  }

  @override
  void onUserSwitchStart(String? oldUserId, String newUserId, UserSwitchStrategy strategy) {
    print('Switching user from $oldUserId to $newUserId');
  }
}
```

```dart continue
// Register global observer
Datum.instance.addObserver(AuditObserver());
```

### Local Observers

Add entity-specific observers:

```dart
class TaskObserver extends DatumObserver<Task> {
  @override
  void onCreateStart(Task entity) {
    print('Creating task: ${entity.title}');
  }

  @override
  void onUpdateEnd(Task entity) {
    print('Updated task: ${entity.title}');
  }

  @override
  void onDeleteStart(String id) {
    print('Deleting task: $id');
  }
}
```

```dart continue
// Register during initialization
final registration = DatumRegistration<Task>(
  localAdapter: localAdapter,
  remoteAdapter: remoteAdapter,
  observers: [TaskObserver()],
);
```

## Data Transformation Middleware

### Middleware Pipeline

Implement data transformation pipelines for preprocessing and postprocessing:

```dart
class ValidationMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    if (item.title.isEmpty) {
      throw const ValidationException(message: 'Task title cannot be empty');
    }
    if (item.priority < 0) {
      throw const ValidationException(message: 'Priority cannot be negative');
    }
    return item;
  }
}

class EncryptionMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Encrypt sensitive fields before saving
    final encryptedDescription = await encrypt(item.description ?? '');
    return item.copyWith(description: encryptedDescription);
  }

  @override
  Future<Task> transformAfterFetch(Task item) async {
    // Decrypt sensitive fields after fetching
    final decryptedDescription = await decrypt(item.description ?? '');
    return item.copyWith(description: decryptedDescription);
  }

  Future<String> encrypt(String value) async => value; // your crypto here
  Future<String> decrypt(String value) async => value; // your crypto here
}

class AuditMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Add audit trail
    final auditEntry = {
      'entityId': item.id,
      'modifiedBy': item.userId,
      'modifiedAt': DateTime.now().toIso8601String(),
    };
    print('AUDIT: $auditEntry'); // forward to your audit log
    return item;
  }
}
```

```dart continue
// Register middleware pipeline
final registration = DatumRegistration<Task>(
  localAdapter: localAdapter,
  remoteAdapter: remoteAdapter,
  middlewares: [
    ValidationMiddleware(),
    EncryptionMiddleware(),
    AuditMiddleware(),
  ],
);
```

<Info>
**Pipeline Order**: Middleware executes in registration order. Place validation first, then transformations, then audit/logging.
</Info>

### Advanced Middleware Patterns

```dart
class CompressionMiddleware extends DatumMiddleware<Task> {
  static const _marker = 'gzip:';

  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Compress large text fields
    final description = item.description ?? '';
    if (description.length > 1000) {
      final compressed = await compress(description);
      return item.copyWith(description: '$_marker$compressed');
    }
    return item;
  }

  @override
  Future<Task> transformAfterFetch(Task item) async {
    // Decompress if needed
    final description = item.description ?? '';
    if (description.startsWith(_marker)) {
      final decompressed =
          await decompress(description.substring(_marker.length));
      return item.copyWith(description: decompressed);
    }
    return item;
  }

  Future<String> compress(String value) async => value; // your codec here
  Future<String> decompress(String value) async => value;
}

class RelationshipEnrichmentMiddleware extends DatumMiddleware<Task> {
  RelationshipEnrichmentMiddleware(this.commentCounts);

  /// Precomputed enrichment data, e.g. comment counts per task id.
  final Map<String, int> commentCounts;

  @override
  Future<Task> transformAfterFetch(Task item) async {
    // Enrich with related data
    final commentCount = commentCounts[item.id] ?? 0;
    return item.copyWith(
      description: '${item.description ?? ''} ($commentCount comments)',
    );
  }
}
```

<Warning>
**Performance Consideration**: Middleware runs on the main thread. For CPU-intensive operations, consider using background isolates or delegating to background services.
</Warning>

## Error Handling and Recovery

### Error Recovery Strategies

Configure automatic error recovery:

```dart
final config = DatumConfig(
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    shouldRetry: (error) async =>
        error is NetworkException && error.isRetryable,
    maxRetries: 3,
    backoffStrategy: ExponentialBackoff(
      baseDelay: Duration(seconds: 1),
      maxDelay: Duration(minutes: 5),
    ),
  ),
);
```

### Sync Error Handling

Handle synchronization errors:

```dart
try {
  final result = await manager.synchronize('user123');
} on DatumException catch (e) {
  print('Sync failed: ${e.message}');
  switch (e.code) {
    case DatumExceptionCode.networkError:
      // Handle network issues
      break;
    case DatumExceptionCode.authenticationError:
      // Handle authentication issues
      break;
    case DatumExceptionCode.schemaMismatch:
      // Handle schema conflicts
      break;
    default:
      // Other errors
      break;
  }
}
```

### Event-Based Error Monitoring

```dart
// Listen for sync errors
manager.onSyncError.listen((event) {
  print('Sync error: ${event.error}');
  // Implement retry logic or user notification
});
```

## Performance Optimization

### Batch Operations

Use batch operations for multiple items:

```dart
final taskList = [task, task.copyWith(title: 'Another task')];

// Batch create
await manager.saveMany(
  items: taskList,
  userId: userId,
  andSync: true, // Sync after all items are saved
);

// Batch with immediate sync for each chunk
const chunkSize = 10;
for (var i = 0; i < taskList.length; i += chunkSize) {
  final end = i + chunkSize > taskList.length ? taskList.length : i + chunkSize;
  await manager.saveMany(items: taskList.sublist(i, end), userId: userId);
  await manager.synchronize(userId); // Sync each batch
}
```

### Selective Sync

Use sync scopes for partial synchronization:

```dart
// Pull only entities matching a scope query
final scope = DatumSyncScope(
  query: DatumQuery(
    filters: [
      Filter('id', FilterOperator.isIn, ['task1', 'task2', 'task3']),
    ],
  ),
);

final result = await manager.synchronize(
  'user123',
  scope: scope,
);
```

### Connection-Aware Sync

Adapt sync behavior based on connectivity:

```dart
enum ConnectionQuality { none, poor, fair, good }

class SmartConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async {
    // Check connection quality
    final quality = await checkConnectionQuality();
    return quality != ConnectionQuality.none;
  }

  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();

  Future<ConnectionQuality> checkConnectionQuality() async {
    // Probe your backend and return none/poor/fair/good
    return ConnectionQuality.good;
  }
}
```

```dart continue
// Wire it in at initialization
final checker = SmartConnectivityChecker();
final either = await Datum.initialize(
  config: DatumConfig(),
  connectivityChecker: checker,
);

// Adaptive sync intervals
if (await checker.isConnected) {
  manager.startAutoSync('user123', interval: Duration(minutes: 5));
} else {
  manager.startAutoSync('user123', interval: Duration(hours: 1));
}
```

## Advanced Querying

### Complex Queries

Build sophisticated queries:

```dart
final complexQuery = DatumQueryBuilder<Task>()
  .where('status', isEqualTo: 'active')
  .where('priority', isGreaterThan: 3)
  .where('dueDate', isLessThan: DateTime.now().add(Duration(days: 7)))
  .where('tags', arrayContains: 'urgent')
  .orderBy('priority', descending: true)
  .orderBy('dueDate', descending: false)
  .limit(50)
  .withRelated(['assignee', 'comments'])
  .build();

// Execute query
final urgentTasks = await manager.query(complexQuery, userId: 'user123');
```

### Reactive Queries

Watch query results in real-time:

```dart
final complexQuery = DatumQueryBuilder<Task>()
    .where('priority', isGreaterThan: 3)
    .build();

final subscription = manager.watchQuery(complexQuery, userId: 'user123')
    .listen((tasks) {
  print('Urgent tasks updated: ${tasks.length}');
  // UI updates automatically
});
```

## Migration and Schema Evolution

### Schema Migrations

Handle database schema changes:

```dart
class MigrateTaskV1ToV2 extends Migration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    // Transform v1 data to v2 format
    return {
      ...oldData,
      'newField': oldData['oldField'] ?? 'default',
    };
  }
}
```

```dart continue
final config = DatumConfig(
  schemaVersion: 2,
  migrations: [MigrateTaskV1ToV2()],
  onMigrationError: (error, stack) async {
    // Handle migration failures (report, alert, etc.)
    print('Migration failed: $error');
  },
);
```

### Migration Strategies

A `Migration` declares the version pair it covers and transforms one serialized
entity map at a time:

```dart
class Migration1To2 extends Migration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    // Add new fields and transform existing ones
    return {
      ...oldData,
      'migratedAt': DateTime.now().toIso8601String(),
      'status':
          (oldData['isCompleted'] as bool? ?? false) ? 'completed' : 'pending',
    };
  }
}
```

For multi-step chains — including ones that must also run real `ALTER TABLE`
DDL on SQL stores — prefer the declarative `SchemaMigration` +
`MigrationExecutor` / `SqlMigrationExecutor` API.

## Production Monitoring

### Health Checks

Monitor system health:

```dart
import 'dart:async';

// Periodic health checks
Timer.periodic(Duration(minutes: 5), (_) async {
  final health = await manager.checkHealth();
  if (health.status == DatumSyncHealth.error) {
    print('Manager unhealthy:\n${health.describe()}');
  }
});

// Global health monitoring
Datum.instance.allHealths.listen((healthMap) {
  final unhealthy = healthMap.entries
      .where((e) => e.value.status == DatumSyncHealth.error);

  if (unhealthy.isNotEmpty) {
    print('Unhealthy managers: ${unhealthy.map((e) => e.key).join(', ')}');
  }
});
```

### Metrics Collection

Track performance metrics:

```dart
void reportMetric(String name, num value) {
  // Forward to your monitoring system
  print('$name = $value');
}

Datum.instance.metrics.listen((metrics) {
  // Report to monitoring system
  reportMetric('total_syncs', metrics.totalSyncOperations);
  reportMetric('successful_syncs', metrics.successfulSyncs);
  reportMetric('failed_syncs', metrics.failedSyncs);
  reportMetric('bytes_synced',
      metrics.totalBytesPushed + metrics.totalBytesPulled);
});
```

### Performance Profiling

Profile sync performance:

```dart
final stopwatch = Stopwatch()..start();
final result = await manager.synchronize('user123');
stopwatch.stop();

final duration = stopwatch.elapsed;
final throughput = result.syncedCount / duration.inSeconds;

print('Sync performance: $throughput items/second');
print('Data transferred: '
    '${result.bytesPushedInCycle + result.bytesPulledInCycle} bytes');
```

This guide covers the advanced patterns you'll need for building robust, scalable applications with Datum. Combine these patterns based on your specific requirements and constraints.

## 🚀 What's Next

Looking for even more advanced features? Check out our **[planned improvements](/coming_soon)** including new adapter support, enhanced developer tools, and interactive learning resources.
