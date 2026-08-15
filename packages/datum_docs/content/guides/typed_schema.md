---
title: Typed Schemas & Auto-Migration
description: One runtime schema declaration per entity — typed queries, cast-free map reads, derived SQLite columns, and automatic schema reconciliation. No code generation.
---

Hand-written entities repeat every field name as a string in three unconnected
places: `toDatumMap` keys, query `Filter`s, and SQLite `columns` /
`ColumnOperation`s. A typo in any of them fails at runtime, silently or loudly.

`DatumSchema` closes that gap **without build_runner**: declare each field once
as a `DatumFieldSpec`, and that single declaration powers

1. **typed query field refs** (a spec IS-A `DatumQueryField`),
2. **cast-free map reads** with precise, field-named errors,
3. **derived SQLite columns** for `SqliteLocalAdapter`, and
4. **auto-migration** — the engine diffs the declared shape against what is
   actually stored and reconciles it.

Everything here is opt-in and layered: adopt only the pieces you want, keep
your existing `fromMap`/`toDatumMap` untouched, and nothing changes for
entities that don't declare a schema.

## Declare the schema once

```dart
abstract final class TaskFields {
  static final title = DatumFieldSpec<Task, String>('title',
      getter: (t) => t.title, defaultValue: '');
  static final priority = DatumFieldSpec<Task, int>('priority',
      getter: (t) => t.priority, defaultValue: 0, renamedFrom: 'prio');
  static final description = DatumFieldSpec<Task, String?>('description',
      getter: (t) => t.description);
}

final core = datumCoreFieldSpecs<Task>();

final taskSchema = DatumSchema<Task>(
  name: 'tasks',
  fields: [...core.all, TaskFields.title, TaskFields.priority, TaskFields.description],
);
```

`datumCoreFieldSpecs` provides the six sync fields (`id`, `userId`,
`modifiedAt`, `createdAt`, `version`, `isDeleted`) with camelCase keys —
every key and the timestamp codec are overridable for snake_case stores.
Specs carry closures, so they are `static final`, not `const`.

The schema validates itself at construction — duplicate names or a
`renamedFrom` that collides with a declared field fail immediately, listing
every problem at once.

## 1. Typed queries

A `DatumFieldSpec` **is** a `DatumQueryField`, so everything the typed query
surface accepts already works — misspelled fields and wrongly-typed values
now fail at compile time:

```dart continue
final query = DatumQueryBuilder<Task>()
    .whereField(TaskFields.priority, isGreaterThan: 2)
    .orderByField(TaskFields.title, descending: true)
    .build();

// Filter helpers directly on the spec:
final open = TaskFields.priority.greaterThanOrEqual(3);
print('$query $open');
```

## 2. Cast-free map reads

Implement `fromMap` with a reader instead of `as` casts. A missing key, a
null in a non-nullable field, or a wrong type throws a `SchemaReadException`
naming the entity, field, expected type, and actual value:

```dart continue
Task taskFromMap(Map<String, dynamic> map) {
  final r = taskSchema.reader(map);
  return Task(
    id: r(core.id),
    userId: r(core.userId),
    title: r(TaskFields.title),
    priority: r.getOr(TaskFields.priority, 0),
    description: r(TaskFields.description),
    createdAt: r(core.createdAt),
    modifiedAt: r(core.modifiedAt),
    version: r(core.version),
    isDeleted: r.getOr(core.isDeleted, false),
  );
}
```

Field codecs are inferred for primitives and `DateTime` (lenient: ISO-8601
strings *and* epoch milliseconds decode). For enums, durations, URIs, or
nested objects pass one explicitly — `DatumFieldCodec.enumByName(...)`,
`.durationMicros`, `.jsonObject(...)`, or your own; wrap with `.nullable`
for nullable fields.

Prefer full delegation? Give the schema a `construct:` callback and
`taskSchema.decode` becomes a valid `fromMap` tear-off; with getters on
every field, `taskSchema.toMap(entity)` can implement `toDatumMap` too.

## 3. Derived SQLite columns

`SqliteLocalAdapter` can derive its payload columns from the schema instead
of a hand-maintained map (explicit `columns:` still wins when both are
given), and `strictColumns: true` turns the historical silent-drop of
undeclared keys into an error:

```dart continue
final adapter = SqliteLocalAdapter<Task>(
  database: db,
  table: 'tasks',
  fromMap: Task.fromMap,
  schema: taskSchema,
  strictColumns: true,
);
print(adapter.table);
```

## 4. Auto-migration

Hand the schema to the config and let `initialize()` reconcile the store:

```dart continue
final config = DatumConfig<Task>(
  schema: taskSchema,
  autoMigrate: true,
  // Destructive changes stay opt-in:
  // autoMigrateDropColumns: true,
);
print(config.autoMigrate);
```

On each launch the engine

1. checks the stored **schema fingerprint** — unchanged declaration means
   the whole pass is skipped (adapters mixing in `SchemaFingerprintCapable`,
   like `datum_sqlite` and `datum_hive`, persist it);
2. introspects the actual shape — `PRAGMA table_info` through the adapter's
   own `rawQuery` on SQL stores, a raw-row key scan on schemaless stores;
3. diffs it against the declaration and applies the difference:
   - **missing declared fields** are added and backfilled with their
     `defaultValue` (non-nullable fields *must* declare one — the pass
     fails fast before touching data otherwise);
   - **renames** need the one-line `renamedFrom: 'prio'` hint — a rename is
     indistinguishable from drop + add, and guessing would lose data. The
     rename is row-safe: a row that already carries the new key keeps it;
   - **undeclared stored columns** are kept and logged by default;
     `autoMigrateDropColumns: true` removes them. Core sync columns and
     `__`-prefixed internals are never touched.

On SQL adapters the reconciliation runs as real `ALTER TABLE` / `UPDATE`
statements in one transaction; on schemaless stores as snapshot-protected
raw-map rewrites. A failure rolls back, leaves no fingerprint stamp, and
surfaces through the same `onMigrationError` / `MigrationException` path as
manual migrations.

### Coexistence with manual migration chains

Auto-migration runs **after** your [`SchemaMigration` chain](/guides/migrations)
and never reads or writes the stored integer schema version — versioned
chains keep their exact semantics. Use manual steps for what a diff cannot
express (value transforms, type changes, scoped rewrites); let auto-migration
absorb the routine add-a-field / rename-a-field churn.

## Certify your adapter

The conformance kit ships a suite for the auto-migration contract — seeded
legacy stores, rename-with-hint, kept-vs-dropped columns, and fingerprint
run-once across a simulated relaunch:

```dart
runAutoMigrationConformanceTests(
  name: 'InMemory',
  createLocal: () async {
    final adapter = InMemoryLocalAdapter<ConformanceEntity>(
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    return adapter;
  },
);
```

See [Testing Your Sync Stack](/guides/testing) for the rest of the kit.
