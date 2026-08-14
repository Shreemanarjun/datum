---




title:  🔧 Troubleshooting Guide
description: Debug and resolve common Datum sync issues.
---




Common issues and solutions for Datum synchronization problems.

## Common Errors

### Generic Type & Entity Registration Issues
**Quick fixes for the most common errors:**
- ["Entity type DatumEntityInterface is not registered"](./common_errors#entity-type-datumentityinterface-is-not-registered)
- ["Cannot use DatumEntityInterface directly"](./common_errors#cannot-use-datumentityinterface-directly)
- [Choosing the right database adapter](./common_errors#choosing-local-database-adapters)

## Sync Not Working

### Issue: Initial sync fails
**Symptoms:** `synchronize()` throws exception on first call

**Solutions:**
```dart
// 1. Check connectivity
final isConnected = await Datum.instance.connectivityChecker.isConnected;
if (!isConnected) {
  print('No internet connection');
  return;
}

// 2. Verify adapter initialization
try {
  await localAdapter.initialize();
  await remoteAdapter.initialize();
} catch (e) {
  print('Adapter initialization failed: $e');
}

// 3. Make sure a user is signed in before syncing
if (userId.isEmpty) {
  throw StateError('User not authenticated');
}
```

### Issue: Sync hangs indefinitely
**Symptoms:** `synchronize()` call never returns

**Debug Steps:**
```dart
import 'dart:async';

// Add a timeout to individual sync calls...
try {
  final result =
      await manager.synchronize(userId).timeout(const Duration(seconds: 30));
  print('Synced ${result.syncedCount} operation(s)');
} on TimeoutException {
  print('Sync timeout - check network and server');
}

// ...or configure the timeout on the engine / per sync cycle instead:
final config = DatumConfig<Task>(
  syncTimeout: Duration(minutes: 1), // whole-cycle timeout
);
await manager.synchronize(
  userId,
  options: const DatumSyncOptions(timeout: Duration(seconds: 30)),
);

// Also check for circular dependencies in relationships:
// ensure no self-referencing entities.
```

## Conflict Resolution Issues

### Issue: Unexpected conflict behavior
**Symptoms:** Conflicts not resolving as expected

**Check conflict resolver configuration:**
```dart
final config = DatumConfig<Task>(
  // Used whenever no per-operation resolver is provided.
  // If null, LastWriteWinsResolver is the default.
  defaultConflictResolver: LastWriteWinsResolver<Task>(),
);
```

**Verify custom resolver logic** — a resolver implements `name` and
`resolve({local, remote, context})` and returns a `DatumConflictResolution`:

```dart
class CustomResolver implements DatumConflictResolver<Task> {
  @override
  String get name => 'CustomResolver';

  @override
  Future<DatumConflictResolution<Task>> resolve({
    Task? local,
    Task? remote,
    required DatumConflictContext context,
  }) async {
    // Add logging to debug resolution logic
    print('Resolving conflict: ${context.entityId} (${context.type.name})');
    if (local != null) {
      return DatumConflictResolution.useLocal(local);
    }
    return DatumConflictResolution.useRemote(remote!);
  }
}
```

```dart continue
final config = DatumConfig<Task>(
  defaultConflictResolver: CustomResolver(),
);
```

### Issue: Conflict resolution UI not showing
**Symptoms:** Conflicts detected but no user prompt

**Listen to conflict events and apply the user's choice:**
```dart
manager.onConflict.listen((event) async {
  print('Conflict on ${event.context.entityId} (${event.context.type.name})');

  // Show your dialog comparing event.localData and event.remoteData,
  // then write the winning version back as the latest change.
  final winner = event.localData ?? event.remoteData;
  if (winner != null) {
    await manager.push(item: winner, userId: event.userId);
  }
});
```

## Adapter Problems

### Issue: Local adapter data corruption
**Symptoms:** Local data inconsistent or missing

**Recovery steps:**
```dart
// Clear corrupted local data for this user
await localAdapter.clearUserData(userId);

// Force a full pull from the remote
final result = await manager.synchronize(
  userId,
  options: const DatumSyncOptions(
    forceFullSync: true,
    direction: SyncDirection.pullThenPush,
  ),
);
```

### Issue: Remote adapter authentication errors
**Symptoms:** 401/403 errors from remote API

**Detect auth failures with the typed error API and re-authenticate:**
```dart
final result = await manager.trySynchronize(userId);
switch (result) {
  case Success():
    print('Sync succeeded');
  case Failure(value: final error):
    final cause = error.cause;
    if (cause is DatumException &&
        cause.code == DatumExceptionCode.authenticationError) {
      // Refresh your session with your auth provider, update the
      // credentials your RemoteAdapter uses, then retry the sync.
      await manager.synchronize(userId);
    }
}
```

## Performance Issues

### Issue: Sync too slow
**Symptoms:** Synchronization takes too long

**Optimization strategies:**
```dart
// 1. Process the sync queue in parallel batches
final parallel = DatumConfig<Task>(
  syncExecutionStrategy: const ParallelStrategy(batchSize: 10, failFast: false),
);

// 2. Tune the pull batch sizes for your payloads
final batching = DatumConfig<Task>(
  remoteSyncBatchSize: 200, // remote changes handled per batch
  remoteStreamBatchSize: 100, // items streamed from adapters at a time
);

// 3. Sync only critical data with a scoped query
final scope = DatumSyncScope(
  query: DatumQuery(
    filters: [Filter('priority', FilterOperator.greaterThanOrEqual, 3)],
  ),
);
await manager.synchronize(userId, scope: scope);
```

### Issue: Memory usage too high
**Symptoms:** App crashes with out-of-memory errors

**Memory optimization:**
```dart
// Process in smaller chunks instead of holding everything at once
const chunkSize = 100;
final entities = await manager.readAll(userId: userId);

for (var i = 0; i < entities.length; i += chunkSize) {
  final end =
      (i + chunkSize < entities.length) ? i + chunkSize : entities.length;
  final chunk = entities.sublist(i, end);
  print('Processing ${chunk.length} entities...');

  // Yield to the event loop between chunks
  await Future<void>.delayed(const Duration(milliseconds: 10));
}
```

## Network Issues

### Issue: Intermittent connectivity
**Symptoms:** Sync fails randomly

**Implement retry logic:**
```dart
final config = DatumConfig<Task>(
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    maxRetries: 3,
    // Only retry errors that are worth retrying.
    shouldRetry: (error) async =>
        error is NetworkException && error.isRetryable,
    backoffStrategy: const ExponentialBackoff(
      baseDelay: Duration(seconds: 1),
      multiplier: 2.0,
      maxDelay: Duration(minutes: 2),
    ),
  ),
);
```

### Issue: Large payload failures
**Symptoms:** Sync fails with large datasets

**Chunk large operations:**
```dart
// Cap the per-cycle batch size for this sync
await manager.synchronize(
  userId,
  options: const DatumSyncOptions(overrideBatchSize: 20),
);

// Or save-and-sync in explicit batches
final allEntities = await manager.readAll(userId: userId);
const batchSize = 20;
for (var i = 0; i < allEntities.length; i += batchSize) {
  final end = (i + batchSize < allEntities.length)
      ? i + batchSize
      : allEntities.length;
  final batch = allEntities.sublist(i, end);
  await manager.saveMany(items: batch, userId: userId, andSync: true);
}
```

## Database Issues

### Issue: Schema version conflicts
**Symptoms:** Migration errors during initialization

**Handle schema updates:**
```dart
final config = DatumConfig<Task>(
  schemaVersion: 2,
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [
        ColumnOperation.rename('name', to: 'title'),
        ColumnOperation.add('priority', defaultValue: 0),
      ],
    ),
  ],
);
```

### Issue: Database locked errors
**Symptoms:** SQLite "database locked" errors

**Implement proper transaction handling:**
```dart
// Group writes into a single transaction so they don't
// contend for the database lock.
await localAdapter.transaction(() async {
  await localAdapter.create(task);
  await localAdapter.update(task.copyWith(isCompleted: true));
});
```

## Debugging Tools

### Enable detailed logging
```dart
// Logging is configured on DatumConfig...
final config = DatumConfig<Task>(
  enableLogging: true,
  logLevel: LogLevel.debug,
);

// ...and a custom DatumLogger can be passed to Datum.initialize
// (use `sink:` to route log output to your own destination).
final debugLogger = DatumLogger(
  enabled: true,
  minimumLevel: LogLevel.debug,
);
```

### Health checks
```dart
import 'dart:async';

// Regular health monitoring
Timer.periodic(const Duration(minutes: 5), (_) async {
  final health = await manager.checkHealth();
  if (health.status == DatumSyncHealth.error ||
      health.status == DatumSyncHealth.degraded) {
    print('Health check failed:\n${health.describe()}');
  }
});
```

### Sync status monitoring
```dart
// Track sync progress
final subscription = manager.statusStream.listen((snapshot) {
  print('Sync status: ${snapshot.status.name} '
      '(${(snapshot.progress * 100).toStringAsFixed(0)}%)');
  if (snapshot.hasFailures) {
    print('Sync errors: ${snapshot.errors}');
  }
});
```

## Common Error Codes

Thrown errors are `DatumException`s carrying a `DatumExceptionCode`:

| Error Code | Description | Solution |
|------------|-------------|----------|
| `networkError` | Network connectivity issues | Check internet connection |
| `authenticationError` | Authentication failed | Refresh auth tokens |
| `schemaMismatch` | Database schema conflict | Run migrations |
| `conflictDetected` | Data conflicts found | Implement conflict resolution |
| `timeout` | Operation timed out | Increase timeout or reduce batch size |
| `migrationError` | Schema migration failed | Fix the migration chain, see `onMigrationError` |

The non-throwing `tryX` methods (`trySynchronize`, `tryRead`, `tryPush`, ...)
map these onto a small, pattern-matchable `DatumError` hierarchy instead:
`NotFoundError`, `ConflictError`, `NetworkError`, `ValidationError`,
`StorageError`, and `UnknownError`.

## Getting Help

If these solutions don't resolve your issue:

1. **Check the logs** - Enable debug logging for detailed information
2. **Review your configuration** - Verify adapter setup and options
3. **Test with minimal example** - Isolate the problem
4. **Report on GitHub** - Include logs, configuration, and reproduction steps

---


*This guide covers the most common Datum issues. For more advanced debugging, check the [Advanced Sync Patterns](guides/advanced_sync) guide.*
