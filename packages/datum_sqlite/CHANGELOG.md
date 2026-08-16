## 1.1.0

- Initial release.
- **Fix — rows are keyed by `(id, userId)`**: the table used
  `id TEXT PRIMARY KEY`, so one user's `INSERT OR REPLACE` silently
  overwrote another user's row with the same entity id, and `delete`
  removed every user's row after verifying only one. Fresh tables get a
  composite `PRIMARY KEY (id, userId)`; legacy tables are rebuilt in a
  transaction on `initialize()` preserving every row and column (including
  columns added by manual migrations), and `delete` scopes by owner.
- **Fix — per-listener watch streams**: `watchAll`/`watchById`/`watchQuery`
  now deliver a current snapshot to every listener (a second concurrent
  listener previously stayed silent until the next write) and honor
  `includeInitialData: false`. Certified by `runWatchConformanceTests`.
- **Fix — user scoping under OR queries**: the `userId` scope filter was
  appended flat to the query's filter list, so with `LogicalOperator.or`
  it became just another OR alternative — returning OTHER USERS' rows
  (cross-tenant leak) plus same-user rows that didn't match the filters.
  The caller's filters are now wrapped in a composite that always ANDs
  with the scope.
- **Fix — query filter values are encoded**: `DateTime` (and `bool`)
  filter values were handed raw to sqlite3's binder, which rejects
  `DateTime` with an `ArgumentError`; they now go through the same codec
  as the write path.
- **Runtime schema support**: optional `schema:` derives the payload columns from a `DatumSchema` (explicit `columns:` still wins), and `strictColumns: true` turns the historical silent drop of undeclared payload keys into an error. Mixes in `SqlSchemaCapable` + `SchemaFingerprintCapable`, so `DatumConfig.autoMigrate` reconciles the table with real DDL and skips unchanged launches via the fingerprint stored in the meta table.
- `SqliteLocalAdapter` — full `LocalAdapter` implementation over `package:sqlite3` with native `DatumQuery` → SQL pushdown, real `BEGIN`/`COMMIT`/`ROLLBACK` transactions, change-notified watch streams, and `RawQueryCapable` support so `SqlMigrationExecutor` runs `SchemaMigration` chains as real `ALTER TABLE`/`UPDATE` statements.
- Certified by the `datum_test` conformance suite.
