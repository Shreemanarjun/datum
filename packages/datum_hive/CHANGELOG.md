## 0.1.0

- `query()` now actually honors `DatumQuery` (filters, sorting, pagination) via `DatumQueryMatcher` instead of returning all entities.
- Implemented `readAllPaginated()` for paginated local reads.
- Added `watchQuery()` for reactive, query-scoped streams.
- **Fixed**: the schema version is now persisted in the metadata box. Previously it lived only in memory, so schema migrations re-ran on **every app launch** — corrupting data for non-idempotent transforms. Applies to both `HiveLocalAdapter` and `IsolatedHiveLocalAdapter`.
- **Fixed**: `overwriteAllRawData()` stores the raw maps as given instead of round-tripping through the entity, so columns added by a migration are no longer silently dropped.
- Requires `datum ^1.1.0`.

## 0.0.2
- Update for datum dependency

## 0.0.1
- Initial Release with Datum
