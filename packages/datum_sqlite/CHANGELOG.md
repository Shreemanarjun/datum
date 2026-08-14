## 0.1.0

- Initial release.
- `SqliteLocalAdapter` — full `LocalAdapter` implementation over `package:sqlite3` with native `DatumQuery` → SQL pushdown, real `BEGIN`/`COMMIT`/`ROLLBACK` transactions, change-notified watch streams, and `RawQueryCapable` support so `SqlMigrationExecutor` runs `SchemaMigration` chains as real `ALTER TABLE`/`UPDATE` statements.
- Certified by the `datum_test` conformance suite.
