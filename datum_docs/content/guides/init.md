---
title: Datum Initialization
---

Before using Datum, you must initialize it with your configuration, connectivity checker, and entity registrations. This typically happens once at your application's startup.


## 2. Implement Local and Remote Adapters

Datum uses adapters to interact with your local storage (e.g., SQLite, Hive) and remote backend (e.g., REST API, GraphQL). You need to implement `LocalAdapter` and `RemoteAdapter` for each `DatumEntity` you define.

These examples are simplified; your actual implementations will contain logic for data persistence and network communication.

```dart
// These bridge Datum to your specific local database and backend API.
// (These are simplified for example purposes)
class MyLocalAdapter<T extends DatumEntity> extends LocalAdapter<T> {
  @override
  Future<void> initialize() async { /* Setup local database */ }
  @override
  Future<void> dispose() async { /* Close local database */ }
  // Implement other LocalAdapter methods like `save`, `findById`, `findAll`, etc.
}

class MyRemoteAdapter<T extends DatumEntity> extends RemoteAdapter<T> {
  @override
  Future<void> initialize() async { /* Setup remote API client */ }
  @override
  Future<void> dispose() async { /* Close remote API client */ }
  // Implement other RemoteAdapter methods like `push`, `pull`, etc.
}
```

## 3. Implement a Connectivity Checker

Datum needs to know the network status to manage synchronization. Implement the `DatumConnectivityChecker` interface to provide this information.

```dart
class MyConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true; // Replace with actual connectivity check
}
```

## 4. Initialize Datum

Finally, initialize Datum in your application's bootstrap code (e.g., `main.dart`). This involves providing a `DatumConfig`, your `DatumConnectivityChecker`, and registering each `DatumEntity` with its corresponding `LocalAdapter` and `RemoteAdapter`.

```dart
import 'package:datum/datum.dart';
import 'package:uuid/uuid.dart'; // For generating unique IDs
import 'package:flutter/widgets.dart'; // If in a Flutter app

// In your main.dart or application bootstrap:
Future<void> bootstrapApp() async {
  // Ensure Flutter widgets are initialized if you are in a Flutter app.
  // WidgetsFlutterBinding.ensureInitialized();

  await Datum.initialize(
    config: const DatumConfig(
      enableLogging: true,
      schemaVersion: 1, // Increment this when your entity schema changes
      // Add other global configurations as needed, e.g., conflict resolution strategy.
    ),
    connectivityChecker: MyConnectivityChecker(),
    registrations: [
      // Register each DatumEntity type with its adapters
      DatumRegistration<Task>(
        localAdapter: MyLocalAdapter<Task>(),
        remoteAdapter: MyRemoteAdapter<Task>(),
        // Optional: You can also provide specific conflictResolver, middlewares, or observers here.
      ),
      // Add registrations for other entities (e.g., User, Project)
      // DatumRegistration<User>(
      //   localAdapter: MyLocalAdapter<User>(),
      //   remoteAdapter: MyRemoteAdapter<User>(),
      // ),
    ],
    // Optional: globalObservers can be provided here to observe all entity changes.
  );

  // Your application can now safely use Datum.instance to access registered entities and perform operations.
  // runApp(const MyApp()); // If in a Flutter app, you can now run your app.
}
```