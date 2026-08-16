<p align="center">
  <img src="https://zmozkivkhopoeutpnnum.supabase.co/storage/v1/object/public/images/datum_logo.png" alt="Datum Logo" width="200">
</p>

# **Datum Hive**


A Hive-based persistence layer for the Datum ecosystem, enabling efficient local data storage and synchronization for Flutter applications.

## Features

- Seamless integration with Datum for local data persistence.
- Leverages Hive's high performance and ease of use.
- Supports offline-first capabilities for Datum entities.
- Provides robust and reliable data storage.

## Getting started

### Prerequisites

Ensure you have the `datum` package integrated into your Flutter project.

### Installation

Add `datum_hive` to your `pubspec.yaml` file:

```yaml
dependencies:
  datum_hive: ^1.1.0
```

Then, run `flutter pub get`.

## Usage

To integrate `datum_hive` with your Datum setup, you'll typically initialize Datum with `IsolatedHiveLocalAdapter` or `HiveLocalAdapter` for your entities.

First, define your Datum entity and a `fromMap` factory:

```dart
import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart'; // For DatumHiveEntity
import 'package:hive_flutter/hive_flutter.dart'; // For Hive.initFlutter()

// Example Task entity
class Task extends DatumHiveEntity {
  Task(super.id, super.collection, {required this.title, required this.isComplete});

  final String title;
  final bool isComplete;

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      map['id'] as String,
      map['collection'] as String,
      title: map['title'] as String,
      isComplete: map['isComplete'] as bool,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ...super.toMap(), // Include base DatumHiveEntity fields
      'title': title,
      'isComplete': isComplete,
    };
  }
}
```

Then, initialize Hive and Datum based on your needs.

### Using `HiveLocalAdapter`

If you don't need to run Hive in a separate isolate, you can use `HiveLocalAdapter`.

```dart
import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:your_app/models/task.dart'; // Assuming Task is defined here
import 'package:your_app/services/connectivity_checker.dart'; // CustomConnectivityChecker
import 'package:your_app/services/datum_logger.dart'; // CustomDatumLogger
import 'package:your_app/observers/my_datum_observer.dart'; // MyDatumObserver
import 'package:your_app/remote_adapters/supabase_remote_adapter.dart'; // SupabaseRemoteAdapter

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required for Flutter apps
  await Hive.initFlutter(); // Initialize Hive for the main isolate

  // Example Datum configuration
  final config = DatumConfig(
    appName: 'MyAwesomeApp',
    // ... other configurations
  );

  final datum = await Datum.initialize(
    config: config,
    connectivityChecker: CustomConnectivityChecker(),
    logger: CustomDatumLogger(enabled: config.enableLogging),
    observers: [
      MyDatumObserver(),
    ],
    registrations: [
      DatumRegistration<Task>(
        localAdapter: HiveLocalAdapter<Task>(
          entityBoxName: "tasks",
          fromMap: (map) => Task.fromMap(map),
          schemaVersion: 0,
        ),
        remoteAdapter: SupabaseRemoteAdapter(
          tableName: 'tasks',
          fromMap: Task.fromMap,
        ),
      ),
      // Add more DatumRegistrations for other entities
    ],
  );

  // Now you can use Datum to interact with your data
  final task = Task('123', 'tasks', title: 'Buy groceries', isComplete: false);
  await datum.save(task);
  final fetchedTask = await datum.get<Task>('123', 'tasks');
  print(fetchedTask?.title);
}
```

### Using `IsolatedHiveLocalAdapter`

For better performance in Flutter, especially with large datasets, you can use `IsolatedHiveLocalAdapter` to run Hive in a separate isolate.

```dart
import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:your_app/models/task.dart'; // Assuming Task is defined here
import 'package:your_app/services/connectivity_checker.dart'; // CustomConnectivityChecker
import 'package:your_app/services/datum_logger.dart'; // CustomDatumLogger
import 'package:your_app/observers/my_datum_observer.dart'; // MyDatumObserver
import 'package:your_app/remote_adapters/supabase_remote_adapter.dart'; // SupabaseRemoteAdapter

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required for Flutter apps
  await IsolatedHive.initFlutter(); // Initialize Hive for a separate isolate

  // Example Datum configuration
  final config = DatumConfig(
    appName: 'MyAwesomeApp',
    // ... other configurations
  );

  final datum = await Datum.initialize(
    config: config,
    connectivityChecker: CustomConnectivityChecker(),
    logger: CustomDatumLogger(enabled: config.enableLogging),
    observers: [
      MyDatumObserver(),
    ],
    registrations: [
      DatumRegistration<Task>(
        localAdapter: IsolatedHiveLocalAdapter<Task>(
          entityBoxName: "tasks", // Unique name for your Hive box
          fromMap: (map) => Task.fromMap(map),
          schemaVersion: 0, // Increment this when your entity schema changes
        ),
        remoteAdapter: SupabaseRemoteAdapter(
          tableName: 'tasks',
          fromMap: Task.fromMap,
        ),
      ),
      // Add more DatumRegistrations for other entities
    ],
  );

  // Now you can use Datum to interact with your data
  final task = Task('123', 'tasks', title: 'Buy groceries', isComplete: false);
  await datum.save(task);
  final fetchedTask = await datum.get<Task>('123', 'tasks');
  print(fetchedTask?.title);
}
```


## Isolates and `IsolatedHive`

Hive CE supports concurrent access across multiple isolates through the `IsolatedHive` interface.

### The problem

The normal Hive interface is not safe to use across multiple isolates. Concurrent writes are almost guaranteed to corrupt box data.

Hive CE will print a warning in most cases when attempting to use Hive across multiple isolates.

### Examples of multi-isolate usage

You may be using multiple isolates without even realizing it. Here are some common use-cases that result in code running in multiple isolates:

*   A Flutter desktop app with multiple windows
*   Running background tasks with `flutter_workmanager`, `background_fetch`, etc.
*   Push notification processing


## Additional information

For more information on Datum, visit the
[Datum documentation](https://datum.dev).
To contribute or report issues, please visit the [GitHub repository](https://github.com/Shreemanarjun/datum).
For issue tracking, please visit [GitHub issues](https://github.com/Shreemanarjun/datum/issues).
