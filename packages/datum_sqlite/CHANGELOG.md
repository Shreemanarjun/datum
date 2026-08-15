## 0.1.0

- Initial release.
- **Runtime schema support**: optional `schema:` derives the payload columns from a `DatumSchema` (explicit `columns:` still wins), and `strictColumns: true` turns the historical silent drop of undeclared payload keys into an error. Mixes in `SqlSchemaCapable` + `SchemaFingerprintCapable`, so `DatumConfig.autoMigrate` reconciles the table with real DDL and skips unchanged launches via the fingerprint stored in the meta table.
- `SqliteLocalAdapter` — full `LocalAdapter` implementation over `package:sqlite3` with native `DatumQuery` → SQL pushdown, real `BEGIN`/`COMMIT`/`ROLLBACK` transactions, change-notified watch streams, and `RawQueryCapable` support so `SqlMigrationExecutor` runs `SchemaMigration` chains as real `ALTER TABLE`/`UPDATE` statements.
- Certified by the `datum_test` conformance suite.
