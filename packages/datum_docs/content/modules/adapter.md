# Adapter Module




The Adapter module provides the abstraction layer that allows Datum to work with any local database and remote backend. This module defines the interfaces, capability mixins, and base implementations for adapters.

## Local Adapters

Local adapters handle data persistence on the device. The Datum ecosystem ships ready-made adapters and a framework for creating custom ones.

### Built-in Local Adapters

#### InMemoryLocalAdapter (datum)

A complete, transactional in-memory adapter bundled with the core package — ideal for tests, prototypes, and ephemeral caches. It mixes in `WatchableAdapter`, `TransactionalAdapter`, and `PaginatedAdapter`.

**Usage:**
```dart
final adapter = InMemoryLocalAdapter<Task>(fromMap: Task.fromMap);
await adapter.initialize();
```

#### HiveLocalAdapter (datum_hive)

A high-performance, lightweight key-value adapter backed by Hive boxes.

**Features:**
- Fast read/write operations
- Box management per entity (`entityBoxName`, plus derived boxes for pending operations and metadata)
- Map-based serialization via your entity's `fromMap`
- `IsolatedHiveLocalAdapter` variant for isolate-safe access

**Usage:**
```dart no-verify
// datum_hive is a Flutter package — add it to your app's pubspec
final taskAdapter = HiveLocalAdapter<Task>(
  entityBoxName: 'tasks',
  fromMap: Task.fromMap,
);
```

#### SqliteLocalAdapter (datum_sqlite)

A SQLite-backed adapter where entities live in real tables with one column per field — unlocking native SQL query pushdown, real transactions, and `ALTER TABLE` schema migrations via `SqlMigrationExecutor`. It mixes in `TransactionalAdapter`, `PaginatedAdapter`, `WatchableAdapter`, and `RawQueryCapable`.

**Usage:**
```dart
final taskAdapter = SqliteLocalAdapter<Task>(
  database: db, // an open sqlite3 Database (can be shared across adapters)
  table: 'tasks',
  fromMap: Task.fromMap,
  columns: {
    'title': 'TEXT',
    'description': 'TEXT',
    'isCompleted': 'BOOLEAN',
    'priority': 'INTEGER',
  },
);
```

### Custom Local Adapters

Extend `LocalAdapter<T>` to create adapters for other databases.

**Core Contract:**
- `initialize()` / `dispose()`: Set up and tear down the storage
- `create(T entity)` / `update(T entity)` / `createAll` / `updateAll`: Writes
- `patch({required String id, required Map<String, dynamic> delta, String? userId})`: Partial update
- `delete(String id, {String? userId})` / `deleteAll` / `clearUserData(String userId)` / `clear()`: Deletion
- `read(String id, {String? userId})` / `readAll({String? userId})` / `readByIds(List<String> ids, {required String userId})`: Reads
- `readAllPaginated(PaginationConfig config, {String? userId})`: Paginated reads
- `query(DatumQuery query, {String? userId})`: Query execution (use `DatumQueryMatcher` or translate to SQL)
- `getAllUserIds()`: All user IDs with local data

**Reactive Contract (return `null` when unsupported):**
- `changeStream()`: Stream of `DatumChangeDetail<T>` for local changes
- `watchAll({String? userId, bool includeInitialData})` / `watchById(String id, {String? userId})` / `watchQuery(DatumQuery query, {String? userId})`
- `watchAllPaginated`, `watchCount`, `watchFirst`
- `getStorageSize({String? userId})` / `watchStorageSize({String? userId})`

**Sync & Migration Contract:**
- `getPendingOperations(String userId)` / `addPendingOperation(String userId, DatumSyncOperation<T> op)` / `removePendingOperation(String operationId)`: Sync queue
- `getSyncMetadata(String userId)` / `updateSyncMetadata(DatumSyncMetadata metadata, String userId)`: Sync state
- `getStoredSchemaVersion()` / `setStoredSchemaVersion(int version)`: Schema versioning
- `getAllRawData({String? userId})` / `overwriteAllRawData(List<Map<String, dynamic>> data)`: Raw access for migrations
- `transaction<R>(Future<R> Function() action)`: Atomic execution (crucial for migrations)
- `saveLastSyncResult(String userId, DatumSyncResult<T> result)` / `getLastSyncResult(String userId)`
- `checkHealth()`: Returns an `AdapterHealthStatus`

