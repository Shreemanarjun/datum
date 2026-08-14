---
title: Datum
description: Offline-first data synchronization for Dart & Flutter — your backend, your database, one type-safe sync engine.
layout: home
---

Datum is an **offline-first sync engine for Dart & Flutter** that owns the
hard part of local-first apps: reconciling a device's database with a remote
backend — conflicts, retries, queues, migrations and all — behind one
type-safe API. Local writes are instant; sync happens when connectivity
allows; every device converges.

**Your backend, your database.** Datum is a pure client library with a
pluggable adapter architecture — Hive, SQLite, or in-memory locally;
Supabase, Firebase, or any REST API remotely. No hosted service, no
lock-in, MIT licensed.

## Sixty seconds to synced

```dart
Future<void> sixtySeconds() async {
  final datumResult = await Datum.initialize(
    config: const DatumConfig(enableLogging: true),
    connectivityChecker: const SnippetConnectivity(),
    registrations: [
      DatumRegistration<Task>(
        localAdapter: InMemoryLocalAdapter<Task>(fromMap: Task.fromMap),
        remoteAdapter: HttpRemoteAdapter<Task>(baseUri: Uri.parse('https://api.example.com'), fromMap: Task.fromMap),
      ),
    ],
  );
  print('initialized: ${datumResult.isSuccess()}');
  final tasks = Datum.manager<Task>();

  // Instant local write — queued for sync automatically.
  await tasks.push(
    item: Task(id: 't1', userId: 'u1', title: 'Ship it', createdAt: DateTime.now(), modifiedAt: DateTime.now(), version: 1),
    userId: 'u1',
  );

  // React to data changes anywhere in the app.
  tasks.watchAll(userId: 'u1').listen((all) => print('${all.length} tasks'));

  // Reconcile with the backend whenever you choose (or let auto-sync run).
  final result = await tasks.synchronize('u1');
  print('synced: ${result.syncedCount}, failed: ${result.failedCount}');
}
```

Swap the adapters for [Hive](/guides/custom_adapters/hive_adapter),
[SQLite](/guides/custom_adapters/sqlite_adapter),
[Supabase](/guides/custom_adapters/supabase_adapter), or
[your own backend](/guides/remote_adapter_implement) — the rest of your code
does not change.

## What's in the box

<Card title="🔌 Offline-first core">
Instant local writes, an automatic pending-operation queue, replay on
reconnect, reactive <code>watch*</code> streams, and multi-user isolation.
Start with <a href="/guides/entity_define">entities</a> and
<a href="/guides/initialization">initialization</a>.
</Card>

<Card title="⚡ Incremental sync at scale">
Pull only what changed: timestamp deltas or opaque change-feed cursors, with
clock-skew tolerance and per-device cursor tracking. Idle cycles cost almost
nothing thanks to content-hash skip checks and metadata hash caching.
<a href="/guides/performance/incremental_sync">Incremental Sync</a> ·
<a href="/guides/performance/tuning">Performance Tuning</a>
</Card>

<Card title="🤝 Conflict resolution that converges">
Version + timestamp last-write-wins with deterministic tie-breaking, vector
clocks for true causality, custom resolvers — and real CRDTs
(counters, sets, ordered lists, collaborative text) when concurrent edits
must all survive. <a href="/guides/collaborative_editing">Collaborative
Editing</a>
</Card>

<Card title="🗂️ Schema migrations">
Declarative column operations with fail-fast chain validation, rollback,
and run-once stamping — the same chain runs as raw-map rewrites on Hive and
as real <code>ALTER TABLE</code> DDL on SQLite.
<a href="/guides/migrations">Schema Migrations</a>
</Card>

<Card title="🧪 A conformance kit, not just tests">
Certify your adapter or whole stack with one call, then keep going: network
chaos profiles, crash-recovery with exactly-once delivery, and seeded
convergence fuzzing. <a href="/guides/testing">Testing Your Sync Stack</a>
</Card>

<Card title="🛠️ Type-safe by construction">
Typed errors with <code>tryX</code> result APIs, generated entity
boilerplate, type-safe query fields, and adapter capability mixins instead
of runtime probing. <a href="/guides/code_generation">Code Generation</a> ·
<a href="/guides/querying">Querying</a>
</Card>

