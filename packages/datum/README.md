<p align="center">
  <img src="https://zmozkivkhopoeutpnnum.supabase.co/storage/v1/object/public/images/datum_banner.svg" alt="Datum Banner">
</p>

# 🧠 **Datum** — Offline-First Data Synchronization for Dart & Flutter

<a href="https://pub.dev/packages/datum"><img src="https://img.shields.io/pub/v/datum.svg" alt="Pub"></a> <a href="https://github.com/shreemanarjun/datum/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a> <img src="https://img.shields.io/badge/coverage-100%25-brightgreen" alt="Code Coverage"> <img src="https://img.shields.io/badge/tests-2200%2B-brightgreen" alt="Tests"> <img src="https://img.shields.io/badge/version-1.1.0-blue" alt="Version">

> **Your backend, your database — one type-safe sync engine.**
>
> Datum owns the hard part of local-first apps: reconciling a device's
> database with a remote backend — conflicts, retries, queues, migrations and
> all — behind a single API. Local writes are instant; sync happens when
> connectivity allows; every device converges.

**[📚 Full documentation → datum.shreeman.dev](https://datum.shreeman.dev/)**

Every code snippet in this README is compiled against the real APIs by the
documentation snippet checker — what you copy is what runs.

---

## Why Datum

- **🔌 Offline-first core** — instant local writes, an automatic
  pending-operation queue, replay on reconnect, reactive `watch*` streams,
  and per-user data isolation.
- **⚡ Incremental sync at scale** — timestamp deltas or opaque change-feed
  cursors pull only what changed; content-hash skip checks make idle cycles
  cost almost nothing (O(1) in requests, regardless of dataset size).
- **🤝 Conflict resolution that converges** — version + timestamp
  last-write-wins with deterministic tie-breaking, vector clocks for true
  causality, custom resolvers, and real CRDTs (counters, sets, ordered lists,
  collaborative text) when concurrent edits must all survive.
- **🗂️ Schema migrations** — declarative column operations with fail-fast
  chain validation, snapshot rollback, and run-once stamping. The same chain
  runs as raw-map rewrites on Hive and as real `ALTER TABLE` DDL on SQLite.
- **🧪 A conformance kit, not just tests** — certify your adapter or whole
  stack with one call from [`datum_test`](https://pub.dev/packages/datum_test):
  network chaos profiles, crash-recovery, seeded convergence fuzzing.
- **🛠️ Type-safe by construction** — typed errors with `tryX` result APIs,
  generated entity boilerplate, type-safe query fields, and adapter
  capability mixins instead of runtime probing.

**Pure client library.** No hosted service, no lock-in — Hive, SQLite, or
in-memory locally; Supabase, Firebase, or any REST API remotely. MIT licensed.

---

## 🚀 Quick start

### 1. Install

```yaml
dependencies:
  datum: ^1.1.0
```

### 2. Define an entity

Extend `DatumEntity` — `id`, `userId`, and the sync metadata fields are what
the engine reconciles on. (Or let
[code generation](https://datum.shreeman.dev/guides/code_generation) write
the boilerplate for you.)

```dart
import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart'; // HttpRemoteAdapter (reference adapter)

class Task extends DatumEntity {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    this.done = false,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  factory Task.fromMap(Map<String, dynamic> map) => Task(
        id: map['id'] as String,
        userId: map['userId'] as String,
        title: map['title'] as String? ?? '',
        done: map['done'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
        modifiedAt: DateTime.parse(map['modifiedAt'] as String),
        version: (map['version'] as num?)?.toInt() ?? 1,
        isDeleted: map['isDeleted'] as bool? ?? false,
      );

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final bool done;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'done': done,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      toDatumMap(target: MapTarget.remote);

  /// Every edit bumps [version] and [modifiedAt] — that's what sync compares.
  Task copyWith({String? title, bool? done}) => Task(
        id: id,
        userId: userId,
        title: title ?? this.title,
        done: done ?? this.done,
        createdAt: createdAt,
        modifiedAt: DateTime.now(),
        version: version + 1,
        isDeleted: isDeleted,
      );

  @override
  List<Object?> get props => [...super.props, title, done];
}

/// Wire in connectivity_plus or your own checker in a real app.
class AlwaysOnline implements DatumConnectivityChecker {
  const AlwaysOnline();
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
```

### 3. Initialize once, then it's three calls

```dart continue
Future<void> main() async {
  await Datum.initialize(
    config: const DatumConfig(enableLogging: true),
    connectivityChecker: const AlwaysOnline(),
    registrations: [
      DatumRegistration<Task>(
        localAdapter: InMemoryLocalAdapter<Task>(fromMap: Task.fromMap),
        // The reference HTTP adapter from datum_test — swap in the Supabase,
        // Firebase, or REST adapter for your backend (guides below).
        remoteAdapter: HttpRemoteAdapter<Task>(
          baseUri: Uri.parse('https://api.example.com'),
          fromMap: Task.fromMap,
        ),
      ),
    ],
  );

  final tasks = Datum.manager<Task>();

  // 1. Instant local write — queued for sync automatically.
  await tasks.push(
    item: Task(
      id: 't1',
      userId: 'u1',
      title: 'Ship it',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      version: 1,
    ),
    userId: 'u1',
  );

  // 2. React to data changes anywhere in the app.
  tasks.watchAll(userId: 'u1').listen((all) => print('${all.length} tasks'));

  // 3. Reconcile with the backend whenever you choose (or let auto-sync run).
  final result = await tasks.synchronize('u1');
  print('synced: ${result.syncedCount}, failed: ${result.failedCount}');
}
```

Swap the adapters for [Hive](https://datum.shreeman.dev/guides/custom_adapters/hive_adapter),
[SQLite](https://datum.shreeman.dev/guides/custom_adapters/sqlite_adapter),
[Supabase](https://datum.shreeman.dev/guides/custom_adapters/supabase_adapter),
[Firebase](https://datum.shreeman.dev/guides/custom_adapters/firebase_adapter), or
[your own backend](https://datum.shreeman.dev/guides/remote_adapter_implement)
— the rest of your code does not change.

---

## 📝 Everyday operations

CRUD, typed queries, and reactive streams all hang off the manager:

```dart continue
final tasks = Datum.manager<Task>();

// Read one / all (local-first).
final one = await tasks.read('t1', userId: 'u1');
final all = await tasks.readAll(userId: 'u1');

// Update = push a bumped copy; delete is a soft delete that syncs.
if (one != null) {
  await tasks.push(item: one.copyWith(done: true), userId: 'u1');
}
await tasks.delete(id: 't1', userId: 'u1');

// Typed queries: filter + sort + paginate. SQL-backed adapters push this
// down into the database instead of filtering in memory.
final urgent = await tasks.query(
  const DatumQuery(
    filters: [Filter('done', FilterOperator.equals, false)],
    sorting: [SortDescriptor('createdAt', descending: true)],
    limit: 20,
  ),
  source: DataSource.local,
  userId: 'u1',
);
print('${all.length} total, ${urgent.length} open');

// Reactive variants keep UI live: watchAll / watchById / watchQuery.
tasks.watchQuery(
  const DatumQuery(filters: [Filter('done', FilterOperator.equals, false)]),
  userId: 'u1',
).listen((open) => print('${open.length} open tasks'));

// Choose freshness per call when reading through to the backend.
final freshest = await tasks.fetchById(
  't2',
  strategy: DataFetchStrategy.remoteFirst,
  userId: 'u1',
);
print(freshest?.title);
```

Offline is not an error state: writes made without connectivity queue as
pending operations and replay on the next sync — verified end to end by the
[conformance suites](https://datum.shreeman.dev/guides/testing).

---

## 🤝 Conflict resolution

When the same entity changed on two devices, the engine detects it (version +
timestamp + content comparison, or vector clocks for true causality) and asks
a resolver. The default is last-write-wins with a deterministic tie-break, so
every device converges to the same answer:

```dart continue
final config = DatumConfig<Task>(
  defaultConflictResolver: LastWriteWinsResolver<Task>(),
);
print(config.schemaVersion);
```

Plug in your own `DatumConflictResolver` for field-level merges — see
[Advanced Sync](https://datum.shreeman.dev/guides/advanced_sync).

### CRDTs, when every edit must survive

For counters, sets, lists, and collaborative text, Datum ships real CRDTs —
merge in any order, converge everywhere:

```dart continue
var likesOnPhone = const PNCounter();
var likesOnLaptop = const PNCounter();

likesOnPhone = likesOnPhone.increment('phone');
likesOnPhone = likesOnPhone.increment('phone');
likesOnLaptop = likesOnLaptop.increment('laptop');

// Merge in any order — both devices converge on 3.
print(likesOnPhone.merge(likesOnLaptop).value); // 3
```

```dart continue
var note = RgaText(replicaId: 'phone');
note = note.insert(0, 'Hello world');

// A second device loads the same document…
var laptop = RgaText.fromMap(note.toMap(), replicaId: 'laptop');

// …and both edit concurrently.
note = note.insert(5, ',');
laptop = laptop.insert(laptop.length, '!');

note = note.merge(laptop);
laptop = laptop.merge(note);
print(note.value == laptop.value); // true — "Hello, world!"
```

More in [Collaborative Editing & CRDTs](https://datum.shreeman.dev/guides/collaborative_editing).

---

## 🗂️ Schema migrations

Your app ships v2 with a renamed field and a new column; devices still hold
v1 data. Declare the chain once — it runs in place, on startup, exactly once,
with fail-fast validation and rollback:

```dart continue
final config = DatumConfig<Task>(
  schemaVersion: 1,
  migrations: [
    SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
      ColumnOperation.rename('name', to: 'title'),
      ColumnOperation.add('priority', defaultValue: 0),
    ]),
  ],
);
print(config.schemaVersion);
```

On SQL stores the **same chain** executes as real DDL
(`ALTER TABLE` / `UPDATE`) inside one transaction:

```dart continue
final result = await SqlMigrationExecutor<Task>(
  localAdapter: localAdapter, // any adapter mixing in RawQueryCapable
  table: 'tasks',
  migrations: [
    SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
      ColumnOperation.add('priority', defaultValue: 0),
      ColumnOperation.transform(
        'title',
        (value, row) => (value as String? ?? '').trim(),
        sqlExpression: 'TRIM(title)',
      ),
    ]),
  ],
  targetVersion: 1,
  dialect: SqlDialect.sqlite,
  logger: DatumLogger(),
).execute();
if (!result.success) {
  print('Nothing was modified: ${result.migrationError}');
}
```

Full guide: [Schema Migrations](https://datum.shreeman.dev/guides/migrations).

---

## 🧬 Typed schemas & auto-migration — no codegen

Declare each field **once** as a `DatumFieldSpec` and that declaration powers
typed queries, cast-free map reads, derived SQLite columns, and automatic
schema reconciliation:

```dart continue
abstract final class TaskFields {
  static final title = DatumFieldSpec<Task, String>('title',
      getter: (t) => t.title, defaultValue: '');
  static final done = DatumFieldSpec<Task, bool>('done',
      getter: (t) => t.done, defaultValue: false, renamedFrom: 'completed');
}

final core = datumCoreFieldSpecs<Task>();
final taskSchema = DatumSchema<Task>(
  name: 'tasks',
  fields: [...core.all, TaskFields.title, TaskFields.done],
);

// Typed queries — a spec IS-A DatumQueryField, typos fail at compile time:
final open = DatumQueryBuilder<Task>()
    .whereField(TaskFields.done, isEqualTo: false)
    .orderByField(TaskFields.title)
    .build();

// Cast-free reads with field-named errors (no `as` in fromMap):
Task readTask(Map<String, dynamic> map) {
  final r = taskSchema.reader(map);
  return Task(
    id: r(core.id),
    userId: r(core.userId),
    title: r(TaskFields.title),
    done: r.getOr(TaskFields.done, false),
    createdAt: r(core.createdAt),
    modifiedAt: r(core.modifiedAt),
    version: r(core.version),
  );
}
```

Then let `initialize()` keep the store in shape — added fields are backfilled
with their defaults, renames are honored via the `renamedFrom:` hint (real
`ALTER TABLE` on SQLite, raw-map rewrites on Hive), and a stored fingerprint
makes unchanged launches skip the whole pass:

```dart continue
final config = DatumConfig<Task>(schema: taskSchema, autoMigrate: true);
print(config.autoMigrate);
```

Manual `SchemaMigration` chains keep working unchanged — the auto pass runs
after them and never touches the stored schema version. Full guide:
[Typed Schemas & Auto-Migration](https://datum.shreeman.dev/guides/typed_schema).

---

## 🗄️ Storage & backends

| Package | What it is |
|---|---|
| [`datum`](https://pub.dev/packages/datum) | The engine + in-memory adapter (this package) |
| [`datum_sqlite`](https://pub.dev/packages/datum_sqlite) | SQLite local adapter — real tables, SQL query pushdown, transactions, DDL migrations |
| [`datum_hive`](https://pub.dev/packages/datum_hive) | Hive CE local adapter for Flutter |
| [`datum_test`](https://pub.dev/packages/datum_test) | Conformance kit + local sync server + reference HTTP adapters |
| [`datum_generator`](https://pub.dev/packages/datum_generator) | Code generation for entity boilerplate |

```dart continue
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';

final db = sqlite3.open('app.db');
final sqliteAdapter = SqliteLocalAdapter<Task>(
  database: db,
  table: 'tasks',
  fromMap: Task.fromMap,
  columns: {'title': 'TEXT', 'done': 'BOOLEAN'},
);
print(sqliteAdapter.table);
```

```dart no-verify
import 'package:datum_hive/datum_hive.dart';

final hiveAdapter = HiveLocalAdapter<Task>(
  entityBoxName: 'tasks',
  fromMap: Task.fromMap,
);
```

Building your own is two small interfaces:
[local adapter guide](https://datum.shreeman.dev/guides/local_adapter_implement) ·
[remote adapter guide](https://datum.shreeman.dev/guides/remote_adapter_implement).

---

## 🧪 Testing your stack

Certify any adapter (or your entire sync stack) with one call from
[`datum_test`](https://pub.dev/packages/datum_test) — then go further with
network chaos profiles, crash-recovery with exactly-once delivery, and seeded
multi-device convergence fuzzing:

```dart continue
runLocalAdapterConformanceTests(
  name: 'InMemory',
  create: () async {
    final adapter = InMemoryLocalAdapter<ConformanceEntity>(
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    return adapter;
  },
);
```

Full guide: [Testing Your Sync Stack](https://datum.shreeman.dev/guides/testing).

---

## ⚡ Performance

Measured, not promised — by the micro-benchmark suite (`benchmark/` on the
Dart VM) and an end-to-end integration suite that runs both SQLite and Hive
against a real HTTP sync server on an iOS simulator (debug build):

| What | Result |
|---|---|
| Idle sync cycle | **~1–2 ms**, O(1) requests — flat at any dataset size |
| Cursor delta pull (10 changed of 500) | only the change feed is transferred, never the full table |
| SQL migration, 3 steps × 1,000 rows | **~5 µs/row** (set-based DDL) vs ~24 µs/row map path |
| Collaborative-text keystroke | ~26 µs (VM micro-benchmark) |
| Incremental dataset-hash update | ~17 µs — full rescans eliminated |

Tuning knobs, delta sync, cursors, and hash caching:
[Incremental Sync](https://datum.shreeman.dev/guides/performance/incremental_sync) ·
[Performance Tuning](https://datum.shreeman.dev/guides/performance/tuning).

---

## ⚖️ How Datum compares

| Approach | Examples | Where Datum differs |
|---|---|---|
| **Hosted sync service** | PowerSync, Ditto, Realm/Atlas Device Sync | Datum is a **pure client library** — no service to run or pay for; your backend stays exactly as it is |
| **Backend-bundled offline cache** | Firebase/Firestore offline persistence | Datum is **backend-agnostic** — the same app code syncs against Supabase, Firebase, or any REST API via adapters |
| **Roll your own** | timestamps + `ConnectivityPlus` + hope | Datum is that engine, already built — 100% test line coverage, wire-level integration suites, fuzz-verified convergence |

The honest flip side: a hosted service can give you server-enforced partial
replication and dashboards out of the box; a backend-bundled cache is nearly
zero-setup if you're all-in on that backend. Datum's bet is **control without
lock-in** — you bring the backend, it brings the engine.

---

## 📚 Explore the docs

- **Getting started** — [Quick Start](https://datum.shreeman.dev/getting_started/quick_start) · [Define Entities](https://datum.shreeman.dev/guides/entity_define) · [Code Generation](https://datum.shreeman.dev/guides/code_generation) · [Initialization](https://datum.shreeman.dev/guides/initialization)
- **Data & queries** — [Querying](https://datum.shreeman.dev/guides/querying) · [Relationships](https://datum.shreeman.dev/guides/relationships) · [Cascading Delete](https://datum.shreeman.dev/guides/cascading_delete)
- **Sync** — [Sync Patterns](https://datum.shreeman.dev/guides/sync_patterns) · [Advanced Sync](https://datum.shreeman.dev/guides/advanced_sync) · [Incremental Sync](https://datum.shreeman.dev/guides/performance/incremental_sync) · [Collaborative Editing](https://datum.shreeman.dev/guides/collaborative_editing)
- **Quality** — [Schema Migrations](https://datum.shreeman.dev/guides/migrations) · [Testing Your Sync Stack](https://datum.shreeman.dev/guides/testing) · [Troubleshooting](https://datum.shreeman.dev/troubleshooting)
- **Example app** — a full Flutter app (Riverpod, multi-adapter, observers) lives in [`example/`](example/), including an [integration + benchmark suite](example/integration_test/) you can run on a simulator.

---

## 🔮 Future plans

- **Multi-adapter fan-out** — register multiple remotes (or locals) per
  entity, e.g. sync to a REST API and Firebase simultaneously.
- More adapters (Drift, PostgreSQL, GraphQL), CLI tooling, and a first-class
  web story — see [Coming Soon](https://datum.shreeman.dev/coming_soon).

---

## ❤️ Support & Contributions

### Support This Project

If you find this package helpful and would like to support its development, please consider buying me a coffee. Your support is greatly appreciated and helps me dedicate more time to improving and maintaining this project.

<a href="https://buymeacoffee.com/shreemanarjun" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.webp" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

### Contributing

Contributions are welcome! If you have a feature request, bug report, or want to contribute to the code, please see our [Contributing Guidelines](CONTRIBUTING.md). Let's make Datum even better together!

---

## 🙏 Acknowledgements

This project is heavily inspired by the great work of the [`synq_manager`](https://pub.dev/packages/synq_manager) package and its author [Ahmet Aydin](https://github.com/ahmtydn). A big thank you for the inspiration and the solid foundation provided to the Flutter community.

---

## 🪪 License

MIT License

Copyright (c) 2025 [**Shreeman Arjun Sahu**](https://shreeman.dev)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
