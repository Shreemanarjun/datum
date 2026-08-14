---
title: Datum Singleton API
---


The `Datum` class provides a global singleton instance that offers convenient access to all Datum functionality. While you can access managers directly through `Datum.manager<T>()`, the singleton also provides high-level convenience methods for common operations.

## Initialization

Before using any Datum functionality, you must initialize the singleton:

```dart
class MyConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true; // Replace with a real check

  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

Future<void> bootstrap(
  LocalAdapter<Task> localAdapter,
  RemoteAdapter<Task> remoteAdapter,
) async {
  final result = await Datum.initialize(
    config: const DatumConfig(
      enableLogging: true,
      autoStartSync: true,
      autoSyncInterval: Duration(minutes: 5),
    ),
    connectivityChecker: MyConnectivityChecker(),
    registrations: [
      DatumRegistration<Task>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
      ),
    ],
  );

  switch (result) {
    case Success():
      print('Datum is ready to use');
    case Failure(value: final error):
      print('Failed to initialize Datum: $error');
  }
}
```

## Accessing Managers

Get a manager for a specific entity type:

```dart
final taskManager = Datum.manager<Task>();
```

<Tip>
**Tip**: The singleton methods are perfect for simple operations. For advanced features like custom conflict resolution or detailed event monitoring, use the manager APIs directly.
</Tip>

## Convenience CRUD Methods

The singleton provides direct access to CRUD operations without needing to get managers first:

### Create Operations

```dart
// Create a single entity
final newTask = Task(
  id: '1',
  title: 'New Task',
  userId: 'user123',
  createdAt: DateTime.now(),
  modifiedAt: DateTime.now(),
  version: 1,
);
await Datum.instance.create(newTask);

// Create multiple entities
final tasks = [
  Task(
    id: '2',
    title: 'Task 2',
    userId: 'user123',
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
    version: 1,
  ),
  Task(
    id: '3',
    title: 'Task 3',
    userId: 'user123',
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
    version: 1,
  ),
];
await Datum.instance.createMany<Task>(items: tasks, userId: 'user123');
```

### Read Operations

```dart
// Read a single entity
final task = await Datum.instance.read<Task>('task-id', userId: 'user123');

// Read all entities for a user
final allTasks = await Datum.instance.readAll<Task>(userId: 'user123');

// Query entities
final query = DatumQueryBuilder<Task>()
  .where('isCompleted', isEqualTo: false)
  .orderBy('createdAt', descending: true)
  .build();

final pendingTasks = await Datum.instance.query<Task>(
  query,
  source: DataSource.local,
  userId: 'user123',
);
```

### Update Operations

```dart
// Update a single entity
final updatedTask = task.copyWith(title: 'Updated Title');
await Datum.instance.update(updatedTask);

// Update multiple entities
final tasksToUpdate = [
  task.copyWith(priority: 1),
  task.copyWith(isCompleted: true),
];
await Datum.instance.updateMany<Task>(items: tasksToUpdate, userId: 'user123');
```

### Delete Operations

```dart
// Delete a single entity
await Datum.instance.delete<Task>(id: 'task-id', userId: 'user123');
```

## Sync Operations

### Immediate Sync

```dart
// Create/update and immediately sync
final (savedTask, pushResult) = await Datum.instance.pushAndSync(
  item: task,
  userId: 'user123',
);

// Update and immediately sync
final (updatedTask, updateResult) = await Datum.instance.updateAndSync(
  item: task,
  userId: 'user123',
);

// Delete and immediately sync
final (deleted, deleteResult) = await Datum.instance.deleteAndSync<Task>(
  id: 'task-id',
  userId: 'user123',
);
```

### Global Sync

Synchronize all registered entity types for a user:

```dart
final syncResult = await Datum.instance.synchronize('user123');
print('Synced ${syncResult.syncedCount} items across all entities');
```

## User Change Streams

Datum provides reactive user change streams that automatically update data when users switch. This is particularly useful for multi-tenant applications where different users have separate data.

### Using Datum.userChangeStream

Listen to global user changes across all entity types:

```dart
// Listen to global user changes
final subscription = Datum.instance.userChangeStream.listen((userId) {
  print('User changed to: $userId');
  // Automatically refresh UI or data
});

// The stream emits whenever a manager switches users, e.g.:
await Datum.manager<Task>().switchUser(
  oldUserId: 'old-user-id',
  newUserId: 'new-user-id',
);
```

### Using Manager.onUserChanged

Listen to user changes for specific entity types:

```dart
// Get a specific manager
final taskManager = Datum.manager<Task>();

// Listen to user changes for this entity type
final userSubscription = taskManager.onUserChanged.listen((userId) {
  print('User changed for tasks: $userId');
  // Tasks will automatically refresh for the new user
});
```

### Integration with Authentication

```dart
class AuthService {
  String? _currentUserId;

  Future<void> login(String userId) async {
    // Switching users through a manager syncs the outgoing user's
    // data (per the configured strategy) and notifies userChangeStream.
    await Datum.manager<Task>().switchUser(
      oldUserId: _currentUserId,
      newUserId: userId,
    );
    _currentUserId = userId;

    // Your authentication logic here
    // ...
  }

  Future<void> switchAccount(String newUserId) async {
    await Datum.manager<Task>().switchUser(
      oldUserId: _currentUserId,
      newUserId: newUserId,
      strategy: UserSwitchStrategy.syncThenSwitch,
    );
    _currentUserId = newUserId;
  }
}
```

### Reactive UI Updates

```dart
import 'package:flutter/material.dart';

class TaskListWidget extends StatefulWidget {
  @override
  _TaskListWidgetState createState() => _TaskListWidgetState();
}

class _TaskListWidgetState extends State<TaskListWidget> {
  late StreamSubscription<String?> _userSubscription;
  List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();

    // Listen to user changes and refresh data
    _userSubscription = Datum.manager<Task>().onUserChanged.listen((userId) {
      _loadTasks();
    });

    _loadTasks(); // Initial load
  }

  Future<void> _loadTasks() async {
    final tasks = await Datum.manager<Task>().readAll();
    setState(() => _tasks = tasks);
  }

  @override
  void dispose() {
    _userSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(_tasks[index].title));
      },
    );
  }
}
```

### Benefits

- **Automatic Data Isolation**: Each user's data is kept separate
- **Reactive Updates**: UI automatically refreshes when users switch
- **Memory Management**: Old user's data is cleaned up automatically
- **Performance**: Only active user's data is loaded in memory
- **Security**: Prevents data leakage between users

## Stream Management

### Refreshing Streams

Datum provides a `refreshStreams()` method to force all reactive streams to re-evaluate their data. This is particularly useful when external state changes require all streams to refresh their data.

```dart
// Refresh all streams across all managers
await Datum.instance.refreshStreams();

// This will:
// - Clear internal caches in all managers
// - Force reactive streams to emit fresh data
// - Ensure streams show the most current data after state changes
```

### Use Cases

- **User Switching**: When switching between users, refresh streams to show the new user's data
- **External Data Changes**: When external systems modify data that Datum isn't aware of
- **Cache Invalidation**: When you need to ensure all streams have the latest data
- **Testing**: In test scenarios where you need to reset stream state

### Manager-Level Refresh

You can also refresh streams for specific entity types:

```dart
// Refresh streams for a specific entity type
final taskManager = Datum.manager<Task>();
await taskManager.refreshStreams();
```

### Automatic Refresh

Streams are automatically refreshed in certain scenarios:
- When users switch (via `onUserChanged` streams)
- After certain sync operations
- When the system detects state inconsistencies

### Performance Considerations

- `refreshStreams()` clears all internal caches, which may impact performance
- Use sparingly and only when necessary
- Consider using targeted cache invalidation for better performance when possible

### Combining onUserChanged and refreshStreams

For optimal user switching behavior, combine `onUserChanged` with `refreshStreams`:

```dart
import 'dart:async';

class UserManager {
  StreamSubscription<String?>? _userSubscription;

  void initialize() {
    // Listen to user changes and refresh streams
    _userSubscription = Datum.manager<Task>().onUserChanged.listen((userId) {
      print('User changed to: $userId');

      // Refresh streams to clear user-specific caches
      Datum.instance.refreshStreams();

      // Additional user switch logic
      _onUserSwitched(userId);
    });
  }

  void _onUserSwitched(String? userId) {
    if (userId == null) {
      // User logged out - clear any user-specific state
    } else {
      // User logged in - load user preferences, update UI, etc.
    }
  }

  void dispose() {
    _userSubscription?.cancel();
  }
}
```

### Advanced User Switching Pattern