## Remote Adapters

Remote adapters handle communication with backend services and APIs. You implement `RemoteAdapter<T>` against your backend — see the dedicated guides for complete Supabase, Firebase, and REST implementations.

### HttpRemoteAdapter (datum_test)

For integration testing, the `datum_test` package provides `HttpRemoteAdapter` (a REST adapter with `DeltaSyncCapable` support) and `LocalSyncServer` (an in-process HTTP sync backend):

```dart
// Start an in-process backend and point a remote adapter at it
final remote = HttpRemoteAdapter<Task>(
  baseUri: server.baseUri,
  fromMap: Task.fromMap,
);
```

### Custom Remote Adapters

Extend `RemoteAdapter<T>` to connect to any backend service.

**Core Contract:**
- `initialize()` / `dispose()`: Set up and tear down the connection
- `create(T entity)` / `update(T entity)` / `createAll` / `updateAll`: Writes
- `patch({required String id, required Map<String, dynamic> delta, String? userId})`: Partial update
- `delete(String id, {String? userId})` / `deleteAll`: Deletion
- `read(String id, {String? userId})` / `readAll({String? userId, DatumSyncScope? scope})`: Reads
- `query(DatumQuery query, {String? userId})`: Remote query execution
- `getSyncMetadata(String userId)` / `updateSyncMetadata(DatumSyncMetadata metadata, String userId)`: Sync state
- `isConnected()`: Whether the remote is currently reachable
- `checkHealth()`: Returns an `AdapterHealthStatus`

**Reactive Contract (return `null` when unsupported):**
- `changeStream`: Stream of remote changes (getter)
- `unsubscribeFromChanges()` / `resubscribeToChanges()`: Pause/resume the change feed
- `watchAll({String? userId, DatumSyncScope? scope})` / `watchById` / `watchQuery`

## Capability Mixins

The base adapter contracts declare optional methods that default to `null` or throw. Capability mixins let an adapter *advertise* what it genuinely supports, so the engine and callers can branch on `adapter is WatchableAdapter` instead of probing at runtime:

- **`WatchableAdapter`**: Reactive queries (`watchAll`/`watchById`/`watchQuery`) return live, non-null streams
- **`TransactionalAdapter`**: `transaction` has real ACID semantics (atomic commit/rollback)
- **`PaginatedAdapter`**: Native pagination (`readAllPaginated`/`watchAllPaginated`)
- **`RelationalAdapter`**: Storage-layer relationship resolution (`fetchRelated`/`watchRelated`)
- **`RawQueryCapable`**: Declares `rawQuery(DatumRawQuery query, {String? userId})` for projections and aggregations without entity hydration
- **`DeltaSyncCapable<T>`**: Declares `readSince(DateTime since, ...)` so the pull phase can fetch only entities modified since the last sync watermark
- **`CursorSyncCapable<T>`**: Declares `readChanges(String? cursor, ...)` for changes-feed backends with opaque cursors (the generalization of delta sync)

### Branching on Capabilities

```dart
if (localAdapter is RawQueryCapable) {
  final rows = await (localAdapter as RawQueryCapable).rawQuery(
    const DatumRawQuery(sql: 'SELECT COUNT(*) AS n FROM tasks'),
  );
  print('Row count: ${rows.first['n']}');
}
```

### Incremental Pulls

Mix `DeltaSyncCapable` into a remote adapter to serve incremental pulls (enabled by `DatumConfig.enableDeltaSync`, its default). Prefer comparing against a *server-maintained* received-at timestamp so late-pushed rows are never missed:

