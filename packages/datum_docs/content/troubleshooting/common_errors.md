---




title:  🚨 Common Errors & Solutions
description: Fix frequent errors with generics, entity registration, and database selection.
---




Common errors developers encounter when working with Datum's type system and database adapters.

## Generic Type Errors

### Issue: "Entity type DatumEntityInterface is not registered"

**Symptoms:** Getting this error when calling `Datum.instance.watchAll<DatumEntityInterface>()` or similar methods.

**Cause:** Attempting to use the base `DatumEntityInterface` directly instead of a concrete entity type.

**Solution:** Always use concrete entity classes:

```dart
// ❌ Wrong - Using the base interface as the type argument
final wrong = Datum.instance.watchAll<DatumEntityInterface>(userId: 'user1');

// ✅ Correct - Using a concrete entity type
final stream = Datum.instance.watchAll<Task>(userId: 'user1');
final taskManager = Datum.manager<Task>();
```

A concrete entity extends `DatumEntity` and implements its required members:

```dart
class Task extends DatumEntity {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    this.completed = false,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final bool completed;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      toDatumMap(target: MapTarget.remote);
}
```

**Prevention:** The framework prevents using `DatumEntityInterface` directly to maintain type safety.

### Issue: "Cannot use DatumEntityInterface directly"

**Symptoms:** Compilation or runtime error when trying to access managers with the base interface.

**Cause:** Attempting to call `Datum.manager<DatumEntityInterface>()` or similar generic methods.

**Solution:** Use concrete entity types — one manager exists per registered entity class:

```dart
// ❌ Wrong
final broken = Datum.manager<DatumEntityInterface>();

// ✅ Correct — request the manager for a concrete, registered type
final taskManager = Datum.manager<Task>();
// final userManager = Datum.manager<User>();  // one per entity type
```

### Issue: Type mismatch in conflict resolvers

**Symptoms:** Compilation errors when implementing `DatumConflictResolver<T>`.

**Cause:** Using wrong generic type parameter in conflict resolver.

**Solution:** Ensure the conflict resolver type matches the entity type:

```dart
// ✅ Correct - Resolver type matches entity type
class TaskConflictResolver implements DatumConflictResolver<Task> {
  @override
  String get name => 'TaskConflictResolver';

  @override
  Future<DatumConflictResolution<Task>> resolve({
    Task? local,
    Task? remote,
    required DatumConflictContext context,
  }) async {
    // Resolve conflicts for Task entities
    if (local != null) {
      return DatumConflictResolution.useLocal(local);
    }
    return DatumConflictResolution.useRemote(remote!);
  }
}
```

```dart continue
// Use in configuration
final config = DatumConfig<Task>(
  defaultConflictResolver: TaskConflictResolver(),
);
```

## Entity Registration Issues

### Issue: "Entity type X is not registered"

**Symptoms:** Runtime error when trying to access a manager for an unregistered entity type.

**Cause:** Entity type not included in Datum initialization registrations.

**Solution:** Register all entity types during Datum initialization:

```dart
await Datum.initialize(
  config: const DatumConfig(),
  connectivityChecker: const SnippetConnectivity(), // your DatumConnectivityChecker
  registrations: [
    // ✅ Register every entity type your app syncs —
    // one DatumRegistration per concrete entity class.
    DatumRegistration<Task>(
      // e.g. HiveLocalAdapter<Task>(...) from package:datum_hive,
      // or SqliteLocalAdapter<Task>(...) from package:datum_sqlite
      localAdapter: InMemoryLocalAdapter<Task>(fromMap: Task.fromMap),
      remoteAdapter: remoteAdapter, // your RemoteAdapter<Task>
    ),
    // DatumRegistration<User>(localAdapter: ..., remoteAdapter: ...),
    // DatumRegistration<Project>(localAdapter: ..., remoteAdapter: ...),
  ],
);
```

**Prevention:** Create a central registry of all entity types used in your app.

### Issue: Manager creation fails

**Symptoms:** `Datum.initialize()` reports errors about missing adapters.

**Cause:** Incomplete registration - missing local or remote adapter.

**Solution:** Both adapters are required parameters for each entity type:

```dart
// ✅ Complete registration
final registration = DatumRegistration<Task>(
  localAdapter: localAdapter, // Required
  remoteAdapter: remoteAdapter, // Required
  conflictResolver: LastWriteWinsResolver<Task>(), // Optional
  middlewares: [], // Optional: List<DatumMiddleware<Task>>
  observers: [], // Optional: List<DatumObserver<Task>>
);

// ❌ Incomplete — this does not even compile, because
// `remoteAdapter` is a required parameter:
// DatumRegistration<Task>(localAdapter: localAdapter);
```

