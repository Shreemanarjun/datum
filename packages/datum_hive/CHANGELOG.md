## 0.1.0

- `query()` now actually honors `DatumQuery` (filters, sorting, pagination) via `DatumQueryMatcher` instead of returning all entities.
- Implemented `readAllPaginated()` for paginated local reads.
- Added `watchQuery()` for reactive, query-scoped streams.
- Requires `datum ^1.1.0`.

## 0.0.2
- Update for datum dependency

## 0.0.1
- Initial Release with Datum