```dart
import 'dart:async';

class AdvancedUserSwitcher {
  final StreamController<String?> _userController = StreamController.broadcast();
  String? _currentUserId;

  // Expose user change stream for other components
  Stream<String?> get onUserChanged => _userController.stream;

  Future<void> switchToUser(String newUserId) async {
    // 1. Perform the switch — Datum syncs the outgoing user's data
    //    first when using UserSwitchStrategy.syncThenSwitch.
    final result = await Datum.manager<Task>().switchUser(
      oldUserId: _currentUserId,
      newUserId: newUserId,
      strategy: UserSwitchStrategy.syncThenSwitch,
    );
    print('Switch completed: $result');

    // 2. Track and broadcast the change
    _currentUserId = newUserId;
    _userController.add(newUserId);

    // 3. Refresh all streams to clear caches
    await Datum.instance.refreshStreams();
  }

  Future<void> logout() async {
    // Clear user and refresh streams
    _currentUserId = null;
    _userController.add(null);
    await Datum.instance.refreshStreams();

    // Clear authentication state in your auth system here
  }

  void dispose() {
    _userController.close();
  }
}
```

### Reactive UI with User Switching

```dart
import 'package:flutter/material.dart';

class MultiUserApp extends StatefulWidget {
  @override
  _MultiUserAppState createState() => _MultiUserAppState();
}

class _MultiUserAppState extends State<MultiUserApp> {
  late StreamSubscription<String?> _userSubscription;
  String? _currentUserId;
  List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();

    // Listen to user changes
    _userSubscription = Datum.manager<Task>().onUserChanged.listen((userId) {
      setState(() => _currentUserId = userId);

      if (userId != null) {
        // Load user's tasks when they switch in
        _loadUserTasks(userId);
      } else {
        // Clear tasks when user logs out
        setState(() => _tasks = []);
      }
    });

    // Initial load
    _loadCurrentUser();
  }

  Future<void> _loadUserTasks(String userId) async {
    final tasks = await Datum.manager<Task>().readAll(userId: userId);
    if (mounted) {
      setState(() => _tasks = tasks);
    }
  }

  Future<void> _loadCurrentUser() async {
    // Get current user from your auth system
    final userId = await _getCurrentUserId();
    setState(() => _currentUserId = userId);

    if (userId != null) {
      await _loadUserTasks(userId);
    }
  }

  @override
  void dispose() {
    _userSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentUserId != null
          ? 'Tasks for User $_currentUserId'
          : 'Please log in'),
      ),
      body: _currentUserId == null
        ? Center(child: Text('No user logged in'))
        : TaskList(tasks: _tasks, userId: _currentUserId!),
    );
  }
}
```

### Benefits of Combined Usage

- **Automatic Cache Management**: `refreshStreams()` ensures no stale data from previous user
- **Reactive UI Updates**: `onUserChanged` triggers immediate UI updates
- **Data Isolation**: Each user's data is properly separated and cached
- **Performance**: Targeted cache clearing prevents memory leaks
- **Consistency**: All reactive streams show correct data for current user

## Reactive Operations

Watch for real-time data changes:

```dart
// Watch all entities
final subscription = Datum.instance.watchAll<Task>(userId: 'user123')
  ?.listen((tasks) {
    print('Tasks updated: ${tasks.length} items');
  });

// Watch a single entity
final singleSub = Datum.instance.watchById<Task>('task-id', 'user123')
  ?.listen((task) {
    if (task != null) {
      print('Task updated: ${task.title}');
    } else {
      print('Task was deleted');
    }
  });

// Watch paginated results
final paginatedSub = Datum.instance.watchAllPaginated<Task>(
  PaginationConfig(pageSize: 20),
  userId: 'user123',
)?.listen((result) {
  print('Page ${result.currentPage}: ${result.items.length} items');
});

// Watch query results
final query = DatumQueryBuilder<Task>()
  .where('isCompleted', isEqualTo: false)
  .build();

final querySub = Datum.instance.watchQuery<Task>(query, userId: 'user123')
  ?.listen((tasks) {
    print('Pending tasks: ${tasks.length}');
  });
```

## Relationship Operations

Work with related entities. This assumes relational entities like `Post` and `Comment` with a declared `comments` relation — see the [Relationships Guide](/guides/relationships):

```dart no-verify
// Fetch related entities
final comments = await Datum.instance.fetchRelated<Post, Comment>(
  post,
  'comments',
  source: DataSource.local,
);

// Watch related entities
final relatedSub = Datum.instance.watchRelated<Post, Comment>(post, 'comments')
  ?.listen((comments) {
    print('Post has ${comments.length} comments');
  });
```

## Monitoring & Health

### Health Monitoring

