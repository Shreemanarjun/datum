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
