## 0.1.0

- **Fix — rows are keyed by `(userId, id)`**: the box was keyed by entity
  id alone, so one user's create/update silently overwrote another user's
  same-id row, and `delete`/`patch` ignored the owner entirely — cross-user
  data destruction. Rows now use composite, escape-safe box keys; legacy
  boxes are re-keyed automatically on `initialize()` with every row
  preserved. Applies to both `HiveLocalAdapter` and
  `IsolatedHiveLocalAdapter`.
- **Fix — watch streams emit initial snapshots**: `watchAll` emitted
  NOTHING until the next box event, so screens watching an
  already-populated box rendered empty forever. Every listener now gets a
  current snapshot (suppressed with `includeInitialData: false`), a second
  concurrent listener works, and `watchById` is implemented. Certified by
  `runWatchConformanceTests`.
- **Auto-migration support**: both adapters mix in `SchemaFingerprintCapable`, persisting the declaration fingerprint in the metadata box (`__datum_schema_fingerprint__`) so `DatumConfig.autoMigrate` reconciliation is run-once across launches.
- `query()` now actually honors `DatumQuery` (filters, sorting, pagination) via `DatumQueryMatcher` instead of returning all entities.
- Implemented `readAllPaginated()` for paginated local reads.
- Added `watchQuery()` for reactive, query-scoped streams.
- **Fixed**: the schema version is now persisted in the metadata box. Previously it lived only in memory, so schema migrations re-ran on **every app launch** — corrupting data for non-idempotent transforms. Applies to both `HiveLocalAdapter` and `IsolatedHiveLocalAdapter`.
- **Fixed**: `overwriteAllRawData()` stores the raw maps as given instead of round-tripping through the entity, so columns added by a migration are no longer silently dropped.
- **Fixed**: `clearUserData()` passed entity value maps instead of box keys to `deleteAll`, so it threw a `TypeError` whenever the user actually had stored entities (both adapters). It now deletes exactly the user's entities.
- Requires `datum ^1.1.0`.

## 0.0.2
- Update for datum dependency

## 0.0.1
- Initial Release with Datum
