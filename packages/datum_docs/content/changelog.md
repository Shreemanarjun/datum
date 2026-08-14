---
title: Changelog
description: Version history and release notes for Datum.
---

# Changelog

## 1.1.0

The largest release to date. Full details in the
[package changelog](https://pub.dev/packages/datum/changelog); highlights:

### ⚡ Sync performance & scale
- **Incremental pulls** — `DeltaSyncCapable` (timestamp watermark) and `CursorSyncCapable` (opaque change cursor) let a pull transfer only what changed instead of the full dataset. See [Incremental Sync](/guides/performance/incremental_sync).
- **Metadata hash cache** — idle sync cycles no longer re-read and re-hash the local store. See [Performance Tuning](/guides/performance/tuning).
- **Isolate sync fixed** — `useIsolateSync: true` now genuinely offloads the whole cycle to a background isolate (it previously always failed to spawn).

### 🗂️ Declarative schema migrations
- `SchemaMigration` + `ColumnOperation` (add/rename/remove/transform/row) with fail-fast chain validation, rollback, and run-once stamping — and the same chain runs as **real `ALTER TABLE` DDL** on SQL stores via `SqlMigrationExecutor`. See [Schema Migrations](/guides/migrations).

### ✨ Collaborative editing
- `RgaList`/`RgaText` sequence CRDTs with stable cursor anchors and tombstone compaction, joining `PNCounter` and `ORSet`. See [Collaborative Editing](/guides/collaborative_editing).

### 🧰 New ecosystem packages
- **`datum_sqlite`** — SQL-backed local adapter with native query pushdown, real transactions, and DDL migrations. See [SQLite Adapter](/guides/custom_adapters/sqlite_adapter).
- **`datum_test`** — the conformance kit: certify adapters and whole sync stacks, then go further with chaos profiles, crash-recovery, and convergence fuzzing. See [Testing](/guides/testing).

### 🛡️ Correctness
- Typed errors + `tryX` result APIs, type-safe query fields, adapter capability mixins, engine hardening (real content hashing, enforced timeouts, conflict push-back convergence, batch retry parity), and fuzz-discovered fixes for equal-version conflict detection and deterministic LWW tie-breaking.
- The whole library sits at **100% test line coverage** (1,900+ tests), including wire-level integration suites against a real HTTP server and a real SQLite database.

### Merged from the unpublished 1.0.5
- Granular `@DatumIgnore` flags (`copyWith`, `equality`, `fromMap`/`toMap`).
- `ManyToMany` takes a pivot `Type` instead of an instance *(breaking vs 1.0.4)*.

## 1.0.4

- Generator refinements: `TypeChecker`-based type handling, `DatumConverter` support for custom field serialization, improved handling of `Color`, `Offset`, `Duration`, `DateTime`, `Uri`, and `BigInt`.

## 1.0.3

### 🚀 Relational Data Enhancements
- **Eager Loading**: Support `withRelated` in `read()` and `readAll()` to solve N+1 query problems.
- **Advanced Cascade Controls**: More granular deletion behaviors (e.g., `SetNull`) and visualization of delete plans.
- **Transactional Relationships**: Atomic saves for entities and their pivot/related records.

### ⚡ Performance & Scaling
- **Batch Operations**: Support for batch push/pull in adapters and sync engine.
- **LRU Cache**: Size-limited caching in `DatumManager` to prevent memory bloat.
- **Full Isolate Syncing**: Offloading the entire synchronizer to a background Isolate.

### 🔄 Advanced Sync Logic
- **Conflict Resolution Strategies**: Initial support for CRDT-based merging implemented via `VectorClock` and `DatumEntityInterface.merge()`.
- **Vector Clocks**: Implemented for complex multi-device conflict detection and causality tracking.

### 🛠 Developer Experience (DX)
- **Code Generation**: Automated `toDatumMap`, `fromMap`, `diff`, and `copyWith` using `datum_generator`.

## 1.0.2

### 🐛 Bug Fixes

- **core**: prevent direct usage of DatumEntityInterface
  - add checks to prevent using DatumEntityInterface directly in manager and query methods
  - throw ArgumentError with a descriptive message if DatumEntityInterface is used directly
  - add test cases to ensure ArgumentError is thrown when using DatumEntityInterface directly

- **datum-manager**: add error handling to post-fetch transforms
  - Prevent entire read/watch operations from failing when individual entity transforms throw errors. Log errors and use original entities instead, improving robustness in DatumManager methods like readAll, watchAll, watchById, and watchQuery.

### ✨ Features

- **adapter**: add realtime watch methods for Supabase adapter
  - Implement watchAll and watchById methods to enable real-time data watching via Supabase RealtimeChannel. These methods allow subscribing to changes in the table, fetching initial data, and emitting updates on changes, improving data synchronization for user-specific or all records. Includes proper error handling, logging, and channel management

- **hive_adapter**: add reactive user change support to watchAll method
  - Add optional userChangeStream parameter to HiveLocalAdapter constructor and enhance watchAll method to emit updated data when the active user changes. This enables reactive queries that filter and refresh data based on user ID switches, improving app responsiveness in multi-user environments. Includes error handling and proper stream management.

## 1.0.1

### ✨ Features

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

### 🐛 Bug Fixes

- **datum**: revert default delete behavior to hard delete
  - revert default deleteBehavior to hardDelete in DatumConfig
  - update tests to explicitly use soft delete where needed

## 1.0.0

### 🗑️ Breaking Changes
- **core**: Removed deprecated `pause()` and `resume()` methods from `DatumManager` and `Datum` classes - use `unsubscribeFromRemoteChanges()` and `resubscribeToRemoteChanges()` instead

### ✨ Core Library Features
- **Entity System**: Enhanced entity definitions with interfaces and mixins for more flexible implementations
- **Sync Engine**: Added initial sync on user authentication, metadata comparison for optimized syncing, device tracking, and improved error handling
- **Auto-sync**: Enhanced auto-sync functionality with better scheduling and management
- **Configuration**: Added default sync options and remote metadata access
- **Logging**: Advanced logging features with performance monitoring and sampling
- **Cold Start Manager**: Major architectural improvements to cold start synchronization including per-user state isolation, configurable retry logic with exponential backoff, pluggable persistence interface, enhanced error handling and recovery, and comprehensive testing. Replaced static state with instance-level per-user state management to prevent race conditions and enable proper multi-user support. Added retry policies, error recovery mechanisms, and extensible persistence layer for custom storage solutions.
- **Cascading Delete**: Major enhancements to cascading delete functionality including dry-run mode, progress callbacks, cancellation support, timeout protection, and improved error handling. Added comprehensive dry-run capabilities for safely previewing deletion operations before execution. Enhanced cascading delete integration tests with 48 total test cases covering complex relationship scenarios, mixin usage patterns, restrict violations, and edge cases.

### ♻️ Refactors
- **Entity Handling**: Improved entity mixins and relational detection
- **Sync Performance**: Batch processing, performance monitoring, and enhanced error boundaries
- **Concurrent Operations**: Better handling of concurrent sync operations

### 🐛 Bug Fixes
- **Sync Engine**: Fixed return values and unused variables in tests
- **Cascading Delete**: Removed unused `_CascadeDeleteStep` and `_CascadeDeletePlan` classes and fixed method call in `CascadeDeleteBuilder.execute()`

### 📖 Documentation
- **API Documentation**: Enhanced documentation for Datum singleton API, sync patterns, and troubleshooting guides

_Medium Priority (Next Release):_

1. Parallel execution
2. Progress callbacks
3. Relationship caching
4. Rollback capability

## 0.0.13
- fixed type casting error in `initialize()` method in Datum

## 0.0.12

### ✨ Features

- **core**: Add stacktrace to DatumEither
  - The `Failure` class now includes an optional `StackTrace` property.
  - The `fold` method in `DatumEither` now passes the `StackTrace` to the `onFailure` callback.
  - The `onFailure` method now accepts a `StackTrace` parameter.
  - The `getError` method now returns a tuple containing the error value and the stack trace.

- **core**: Bring back getSuccess method
  - Added the `getSuccess` method back to the `DatumEither` class.
  - This method returns the success value if the `DatumEither` is a `Success`, otherwise it throws a `StateError`.

### ♻️ Refactors

- **core**: Remove isSuccess and isFailure methods
  - Removed the `isSuccess` and `isFailure` methods from the `DatumEither` class.

- **core**: Use switch statement instead of if statement
  - Refactor the `onSuccess`, `onFailure`, `getSuccess`, `getError`, `successOrNull`, and `errorOrNull` methods to use switch statement instead of if statement.

## 0.0.11

### ✨ Features

- **core**: introduce DatumEither for initialization result
  - Use DatumEither to handle potential errors during Datum initialization
  - Return Success or Failure based on the outcome of the initialization process
  - Update related code to handle the new DatumEither return type
  - Add DatumEither model for typing success or failure.

## 0.0.10

### ✨ Features

- **Batch Operations**: Added `createMany` and `updateMany` methods for performing batch create and update operations.
- **Lifecycle Management**: Implemented `DatumProviderWithLifecycle` widget to manage Datum's lifecycle based on app state.
- **Flexible Entity Implementation**: Introduced `DatumEntityMixin` and `RelationalDatumEntityMixin` to allow for more flexible entity implementation without requiring inheritance from a base class.
- **Schema Versioning**: Added `schemaVersion` property to `IsolatedHiveLocalAdapter` for easier schema migration.
- **Type Comparison**: Added a `sameTypes` method for type comparison.
- **Dependencies**: Added `equatable` dependency for easier object comparison.

### 🐛 Bug Fixes

- **Logging**: Removed unnecessary debug logs from `tasksStreamProvider`.
- **Initialization**: Ensured managers are initialized before `saveMany` operations.
- **Memory Leaks**: Improved stream handling in `SupabaseRemoteAdapter` to prevent memory leaks.
- **Error Handling**: Improved type safety and error handling in `fetchRelated` methods.

### ♻️ Refactors

- **Background Sync**: Enhanced `SupabaseRemoteAdapter` with `resubscribeToChanges` and `unsubscribeFromChanges` methods for better background sync and lifecycle management.
- **Entity Handling**: Updated `DatumEntityBase` and related classes for better sync and versioning.
- **Adapters**: Updated `HiveLocalAdapter` and `SupabaseRemoteAdapter` to use `DatumEntityBase` instead of `DatumEntity`.
- **Task Entity**: Refactored the `Task` entity to use `DatumEntityMixin`.
- **Sync Execution**: Updated the default sync execution strategy to `parallel`.
- **Data Serialization**: Enhanced data serialization for local and remote persistence.

### 📖 Documentation

- **Datum Class**: Enhanced `Datum` class documentation for clarity and improved usage examples.
- **Sync Options**: Enhanced `DatumSyncOptions` documentation for better clarity.
- **General**: Improved overall documentation for clarity.

### ✅ Tests

- **Background Sync**: Added tests for background sync functionality.

## 0.0.9

### ✨ Features

### Core

- **Implement Sync Request Strategies**: Introduced a new system to control how concurrent calls to the `synchronize` method are handled, preventing race conditions and improving data consistency.
  - Added `DatumSyncRequestStrategy` as the base for defining execution behavior.
  - Implemented `SequentialRequestStrategy` to queue and process all `synchronize` calls in the order they are received. This is the new default behavior.
  - Implemented `SkipConcurrentStrategy` as an alternative strategy to ignore new `synchronize` calls if a sync is already in progress.
  - Added `syncRequestStrategy` to `DatumConfig` to allow global configuration of this behavior.
  - Added an `isSyncing` getter to `DatumSyncEngine` to check the current sync status.

### 🐛 Bug Fixes

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
