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
now fail at compile time. Typed queries are a **certified default across
adapters**: the conformance kit's `runTypedQueryConformanceTests` proves,
per adapter, that the typed path, the string path, and a reference
evaluation return identical results for the whole operator matrix — through
real SQL push-down on SQLite and map matching on Hive/in-memory alike:

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

## Schema-driven diff and equality

The same declaration also replaces the hand-written `diff` and `props`
boilerplate. `diffOf` compares payload fields through their codecs (core
sync fields excluded) and stamps the new `modifiedAt`/`version` into a
non-empty delta; `propsOf` yields the payload values for `Equatable`:

```dart continue
final updated = Task(
  id: task.id,
  userId: task.userId,
  title: 'renamed',
  createdAt: task.createdAt,
  modifiedAt: DateTime.now(),
  version: task.version + 1,
);
final delta = taskSchema.diffOf(task, updated);
print(delta?.keys); // (title, modifiedAt, version) — unchanged fields stay out
print(taskSchema.diffOf(task, task)); // null — nothing changed

final payloadProps = taskSchema.propsOf(task);
print(payloadProps.length);
```

In your entity they become one-liners:

```dart no-verify
@override
Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
    taskSchema.diffOf(oldVersion as Task, this);

@override
List<Object?> get props => [...super.props, ...taskSchema.propsOf(this)];
```

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

## Type-safe relations

`DatumRelationSpec` extends the same declare-once idea to relations: the
name, both entity types, and the foreign key **as a field spec** are bound
together, so `withRelated`, access, lazy fetching, and cascade behavior are
all checked at compile time — across every adapter, since relations resolve
at the manager layer:

```dart continue
class Blog extends RelationalDatumEntity with MemoizedRelations {
  Blog({required this.id, required this.userId, required this.title});

  @override
  final String id;
  @override
  final String userId;
  final String title;
  @override
  DateTime get createdAt => DateTime.utc(2026);
  @override
  DateTime get modifiedAt => DateTime.utc(2026);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final postsRel = DatumRelationSpec<Blog, Post>.hasMany(
    'posts',
    foreignKey: Post.blogIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      {'id': id, 'userId': userId, 'title': title};
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();
  @override
  Blog copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Blog(id: id, userId: userId, title: title);
  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [postsRel]);
}

class Post extends RelationalDatumEntity with MemoizedRelations {
  Post({required this.id, required this.userId, required this.blogId});

  @override
  final String id;
  @override
  final String userId;
  final String blogId;
  @override
  DateTime get createdAt => DateTime.utc(2026);
  @override
  DateTime get modifiedAt => DateTime.utc(2026);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final blogIdField = DatumFieldSpec<Post, String>('blogId', getter: (p) => p.blogId);
  static final blogRel = DatumRelationSpec<Post, Blog>.belongsTo('blog', foreignKey: blogIdField);

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      {'id': id, 'userId': userId, 'blogId': blogId};
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();
  @override
  Post copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Post(id: id, userId: userId, blogId: blogId);
  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [blogRel]);
}

Future<void> typedRelationUsage(DatumManager<Blog> blogs) async {
  // Typed names for eager loading; access bound to name AND type:
  final blog = (await blogs.read('b1', userId: 'u1', withRelated: [Blog.postsRel].names))!;
  final posts = Blog.postsRel.listOf(blog) ?? const [];

  // Or fetch lazily — resolved through Datum.manager<Post>() on any adapter:
  final lazyPosts = await Blog.postsRel.fetchListFor(blog);
  print('${posts.length} ${lazyPosts.length}');
}
```

Many-to-many joins through a **registered pivot entity**, with both pivot
keys spelled as the pivot's own field specs:

```dart no-verify
static final tagsRel = DatumRelationSpec.manyToMany<Ticket, Tag, TicketTag>(
  'tags',
  pivotSelfKey: TicketTag.ticketIdField,
  pivotOtherKey: TicketTag.tagIdField,
);

// Eager: withRelated: [Ticket.tagsRel].names — or lazy, both directions:
final tags = await Ticket.tagsRel.fetchListFor(ticket);
final tickets = await Tag.ticketsRel.fetchListFor(tag);
```

Give the pivot its own `hasMany` with `cascadeDelete` so link rows die with
their owner while the shared far side survives. All four
`CascadeDeleteBehavior`s work through specs: `cascade` walks the subtree
transitively (with a per-type breakdown in `result.deletedEntities`),
`none` leaves the branch orphaned, `restrict` makes `cascadeDelete` return
`success: false` with the blockers listed in `result.restrictedRelations`,
and `setNull` detaches children by nulling their foreign key — declare that
field nullable in the entity. One caveat: `fetch()` caches
per entity **instance** — after local mutations, re-read the entity (or
query the pivot) rather than re-fetching on a stale instance. The complete
multi-adapter example (three-level chain + many-to-many, verified on
InMemory/SQLite/Hive) lives in
[`example/integration_test/datum_relations_typed_test.dart`](https://github.com/shreemanarjun/datum/blob/main/packages/datum/example/integration_test/datum_relations_typed_test.dart).

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

1. checks the stored **schema fingerprint** — an unchanged declaration means
   the whole pass is skipped (adapters mixing in `SchemaFingerprintCapable`,
   like `datum_sqlite` and `datum_hive`, persist it). The drop policy is
   part of the stamp, so turning `autoMigrateDropColumns` on later re-runs
   the pass once instead of being silently ignored;
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
run-once across a simulated relaunch. Run it against a **raw-preserving**
store (SQLite, Hive — anything whose `getAllRawData` returns what is
actually on disk; `InMemoryLocalAdapter` round-trips through the entity and
so cannot hold a legacy shape):

```dart
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  runAutoMigrationConformanceTests(
    name: 'SqliteLocalAdapter',
    createLocal: () async {
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: sqlite3.openInMemory(),
        table: 'entities',
        fromMap: ConformanceEntity.fromMap,
        // The suite seeds a legacy shape; declare its columns.
        columns: const {'name': 'TEXT', 'legacy': 'INTEGER'},
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
```

See [Testing Your Sync Stack](/guides/testing) for the rest of the kit.
