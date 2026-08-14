# Core Module




The Core module is the heart of the Datum ecosystem, encompassing the fundamental functionalities and architectural components. It orchestrates data management, synchronization, event handling, and conflict resolution.

## Sub-modules

<Info>
**Thread Safety**: Datum is designed to be thread-safe. All operations can be called from any isolate, and the framework handles synchronization internally.
</Info>

### Datum Singleton

The `Datum` class provides a global singleton instance that offers convenient access to all Datum functionality. It serves as the central entry point for initialization, global operations, and convenience methods.

**Key Features:**
- Global access to all registered entity managers
- Convenience methods for common operations
- Global synchronization control
- Health monitoring across all entities
- Metrics collection and reporting

**Initialization:**
```dart
class MyConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true; // plug in connectivity_plus here
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

Future<void> main() async {
  // Initialize the singleton (required before use)
  final result = await Datum.initialize(
    config: const DatumConfig(),
    connectivityChecker: MyConnectivityChecker(),
    registrations: [/* entity registrations */],
  );

  if (result.isSuccess()) {
    // Datum is ready to use
  }
}
```

**Global Operations:**
- `Datum.manager<T>()`: Get manager for entity type
- `Datum.managerByType(Type type)`: Get manager by runtime `Type`
- `Datum.instance.synchronize(userId)`: Sync all entities
- `Datum.instance.startAutoSync(userId)`: Start auto-sync across all managers
- `Datum.instance.getRemoteSyncMetadata<T>(userId)`: Get remote sync metadata
- `Datum.instance.allHealths`: Monitor all entity health (`Stream<Map<Type, DatumHealth>>`)
- `Datum.instance.metrics` / `currentMetrics`: Global metrics stream and snapshot
- `Datum.instance.events`: Stream of all sync events across managers

### Manager

The Manager sub-module provides high-level interfaces for interacting with Datum's functionalities, primarily through the `DatumManager<T>` class.

#### DatumManager<T>

The main entry point for Datum operations, providing a comprehensive API for data management and synchronization.

**Initialization:**
- `DatumManager(localAdapter: ..., remoteAdapter: ..., connectivity: ..., ...)`: Constructor with required adapters and optional configuration
- `initialize()`: Must be called before any other operations

**CRUD Operations:**
- `push({required T item, required String userId, DataSource source, bool forceRemoteSync})`: Saves entity locally and queues for sync
- `read(String id, {String? userId, List<String> withRelated})`: Retrieves single entity
- `readAll({String? userId, List<String> withRelated})`: Retrieves all entities
- `delete({required String id, required String userId, DeleteBehavior? behavior})`: Deletes entity and queues for sync
- `exists(String id, {String? userId})` / `count({String? userId})`: Existence and count checks

**Batch & Combined Operations:**
- `saveMany({required List<T> items, required String userId})`: Saves multiple entities
- `pushAndSync({required T item, required String userId})`: Saves and immediately syncs
- `deleteAndSync({required String id, required String userId})`: Deletes and immediately syncs
- `tryPush`, `tryRead`, `tryDelete`, `trySynchronize`, ...: `DatumEither`-returning variants that never throw

**Reactive Streams:**
- `eventStream`: Stream of all sync-related events
- `onDataChange`: Stream of data change events
- `onSyncStarted` / `onSyncProgress` / `onSyncCompleted` / `onSyncError`: Sync lifecycle events
- `onConflict`: Conflict detection events
- `watchAll({String? userId})`: Reactive stream of all entities
- `watchById(String id, String? userId)`: Reactive stream of single entity
- `watchStorageSize({String? userId})`: Reactive storage size monitoring

**Querying:**
- `query(DatumQuery query, {DataSource source, String? userId})`: Executes queries against local or remote
- `watchQuery(DatumQuery query, {String? userId})`: Reactive query results
- `rawQuery(DatumRawQuery query, {DataSource source, String? userId})`: Raw rows via a `RawQueryCapable` adapter

