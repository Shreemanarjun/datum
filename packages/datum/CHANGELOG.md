# 1.1.0

All changes below are additive and backward compatible unless noted.

## ✨ Realtime / collaborative editing

- **crdt**: added `RgaList<T>` — a Replicated Growable Array (convergent
  ordered-sequence CRDT) — and `RgaText`, a collaborative text type built on
  it. Concurrent inserts/deletes on different devices merge deterministically
  (commutative, associative, idempotent), contiguous runs never interleave,
  and element/character ids provide stable anchors for remote cursors.
  Combine with `CRDTResolver`, per-device `deviceId`, and vector clocks for
  editor-grade multi-device sync; see
  `test/integration/collaborative_editor_test.dart` for the end-to-end
  reference pattern (two devices editing offline and converging, including
  the backend).

## 🐛 Bug fixes (sync-engine hardening)

- **metadata**: replaced the hardcoded `'testhash'` placeholder with a real
  order-independent content hash. The sync-skip check had degraded to a bare
  count comparison, so a remote content change that kept the entity count
  identical was never pulled and devices diverged permanently.
- **request strategy**: rewrote `SequentialRequestStrategy` without
  `async_queue`. The old implementation assumed `queue.retry()` throws on
  exhaustion (it doesn't), could hang `synchronize()` futures forever, shared
  one global queue across every default-config manager (const canonicalization)
  and stopped it for everyone on `dispose()`. `retryCount` now actually works
  and defaults to 0 (matching real shipped behavior).
- **cancellation**: pausing mid-sync now returns `wasCancelled: true`, keeps
  the `paused` status, and skips the metadata stamp — a truncated cycle was
  previously reported as a fully successful sync.
- **timeout**: `config.syncTimeout` / `options.timeout` is now enforced (it was
  configured everywhere but never applied); a hung remote surfaces a typed
  `DatumExceptionCode.timeout` and fails the status.
- **conflicts**: `takeLocal`/`merge` resolutions now queue a push of the winner
  so the remote converges (the same conflict previously re-fired forever and
  merged values never reached other devices); `takeRemote` honors a
  resolver-transformed `resolvedData`; `abort`/`askUser` are no longer counted
  and reported as resolved; deletion-conflict resolutions increment
  `conflictsResolved`.
- **batching**: a retryable batch failure re-queues its operations with
  `retryCount + 1` instead of permanently dropping the whole batch (a single
  offline blip during a batched push previously lost every operation in it).
- **isolate sync**: `useIsolateSync` config sanitization actually clears
  unsendable callbacks now (`copyWith(x: null)` keeps the old value) via
  `DatumConfig.sanitizedForIsolate`.
- **testing**: added a real local HTTP sync-server harness
  (`test/harness/local_sync_server.dart` + reference `HttpRemoteAdapter`) with
  fault injection (latency, 5xx/4xx, severed sockets, offline, version
  conflicts, corrupted payloads) and 28 scenarios covering transport edge
  cases, multi-stream consistency, leak/timer hygiene, cache boundedness, and
  soak/lifecycle-churn stability.
- **sync**: the metadata skip pre-check now degrades to a full sync when the
  remote metadata fetch fails transiently (previously an unprotected read
  failed the whole cycle before it started).
- **sync**: a failed **remote** metadata beacon write no longer fails an
  otherwise-successful cycle (it is an optimization rewritten by the next
  successful sync); a failed **local** metadata write still surfaces.
- **relations**: `HasOne.fetch()` now queries the child by its **foreign key**
  (mirroring `HasMany` and the eager-loading stitcher); it previously looked
  the child up by primary id equal to the parent's key, returning null unless
  the ids coincidentally matched.
- **metadata**: a push-only sync no longer stamps the local metadata with its
  own content hash (which fabricated a "local == remote" match and caused the
  next sync to skip unpulled remote changes); the remote still receives the
  change beacon so other devices pull.
- **strategy**: `ParallelStrategy(failFast: true)` now waits for
  already-dispatched sibling operations to settle before rethrowing, so no
  writes continue in the background after a sync reports failure.
- **errors**: the manager's sync error path delegates to
  `SyncErrorHandler.handleManagerSyncErrorSync`, preserving the original stack
  trace (previously dropped by a bare `throw e.originalError`).
- **misc**: global sync result accumulates pull failures/conflicts uniformly
  across directions; `DatumSyncStartedEvent` reports the fresh pending count;
  global observers receive `onSyncEnd` on failed syncs; `ExponentialBackoff`
  clamps instead of overflowing negative; `ParallelStrategy(batchSize <= 0)` no
  longer loops forever; cold-start guard is claimed before its awaited check
  (TOCTOU); `pauseSync`/`resumeSync` hardened; `CascadeDeleteResult`/
  `ColdStartConfig`/`ColdStartStrategy` are now exported (public API types that
  were unnameable).

## 🐛 Bug fixes

- **config**: `DatumConfig.copyWith<T>()` no longer drops the global
  `defaultConflictResolver` (and `defaultSyncOptions`) when deriving a
  per-entity config. A base-typed resolver is now adapted via
  `TypeAdaptedConflictResolver` instead of being silently nulled.
- **read**: `read()` no longer caches negative (absent) results, so data that
  arrives later via sync/realtime is observed instead of returning a stale null.
- **query**: local query caching is now **off by default** (`enableQueryCache`),
  fixing stale/mutated results and broken reactive updates. Opt in if needed.
- **sync**: the pull phase no longer blindly overwrites local data when a
  `vectorClock` is null — it falls back to version, then `modifiedAt`, avoiding
  redundant writes and sync noise.
- **sync**: `pauseSync()`/`resumeSync()` reliably restore auto-sync timers
  (hardened against the `stopAutoSync()` clear side-effect).
- **generator**: fixed `fromMap` timestamp key mismatch (snake_case with a
  camelCase fallback) and removed the redundant duplicate key lookup.
- **generator**: `copyWithAll` and `fromMap` now only pass real constructor
  parameters, so entities with initializer-derived fields (e.g. `: userId = id`)
  generate valid code.

## ✨ Features

- **query**: `DataFetchStrategy` (`localOnly`/`remoteOnly`/`localFirst`/
  `remoteFirst`) via `manager.fetch(...)` and `manager.fetchById(...)`, with an
  optional `persistRemoteResults` cache-fill.
- **relations**: nested eager loading with dot notation, e.g.
  `withRelated: ['posts.author']`.
- **relations**: instance-free relation schema (`DatumRelationSchema` +
  `RelationDescriptor`) so adapters can traverse relations by type alone.
- **relations**: `relatedList<R>('posts')` / `relatedOne<R>('author')` typed
  accessors, and `preserveRelationsFrom(...)` to keep in-memory relation
  references across a `copyWith`.
- **query**: adapter-aware raw queries (`DatumRawQuery` + `RawQueryCapable` +
  `manager.rawQuery(...)`) for projections/aggregations without hydration.
- **manager**: `exists(id)` and `count({query})` convenience methods.
- **errors**: sealed `DatumError` type + `tryRead`/`tryPush`/`tryQuery`/
  `tryDelete`/`trySynchronize` result-returning API (no try/catch needed).
- **query**: type-safe field selectors (`DatumQueryField` +
  `whereField`/`orderByField`).
- **logging**: pluggable `DatumLogSink` (redirect logs without subclassing).
- **adapters**: shipped `InMemoryLocalAdapter`, a reusable `DatumQueryMatcher`,
  and capability markers (`WatchableAdapter`, `TransactionalAdapter`,
  `RawQueryCapable`, …).
- **sync**: opt-in remote-deletion detection (`detectRemoteDeletions`) with a
  `DatumConflictResolution.deleteLocal()` resolution.
- **sync**: `excludedSyncUserIds` to keep local-only/system users out of sync.
- **sync**: `DatumSyncOperation.entityTable` for deterministic multi-entity
  pending stores.
- **generator**: `@DatumSerializable(strictNullChecks: true)` opt-in so missing
  non-nullable primitives surface instead of being silently defaulted;
  `generateMixin` now defaults to `true`.
- **perf**: order-independent `hashEntitiesUnordered` + O(1) incremental
  `DatumRollingHash` (~420× faster set-hash updates than a full rehash).
- **relations**: `withRelated` now eager-loads all four relation kinds
  (`HasOne`/`ManyToMany` added); reactive `watchAll`/`watchQuery` accept
  `withRelated`; hand-written entities can use the `MemoizedRelations` mixin.
- **manager**: `exists`, `count`, `deleteMany`, `trySaveMany` conveniences;
  `query` now defaults to `source: DataSource.local`.
- **streams**: reactive `watch*` methods return **non-null** streams (empty when
  the adapter isn't watchable).
- **errors**: `Datum.initialize` returns `DatumEither<DatumError, Datum>`
  (typed failure); `DatumError implements Exception`; `DatumEither` gains
  `success`/`failure` getters.
- **debug**: `DatumSyncResult.describe()` and `DatumHealth.describe()`
  for readable logging; `DatumConfigPresets.custom(...)` exposes the newer flags;
  typed relation accessors `relatedList<R>()` / `relatedOne<R>()`.
- **manager**: `trySwitchUser` / `tryCascadeDelete` result-returning variants.
- **exports**: `CascadeDeleteResult` / `CascadeResult` / `CascadeDeleteBuilder`
  are now exported (public return types were previously unnameable).
- **docs**: new `doc/API_GUIDE.md` covering querying, relations, results/errors,
  and configuration.

See `doc/ADAPTERS_AND_MIGRATIONS_GUIDE.md` (Drift/Isar/migrations) and
`doc/API_DESIGN_AND_TESTING_PLAN.md` for details.


# 1.0.5

## ✨ Features

- **generator**: scalar @DatumIgnore flags
  - Added support for granular control in `@DatumIgnore` annotation
  - Developers can now specify:
    - `copyWith: true` to exclude fields from `copyWith` / `copyWithAll`
    - `equality: true` to exclude fields from `==` and `hashCode`
    - `fromMap: true` / `toMap: true` to exclude from serialization (default)
  - Perfect for handling runtime-only state (e.g., `ValueNotifier`, `StreamController`) inside entities without breaking immutability or equality checks
  - Fully backward compatible with existing `@DatumIgnore()` usage
## 🗑️ Breaking Changes

- **relations**: `ManyToMany` now requires `Type` for pivot entity
  - Updated `ManyToMany` constructor to accept `Type` for pivot entity instead of an instance.
  - This removes the requirement for a `const` zero-argument constructor on pivot entities.


# 1.0.4

## 🐛 Bug Fixes

- **auto-sync**: fix stopAutoSync() incorrectly clearing _pausedAutoSyncUserIds
  - Fixed an issue where `stopAutoSync()` was incorrectly clearing the `_pausedAutoSyncUserIds` set, which prevented auto-sync restoration after pause/resume cycles
  - This ensures that paused user IDs are properly maintained when stopping auto-sync, allowing correct restoration of auto-sync state when resumed
  - Thanks to [@vipwpcom](https://github.com/vipwpcom) for the bug report and test

## 📚 Documentation

- **dartdoc**: fix unresolved documentation references
  - Fixed `remoteAdapter.getSyncMetadata` → `RemoteAdapter.getSyncMetadata`
  - Fixed `resubscribeToRemoteChanges` → `DatumManager.resubscribeToRemoteChanges`
  - Fixed `unsubscribeFromRemoteChanges` → `DatumManager.unsubscribeFromRemoteChanges`
  - Fixed `AdapterHealthStatus.ok` → `AdapterHealthStatus.healthy` (2 instances)
  - All dartdoc warnings resolved (0 warnings, 0 errors)

## ⚡ Improvements

- **dependencies**: move flutter_test to dev_dependencies
  - Moved `flutter_test` from dependencies to dev_dependencies in pubspec.yaml
  - Improves package compatibility and pub.dev score (now 150/160 points)
  - Package can now be analyzed without requiring Flutter SDK for consumers

# 1.0.3

## 🚀 Relational Data Enhancements
- **Eager Loading**: Support `withRelated` in `read()` and `readAll()` to solve N+1 query problems.
- **Advanced Cascade Controls**: More granular deletion behaviors (e.g., `SetNull`) and visualization of delete plans.
- **Transactional Relationships**: Atomic saves for entities and their pivot/related records.

## ⚡ Performance & Scaling
- **Batch Operations**: Support for batch push/pull in adapters and sync engine (Includes comprehensive test suite with 14 edge case scenarios and 100% pass rate)
- **LRU Cache**: Size-limited caching in `DatumManager` to prevent memory bloat.
- **Full Isolate Syncing**: Offloading the entire synchronizer to a background Isolate.

## 🔄 Advanced Sync Logic
- **Conflict Resolution Strategies**: Initial support for CRDT-based merging implemented via `VectorClock` and `DatumEntityInterface.merge()`.
- **Vector Clocks**: Implemented for complex multi-device conflict detection and causality tracking (moving beyond simple version numbers).

## 🛠 Developer Experience (DX)
- **Code Generation**: Automated `toDatumMap`, `fromMap`, `diff`, and `copyWith` using `datum_generator`.

# 1.0.2

## 🐛 Bug Fixes

- **core**: prevent direct usage of DatumEntityInterface
  - add checks to prevent using DatumEntityInterface directly in manager and query methods
  - throw ArgumentError with a descriptive message if DatumEntityInterface is used directly
  - add test cases to ensure ArgumentError is thrown when using DatumEntityInterface directly

- **datum-manager**: add error handling to post-fetch transforms
  - Prevent entire read/watch operations from failing when individual entity transforms throw errors. Log errors and use original entities instead, improving robustness in DatumManager methods like readAll, watchAll, watchById, and watchQuery.

## ✨ Features

- **core**: add refreshStreams method to Datum singleton
  - Add refreshStreams() method to Datum.instance that clears caches and forces all reactive streams across all managers to re-evaluate their data. This ensures streams show the most current data after external state changes like user switches. Includes proper logging and error handling.

- **datum-manager**: add refreshStreams method to DatumManager
  - Add refreshStreams() method to DatumManager that clears internal caches (query, relationship, entity existence) and forces reactive streams to emit fresh data. Useful for cache invalidation when external systems modify data that Datum isn't aware of. Includes proper logging and cache management.

- **core**: add userChangeStream to Datum singleton
  - Add userChangeStream property to Datum.instance that emits when the active user changes. This enables reactive queries and UI updates when users switch in multi-tenant applications. The stream emits the new user ID or null when logging out.

- **adapter**: add realtime watch methods for Supabase adapter
  - Implement watchAll and watchById methods to enable real-time data watching via Supabase RealtimeChannel. These methods allow subscribing to changes in the table, fetching initial data, and emitting updates on changes, improving data synchronization for user-specific or all records. Includes proper error handling, logging, and channel management

- **hive_adapter**: add reactive user change support to watchAll method
  - Add optional userChangeStream parameter to HiveLocalAdapter constructor and enhance watchAll method to emit updated data when the active user changes. This enables reactive queries that filter and refresh data based on user ID switches, improving app responsiveness in multi-user environments. Includes error handling and proper stream management.

# 1.0.1

## ✨ Features

- **core**: add connectivity monitoring and auto-sync
  - Introduces a new feature that monitors the device's connectivity status and automatically triggers a sync when connectivity is restored.
  - This ensures that any pending operations that were queued while offline are automatically synchronized once the device is back online.
  - Fixes an issue where users had to manually trigger a sync after regaining connectivity.
  - Adds a new deleteBehavior option to the DatumConfig to allow developers to choose between soft and hard deletes. Soft deletes mark items as deleted locally and queue a delete operation, while hard deletes immediately remove the item from local storage.
  - Adds a HiveDatumPersistence class to the example app to demonstrate how to use Hive for data persistence.

- **delete**: add optional behavior parameter to delete methods
  - added DeleteBehavior? behavior parameter to delete and deleteAndSync methods in Datum class, allowing per-operation override of global delete behavior
  - updated method documentation to explain the new parameter
  - improved dispose method to safely handle instance checks and nullify the singleton instance
  - enhanced test setup in background_sync_test.dart with proper mocking of ConnectivityChecker
  - added error handling in integration test for Datum.initialize to catch and report failures

## 🐛 Bug Fixes

- **datum**: revert default delete behavior to hard delete
  - revert default deleteBehavior to hardDelete in DatumConfig
  - update tests to explicitly use soft delete where needed

# 1.0.0

## 🗑️ Breaking Changes
- **core**: Removed deprecated `pause()` and `resume()` methods from `DatumManager` and `Datum` classes - use `unsubscribeFromRemoteChanges()` and `resubscribeToRemoteChanges()` instead

## ✨ Core Library Features
- **Entity System**: Enhanced entity definitions with interfaces and mixins for more flexible implementations
- **Sync Engine**: Added initial sync on user authentication, metadata comparison for optimized syncing, device tracking, and improved error handling
- **Auto-sync**: Enhanced auto-sync functionality with better scheduling and management
- **Configuration**: Added default sync options and remote metadata access
- **Logging**: Advanced logging features with performance monitoring and sampling
- **Cold Start Manager**: Major architectural improvements to cold start synchronization including per-user state isolation, configurable retry logic with exponential backoff, pluggable persistence interface, enhanced error handling and recovery, and comprehensive testing. Replaced static state with instance-level per-user state management to prevent race conditions and enable proper multi-user support. Added retry policies, error recovery mechanisms, and extensible persistence layer for custom storage solutions.
- **Cascading Delete**: Major enhancements to cascading delete functionality including dry-run mode, progress callbacks, cancellation support, timeout protection, and improved error handling. Added comprehensive dry-run capabilities for safely previewing deletion operations before execution. Enhanced cascading delete integration tests with 48 total test cases covering complex relationship scenarios, mixin usage patterns, restrict violations, and edge cases.

## ♻️ Refactors
- **Entity Handling**: Improved entity mixins and relational detection
- **Sync Performance**: Batch processing, performance monitoring, and enhanced error boundaries
- **Concurrent Operations**: Better handling of concurrent sync operations

## 🐛 Bug Fixes
- **Sync Engine**: Fixed return values and unused variables in tests
- **Cascading Delete**: Removed unused `_CascadeDeleteStep` and `_CascadeDeletePlan` classes and fixed method call in `CascadeDeleteBuilder.execute()`

## 📖 Documentation
- **API Documentation**: Enhanced documentation for Datum singleton API, sync patterns, and troubleshooting guides

_Medium Priority (Next Release):_

1. Parallel execution
2. Progress callbacks
3. Relationship caching
4. Rollback capability

# 0.0.13
- fixed type casting error in `initialize()` method in Datum


# 0.0.12

## ✨ Features

- **core**: Add stacktrace to DatumEither
  - The `Failure` class now includes an optional `StackTrace` property.
  - The `fold` method in `DatumEither` now passes the `StackTrace` to the `onFailure` callback.
  - The `onFailure` method now accepts a `StackTrace` parameter.
  - The `getError` method now returns a tuple containing the error value and the stack trace.

- **core**: Bring back getSuccess method
  - Added the `getSuccess` method back to the `DatumEither` class.
  - This method returns the success value if the `DatumEither` is a `Success`, otherwise it throws a `StateError`.

## ♻️ Refactors

- **core**: Remove isSuccess and isFailure methods
  - Removed the `isSuccess` and `isFailure` methods from the `DatumEither` class.

- **core**: Use switch statement instead of if statement
  - Refactor the `onSuccess`, `onFailure`, `getSuccess`, `getError`, `successOrNull`, and `errorOrNull` methods to use switch statement instead of if statement.

# 0.0.11

## ✨ Features

- **core**: introduce DatumEither for initialization result
  - Use DatumEither to handle potential errors during Datum initialization
  - Return Success or Failure based on the outcome of the initialization process
  - Update related code to handle the new DatumEither return type
  - Add DatumEither model for typing success or failure.

# 0.0.10

## ✨ Features

- **Batch Operations**: Added `createMany` and `updateMany` methods for performing batch create and update operations.
- **Lifecycle Management**: Implemented `DatumProviderWithLifecycle` widget to manage Datum's lifecycle based on app state.
- **Flexible Entity Implementation**: Introduced `DatumEntityMixin` and `RelationalDatumEntityMixin` to allow for more flexible entity implementation without requiring inheritance from a base class.
- **Schema Versioning**: Added `schemaVersion` property to `IsolatedHiveLocalAdapter` for easier schema migration.
- **Type Comparison**: Added a `sameTypes` method for type comparison.
- **Dependencies**: Added `equatable` dependency for easier object comparison.

## 🐛 Bug Fixes

- **Logging**: Removed unnecessary debug logs from `tasksStreamProvider`.
- **Initialization**: Ensured managers are initialized before `saveMany` operations.
- **Memory Leaks**: Improved stream handling in `SupabaseRemoteAdapter` to prevent memory leaks.
- **Error Handling**: Improved type safety and error handling in `fetchRelated` methods.

## ♻️ Refactors

- **Background Sync**: Enhanced `SupabaseRemoteAdapter` with `resubscribeToChanges` and `unsubscribeFromChanges` methods for better background sync and lifecycle management.
- **Entity Handling**: Updated `DatumEntityBase` and related classes for better sync and versioning.
- **Adapters**: Updated `HiveLocalAdapter` and `SupabaseRemoteAdapter` to use `DatumEntityBase` instead of `DatumEntity`.
- **Task Entity**: Refactored the `Task` entity to use `DatumEntityMixin`.
- **Sync Execution**: Updated the default sync execution strategy to `parallel`.
- **Data Serialization**: Enhanced data serialization for local and remote persistence.

## 📖 Documentation

- **Datum Class**: Enhanced `Datum` class documentation for clarity and improved usage examples.
- **Sync Options**: Enhanced `DatumSyncOptions` documentation for better clarity.
- **General**: Improved overall documentation for clarity.

## ✅ Tests

- **Background Sync**: Added tests for background sync functionality.

# 0.0.9

## ✨ Features

### Core

- **Implement Sync Request Strategies**: Introduced a new system to control how concurrent calls to the `synchronize` method are handled, preventing race conditions and improving data consistency.
  - Added `DatumSyncRequestStrategy` as the base for defining execution behavior.
  - Implemented `SequentialRequestStrategy` to queue and process all `synchronize` calls in the order they are received. This is the new default behavior.
  - Implemented `SkipConcurrentStrategy` as an alternative strategy to ignore new `synchronize` calls if a sync is already in progress.
  - Added `syncRequestStrategy` to `DatumConfig` to allow global configuration of this behavior.
  - Added an `isSyncing` getter to `DatumSyncEngine` to check the current sync status.

## 🐛 Bug Fixes

### Build

- **Correct Conditional Imports**: Fixed conditional imports to ensure compatibility across both `dart:io` and `dart:html` environments.


## 0.0.8
- fix conditional import for web and io

## 0.0.7

### 🐛 Bug Fixes

- **🐛 Isolate Error Handling & Web Compatibility**:
  - Ensured errors during isolate operations are properly caught and sent back to the main thread.
  - Enhanced web compatibility by using `compute` function for isolate operations.
  - Removed unnecessary newline at end of file for consistency.
  - Removed unused import in `supabase_security_dialog.dart`.

## 0.0.6

### 🚀 Features

- **🚀 Isolate Sync Strategy**: Introduced a new `IsolateStrategy` that runs data synchronization in a background isolate for improved performance and UI responsiveness. This includes platform-specific runners for both mobile/desktop (`dart:io`) and web (`dart:html`) via conditional imports, ensuring broad platform support.
- **✨ Sealed Class Migration**: Migrated `DatumEntity` and `RelationalDatumEntity` to a `DatumEntityBase` sealed class for enhanced type safety and to remove the need for `sampleInstance`.
- **🚀 New Facade Methods**: Added a suite of new methods to the global `Datum` facade for easier data interaction:
  - **Reactive Watching**: `watchAll`, `watchById`, `watchQuery`, `watchRelated`.
  - **One-time Fetching**: `query`, `fetchRelated`.
  - **Data & Sync Management**: `getPendingCount`, `getPendingOperations`, `getStorageSize`, `watchStorageSize`, `getLastSyncResult`, `checkHealth`.
  - **Sync Control**: `pauseSync`, `resumeSync`.

### ✅ Tests

- **🧪 Enhanced Core Tests**: Added test cases for uninitialized state errors, `statusForUser`, `allHealths`, and relational method behavior. Introduced a `CustomManagerConfig` for easier mock manager injection in tests.

### ♻️ Refactors & 🧹 Chores

- **♻️ Isolate Helper Improvements**:
  - Replaced conditional imports with platform-specific implementations.
  - Removed `isolate_helper.dart` and `isolate_helper_unsupported.dart`.
  - Added `_isolate_helper_io.dart` for IO platforms.
  - Updated `_isolate_helper_web.dart` to use synchronous JSON encoding.
  - Updated `datum_sync_engine.dart` to use the new isolate helper.
  - Removed unused imports in `test.dart`, `adapter_test.dart`, `relational_data_test.dart`, `relational_data_integration_test.dart`, `mock_adapters.dart`, and `test_entity.dart`.
  - Updated `isolate_helper_test.dart` to use the new isolate helper.
- **🗑️ Removed `sampleInstance`**: The `sampleInstance` property on `LocalAdapter` is no longer needed due to the sealed class migration and has been removed.
- **🩺 Renamed `AdapterHealthStatus.ok`** to `AdapterHealthStatus.healthy` for better clarity.
- **📦 Refactored internal imports** to use the `datum` package consistently.
- **⚙️ Made `MigrationExecutor` generic** to improve type safety during migrations.
- **🗺️ Added `DataSource` enum** to explicitly specify the source for query operations.

## 0.0.5
- Add docs link



## 0.0.4

### Features

- Added support for funding and contributions.

### Documentation

- Added `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
- Updated `README.md` with funding and contribution sections.
- Updated `README.md` to mention future support for multiple adapters for a single entity.

### Chores

- ✨ chore(analysis): apply linter and formatter rules
- enable recommended linter rules for code quality
- set formatter rules for consistent code style
- ignore non_constant_identifier_names error

## 0.0.3
- 📝 docs(readme): enhance architecture diagrams in README

- update architecture diagrams for better clarity
- improve image display using <p> tag for alignment


## 0.0.2
- Update readme to add images correctly


## 0.0.1
- Initial release 🎉