```dart
abstract class MyDeltaRemoteAdapter extends RemoteAdapter<Task>
    with DeltaSyncCapable<Task> {
  @override
  Future<List<Task>> readSince(
    DateTime since, {
    String? userId,
    DatumSyncScope? scope,
  }) async {
    // e.g. GET /tasks?modified_since=<since> — return only changed entities
    return [];
  }
}
```

For changes-feed backends (Firestore snapshot tokens, CouchDB sequences, change counters), implement `CursorSyncCapable.readChanges` instead — it returns a `CursorPage<T>` record (`items` + `nextCursor`), and the engine persists the cursor between cycles. When an adapter mixes in both, the cursor path wins.

## Adapter Configuration

### DatumConfig

Configuration options that affect adapter behavior:

```dart
final config = DatumConfig<Task>(
  // Schema and migrations
  schemaVersion: 2,
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [ColumnOperation.add('priority', defaultValue: 0)],
    ),
  ],

  // Sync behavior
  autoStartSync: true,
  autoSyncInterval: Duration(minutes: 5),
  defaultSyncDirection: SyncDirection.pushThenPull,

  // Conflict resolution
  defaultConflictResolver: LastWriteWinsResolver<Task>(),

  // Performance tuning
  syncExecutionStrategy: const SequentialStrategy(),
  syncRequestStrategy: const SequentialRequestStrategy(),
  remoteEventDebounceTime: Duration(milliseconds: 100),

  // Error handling
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    shouldRetry: (error) async => error is NetworkException && error.isRetryable,
    maxRetries: 3,
    backoffStrategy: const ExponentialBackoff(),
  ),

  // User switching
  defaultUserSwitchStrategy: UserSwitchStrategy.syncThenSwitch,
);
```

### Adapter Registration

Register adapters during Datum initialization:

```dart
class MyConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
```

```dart continue
await Datum.initialize(
  config: const DatumConfig(),
  connectivityChecker: MyConnectivityChecker(),
  registrations: [
    DatumRegistration<Task>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
      config: DatumConfig<Task>(
        // Entity-specific config
      ),
      conflictResolver: LastWriteWinsResolver<Task>(),
      middlewares: [/* DatumMiddleware<Task> instances */],
      observers: [/* DatumObserver<Task> instances */],
    ),
  ],
);
```

<Warning>
**Adapter Compatibility**: Ensure your local and remote adapters work together. For example, if your remote adapter expects JSON data, your local adapter should also handle JSON serialization consistently.
</Warning>

## Adapter Best Practices

### Local Adapter Guidelines

1. **Performance**: Optimize for fast local operations
2. **Indexing**: Use appropriate indexes for query performance
3. **Memory Management**: Implement efficient caching strategies
4. **Error Handling**: Gracefully handle storage failures
5. **Migration Support**: Implement `getAllRawData`/`overwriteAllRawData` and `transaction` so schema migrations are safe

### Remote Adapter Guidelines

1. **Network Efficiency**: Minimize requests and payload sizes (consider `DeltaSyncCapable`)
2. **Authentication**: Securely handle auth tokens and refresh
3. **Retry Logic**: Let `DatumErrorRecoveryStrategy` drive retries; surface `NetworkException` with `isRetryable`
4. **Change Detection**: Efficiently detect remote changes via `changeStream`
5. **Rate Limiting**: Respect API rate limits and implement throttling

### Testing Adapters

The `datum_test` package ships conformance suites that exercise the full adapter contract — CRUD, user scoping, pending operations, sync metadata, raw data access, and (capability-gated) watch streams, transactions, and pagination:

```dart
void main() {
  runLocalAdapterConformanceTests(
    name: 'InMemoryLocalAdapter',
    create: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
```

Remote adapters have an equivalent `runRemoteAdapterConformanceTests`, and `runSyncStackConformanceTests` exercises a full local + remote + manager stack. Point them at your adapter wired for `ConformanceEntity` and every contract detail is verified for you.