**Synchronization:**
- `synchronize(String userId, {DatumSyncOptions? options, DatumSyncScope? scope})`: Manual synchronization
- `startAutoSync(String userId, {Duration? interval})`: Enables periodic auto-sync
- `stopAutoSync({String? userId})`: Stops auto-sync
- `pauseSync()` / `resumeSync()`: Pause/resume all sync activity

**Cascading Delete:**
- `cascadeDelete({required String id, required String userId})`: Delete entity and related entities based on cascade behaviors
- `getDeletePlan(String id, {String? userId})`: Preview what a cascade delete would touch
- `executeCascadeDeleteWithOptions(...)`: Advanced cascade delete with full control

**User Management:**
- `switchUser({String? oldUserId, required String newUserId, ...})`: Switches active user with configurable strategy

**Monitoring & Health:**
- `health`: Stream of `DatumHealth`
- `checkHealth()`: Performs health check
- `currentStatus`: The live `DatumSyncStatusSnapshot` (pending counts, progress, health)
- `getPendingCount(String userId)`: Gets count of pending operations
- `getLastSyncResult(String userId)`: Gets result of last sync

### Engine

The Engine sub-module manages the core data synchronization and processing logic.

#### DatumSyncEngine<T>

Orchestrates the synchronization process between local and remote adapters.

**Key Methods:**
- `synchronize(String userId, ...)`: Executes sync process
- `checkForUserSwitch(String userId)`: Handles user switching logic

#### DatumConflictDetector<T>

Detects conflicts between local and remote data during synchronization.

#### QueueManager<T>

Manages the queue of pending synchronization operations.

### Events

The Events sub-module handles and dispatches various events within the Datum system.

#### Event Types

**Sync Events:**
- `DatumSyncStartedEvent<T>`: Synchronization started
- `DatumSyncProgressEvent<T>`: Sync progress updates
- `DatumSyncCompletedEvent<T>`: Synchronization completed
- `DatumSyncErrorEvent<T>`: Sync errors

**Data Events:**
- `DataChangeEvent<T>`: Local data changes
- `ConflictDetectedEvent<T>`: Conflicts detected during sync
- `ConflictResolvedEvent<T>`: Conflicts resolved
- `UserSwitchedEvent<T>`: User switching
- `InitialSyncEvent<T>`: Initial sync completion

#### Event Streams

All events are accessible through the manager's event streams for reactive programming.

### Health

The Health sub-module provides mechanisms for monitoring the health and status of Datum.

#### DatumHealth

Represents the operational health of a sync manager.

**Properties:**
- `status`: Overall status (`DatumSyncHealth`: healthy, syncing, pending, degraded, offline, error)
- `localAdapterStatus`: `AdapterHealthStatus` of the local adapter (healthy, unhealthy)
- `remoteAdapterStatus`: `AdapterHealthStatus` of the remote adapter
- `describe()`: Human-readable multi-line summary

#### Health Monitoring

- `checkHealth()`: Performs a health check of both adapters and sync status
- `health`: Reactive stream of health status changes

See the [Health module](/modules/health) for full details.

### Middleware

The Middleware sub-module allows for custom processing and transformation of data operations.

#### DatumMiddleware<T>

Abstract class for implementing middleware that can transform data during save/fetch operations.

**Key Methods:**
- `transformBeforeSave(T item)`: Transform entity before saving
- `transformAfterFetch(T item)`: Transform entity after fetching

**Usage:**
```dart
class EncryptionMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Encrypt sensitive fields
    return item.copyWith(description: encrypt(item.description ?? ''));
  }

  @override
  Future<Task> transformAfterFetch(Task item) async {
    // Decrypt sensitive fields
    return item.copyWith(description: decrypt(item.description ?? ''));
  }
}

String encrypt(String value) => value; // your cipher here
String decrypt(String value) => value; // your cipher here
```

### Migration

The Migration sub-module manages database schema and data migrations.

#### Migration

Abstract class representing one migration step.

**Key Members:**
- `fromVersion` / `toVersion`: The version step this migration performs
- `migrate(Map<String, dynamic> oldData)`: Transforms a single raw entity map

#### SchemaMigration

Declarative migrations built from `ColumnOperation.add/rename/remove/transform/row` — see the [Migration module](/modules/migration).