```dart
// Check health of all managers
Datum.instance.allHealths.listen((healthMap) {
  healthMap.forEach((entityType, health) {
    print('$entityType: ${health.status}');
  });
});

// Check health of specific entity type
final health = await Datum.instance.checkHealth<Task>();
print('Task health: ${health.status}');
```

### Metrics

```dart
// Monitor global metrics
Datum.instance.metrics.listen((metrics) {
  print('Total syncs: ${metrics.totalSyncOperations}');
  print('Successful: ${metrics.successfulSyncs}');
  print('Failed: ${metrics.failedSyncs}');
});
```

### User Status

```dart
// Monitor sync status for a user
Datum.instance.statusForUser('user123').listen((status) {
  if (status != null) {
    print('User sync status: ${status.status}');
    print('Pending operations: ${status.pendingOperations}');
  }
});
```

## Utility Methods

### Pending Operations

```dart
// Get pending operation count
final count = await Datum.instance.getPendingCount<Task>('user123');

// Get pending operations
final operations = await Datum.instance.getPendingOperations<Task>('user123');
```

### Storage Information

```dart
// Get storage size
final size = await Datum.instance.getStorageSize<Task>(userId: 'user123');

// Watch storage size changes
Datum.instance.watchStorageSize<Task>(userId: 'user123').listen((size) {
  print('Storage size: $size bytes');
});
```

### Sync Results

```dart
// Get last sync result
final lastResult = await Datum.instance.getLastSyncResult<Task>('user123');

// Get remote sync metadata
final metadata = await Datum.instance.getRemoteSyncMetadata<Task>('user123');
```

## Global Sync Control

Control synchronization across all managers:

```dart
// Pause all sync operations
Datum.instance.pauseSync();

// Resume all sync operations
Datum.instance.resumeSync();

// Unsubscribe from remote changes
await Datum.instance.unsubscribeAllFromRemoteChanges();

// Resubscribe to remote changes
await Datum.instance.resubscribeAllToRemoteChanges();
```

## Best Practices

1. **Initialization**: Always initialize Datum before use
2. **Error Handling**: Check initialization results and handle sync errors
3. **Resource Management**: Cancel subscriptions when no longer needed
4. **Performance**: Use appropriate data sources (local vs remote) for your use case
5. **Monitoring**: Monitor health and metrics in production applications

## Comparison with Manager API

| Operation | Singleton Method | Manager Method |
|-----------|------------------|----------------|
| Create | `Datum.instance.create(entity)` | `manager.push(item: entity, userId: userId)` |
| Read | `Datum.instance.read<T>(id)` | `manager.read(id)` |
| Watch | `Datum.instance.watchAll<T>()` | `manager.watchAll()` |
| Sync | `Datum.instance.synchronize(userId)` | `manager.synchronize(userId)` |

The singleton methods are convenient for simple operations, while manager methods provide more control and advanced features.

## Examples



```dart
// Initialize Datum (see the Initialization section for the full setup)
Future<void> bootstrap(DatumConnectivityChecker connectivity) async {
  await Datum.initialize(
    config: const DatumConfig(),
    connectivityChecker: connectivity,
    registrations: [
      DatumRegistration<Task>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
      ),
    ],
  );
}

// Use the singleton API
final myTask = Task(
  id: '1',
  title: 'My Task',
  userId: 'user123',
  createdAt: DateTime.now(),
  modifiedAt: DateTime.now(),
  version: 1,
);
await Datum.instance.create(myTask);

final tasks = await Datum.instance.readAll<Task>(userId: 'user123');
print('Found ${tasks.length} tasks');
```


### Status Indicators

Current API Status: <Badge variant="success">Stable</Badge>

Available in: <Badge variant="info">v1.0.3+</Badge>

## Component Showcase

Here are some examples of the enhanced documentation components:

<Steps>
1. **Initialize Datum** with your configuration and adapters
2. **Use the singleton API** for convenient operations
3. **Monitor health** and performance metrics
4. **Handle sync conflicts** with built-in resolvers
</Steps>

<Card title="Advanced Features">
The singleton API provides powerful features beyond basic CRUD operations:

- **Real-time watching** with reactive streams
- **Batch operations** for multiple entities
- **Relationship queries** with eager loading
- **Global sync control** across all managers
- **Health monitoring** and metrics collection

These features make it easy to build sophisticated offline-first applications with minimal boilerplate code.
</Card>

<Warning>
**Performance Note**: While the singleton API is convenient, for high-frequency operations in performance-critical code paths, consider using manager instances directly to avoid the additional indirection.
</Warning>