## How Datum compares

Different tools make different trade-offs — pick honestly:

| Approach | Examples | Model | Where Datum differs |
|---|---|---|---|
| **Hosted sync service** | PowerSync, Ditto, Realm/Atlas Device Sync | A sync service (managed or self-hosted) sits between clients and your database | Datum is a **pure client library** — no service to run or pay for; your backend stays exactly as it is |
| **Backend-bundled offline cache** | Firebase/Firestore offline persistence | Offline support comes with — and is tied to — one specific backend | Datum is **backend-agnostic**: the same app code syncs against Supabase, Firebase, or any REST API via adapters |
| **Roll your own** | timestamps + `ConnectivityPlus` + hope | Full control, but you own conflicts, retries, queues, migrations, and convergence testing | Datum is that engine, already built — with 100% test line coverage, wire-level integration suites, and fuzz-verified convergence |

The honest flip side: a hosted service can give you server-enforced partial
replication and operational dashboards out of the box; a backend-bundled
cache is nearly zero-setup if you're all-in on that backend. Datum's bet is
**control without lock-in** — you bring the backend, it brings the engine.

## What you can build

- **Field & offline work apps** — inspections, delivery, healthcare rounds:
  hours offline, clean reconciliation later, per-user data isolation.
- **Multi-device personal apps** — notes, tasks, finance: edits on phone
  and laptop converge without a "which copy wins?" support ticket.
- **Collaborative tools** — shared lists and documents using
  [CRDTs](/guides/collaborative_editing) where everyone's concurrent edits
  survive the merge.
- **Data-heavy dashboards** — [SQL pushdown](/guides/custom_adapters/sqlite_adapter)
  and [incremental pulls](/guides/performance/incremental_sync) keep 10k+
  row datasets responsive.

## The numbers behind the claims

- **100% test line coverage** across the library — 1,900+ tests including
  wire-level suites against a real HTTP server and a real SQLite database.
- **Convergence is fuzz-verified**: seeded multi-device random workloads
  must reach identical state after quiescence — the suite that found (and
  fixed) two real engine bugs before you ever hit them.
- **Measured hot paths**: ~26 µs collaborative-text keystrokes, ~17 µs
  incremental dataset-hash updates, O(1) idle sync cycles. Full tables in
  [Performance Tuning](/guides/performance/tuning).

## Explore the docs

**Getting started** — [Quick Start](/getting_started/quick_start) ·
[Define Entities](/guides/entity_define) ·
[Code Generation](/guides/code_generation) ·
[Initialization](/guides/initialization) ·
[Singleton API](/guides/singleton_api)

**Data & queries** — [Querying](/guides/querying) ·
[Relationships](/guides/relationships) ·
[Automated Relationships](/guides/code_generation_relationships) ·
[Cascading Delete](/guides/cascading_delete)

**Sync** — [Sync Patterns](/guides/sync_patterns) ·
[Advanced Sync](/guides/advanced_sync) ·
[Incremental Sync](/guides/performance/incremental_sync) ·
[Performance Tuning](/guides/performance/tuning) ·
[Collaborative Editing](/guides/collaborative_editing)

**Storage & backends** — [Hive](/guides/custom_adapters/hive_adapter) ·
[SQLite](/guides/custom_adapters/sqlite_adapter) ·
[Supabase](/guides/custom_adapters/supabase_adapter) ·
[Firebase](/guides/custom_adapters/firebase_adapter) ·
[REST](/guides/custom_adapters/rest_api_adapter) ·
[Build a Local Adapter](/guides/local_adapter_implement) ·
[Build a Remote Adapter](/guides/remote_adapter_implement)

**Quality** — [Schema Migrations](/guides/migrations) ·
[Testing Your Sync Stack](/guides/testing) ·
[Troubleshooting](/troubleshooting)

**Reference** — [Core](/modules/core) · [Query](/modules/query) ·
[Migration](/modules/migration) · [Health](/modules/health) ·
[Observers & Middleware](/modules/observers) · [Adapter](/modules/adapter) ·
[Configuration](/modules/config) · [Utils](/modules/utils) ·
[Changelog](/changelog)
