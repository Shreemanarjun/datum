
<p align="center">
  <img src="logo/datum.png" alt="Datum Logo" width="200">
</p>

# 🧠 **Datum** — Offline-First Data Synchronization Framework for Dart & Flutter

<a href="https://pub.dev/packages/datum"><img src="https://img.shields.io/pub/v/datum.svg" alt="Pub"></a> <a href="https://github.com/your-username/datum/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a> <img src="https://img.shields.io/badge/coverage-92%25-brightgreen" alt="Code Coverage"> <img src="https://img.shields.io/badge/tests-400%2B-brightgreen" alt="Tests">

> **Smart ⚡ Reactive 🔄 Universal 🌍**
>
> Datum unifies your **local database** and **remote backend** with intelligent syncing, automatic conflict resolution, and real-time data updates — all through a single, type-safe API.

---

## Core Concepts

Datum is built around a few core concepts:

- **`DatumEntity`**: The base class for your data models. It requires a unique `id`, `userId`, and other metadata for synchronization.
- **`Adapter`**: The bridge between Datum and your data sources. There are two types of adapters:
    - **`LocalAdapter`**: Manages data persistence on the device (e.g., Hive, Isar, SQLite).
    - **`RemoteAdapter`**: Communicates with your backend (e.g., REST API, Supabase, Firestore).
- **`DatumManager`**: The main entry point for interacting with your data. It provides methods for CRUD operations, queries, and synchronization.
- **`DatumRegistration`**: A class that holds the local and remote adapters for a specific `DatumEntity`.
- **Offline-First:** All CRUD operations are performed on the local database first, ensuring a snappy user experience even without a network connection. Datum then automatically syncs the data with the remote backend when the connection is available.

---

## 🚀 Getting Started

### 1. Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  datum: ^0.0.1
```

Then run `flutter pub get`.

### 2. Initialization

Initialize Datum once in your application. A good place for this is in your `main.dart` or a service provider.

```dart
import 'package:datum/datum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ... other imports

Future<void> main() async {
  // ... other initializations
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  final config = DatumConfig(
    enableLogging: true,
    autoStartSync: true,
    initialUserId: Supabase.instance.client.auth.currentUser?.id,
  );

  final datum = await Datum.initialize(
    config: config,
    connectivityChecker: CustomConnectivityChecker(), // Your implementation
    registrations: [
      DatumRegistration<Task>(
        localAdapter: TaskLocalAdapter(),
        remoteAdapter: SupabaseRemoteAdapter<Task>(
          tableName: 'tasks',
          fromMap: Task.fromMap,
        ),
      ),
    ],
  );
  runApp(MyApp(datum: datum));
}
```

### 3. Database Schema

When using Supabase, you need to create two tables: `tasks` for your data and `sync_metadata` for Datum to keep track of the synchronization state.

#### `tasks` Table

This table stores the `Task` entities.

```sql
create table public.tasks (
  id text not null,
  user_id uuid not null,
  title text not null,
  is_completed boolean not null default false,
  created_at timestamp with time zone not null default now(),
  modified_at timestamp with time zone not null default now(),
  version bigint not null default 0,
  is_deleted boolean not null default false,
  description text null,
  constraint tasks_pkey primary key (id)
) TABLESPACE pg_default;
```

**Columns:**

*   `id`: A unique identifier for the task.
*   `user_id`: The ID of the user who owns the task. This is used for RLS (Row Level Security).
*   `title`: The title of the task.
*   `is_completed`: A boolean indicating whether the task is completed.
*   `created_at`: The timestamp when the task was created.
*   `modified_at`: The timestamp when the task was last modified. This is important for conflict resolution.
*   `version`: A number that is incremented on each modification. This is also used for conflict resolution.
*   `is_deleted`: A boolean indicating whether the task is soft-deleted.
*   `description`: An optional description of the task.

#### `sync_metadata` Table

This table is used by Datum to store metadata about the synchronization process for each user.

```sql
create table public.sync_metadata (
  user_id uuid not null,
  last_sync_time timestamp with time zone null,
  data_hash text null,
  item_count integer null,
  version integer not null default 0,
  schema_version integer not null default 0,
  entity_name text null,
  device_id text null,
  custom_metadata jsonb null,
  entity_counts jsonb null,
  constraint sync_metadata_pkey primary key (user_id)
) TABLESPACE pg_default;
```

**Columns:**

*   `user_id`: The ID of the user.
*   `last_sync_time`: The timestamp of the last successful sync.
*   `data_hash`: A hash of the data at the time of the last sync. This is used to quickly check if the data has changed.
*   `item_count`: The number of items synced.
*   `version`: The version of the metadata record.
*   `schema_version`: The schema version of the app.
*   `entity_name`: The name of the entity being synced.
*   `device_id`: A unique identifier for the device.
*   `custom_metadata`: A JSONB column for storing any custom metadata.
*   `entity_counts`: A JSONB column for storing the count of each entity type.

---

## 📖 Full Examples

Here are complete examples of a `DatumEntity` and its adapters from the example app.

### `DatumEntity` Example: `Task`

This is the data model for a task. It extends `DatumEntity` and implements the required fields and methods.

```dart
import 'package:datum/datum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // ... copyWith, fromMap, toDatumMap, etc.
}
```

### `LocalAdapter` Example: `TaskLocalAdapter` (Hive)

This adapter uses `Hive` to store tasks locally on the device.

```dart
import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

