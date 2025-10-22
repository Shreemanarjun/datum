## 0.0.6

### ✨ Features

- ✨ feat(core): implement reactive and query methods on Datum core
  - add convenience methods to Datum class for accessing reactive and query functionalities
  - introduce `watchAll`, `watchById`, `watchQuery`, `query`, `fetchRelated`, and `watchRelated` methods for streamlined data access
  - implement `getPendingCount`, `getPendingOperations`, `getStorageSize`, `watchStorageSize`, `getLastSyncResult` and `checkHealth` methods for data management
  - add `pauseSync` and `resumeSync` methods to pause/resume synchronization for all managers

### ✅ Tests

- ✅ test(core): enhance datum core tests
  - add test case for uninitialized datum state error
  - add tests for `statusForUser` and `allHealths` methods
  - add `CustomManagerConfig` for testing purposes to inject mock manager into Datum initialization
  - add non relational test entity to test relational methods

### ♻️ Refactors & 🧹 Chores

- rename `AdapterHealthStatus.ok` to `AdapterHealthStatus.healthy` for clarity
- refactor `LocalAdapter` and `RemoteAdapter` to import `datum` package
- refactor `data_change_event` to import `data_source` from the `datum` package
- refactor `health` to import `data_source` from the `datum` package
- refactor `datum manager` to import `datum` package
- refactor `migration executor` to support generic type
- add `DataSource` enum to specify data source for queries

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
