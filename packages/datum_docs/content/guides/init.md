---
title: Datum Initialization
---



Before using Datum, you must initialize it with your configuration, connectivity checker, and entity registrations. This typically happens once at your application's startup.

## 1. Define Your Entities

First, create your data models by extending `DatumEntity` or `RelationalDatumEntity`. See the [Entity Definition Guide](entity_define) for detailed instructions.

## 2. Implement Adapters

Create local and remote adapters for each entity type. See the [Local Adapter Implementation Guide](local_adapter_implement) and [Remote Adapter Implementation Guide](remote_adapter_implement) for details.

## 3. Implement a Connectivity Checker

Datum needs to know the network status to manage synchronization. Implement the `DatumConnectivityChecker` interface to provide this information.

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class MyConnectivityChecker implements DatumConnectivityChecker {
  final Connectivity _connectivity = Connectivity();

  @override
  Future<bool> get isConnected async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  @override
  Stream<bool> get onStatusChange {
    return _connectivity.onConnectivityChanged.map((results) {
      return !results.contains(ConnectivityResult.none);
    });
  }
}
```

## 4. Initialize Datum

Finally, initialize Datum in your application's bootstrap code (e.g., `main.dart`). This involves providing a `DatumConfig`, your `DatumConnectivityChecker`, and registering each `DatumEntity` with its corresponding `LocalAdapter` and `RemoteAdapter`.

```dart
import 'package:datum/datum.dart';
import 'package:flutter/widgets.dart'; // If in a Flutter app

// In your main.dart or application bootstrap:
Future<void> bootstrapApp() async {
  // Ensure Flutter widgets are initialized if you are in a Flutter app.
  WidgetsFlutterBinding.ensureInitialized();

  final result = await Datum.initialize(
    config: const DatumConfig(
      enableLogging: true,
      schemaVersion: 1, // Increment this when your entity schema changes
      autoStartSync: true, // Automatically sync on startup
      autoSyncInterval: Duration(minutes: 15), // Sync every 15 minutes
    ),
    connectivityChecker: MyConnectivityChecker(),
    registrations: [
      // Register each DatumEntity type with its adapters
      DatumRegistration<Task>(
        localAdapter: HiveLocalAdapter<Task>(
          entityBoxName: 'tasks',
          fromMap: Task.fromMap,
        ),
        remoteAdapter: MyTaskRemoteAdapter(), // Your RemoteAdapter<Task>
        // Optional: Provide entity-specific configuration
        config: DatumConfig<Task>(
          defaultConflictResolver: LastWriteWinsResolver<Task>(),
        ),
        // Optional: Add middlewares (List<DatumMiddleware<Task>>) for
        // data transformation, and observers (List<DatumObserver<Task>>)
        // for entity lifecycle events:
        // middlewares: [MyEncryptionMiddleware()],
        // observers: [MyTaskObserver()],
      ),
      // Add registrations for other entities
      DatumRegistration<User>(
        localAdapter: HiveLocalAdapter<User>(
          entityBoxName: 'users',
          fromMap: User.fromMap,
        ),
        remoteAdapter: MyUserRemoteAdapter(),
      ),
    ],
    // Optional: Add global observers for all entities
    // observers: [MyGlobalAnalyticsObserver()],
  );

  // Handle initialization result
  switch (result) {
    case Success(value: final datum):
      // Initialization successful
      print('Datum initialized successfully: $datum');

      // Your application can now use Datum.manager<T>() to access registered entities
      runApp(const MyApp());

    case Failure(value: final error, stackTrace: final stack):
      // Initialization failed
      print('Datum initialization failed: $error\n$stack');
      // Handle error appropriately for your app
  }
}
```

## 5. Using Datum After Initialization

Once initialized, access entity managers through the static `Datum.manager<T>()` method:

```dart
// Get a manager for a specific entity type
final taskManager = Datum.manager<Task>();

// Perform operations
await taskManager.push(item: task, userId: 'user123');
final tasks = await taskManager.readAll(userId: 'user123');

// Global operations across all entities
final syncResult = await Datum.instance.synchronize('user123');
```

## Configuration Options

The `DatumConfig` class provides extensive configuration options:

- **Synchronization**: `autoSyncInterval`, `syncTimeout`, `defaultSyncDirection`
- **User Management**: `defaultUserSwitchStrategy`, `initialUserId`
- **Error Handling**: `errorRecoveryStrategy`, `onMigrationError`
- **Performance**: `remoteEventDebounceTime`, `changeCacheDuration`
- **Schema Management**: `schemaVersion`, `migrations`

See the [Config Module Documentation](../modules/config) for complete details.
