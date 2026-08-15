---
title: SQLite Local Adapter
description: datum_sqlite — real tables, native SQL query pushdown, transactions, and ALTER TABLE migrations.
---

[`datum_sqlite`](https://pub.dev/packages/datum_sqlite) is the official
SQL-backed local adapter, built on `package:sqlite3`. Entities live in a real
table with one column per field, which unlocks the SQL-native half of the
Datum feature set:

- **Query pushdown** — `DatumQuery` compiles to SQL; filtering, sorting, and
  limiting run inside SQLite instead of loading everything into memory.
- **Real transactions** — `transaction()` maps to `BEGIN`/`COMMIT`/`ROLLBACK`;
  SQLite rolls DDL and DML back together.
- **Native schema migrations** — mixes in `RawQueryCapable`, so
  [`SqlMigrationExecutor`](/guides/migrations) runs your migration chain as
  real `ALTER TABLE`/`UPDATE` statements.
- **Reactive watch streams** — `watchAll`/`watchById`/`watchQuery`/
  `watchCount`/`watchFirst`, change-notified.
- **Certified** — passes the full [`datum_test`](/guides/testing) conformance
  suite, including crash-recovery over a file-backed database.

## Install

```bash
dart pub add datum_sqlite
# Flutter apps also need the bundled SQLite binary:
flutter pub add sqlite3_flutter_libs
```

## Wire it up

```dart
Future<SqliteLocalAdapter<Task>> openTaskStore() async {
  final db = sqlite3.open('app.db'); // one db can back many adapters
  final adapter = SqliteLocalAdapter<Task>(
    database: db,
    table: 'tasks',
    fromMap: Task.fromMap,
    // Payload columns: toDatumMap key -> SQLite type. The sync core columns
    // (id, userId, modifiedAt, createdAt, version, isDeleted) are automatic.
    columns: {'title': 'TEXT', 'description': 'TEXT', 'isCompleted': 'BOOLEAN', 'priority': 'INTEGER'},
  );
  await adapter.initialize();
  return adapter;
}
```

Columns declared `BOOLEAN` are stored as `0/1` and decoded back to `bool`
automatically. The adapter does not own the database exclusively — share one
`Database` across several adapters (one per entity type) and close it
yourself when the app shuts down.

## Schema-derived columns and strict mode

Instead of hand-maintaining `columns:`, pass your
[typed schema](/guides/typed_schema) and the payload columns are derived
from it (explicit `columns:` still wins if both are given). The adapter
also gains the auto-migration capabilities (`SqlSchemaCapable`,
`SchemaFingerprintCapable`), so `DatumConfig.autoMigrate` reconciles the
table with real DDL. `strictColumns: true` turns writing an undeclared
payload key into an error instead of the historical silent drop:

```dart no-verify
final adapter = SqliteLocalAdapter<Task>(
  database: db,
  table: 'tasks',
  fromMap: taskSchema.decode,
  schema: taskSchema,
  strictColumns: true,
);
```

## Use it like any other adapter

```dart
await manager.push(item: task, userId: userId);

// This whole query executes inside SQLite:
final urgent = await manager.query(
  (DatumQueryBuilder<Task>()
        ..where('isCompleted', isEqualTo: false)
        ..where('priority', isGreaterThanOrEqualTo: 3)
        ..orderBy('priority', descending: true)
        ..limit(20))
      .build(),
);
print('${urgent.length} urgent tasks');
```

## Raw queries: projections and aggregations

Because the adapter mixes in `RawQueryCapable`, you can bypass entity
hydration for reporting-style reads:

```dart
final rows = await manager.rawQuery(
  DatumRawQuery(
    sql: 'SELECT priority, COUNT(*) AS n FROM tasks WHERE "userId" = ? GROUP BY priority',
    args: [userId],
  ),
  source: DataSource.local,
);
for (final row in rows) {
  print('priority ${row['priority']}: ${row['n']} tasks');
}
```

## Migrations as real DDL

The same declarative chain you would run on Hive runs here as actual
`ALTER TABLE` statements — see [Schema Migrations](/guides/migrations) for
the full walkthrough:

```dart
final result = await SqlMigrationExecutor<Task>(
  localAdapter: localAdapter,
  table: 'tasks',
  migrations: [
    SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
      ColumnOperation.add('archived', defaultValue: false),
      ColumnOperation.rename('description', to: 'details'),
    ]),
  ],
  targetVersion: 1,
  logger: logger,
).execute();
print(result.success);
```

A failing statement mid-chain rolls back the *entire* chain — schema and
data — because SQLite's transactions cover DDL.

## Crash safety

`datum_sqlite` is certified by the kit's crash-recovery suite against a
file-backed database: queued operations written before a crash survive a
process kill and deliver exactly once after reopening; the schema version,
sync metadata, and last sync result all persist. If your app needs the same
guarantee, keep the database on disk (`sqlite3.open(path)`) — an in-memory
database (`sqlite3.openInMemory()`) naturally loses state with the process.

## When to choose it over Hive

| | `datum_sqlite` | `datum_hive` |
|---|---|---|
| Query execution | Inside SQLite (pushdown) | In memory (`DatumQueryMatcher`) |
| Transactions | Real, covers DDL | Best-effort snapshot |
| Migrations | `ALTER TABLE` via `SqlMigrationExecutor` | Raw-map rewrite via `MigrationExecutor` |
| Unknown columns in raw data | Dropped (fixed schema) | Preserved (schemaless) |
| Setup | Declare column types | Just a box name |

Rule of thumb: reach for SQLite when datasets are large or query-heavy;
Hive stays the simplest path for modest, document-shaped data.
