---
title: Quick Start
---


## Installation

Add Datum to your Dart or Flutter project:

### Add to pubspec.yaml
```bash
flutter pub add datum
```
### Or for pure Dart projects

```bash
dart pub add datum
```

## Define Your First Entity

Create a simple entity by extending `DatumEntity`:

```dart
import 'package:datum/datum.dart';

class Task extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String title;
  final String? description;
  final bool isCompleted;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final bool isDeleted;
  @override
  final int version;

  const Task({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  Task copyWith({
    String? title,
    String? description,
    bool? isCompleted,
    bool? isDeleted,
  }) {
    return Task(
      id: id,
      userId: userId,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
      // Bump the sync metadata on every copy so changes are detected.
      modifiedAt: DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
      version: version + 1,
    );
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'isDeleted': isDeleted,
      'version': version,
    };
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! Task) return toDatumMap();
    final delta = <String, dynamic>{};
    if (title != oldVersion.title) delta['title'] = title;
    if (description != oldVersion.description) delta['description'] = description;
    if (isCompleted != oldVersion.isCompleted) delta['isCompleted'] = isCompleted;
    if (delta.isEmpty) return null;
    delta['modifiedAt'] = modifiedAt.toIso8601String();
    delta['version'] = version;
    return delta;
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      userId: map['userId'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      isCompleted: map['isCompleted'] as bool? ?? false,
      createdAt: DateTime.parse(map['createdAt'] as String),
      modifiedAt: DateTime.parse(map['modifiedAt'] as String),
      isDeleted: map['isDeleted'] as bool? ?? false,
      version: map['version'] as int? ?? 1,
    );
  }

  @override
  List<Object?> get props => [...super.props, title, description, isCompleted];
}
```

## Create Adapters

Datum talks to your storage through adapters. For local storage you can use a ready-made adapter — `InMemoryLocalAdapter` ships with `datum` itself, and `datum_hive` provides a Hive-backed one:

```dart
// Built into datum — great for getting started and for tests
final localAdapter = InMemoryLocalAdapter<Task>(fromMap: Task.fromMap);
```

```dart no-verify
// Or persist to disk with the datum_hive package
import 'package:datum_hive/datum_hive.dart';

final localAdapter = HiveLocalAdapter<Task>(
  entityBoxName: 'tasks',
  fromMap: Task.fromMap,
);
```

For the remote side, implement `RemoteAdapter` against your backend. Here is the shape of a REST implementation:

```dart
// Remote adapter (REST API example)
import 'package:dio/dio.dart';

class RestTaskAdapter extends RemoteAdapter<Task> {
  final Dio _dio;

  RestTaskAdapter(this._dio);

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<void> create(Task entity) async {
    await _dio.post('/tasks', data: entity.toDatumMap(target: MapTarget.remote));
  }

  @override
  Future<Task?> read(String id, {String? userId}) async {
    final response = await _dio.get('/tasks/$id');
    return response.data == null ? null : Task.fromMap(response.data);
  }

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    final response = await _dio.get('/tasks', queryParameters: {'userId': userId});
    return (response.data as List)
        .map((json) => Task.fromMap(json))
        .toList();
  }

  @override
  Future<void> update(Task entity) async {
    await _dio.put('/tasks/${entity.id}',
        data: entity.toDatumMap(target: MapTarget.remote));
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    await _dio.delete('/tasks/$id');
    return true;
  }

  // ... implement the remaining RemoteAdapter members
  // (query, changeStream, getSyncMetadata, updateSyncMetadata)
}
```

## Initialize Datum

Set up Datum in your app:

```dart
import 'package:datum/datum.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Datum. `initialize` returns a result you can inspect —
  // see the Initialization guide for full error handling.
  final result = await Datum.initialize(
    config: const DatumConfig(),
    connectivityChecker: MyConnectivityChecker(), // Implement DatumConnectivityChecker
    registrations: [
      DatumRegistration<Task>(
        localAdapter: HiveLocalAdapter<Task>(
          entityBoxName: 'tasks',
          fromMap: Task.fromMap,
        ),
        remoteAdapter: RestTaskAdapter(Dio()),
      ),
    ],
  );

  final datum = result.getSuccess(); // Throws if initialization failed

  runApp(MyApp());
}
```

## Use Datum in Your App

Now you can use Datum for data operations:

```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class TaskList extends StatefulWidget {
  @override
  _TaskListState createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  late Stream<List<Task>> _tasksStream;

  @override
  void initState() {
    super.initState();
    // Watch for task changes
    _tasksStream =
        Datum.instance.watchAll<Task>(userId: 'current-user-id') ?? Stream.empty();
  }

  Future<void> _addTask(String title) async {
    final task = Task(
      id: Uuid().v4(),
      userId: 'current-user-id',
      title: title,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      version: 1,
    );

    await Datum.instance.create(task);
    // Changes will automatically sync and update the UI via the stream
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
      stream: _tasksStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();

        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final task = snapshot.data![index];
            return ListTile(
              title: Text(task.title),
              trailing: Checkbox(
                value: task.isCompleted,
                onChanged: (value) async {
                  await Datum.instance.update(task.copyWith(isCompleted: value));
                },
              ),
            );
          },
        );
      },
    );
  }
}
```

## Next Steps

- **[Changelog](changelog)**: See what's new in the latest version
- **[Complete Entity Definition](guides/entity_define)**: Learn about relational entities and advanced patterns
- **[Adapter Implementation](guides/local_adapter_implement)**: Deep dive into adapter patterns
- **[Sync Patterns](guides/sync_patterns)**: Master synchronization strategies
- **[Advanced Features](guides/advanced_sync)**: Production-ready synchronization features

## Common Issues

If you encounter errors while following this guide:

- **"Entity type DatumEntityInterface is not registered"**: Make sure you're using concrete entity types (like `Task`) instead of the base `DatumEntityInterface`
- **Adapter initialization errors**: Ensure your local and remote adapters are properly implemented and registered
- **Generic type errors**: Check that all your generic type parameters match correctly

For detailed solutions to these and other common issues, see the **[Common Errors Guide](../troubleshooting/common_errors)**.

This quick start gets you up and running with basic Datum functionality. As you build more complex features, explore the other guides for advanced patterns and best practices.
