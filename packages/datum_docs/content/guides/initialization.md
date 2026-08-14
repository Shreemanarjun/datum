---
title: Initialization & Global API
---

This guide covers how to initialize Datum and use the global API for managing your data synchronization.

## Overview

The `Datum` class is the central entry point for all Datum operations. It manages entity registration, synchronization, and provides global access to managers.

## Initialization

Before using any Datum features, you must initialize the singleton instance:

```dart
import 'package:datum/datum.dart';

Future<Datum> bootstrapDatum({
  required DatumConnectivityChecker connectivityChecker,
  required LocalAdapter<Task> localTaskAdapter,
  required RemoteAdapter<Task> remoteTaskAdapter,
}) async {
  // Initialize Datum
  final result = await Datum.initialize(
    config: const DatumConfig(
      // Configuration options
      autoSyncInterval: Duration(minutes: 15),
      enableLogging: true,
    ),
    connectivityChecker: connectivityChecker,
    registrations: [
      // One DatumRegistration per entity type
      DatumRegistration<Task>(
        localAdapter: localTaskAdapter,
        remoteAdapter: remoteTaskAdapter,
      ),
    ],
  );

  // Now you can use Datum. getSuccess() throws the typed DatumError if
  // initialization failed — see "Error Handling" below for pattern matching.
  return result.getSuccess();
}
```

### Configuration Options

```dart
final config = DatumConfig<Task>(
  // Synchronization
  autoSyncInterval: const Duration(minutes: 15),  // How often to auto-sync
  autoStartSync: true,                            // Start sync automatically
  syncTimeout: const Duration(seconds: 30),       // Sync operation timeout
  defaultSyncDirection: SyncDirection.pushThenPull, // Default sync behavior

  // Conflict Resolution
  defaultConflictResolver: LastWriteWinsResolver<Task>(), // Default resolver

  // User Management
  defaultUserSwitchStrategy: UserSwitchStrategy.syncThenSwitch,
  initialUserId: null, // Callback returning the user to sync on startup

  // Performance
  remoteEventDebounceTime: const Duration(milliseconds: 50),
  changeCacheDuration: const Duration(seconds: 5),

  // Error Handling
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    maxRetries: 3,
    backoffStrategy: const ExponentialBackoff(),
    shouldRetry: (error) async => error.code == DatumExceptionCode.networkError,
  ),

  // Schema Management
  schemaVersion: 1,
  migrations: const [], // Your Migration implementations

  // Execution Strategies
  syncExecutionStrategy: const SequentialStrategy(),
  syncRequestStrategy: const SequentialRequestStrategy(),
);
```

### Connectivity Checker

You must provide a connectivity checker implementation:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class MyConnectivityChecker implements DatumConnectivityChecker {
  final _connectivity = Connectivity();

  @override
  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  @override
  Stream<bool> get onStatusChange {
    return _connectivity.onConnectivityChanged.map((results) {
      return !results.contains(ConnectivityResult.none);
    });
  }
}
```

## Entity Registration

Register your entities with their adapters:

```dart
final registrations = [
  DatumRegistration<Task>(
    localAdapter: localAdapter,
    remoteAdapter: remoteAdapter,
    // Optional: entity-specific conflict resolution
    conflictResolver: LastWriteWinsResolver<Task>(),
    // Optional: entity-specific config overrides
    config: DatumConfig<Task>(
      autoSyncInterval: const Duration(minutes: 5),
    ),
    // Optional extras:
    // middlewares: [MyEncryptionMiddleware()],  // List<DatumMiddleware<Task>>
    // observers: [MyTaskObserver()],            // List<DatumObserver<Task>>
  ),
];
```

## Global CRUD Operations

Once initialized, you can perform CRUD operations globally:

```dart
// Create
final newTask = await Datum.instance.create(Task(
  id: 'task-1',
  userId: 'user-123',
  title: 'Learn Datum',
  createdAt: DateTime.now(),
  modifiedAt: DateTime.now(),
  version: 1,
));

// Read
final fetched = await Datum.instance.read<Task>('task-1', userId: 'user-123');
final allTasks = await Datum.instance.readAll<Task>(userId: 'user-123');

// Update
final updatedTask = await Datum.instance.update(
  newTask.copyWith(title: 'Learn Datum v2'),
);

// Delete
final deleted = await Datum.instance.delete<Task>(id: 'task-1', userId: 'user-123');