class TaskLocalAdapter extends LocalAdapter<Task> {
  late Box<Map> _taskBox;

  @override
  Future<void> initialize() async {
    _taskBox = await Hive.openBox<Map>('tasks');
  }

  @override
  Future<void> create(Task entity) {
    return _taskBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<Task?> read(String id, {String? userId}) async {
    final taskMap = _taskBox.get(id);
    if (taskMap == null) return null;
    final task = Task.fromMap(taskMap as Map<String, dynamic>);
    return (userId == null || task.userId == userId) ? task : null;
  }

  @override
  Future<List<Task>> readAll({String? userId}) async {
    final tasks = _taskBox.values.map((e) => Task.fromMap(e as Map<String, dynamic>)).toList();
    return userId == null ? tasks : tasks.where((task) => task.userId == userId).toList();
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    if (_taskBox.containsKey(id)) {
      await _taskBox.delete(id);
      return true;
    }
    return false;
  }

  @override
  Future<void> update(Task entity) {
    return _taskBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  // ... other methods
}
```

### `RemoteAdapter` Example: `SupabaseRemoteAdapter`

This adapter communicates with a `Supabase` backend.

```dart
import 'package:datum/datum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseRemoteAdapter<T extends DatumEntity> extends RemoteAdapter<T> {
  final String tableName;
  final T Function(Map<String, dynamic>) fromMap;
  final SupabaseClient _client;

  SupabaseRemoteAdapter({required this.tableName, required this.fromMap})
      : _client = Supabase.instance.client;

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    final response = await _client.from(tableName).select().eq('user_id', userId);
    return response.map<T>((json) => fromMap(json)).toList();
  }

  @override
  Future<void> create(T entity) async {
    final data = entity.toDatumMap(target: MapTarget.remote);
    await _client.from(tableName).upsert(data);
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final response =
        await _client.from(tableName).select().eq('id', id).maybeSingle();
    if (response == null) {
      return null;
    }
    return fromMap(response);
  }

  @override
  Future<void> delete(String id, {String? userId}) async {
    await _client.from(tableName).delete().eq('id', id);
  }

  @override
  Future<void> update(T entity) async {
    final data = entity.toDatumMap(target: MapTarget.remote);
    await _client.from(tableName).update(data).eq('id', entity.id);
  }

  // ... other methods
}
```

---

## 📝 CRUD and Queries

Once Datum is initialized, you can use the `DatumManager` to perform CRUD operations and queries.

```dart
// Get the manager for the Task entity
final taskManager = Datum.manager<Task>();

// Create a new task
final newTask = Task.create(title: 'My new task');
await taskManager.create(newTask);

// Read a task
final task = await taskManager.read(newTask.id);

// Read all tasks for the current user
final tasks = await taskManager.readAll();

// Update a task
final updatedTask = task!.copyWith(isCompleted: true);
await taskManager.update(updatedTask);

