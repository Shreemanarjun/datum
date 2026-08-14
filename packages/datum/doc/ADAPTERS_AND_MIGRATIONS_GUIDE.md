# Adapters & Migrations Guide

Answers to common integration questions: writing a **Drift** adapter (#4),
the **Isar** dependency conflict (#6), and the **purpose of Datum migrations** (#5).

---

## 1. Working with Drift (#4)

Yes — you can build a `DriftLocalAdapter<T extends DatumEntityInterface>` today by
`extends LocalAdapter<T>`. The key idea: **Datum stores the serialized entity
map (`toDatumMap()`), not Drift-native row objects.** A single generic Drift
table (id, user_id, payload) is enough, so you don't need a Drift table per
entity unless you want native columns for querying.

### Recommended flow

1. Define your `DatumEntity` / `RelationalDatumEntity` models (with
   `datum_generator` or hand-written `toDatumMap`/`fromMap`).
2. Create **one generic Drift table** to hold entities as JSON, plus tables for
   pending operations and sync metadata.
3. Implement `DriftLocalAdapter<T>` over those tables.

```dart
// A generic store table (one row per entity, payload = toDatumMap() JSON).
class DatumRows extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get collection => text()();     // e.g. T.toString() — see #16 entityTable
  TextColumn get payload => text()();         // jsonEncode(entity.toDatumMap())
  IntColumn  get modifiedAt => integer()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryColumns => {id, collection};
}

class DriftLocalAdapter<T extends DatumEntityInterface> extends LocalAdapter<T>
    with WatchableAdapter, TransactionalAdapter {
  DriftLocalAdapter({required this.db, required this.collection, required this.fromMap});
  final MyDatabase db;
  final String collection;                    // usually T.toString()
  final T Function(Map<String, dynamic>) fromMap;

  @override
  Future<T?> read(String id, {String? userId}) async {
    final row = await (db.select(db.datumRows)
          ..where((r) => r.id.equals(id) & r.collection.equals(collection)))
        .getSingleOrNull();
    return row == null ? null : fromMap(jsonDecode(row.payload));
  }

  @override
  Future<void> create(T entity) => db.into(db.datumRows).insertOnConflictUpdate(
        DatumRowsCompanion.insert(
          id: entity.id,
          userId: entity.userId,
          collection: collection,
          payload: jsonEncode(entity.toDatumMap()),
          modifiedAt: entity.modifiedAt.millisecondsSinceEpoch,
        ),
      );

  @override
  Future<R> transaction<R>(Future<R> Function() action) => db.transaction(action);

  // Implement the rest of LocalAdapter over DatumRows / pending-ops / metadata
  // tables. For queries, either scan+match with DatumQueryMatcher, or translate
  // the DatumQuery to SQL with `query.toSql(...)` (DatumQuerySqlConverter) if you
  // store native columns.
}
```

Want **native SQL projections/aggregations** (COUNT, GROUP BY) without hydrating
entities? Mix in `RawQueryCapable` and implement `rawQuery` (see #11):

```dart
class DriftLocalAdapter<T> extends LocalAdapter<T> with RawQueryCapable {
  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery q, {String? userId}) async {
    final rows = await db.customSelect(q.sql!, variables: q.args.map(Variable.new).toList()).get();
    return rows.map((r) => r.data).toList();
  }
}
```

Building relational **joins** in the adapter? Use the type-level relation schema
(see #21) to traverse relations without an instance:

```dart
final rel = DatumRelationSchema.descriptor(T, 'author'); // fk/localKey/targetType
```

### Q: How do we handle migration between Drift and Datum?

They are **separate concerns**:

- **Drift owns its own schema migrations** (adding tables/columns, the
  `MigrationStrategy` / `schemaVersion` in your `MyDatabase`). Datum does not see
  or manage the Drift schema.
- **Datum migrations** transform the *serialized entity payload* (the
  `toDatumMap()` shape) when your model changes — independent of where it's
  stored. See §3.

If you keep entities as an opaque JSON `payload` column (as above), Drift schema
changes are rare (the payload column is stable), and reshaping the entity is a
**Datum migration**, not a Drift one.

---

## 2. Isar dependency conflict (#6)

The error is real and expected:

```
Because every version of datum_generator depends on source_gen >=3.0.0 <5.0.0
and isar >=4.0.0-dev.3 depends on source_gen ^1.4.0, datum_generator is
incompatible with isar >=4.0.0-dev.3.
```

`datum_generator` requires `source_gen >=3.0.0`, while `isar: ^4.0.0-dev`
constrains `source_gen ^1.4.0` — these cannot resolve together. Options, best
first:

1. **Don't use `isar_generator` at all.** You almost never need Isar's own
   codegen with Datum: store each entity as its `toDatumMap()` in a single
   generic Isar collection (a `Map`/JSON payload), exactly like the Drift
   pattern above. Then your `pubspec.yaml` only needs `isar` + `isar_flutter_libs`
   as runtime deps — no `isar_generator`, no `source_gen` conflict.
2. **Use Isar 3.x** (`isar: ^3.1.0`) if you want Isar-native typed collections;
   its `source_gen` constraint is compatible with `datum_generator`.
3. **Drop `datum_generator`** and hand-write `toDatumMap`/`fromMap`/`diff` on
   your entities. Then you can use `isar: ^4.0.0-dev` with `isar_generator`
   freely, since `source_gen` is no longer pulled in by Datum.

The docs recommending `isar: ^4.0.0` **with** `isar_generator` alongside
`datum_generator` are incorrect for the current versions; prefer option 1.

---

## 3. Purpose of Datum migrations (#5)

Short answer: **Datum migrations transform the shape of your entity's serialized
data (`toDatumMap()`) as it exists in the local store, keyed by
`DatumConfig.schemaVersion`.** They are about *your model's payload shape*, not
about the storage engine's schema or the server's schema.

You have (up to) three independent migration layers:

| Layer | Owns | When it runs |
|-------|------|--------------|
| **Storage adapter** (Drift/Isar/SQLite) | Native tables/columns/indexes | On DB open, per the adapter's own version |
| **Server / remote** | The wire shape sent to clients | Server-side, before data reaches the client |
| **Datum migration** | The `toDatumMap()` shape of already-stored local entities | On init, when `schemaVersion` increases |

**When you need a Datum migration:** you have **existing local data** persisted
in an old shape and you change the model (rename/split/merge/retype a field), and
you want that old on-disk data upgraded in place — without waiting for a re-sync
and without the storage engine or server knowing about it.

```dart
class RenameTitleToName extends Migration {
  @override int get fromVersion => 0;
  @override int get toVersion => 1;
  @override
  Map<String, dynamic> migrate(Map<String, dynamic> old) {
    return {...old, 'name': old['title'], 'title': null}..remove('title');
  }
}

final config = DatumConfig(schemaVersion: 1, migrations: [RenameTitleToName()]);
```

**When you *don't* need one:**

- The change is additive and your `fromMap` already tolerates missing fields
  (e.g. a new nullable field, or with `strictNullChecks: false`) — old rows just
  read the default.
- You can afford to clear local data and re-pull from the server (the server
  already sends the new shape).
- The reshaping happens entirely server-side and the client always receives the
  new shape (fresh installs / full re-sync).

So Datum migrations are the tool for **in-place local upgrades of persisted
entity payloads** across model changes — complementary to, not a replacement
for, storage-engine and server migrations. Provide a `DatumConfig.onMigrationError`
handler to control what happens if one fails (default: rethrow to avoid running
on corrupted data).

## 4. Declarative migrations — one chain for SQL *and* schemaless stores

Instead of hand-writing `Migration.migrate` map surgery, declare each step as
a `SchemaMigration` built from `ColumnOperation`s. The same list then drives
**both** executors:

- `MigrationExecutor` (Hive, in-memory, any schemaless store) applies the Dart
  side of each operation to every stored row.
- `SqlMigrationExecutor` (any `LocalAdapter` mixing in `RawQueryCapable`)
  translates the operations into real `ALTER TABLE` / `UPDATE` statements and
  runs them inside the adapter's transaction — the only way columns can
  actually be added or dropped on a SQL table.

Each operation carries its Dart closure *and* (where needed) its SQL
counterpart:

```dart
final migrations = [
  // v0 -> v1: add a column with a default, rename another.
  SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
    ColumnOperation.add('status', defaultValue: 'active'),
    ColumnOperation.rename('name', to: 'full_name'),
  ]),

  // v1 -> v2: computed column — Dart compute for schemaless stores,
  // sqlExpression backfill for SQL stores.
  SchemaMigration(fromVersion: 1, toVersion: 2, operations: [
    ColumnOperation.add(
      'email_domain',
      sqlType: 'TEXT',
      compute: (row) => (row['email'] as String? ?? '').split('@').last.toLowerCase(),
      sqlExpression: "lower(substr(email, instr(email, '@') + 1))",
    ),
  ]),

  // v2 -> v3: scoped in-place transform. `where` scopes the map path,
  // `sqlWhere` scopes the generated UPDATE identically.
  SchemaMigration(
    fromVersion: 2,
    toVersion: 3,
    where: (row) => (row['age'] as int? ?? 0) >= 18,
    sqlWhere: 'age >= 18',
    operations: [
      ColumnOperation.transform('age', (v, _) => (v as int? ?? 0) + 1,
          sqlExpression: 'age + 1'),
    ],
  ),

  // v3 -> v4: drop a legacy column + arbitrary rewrite with raw SQL twin.
  SchemaMigration(fromVersion: 3, toVersion: 4, operations: [
    ColumnOperation.remove('legacy_score'),
    ColumnOperation.row(
      (row) => {...row, 'email': (row['email'] as String? ?? '').toLowerCase()},
      sql: ['UPDATE "users" SET "email" = lower(email)'],
    ),
  ]),
];

// Schemaless store (Hive / in-memory): rewrites rows via the Dart closures.
await MigrationExecutor<User>(
  localAdapter: hiveAdapter,
  migrations: migrations,
  targetVersion: 4,
  logger: logger,
).execute();

// SQL store: emits dialect-aware DDL/DML through RawQueryCapable.rawQuery.
await SqlMigrationExecutor<User>(
  localAdapter: sqlAdapter, // must mix in RawQueryCapable
  table: 'users',
  migrations: migrations,
  targetVersion: 4,
  dialect: SqlDialect.sqlite, // or SqlDialect.postgresql
  logger: logger,
).execute();
```

Guarantees shared by both executors:

- **Fail-fast validation.** `MigrationPlan.resolve` checks the whole chain
  (gaps, duplicate starting versions, backwards steps, overshoot) before any
  data is touched; the SQL executor additionally generates every statement up
  front, so an untranslatable operation in step 3 means steps 1–2 never run.
- **Atomicity.** The map executor snapshots and restores on failure; the SQL
  executor relies on the adapter's transaction (SQLite and PostgreSQL roll
  back DDL and DML together).
- **Run-once semantics.** The stored schema version is stamped per step, so
  a relaunch resumes exactly where the chain left off — never re-applies.

Operations that only exist as Dart closures (`compute`/`transform`/`row`
without their SQL counterpart) are rejected by the SQL generator with a
message telling you which counterpart to provide. Custom operations can join
the SQL path by implementing `SqlConvertibleOperation`.

The executable reference for all of this — against a **real** sqlite3
database, including transactional rollback — is
`test/integration/sqlite_migration_integration_test.dart`, and the shipping
implementation is the `datum_sqlite` package (`SqliteLocalAdapter` +
`SqlMigrationExecutor`).

## 5. Incremental pull (`DeltaSyncCapable`)

By default the pull phase reads the full remote dataset every cycle that
runs. A remote adapter that can answer "what changed since T?" should mix in
`DeltaSyncCapable`:

```dart
class MyRestAdapter<T extends DatumEntityInterface> extends RemoteAdapter<T>
    with DeltaSyncCapable<T> {
  @override
  Future<List<T>> readSince(DateTime since, {String? userId, DatumSyncScope? scope}) async {
    // e.g. GET /entities?updated_since=<since>  — compare against a
    // SERVER-maintained received-at column, not the client's modifiedAt.
    ...
  }
}
```

The engine then pulls incrementally on every cycle except a user's first
sync and `detectRemoteDeletions` cycles (which need the complete remote id
set). `DatumConfig.deltaSyncOverlap` (default 5 minutes) widens the
watermark for clock-skew tolerance — re-delivered rows are dropped by the
strictly-newer check. Soft deletions ride deltas naturally; hard remote
deletions do not (keep soft deletes, or use `detectRemoteDeletions`).

## 6. Certifying custom adapters (`datum_test`)

The `datum_test` package runs the same behavioral contract Datum's own
adapters pass — CRUD, user scoping, `DatumQuery` semantics, pending
operations, sync state, migration raw-data fidelity, and capability checks —
against any adapter in one call:

```dart
runLocalAdapterConformanceTests(
  name: 'MyAdapter',
  create: () async => MyAdapter<ConformanceEntity>(fromMap: ConformanceEntity.fromMap)..initialize(),
);
```

It also ships `LocalSyncServer` (a real HTTP sync server with fault
injection) and `HttpRemoteAdapter` (a reference REST adapter) for
integration-testing sync flows without a backend.