// Batch operations
final newTasks = await Datum.instance.createMany<Task>(
  items: [
    newTask.copyWith(title: 'Chapter 2'),
    newTask.copyWith(title: 'Chapter 3'),
  ],
  userId: 'user-123',
);
```

## Manager Access

Access specific managers for advanced operations:

```dart
// Get manager for a type
final taskManager = Datum.manager<Task>();

// Perform manager-specific operations
taskManager.startAutoSync('user-123');
final pendingCount = await taskManager.getPendingCount('user-123');
```

## Global Synchronization

Trigger synchronization across all registered entities:

```dart
// Sync all entities for a user
final result = await Datum.instance.synchronize('user-123');

// Sync with custom options
final customResult = await Datum.instance.synchronize(
  'user-123',
  options: DatumSyncOptions(
    direction: SyncDirection.pullThenPush,
    includeDeletes: true,
  ),
);
```

## Reactive Streams

Watch for changes globally:

```dart
// Watch all tasks
final allTasksStream = Datum.instance.watchAll<Task>(userId: 'user-123');

// Watch specific task
final singleTaskStream = Datum.instance.watchById<Task>('task-1', 'user-123');

// Watch with pagination
final paginatedStream = Datum.instance.watchAllPaginated<Task>(
  const PaginationConfig(pageSize: 20),
  userId: 'user-123',
);
```

## Querying

Perform queries across entities:

```dart
// Simple query
final completedTasks = await Datum.instance.query<Task>(
  const DatumQuery(
    filters: [Filter('isCompleted', FilterOperator.equals, true)],
    sorting: [SortDescriptor('createdAt', descending: true)],
  ),
  source: DataSource.local,
  userId: 'user-123',
);

// Complex query: recent tasks, eager-loading a declared relation
final recentTasks = await Datum.instance.query<Task>(
  DatumQuery(
    filters: [
      Filter(
        'createdAt',
        FilterOperator.greaterThan,
        DateTime.now().subtract(const Duration(days: 7)),
      ),
    ],
    withRelated: const ['author'],
    sorting: const [SortDescriptor('createdAt', descending: true)],
    limit: 50,
  ),
  source: DataSource.remote,
  userId: 'user-123',
);
```

## Health Monitoring

Check the health of all managers:

```dart
// Check health of all managers
final allHealths = await Datum.instance.allHealths.first;

// Check health of specific manager
final taskHealth = await Datum.instance.checkHealth<Task>();
```

## Metrics and Monitoring

Access global metrics and status:

```dart
// Global metrics stream
final metricsStream = Datum.instance.metrics;

// Current metrics
final currentMetrics = Datum.instance.currentMetrics;

// User-specific status
final userStatus = Datum.instance.statusForUser('user-123');
```

## Error Handling

Handle initialization and runtime errors. `Datum.initialize` never throws — it returns a `DatumEither<DatumError, Datum>` you can pattern-match:

```dart
Future<void> initializeSafely(DatumConnectivityChecker connectivity) async {
  final result = await Datum.initialize(
    config: const DatumConfig(),
    connectivityChecker: connectivity,
  );

  switch (result) {
    case Success(value: final datum):
      print('Datum ready: $datum');
    case Failure(value: final error, stackTrace: _):
      print('Initialization failed: $error');
  }
}
```

Runtime operations throw typed `DatumException`s you can switch on:

```dart
try {
  await manager.synchronize(userId);
} on DatumException catch (e) {
  switch (e.code) {
    case DatumExceptionCode.networkError:
      print('Network connectivity issue');
    case DatumExceptionCode.entityNotFound:
      print('Entity not found');
    default:
      print('Sync failed: ${e.message}');
  }
}
```

## Lifecycle Management

Properly dispose of resources when shutting down:

```dart
// Pause all operations
Datum.instance.pauseSync();

// Resume operations
Datum.instance.resumeSync();

// Complete shutdown
await Datum.instance.dispose();
```

## Best Practices

1. **Initialize early**: Call `Datum.initialize()` as early as possible in your app lifecycle
2. **Handle connectivity**: Always provide a reliable connectivity checker
3. **Configure appropriately**: Tune configuration options based on your app's needs
4. **Monitor health**: Regularly check health status and handle degraded states
5. **Clean up**: Always dispose of Datum when shutting down your app
6. **Error handling**: Implement proper error handling for all Datum operations
