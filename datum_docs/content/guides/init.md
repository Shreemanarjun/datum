---
title: Datum Initialization
---

Before using Datum, you must initialize it with your configuration, connectivity checker, and entity registrations. This typically happens once at your application's startup.



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