## Choosing Local Database Adapters

### When to Use Hive

**Best for:**
- **Simple data structures** - Plain objects without complex relationships
- **High performance** - Fast read/write operations
- **Offline-first apps** - Excellent for cached data
- **Small to medium datasets** - Handles thousands of records efficiently

```dart
import 'package:datum_hive/datum_hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

// Hive stores entities as maps — ideal for simple, flat models.
// (package:datum_hive; a Flutter package built on hive_ce_flutter)
final registration = DatumRegistration<Task>(
  localAdapter: HiveLocalAdapter<Task>(
    entityBoxName: 'tasks',
    fromMap: Task.fromMap,
  ),
  remoteAdapter: remoteAdapter,
);
```

**Pros:**
- ⚡ Very fast (microseconds for operations)
- 📦 Small bundle size
- 🔒 Type-safe with code generation
- 💾 Efficient storage

**Cons:**
- 🔗 Limited relationship support
- 📊 No advanced querying (SQL-like)
- 🔄 Schema changes require migrations

### When to Use SQLite

**Best for:**
- **Complex relationships** - Foreign keys, joins, complex queries
- **Large datasets** - Millions of records
- **Advanced querying** - SQL-like operations, aggregations
- **Data integrity** - ACID compliance, transactions
- **Relational data** - Normalized schemas

```dart
// SQLite shines for relational models — pair it with
// RelationalDatumEntity (BelongsTo / HasMany / ManyToMany relations).
// (package:datum_sqlite over package:sqlite3)
final registration = DatumRegistration<Task>(
  localAdapter: SqliteLocalAdapter<Task>(
    database: db, // a shared sqlite3 Database
    table: 'tasks',
    fromMap: Task.fromMap,
  ),
  remoteAdapter: remoteAdapter,
);
```

**Pros:**
- 🔗 Full relationship support
- 📊 Advanced SQL querying
- 🏗️ ACID transactions
- 📈 Scales to large datasets
- 🔍 Complex filtering and sorting

**Cons:**
- 🐌 Slower than Hive for simple operations
- 📦 Larger bundle size
- ⚙️ More complex setup
- 🔧 Schema management required

### When to Use In-Memory Adapter

**Best for:**
- **Testing** - Fast, isolated test environments
- **Temporary data** - Data that doesn't need persistence
- **Prototyping** - Quick development without database setup
- **Caching layers** - Short-lived cached data

```dart
// In-memory local adapter, plus the test HTTP adapter from
// package:datum_test talking to a LocalSyncServer.
final registration = DatumRegistration<Task>(
  localAdapter: InMemoryLocalAdapter<Task>(fromMap: Task.fromMap),
  remoteAdapter: HttpRemoteAdapter<Task>(
    baseUri: server.baseUri,
    fromMap: Task.fromMap,
  ),
);
```

**Pros:**
- ⚡ Fastest possible operations
- 🔧 No setup required
- 🧪 Perfect for testing
- 💾 No persistence concerns

**Cons:**
- 💨 Data lost on app restart
- 🔍 No persistence
- 🧪 Only for development/testing

## Adapter Selection Guide

| Use Case | Recommended Adapter | Reasoning |
|----------|-------------------|-----------|
| Simple CRUD app | Hive | Fast, simple, good for most apps |
| Task management | Hive | Simple entities, good performance |
| E-commerce catalog | SQLite | Complex queries, large datasets |
| Social media app | SQLite | Relationships, user-generated content |
| IoT sensor data | SQLite | Time-series data, aggregations |
| Chat application | SQLite | Message threads, relationships |
| Testing | In-Memory | Fast, isolated, no setup |
| Prototyping | In-Memory/Hive | Quick development |



### Performance Comparison

| Operation | Hive | SQLite | In-Memory |
|-----------|------|--------|-----------|
| Simple Read | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Simple Write | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Complex Query | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Relationships | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Large Datasets | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Setup Complexity | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| Bundle Size | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

## Best Practices

### 1. Choose the Right Adapter Early

```dart
import 'package:datum_hive/datum_hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

// Flat, self-contained model → Hive
final hiveAdapter = HiveLocalAdapter<Task>(
  entityBoxName: 'tasks',
  fromMap: Task.fromMap,
);
```

