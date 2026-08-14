# datum_sqlite

A SQLite-backed persistence layer for the [Datum](https://pub.dev/packages/datum) offline-first sync ecosystem, built on `package:sqlite3`.

Entities live in a real table with one column per field, which unlocks the SQL-native half of Datum's feature set:

- **Query pushdown** — `DatumQuery` compiles to SQL (`WHERE`/`ORDER BY`/`LIMIT` run inside SQLite), instead of loading everything and filtering in memory.
- **Real transactions** — `transaction()` maps to `BEGIN`/`COMMIT`/`ROLLBACK`; SQLite rolls DDL and DML back together.
- **Native schema migrations** — mixes in `RawQueryCapable`, so `SqlMigrationExecutor` runs your `SchemaMigration` chains as real `ALTER TABLE`/`UPDATE` statements.
- **Reactive watch streams** — `watchAll`/`watchById`/`watchQuery`/`watchCount`/`watchFirst`, change-notified.
- **Certified** — passes the official [`datum_test`](https://pub.dev/packages/datum_test) conformance suite.

## Usage

```dart
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';

final db = sqlite3.open('app.db'); // one db can back many adapters

final adapter = SqliteLocalAdapter<Task>(
  database: db,
  table: 'tasks',
  fromMap: Task.fromMap,
  // Payload columns: toDatumMap key -> SQLite type. The sync core columns
  // (id, userId, modifiedAt, createdAt, version, isDeleted) are automatic.
  columns: {'title': 'TEXT', 'priority': 'INTEGER', 'done': 'BOOLEAN'},
);
await adapter.initialize();
```

Columns declared `BOOLEAN` are stored as `0/1` and decoded back to `bool`.

## Schema migrations

The same declarative `SchemaMigration` list that drives schemaless stores runs here as real DDL:

```dart
await SqlMigrationExecutor<Task>(
  localAdapter: adapter,
  table: 'tasks',
  migrations: [
    SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
      ColumnOperation.add('status', defaultValue: 'active'),
      ColumnOperation.rename('title', to: 'name'),
    ]),
  ],
  targetVersion: 1,
  logger: logger,
).execute();
```

Every statement is generated and validated before anything touches the database, and a failure mid-chain rolls back DDL and data atomically.

## Flutter

Add [`sqlite3_flutter_libs`](https://pub.dev/packages/sqlite3_flutter_libs) to bundle the SQLite binary on Android/iOS/macOS/Windows/Linux.
