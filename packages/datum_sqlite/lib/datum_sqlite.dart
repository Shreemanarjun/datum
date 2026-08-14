/// A SQLite-backed persistence layer for the Datum ecosystem.
///
/// Entities live in real tables with one column per field, unlocking native
/// SQL query pushdown, real transactions, and `ALTER TABLE` schema
/// migrations via `SqlMigrationExecutor`.
library;

export 'src/sqlite_local_adapter.dart';