#### MigrationExecutor

Executes migrations in order inside a transaction, snapshotting the store first so failures restore the original data.

#### ErrorBoundary

Provides error handling and recovery strategies for operations that might fail. `ErrorBoundary` lives in the engine layer and is available via a deep import.

**Strategies:**
- `isolate`: Logs errors but allows operation to continue with fallback values
- `retry`: Automatically retries failed operations up to a maximum number of attempts
- `fallback`: Uses fallback values or operations when errors occur
- `escalate`: Re-throws errors for external handling

**Built-in Boundaries:**
```dart
import 'package:datum/source/core/engine/error_boundary.dart';

// Sync operation isolation
final syncBoundary = ErrorBoundaries.syncIsolation<Task>();

// Adapter operation retries
final retryBoundary = ErrorBoundaries.adapterRetry<List<Task>>(maxRetries: 3);

// Read operations with fallbacks
final readBoundary = ErrorBoundaries.readWithFallback<List<Task>>(fallbackValue: []);

// Observer error isolation
final observerBoundary = ErrorBoundaries.observerIsolation();
```

**Usage:**
```dart continue
final boundary = ErrorBoundaries.readWithFallback<List<Task>>(fallbackValue: []);

final tasks = await boundary.execute(() async {
  // Operation that might fail
  return manager.readAll(userId: userId);
});
```



### DatumEither

A sealed class for handling success and failure results in a type-safe manner. `Datum.initialize` and the manager's `try*` methods return it.

**Key Methods:**
- `fold<T>(onFailure, onSuccess)`: Transforms the Either into a single value (both callbacks are positional)
- `onSuccess(void Function(R r) callback)`: Executes callback if successful
- `onFailure(void Function(L l, StackTrace? s) callback)`: Executes callback if failed
- `getSuccess()`: Returns success value or throws StateError
- `getError()`: Returns record of error value and stack trace
- `successOrNull` / `success`: Returns success value or null
- `errorOrNull` / `failure`: Returns error value or null
- `isSuccess()`: Returns true if this is a Success
- `isFailure()`: Returns true if this is a Failure

**Usage:**
```dart
// Never-throwing read via the manager
final result = await manager.tryRead('task-1', userId: userId);

result.fold(
  (error, stackTrace) {
    print('Read failed: $error');
    // Handle error
  },
  (task) {
    print('Read succeeded: ${task?.title}');
    // Continue with the value
  },
);

// Or using convenience methods
if (result.isSuccess()) {
  final value = result.getSuccess();
  print('Loaded ${value?.id}');
} else {
  final (error, stackTrace) = result.getError();
  print('Failed with $error');
}
```

### Models

The Models sub-module defines the data structures and entities used throughout Datum.

#### DatumEntityInterface

Interface for all entities managed by Datum. Provides flexible entity implementation through either inheritance or mixins.

**Required Properties:**
- `id`: Unique identifier
- `userId`: Owner user ID
- `createdAt`: Creation timestamp
- `modifiedAt`: Last modification timestamp
- `version`: Optimistic concurrency version
- `isDeleted`: Soft delete flag
- `vectorClock`: Optional vector clock for causality tracking

**Key Methods:**
- `toDatumMap({MapTarget target})`: Serializes entity
- `diff(DatumEntityInterface oldVersion)`: Computes changes
- `merge(DatumEntityInterface other)`: Merges with another version (CRDT support)
- `incrementClock(String replicaId)`: Returns a copy with an incremented vector clock

**Implementation Options:**

**Using DatumEntityMixin:**

Use the mixin to compose Datum's capabilities into your own class hierarchy. The mixin provides defaults for `vectorClock`, `merge`, `incrementClock`, `isRelational`, and `props`; you implement the core fields plus `toDatumMap` and `diff`:

```dart
class Task with DatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;
  final String title;
  final String description;

  Task({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    required this.isDeleted,
    required this.title,
    required this.description,
  });

  Task copyWith({
    String? title,
    String? description,
    bool? isDeleted,
  }) {
    return Task(
      id: id,
      userId: userId,
      createdAt: createdAt,
      modifiedAt: DateTime.now(),
      version: version + 1,
      isDeleted: isDeleted ?? this.isDeleted,
      title: title ?? this.title,
      description: description ?? this.description,
    );
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
      'title': title,
      'description': description,
    };
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! Task) return toDatumMap(target: MapTarget.remote);
    final delta = <String, dynamic>{};
    if (title != oldVersion.title) delta['title'] = title;
    if (description != oldVersion.description) delta['description'] = description;
    if (delta.isEmpty) return null;
    delta['modifiedAt'] = modifiedAt.toIso8601String();
    delta['version'] = version;
    return delta;
  }

  @override
  bool? get stringify => true;
}
```

**Extending DatumEntity (Recommended):**

`DatumEntity` bundles the sealed `DatumEntityBase` with `DatumEntityMixin` and Equatable support, so extending it is the most concise option:

```dart
class Task extends DatumEntity {
  final String title;
  final String? description;

  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Task({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
    required this.title,
    this.description,
  });

  Task copyWith({String? title, String? description, bool? isDeleted}) {
    return Task(
      id: id,
      userId: userId,
      createdAt: createdAt,
      modifiedAt: DateTime.now(),
      version: version + 1,
      isDeleted: isDeleted ?? this.isDeleted,
      title: title ?? this.title,
      description: description ?? this.description,
    );
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
      'title': title,
      'description': description,
    };
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! Task) return toDatumMap(target: MapTarget.remote);
    final delta = <String, dynamic>{};
    if (title != oldVersion.title) delta['title'] = title;
    if (description != oldVersion.description) delta['description'] = description;
    return delta.isEmpty ? null : delta;
  }

  @override
  List<Object?> get props => [...super.props, title, description];
}
```

<Info>
`DatumEntityBase` itself is a **sealed** class and cannot be extended directly — extend `DatumEntity` or apply `DatumEntityMixin` instead.
</Info>

#### RelationalDatumEntity

Extends the entity interface with relationship support for connecting entities.

**Additional Features:**
- `relations`: Map of entity relationships (BelongsTo, HasMany, HasOne, ManyToMany)
- Support for eager and lazy loading of related data
- Automatic relationship resolution during queries

**Relationship Types:**
- `BelongsTo<T>`: Current entity holds foreign key pointing to related entity
- `HasMany<T>`: Other entities hold foreign key pointing to this entity (one-to-many)
- `HasOne<T>`: Other entity holds foreign key pointing to this entity (one-to-one)
- `ManyToMany<T>`: Many-to-many relationship using a pivot/junction table

#### DatumSyncOperation<T>

Represents a pending synchronization operation.

**Properties:**
- `id`: Operation ID
- `userId`: Target user
- `type`: Operation type (create, update, delete)
- `entityId`: Target entity ID
- `data`: Entity data (for create/update)
- `delta`: Change delta (for update)
- `timestamp`: Operation timestamp

### Query

The Query sub-module provides tools for querying and filtering data.

#### DatumQuery

Defines query parameters for filtering and sorting data.

**Components:**
- `filters`: List of filter conditions
- `sorting`: List of sort descriptors
- `limit/offset`: Pagination parameters
- `logicalOperator`: AND/OR combination logic
- `withRelated`: Eager loading of relationships

#### DatumQueryBuilder

Fluent API for building complex queries. `where` takes the operator as a named parameter:

**Example:**
```dart
final query = DatumQueryBuilder<Task>()
    .where('isCompleted', isEqualTo: false)
    .where('createdAt', isGreaterThan: DateTime.now().subtract(const Duration(days: 7)))
    .orderBy('createdAt', descending: true)
    .limit(50)
    .withRelated(['author', 'comments'])
    .build();
```

#### Filter Operators

- `equals`, `notEquals`: Equality comparisons
- `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`: Range comparisons
- `contains`, `containsIgnoreCase`, `startsWith`, `endsWith`, `matches`: String matching
- `isIn`, `isNotIn`: Set membership
- `isNull`, `isNotNull`: Null checks
- `arrayContains`, `arrayContainsAny`: Array membership
- `between`, `withinDistance`: Range and geo queries