// Delete a task
await taskManager.delete(task.id);

// Watch for changes to a single task
taskManager.watchById(task.id).listen((task) {
  print('Task updated: ${task?.title}');
});

// Watch for changes to all tasks
taskManager.watchAll().listen((tasks) {
  print('Tasks updated: ${tasks.length}');
});
```

---

## 🤝 Relational Data

Datum supports `HasOne`, `HasMany`, and `ManyToMany` relationships through the `RelationalDatumEntity` class.

### Defining Relationships

To define a relationship, extend `RelationalDatumEntity` and override the `relations` getter.

```dart
class Post extends RelationalDatumEntity {
  // ... fields

  @override
  Map<String, Relation> get relations => {
        'author': BelongsTo('userId'),
        'tags': ManyToMany(PostTag.constInstance, 'postId', 'tagId'),
      };
  // ...
}
```

### Fetching Related Data

Use `fetchRelated` on a `DatumManager` to get related entities.

```dart
// Fetch the author of a post
final author = await Datum.manager<Post>().fetchRelated<User>(post, 'author');
```

---

## 🔬 Advanced Usage

### Custom Conflict Resolution

You can create your own conflict resolution strategy by implementing `DatumConflictResolver`.

```dart
class TakeTheirsResolver<T extends DatumEntity> extends DatumConflictResolver<T> {
  @override
  Future<ConflictResolution<T>> resolve(ConflictContext<T> context) {
    // Always prefer the remote version
    return Future.value(ConflictResolution.takeRemote(context.remote));
  }
}

// Register the resolver during initialization
await Datum.initialize(
  // ...
  registrations: [
    DatumRegistration<Task>(
      // ...
      conflictResolver: TakeTheirsResolver<Task>(),
    ),
  ],
);
```

### Observers and Middlewares

- **`DatumObserver`**: Listen to lifecycle events like data changes and conflicts.
- **`DatumMiddleware`**: Intercept and modify data before it's saved.

```dart
// Observer
class MyDatumObserver extends GlobalDatumObserver {
  @override
  void onEvent(DatumEvent event) {
    // ...
  }
}

// Middleware
class EncryptionMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> process(Task entity, DatumMiddlewareFlow flow) {
    // ...
  }
}

// Register them during initialization
await Datum.initialize(
  // ...
  observers: [MyDatumObserver()],
  registrations: [
    DatumRegistration<Task>(
      // ...
      middlewares: [EncryptionMiddleware()],
    ),
  ],
);
```

### Sync Execution Strategy and Direction

- **`SyncExecutionStrategy`**: Control how sync operations are executed (`parallel` or `sequential`).
- **`SyncDirection`**: Control the direction of the sync (`pushThenPull`, `pullThenPush`, `pushOnly`, `pullOnly`).

```dart
await Datum.initialize(
  config: DatumConfig(
    // ...
    syncExecutionStrategy: ParallelStrategy(batchSize: 5),
    defaultSyncDirection: SyncDirection.pullThenPush,
  ),
  // ...
);
```

---

## ⚙️ Configuration for Other Backends

Datum is designed to be backend-agnostic. To use a different backend (e.g., Firebase, a custom REST API), you need to create a `RemoteAdapter` for it. The `RemoteAdapter` needs to implement methods for CRUD operations and fetching data.

For example, a `RemoteAdapter` for a REST API might look like this:

```dart
class MyRestApiAdapter<T extends DatumEntity> extends RemoteAdapter<T> {
  final String endpoint;
  final T Function(Map<String, dynamic>) fromJson;
  final http.Client client;

  MyRestApiAdapter({
    required this.endpoint,
    required this.fromJson,
    required this.client
  });

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    final response = await client.get(Uri.parse('$endpoint?userId=$userId'));
    final data = json.decode(response.body) as List;
    return data.map((item) => fromJson(item)).toList();
  }

  // ... implement other methods
}
```

You would then register this adapter during Datum's initialization.

---
## 🪪 License

MIT License © 2025

MIT License

Copyright (c) 2025 [**Shreeman Arjun**](https://shreeman.dev)


Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.