```dart
// Relational model, heavy querying → SQLite
final sqliteAdapter = SqliteLocalAdapter<Task>(
  database: db,
  table: 'tasks',
  fromMap: Task.fromMap,
);
```

### 2. Plan for Growth

```dart
import 'package:datum_hive/datum_hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

// Start with Hive for simplicity, keep a migration path to SQLite
const useSqlite = false; // Feature flag for migration

final LocalAdapter<Task> adapter = useSqlite
    ? SqliteLocalAdapter<Task>(
        database: db,
        table: 'tasks',
        fromMap: Task.fromMap,
      )
    : HiveLocalAdapter<Task>(
        entityBoxName: 'tasks',
        fromMap: Task.fromMap,
      );
```

### 3. Test with Multiple Adapters

Run the ready-made conformance suite from `package:datum_test` against every
adapter you ship — the same behavioral contract, per backend:

```dart
void main() {
  runLocalAdapterConformanceTests(
    name: 'in-memory',
    create: () async =>
        InMemoryLocalAdapter<ConformanceEntity>(fromMap: ConformanceEntity.fromMap),
  );

  runLocalAdapterConformanceTests(
    name: 'sqlite',
    create: () async {
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: sqlite3.openInMemory(),
        table: 'conformance_entities',
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );

  // Same pattern for HiveLocalAdapter<ConformanceEntity> in a Flutter app.
}
```

### 4. Handle Adapter-Specific Features

Capability mixins (`TransactionalAdapter`, `RawQueryCapable`,
`PaginatedAdapter`, ...) tell you what an adapter supports:

```dart
if (localAdapter is SqliteLocalAdapter<Task>) {
  // SQL adapters support real transactions...
  await localAdapter.transaction(() async {
    // Complex multi-row operations
  });
}

if (localAdapter is RawQueryCapable) {
  // ...and raw SQL queries (SqliteLocalAdapter mixes this in).
}
```

## Real-World Adapter Examples

For complete, working implementations, check out these examples in the Datum codebase:

### **Hive Local Adapter Example**
📁 `packages/datum_hive/lib/src/hive_local_adapter.dart`

The shipped `HiveLocalAdapter<T>` implementation:
- Handles entity serialization/deserialization
- Implements reactive streams with `watchAll()`, `watchById()`, `watchQuery()`
- Manages pending operations and sync metadata
- Provides transaction support and health checks
- Includes user data isolation and cleanup

**Key Features:**
- Full reactive query support
- User-specific data management
- Schema versioning
- Error handling and recovery

### **Supabase Remote Adapter Example**
📁 `packages/datum/example/lib/data/user/adapters/supabase_adapter.dart`

This file contains a production-ready `SupabaseRemoteAdapter<T>` implementation featuring:
- Real-time subscriptions with automatic retry logic
- Authentication state monitoring
- Complex query filtering and pagination
- Relationship fetching (BelongsTo, HasMany, ManyToMany)
- Reactive streams for related entities
- Error handling and connection recovery

**Key Features:**
- Real-time data synchronization
- Advanced relationship support
- Authentication-aware operations
- Robust error recovery
- Performance optimizations

### **Usage in Your App**

Reference these implementations when building your own adapters:

```dart
import 'package:datum_hive/datum_hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

// Based on the shipped Hive adapter
class MyEntityHiveAdapter extends HiveLocalAdapter<Task> {
  MyEntityHiveAdapter()
      : super(
          entityBoxName: 'my_entities',
          fromMap: Task.fromMap,
        );
}
```

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

// Based on the Supabase adapter example in the example app
class MyEntitySupabaseAdapter extends SupabaseRemoteAdapter<MyEntity> {
  MyEntitySupabaseAdapter()
      : super(
          tableName: 'my_entities',
          fromMap: MyEntity.fromMap,
        );
}
```

## Getting Help

If you're still encountering issues:

1. **Check your entity definitions** - Ensure they properly extend `DatumEntity` or `RelationalDatumEntity`
2. **Verify adapter setup** - Test adapters independently before integration
3. **Review type parameters** - Ensure all generic types match correctly
4. **Check the logs** - Enable debug logging for detailed error information
5. **Test with minimal example** - Isolate the problem to specific components
6. **Study the examples** - Review the complete adapter implementations in the example folder

For more advanced patterns, see the [Advanced Sync Patterns](../guides/advanced_sync) guide.


---

*This guide covers the most common generic type and adapter selection issues. For API-specific questions, check the [API Reference](../modules/api_reference) or [Getting Started](../getting_started) guides.*
