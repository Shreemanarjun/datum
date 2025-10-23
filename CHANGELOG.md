## 0.0.6

### 🚀 Features

- **✨ Sealed Class Migration**: Migrated `DatumEntity` and `RelationalDatumEntity` to a `DatumEntityBase` sealed class for enhanced type safety.
- **🚀 New Facade Methods**: Added a suite of new methods to the global `Datum` facade for easier data interaction:
  - **Reactive Watching**: `watchAll`, `watchById`, `watchQuery`, `watchRelated`.
  - **One-time Fetching**: `query`, `fetchRelated`.
  - **Data & Sync Management**: `getPendingCount`, `getPendingOperations`, `getStorageSize`, `watchStorageSize`, `getLastSyncResult`, `checkHealth`.
  - **Sync Control**: `pauseSync`, `resumeSync`.

### ✅ Tests

- **🧪 Enhanced Core Tests**: Added test cases for uninitialized state errors, `statusForUser`, `allHealths`, and relational method behavior with non-relational entities.

### ♻️ Refactors & 🧹 Chores

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
