---
title: Schema Migrations
description: Evolve your entity schema safely — one declarative migration chain that runs on schemaless stores and as real SQL DDL.
---

Your app ships v2 with a renamed field and a new column. Devices still hold
v1 data on disk. Datum migrations upgrade that persisted data **in place, on
startup, exactly once** — with validation before anything is touched and
rollback if anything fails.

## The mental model

- Each local store persists a **schema version** (starts at 0).
- `DatumConfig.schemaVersion` declares the version your code expects.
- When the stored version is behind, the engine runs your **migration
  chain** step by step (0→1, 1→2, …) and stamps the new version — so a
  relaunch never re-runs completed steps.

## 1. Your first migration

Declare steps as `SchemaMigration`s built from `ColumnOperation`s — no
hand-written map surgery:

```dart
final config = DatumConfig<Task>(
  schemaVersion: 1,
  migrations: [
    SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
      ColumnOperation.rename('name', to: 'title'),
      ColumnOperation.add('priority', defaultValue: 0),
    ]),
  ],
);
```

That's the whole feature for most apps: bump `schemaVersion`, append a step,
ship. On next launch, existing rows get `name` moved to `title` and a
`priority` column with a default; fresh installs skip the chain entirely.

## 2. Every operation

```dart
final operations = [
  // Add with a fixed default (existing column left untouched unless overwrite: true).
  ColumnOperation.add('status', defaultValue: 'active'),

  // Add computed from the row.
  ColumnOperation.add('slug', compute: (row) => (row['title'] as String? ?? '').toLowerCase()),

  // Rename (no-op when the source key is absent).
  ColumnOperation.rename('name', to: 'title'),

  // Remove.
  ColumnOperation.remove('legacyScore'),

  // Transform in place, with access to the whole row.
  ColumnOperation.transform('priority', (value, row) => (value as int? ?? 0).clamp(0, 5)),

  // Arbitrary whole-row rewrite — spread the input to keep other columns.
  ColumnOperation.row((row) => {...row, 'email': (row['email'] as String? ?? '').toLowerCase()}),
];
```

Rows can be scoped so a step only touches what it should:

```dart
final scoped = SchemaMigration(
  fromVersion: 1,
  toVersion: 2,
  // Only rows matching the predicate are migrated; others pass through.
  where: (row) => (row['priority'] as int? ?? 0) >= 3,
  operations: [
    ColumnOperation.add('escalated', defaultValue: true),
  ],
);
```

## 3. The safety rails you get for free

- **Fail-fast validation.** Before any data is read, `MigrationPlan.resolve`
  checks the whole chain: gaps ("nothing starts at v2"), duplicate starting
  versions, backwards steps, and steps that overshoot the target all fail
  with every problem listed — and the store untouched.
- **Snapshot & rollback.** The map-based executor snapshots raw data and the
  stored version; a failure mid-chain restores both.
- **Run-once.** The stored version is stamped per completed step. A crash
  between steps resumes from the last completed one; a relaunch after
  success is a no-op.
- **No input mutation.** `SchemaMigration.migrate` copies each row before
  applying operations, so the rollback snapshot stays intact even for
  adapters that hand out live map references.

## 4. SQL stores: the same chain as real DDL

A raw-map rewrite cannot add a column to a SQLite table. For SQL adapters
(anything mixing in `RawQueryCapable`, like
[`datum_sqlite`](/guides/custom_adapters/sqlite_adapter)), run the **same
migration list** through `SqlMigrationExecutor` — it translates operations
into `ALTER TABLE` / `UPDATE` statements and runs them inside the adapter's
transaction:

```dart
final chain = [
  SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
    ColumnOperation.add('status', defaultValue: 'active'),
    ColumnOperation.rename('name', to: 'title'),
  ]),
  SchemaMigration(
    fromVersion: 1,
    toVersion: 2,
    // `where` scopes the map path; `sqlWhere` scopes the generated UPDATEs
    // identically on the SQL path.
    where: (row) => (row['priority'] as int? ?? 0) >= 3,
    sqlWhere: 'priority >= 3',
    operations: [
      // Dart closure for schemaless stores + SQL counterpart for SQL stores.
      ColumnOperation.transform('priority', (v, _) => (v as int? ?? 0) + 1, sqlExpression: 'priority + 1'),
    ],
  ),
];

final result = await SqlMigrationExecutor<Task>(
  localAdapter: localAdapter, // must mix in RawQueryCapable
  table: 'tasks',
  migrations: chain,
  targetVersion: 2,
  dialect: SqlDialect.sqlite, // or SqlDialect.postgresql
  logger: logger,
).execute();

if (!result.success) {
  // Nothing was modified: every statement for the whole chain is generated
  // and validated up front, and execution runs in one transaction — SQLite
  // and PostgreSQL roll back DDL and DML together.
  print('Migration failed: ${result.migrationError}');
}
```

Operations that only exist as Dart closures are rejected by the SQL
generator with a message telling you which counterpart to provide:

| Operation | SQL needs | Emits |
|---|---|---|
| `add(defaultValue: …)` | type inferred (or `sqlType:`) | `ALTER TABLE … ADD COLUMN … DEFAULT …` |
| `add(compute: …)` | `sqlExpression:` backfill | `ADD COLUMN` + `UPDATE … SET c = expr` |
| `rename` | — | `ALTER TABLE … RENAME COLUMN` |
| `remove` | — | `ALTER TABLE … DROP COLUMN` |
| `transform` | `sqlExpression:` | `UPDATE … SET c = expr` |
| `row` | `sql: [ … ]` verbatim statements | your statements |

Custom operations can join the SQL path by implementing
`SqlConvertibleOperation`:

```dart
class CreateTitleIndex extends ColumnOperation implements SqlConvertibleOperation {
  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) => row; // map path: no-op

  @override
  List<String> toSqlStatements(String table, SqlDialect dialect) =>
      ['CREATE INDEX idx_${table}_title ON $table (title)'];
}
```

## 5. Handling failure at the app level

```dart
final guarded = DatumConfig<Task>(
  schemaVersion: 2,
  migrations: [],
  onMigrationError: (error, stack) async {
    // Default behavior (no handler): rethrow, so the app never runs on
    // half-migrated data. A handler lets you report + decide instead.
    print('Migration failed: $error');
  },
);
```

## 6. Prove it with the conformance kit

The [`datum_test`](/guides/testing) package ships a migration conformance
suite that runs a standard chain against **your** adapter — stamping,
fail-fast on invalid chains, mid-chain rollback, resume, and relaunch
run-once semantics:

```dart no-verify
runMigrationConformanceTests(
  name: 'MyAdapter',
  createLocal: () async => openMyAdapter(),
  reopenLocal: () async => openMyAdapter(), // same persisted storage
);
```

## Cheat sheet

- Additive nullable field + tolerant `fromMap`? You may not need a migration
  at all — old rows read the default.
- Rename/split/retype with existing on-disk data? Migration.
- Schemaless store (Hive, in-memory) → automatic on init via
  `DatumConfig.migrations`.
- SQL store → `SqlMigrationExecutor` with the same chain.
- Never reuse a `fromVersion` and never leave a gap — validation will fail
  the whole chain loudly before touching data (that's a feature).