See the [Query module](/modules/query) for the full reference.

### Resolver

The Resolver sub-module handles conflict resolution strategies during data synchronization.

#### Conflict Resolution Strategies

**LastWriteWinsResolver**: Resolves conflicts by choosing the most recently modified version (the default).

**LocalPriorityResolver**: Always prefers local changes over remote.

**RemotePriorityResolver**: Always prefers remote changes over local.

**MergeResolver**: Attempts to merge conflicting changes intelligently.

**UserPromptResolver**: Presents conflicts to user for manual resolution.

#### Custom Resolvers

Implement `DatumConflictResolver<T>` (providing `name` and `resolve({local, remote, context})`) for custom resolution logic.

### Sync

The Sync sub-module manages the overall data synchronization process.

#### DatumSyncExecutionStrategy

Defines how sync operations are processed.

**SequentialStrategy**: Processes operations one by one (default).

**ParallelStrategy**: Processes multiple operations concurrently (`batchSize`, `failFast`).

#### DatumSyncRequestStrategy

Handles concurrent synchronization requests.

**SequentialRequestStrategy**: Queues requests, processes one at a time (default).

**SkipConcurrentStrategy**: Skips new requests while a sync is already in progress.

#### DatumSyncScope

Defines the scope of a synchronization operation, allowing for partial or filtered syncs.

**Key Properties:**
- `query`: A `DatumQuery` used to filter data fetched from the remote source

**Usage:**
```dart
// Sync only active tasks
final scope = DatumSyncScope(
  query: DatumQueryBuilder<Task>()
      .where('isCompleted', isEqualTo: false)
      .build(),
);

final result = await Datum.manager<Task>().synchronize(
  'user123',
  scope: scope,
);
```

#### DatumSyncOptions<T>

Configuration options for synchronization operations.

**Key Properties:**
- `forceFullSync`: When `true`, forces a complete sync regardless of metadata comparison results
- `resolveConflicts`: Whether conflicts should be resolved during sync (default: `true`)
- `includeDeletes`: Whether delete operations should be included in sync (default: `true`)
- `direction`: Sync direction override (push-then-pull, pull-then-push, push-only, pull-only)
- `timeout`: Maximum time allowed for this sync
- `overrideBatchSize`: Batch-size override for this sync
- `conflictResolver`: Resolver override for this sync only

**Usage:**
```dart
// Force a full sync bypassing metadata comparison
final result = await Datum.manager<Task>().synchronize(
  'user123',
  options: DatumSyncOptions<Task>(
    forceFullSync: true,
    resolveConflicts: true,
  ),
);
```

#### Sync Optimization Features

Datum includes several optimization features to improve sync performance and reduce unnecessary network requests.

##### Metadata Comparison

Datum compares local and remote metadata before performing sync operations to avoid unnecessary data transfer:

```dart
// Automatic metadata comparison (enabled by default)
// Sync is skipped if:
// 1. Local and remote data hashes match
// 2. Entity counts are identical
// 3. No pending local operations exist

final result = await Datum.manager<Task>().synchronize('user123');
if (result.wasSkipped) {
  print('No changes detected: ${result.skipReason}');
}
```

**Metadata Fields Compared:**
- Data hash values
- Entity counts per type
- Pending local operation count

##### Force Full Sync

Override metadata comparison when a complete sync is required:

```dart
final result = await Datum.manager<Task>().synchronize(
  'user123',
  options: DatumSyncOptions<Task>(forceFullSync: true),
);
```

##### Batch Processing

Large datasets are processed in configurable batches to optimize memory usage:

```dart
final config = DatumConfig(
  remoteSyncBatchSize: 100,    // Process remote items in batches
  remoteStreamBatchSize: 50,   // Stream items for memory efficiency
);
```

#### Sync Results and Statistics

**DatumSyncResult<T>**: Contains the sync outcome — `syncedCount`, `failedCount`, `conflictsResolved`, `duration`, `pendingOperations`, byte counters, and `wasSkipped`/`wasCancelled`/`error`.

**DatumSyncStatistics**: Detailed metrics about sync performance and data transfer.
