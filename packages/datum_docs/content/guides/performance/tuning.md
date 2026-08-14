---
title: Performance Tuning
description: The knobs that matter for a fast sync loop, what they cost, and the measured numbers behind them.
---

Datum's defaults are tuned for correctness first. This page covers every
performance knob, what it actually does, and when to reach for it. The
numbers quoted come from the repository's benchmark suite
(`packages/datum/benchmark`, Apple Silicon) — treat them as relative guidance,
not absolutes.

## The sync cycle's cost model

A sync cycle has four cost centers:

1. **The skip check** — compares the local and remote metadata content
   hashes. When they match, the cycle ends without touching entity data.
   This is why idle auto-sync polling is nearly free.
2. **Push** — each queued operation becomes a `PATCH`/`POST`/`PUT`.
3. **Pull** — by default the full remote dataset; with
   [incremental sync](/guides/performance/incremental_sync) only the delta.
4. **Metadata stamping** — hashing the local dataset to publish the new
   content hash.

## Metadata hash caching (on by default)

Stamping used to re-read and re-hash the whole local store every cycle —
O(n) with a SHA-256 per entity (~7 ms per cycle at 1,000 entities). Datum
now caches the per-user `(hash, count)` and invalidates it at every write
chokepoint, so a cycle in which nothing changed locally skips both the read
and the rehash.

```dart
final config = DatumConfig<Task>(
  // Default: true. Disable only if something writes to local storage
  // completely out-of-band (no manager, no adapter changeStream) — such
  // writes are invisible to the cache the same way they are invisible to
  // queueing and reactivity.
  enableMetadataHashCache: false,
);
```

## Incremental pulls

The single biggest lever for large stores — covered in depth in
[Incremental Sync](/guides/performance/incremental_sync). Summary: mix
`DeltaSyncCapable` or `CursorSyncCapable` into your remote adapter and pulls
transfer only changed rows.

## Batch sizes

Two knobs bound memory and per-request payload during pulls:

```dart
final batched = DatumConfig<Task>(
  // Entities reconciled per processing batch during a pull.
  remoteSyncBatchSize: 50,
  // Entities yielded per chunk when streaming a large remote read.
  remoteStreamBatchSize: 25,
);
```

Bigger batches mean fewer event emissions and less overhead; smaller batches
mean earlier progress events and smaller peak memory. The defaults suit most
apps — tune only after measuring.

## Isolate offload

`useIsolateSync: true` runs the whole sync cycle in a background isolate so
large reconciliations never jank the UI thread:

```dart
final offloaded = DatumConfig<Task>(useIsolateSync: true);
```

Two requirements to know about:

- **Everything must be sendable.** The adapters and their object graphs are
  copied into the isolate; stream controllers or open sockets in adapter
  fields will fail the send.
- **`Isolate.run` copies.** Storage-backed adapters (Hive, SQLite, HTTP)
  persist their effects normally, because storage is shared. A purely
  in-memory adapter's writes stay inside the isolate copy — only the sync
  *result* crosses back.

## Query & existence caches (off by default)

```dart
final cached = DatumConfig<Task>(
  // Off by default: the local database is already a fast cache, and cached
  // query results return shared instances that can go stale under
  // sync/realtime writes. Enable only after measuring a need.
  enableQueryCache: true,
  maxQueryCacheSize: 100,
  maxRelationshipQueryCacheSize: 200,
  maxEntityExistenceCacheSize: 500,
);
```

All caches are LRU-bounded; `manager.getCacheStats()` reports live sizes so
you can watch them under load.

## Content hashing at scale

The order-independent dataset hash (`hashEntitiesUnordered`) costs O(n).
When you maintain your own bookkeeping over very large sets, use the
incremental rolling hash instead of rehashing:

```dart
final tasks = [for (var i = 0; i < 1000; i++) Task.fromMap({'id': 't$i', 'userId': userId})];
final rolling = DatumRollingHash()..addAll(tasks);

// One update is O(1) — remove the old version, add the new:
final before = tasks.first;
final after = before.copyWith(title: 'renamed');
rolling
  ..remove(before)
  ..add(after);
print(rolling.value);
```

Measured: a full rehash at n=1000 is ~7–8 ms; a rolling update is ~17 µs
(~420× faster).

## SQL pushdown

With [`datum_sqlite`](/guides/custom_adapters/sqlite_adapter), `DatumQuery`
compiles to SQL — filtering, sorting, and limiting happen inside SQLite
instead of loading everything and matching in memory. Schemaless adapters
(Hive, in-memory) evaluate queries with `DatumQueryMatcher`, which is fast
(sub-microsecond per row for typical filters) but still O(n) per query.

## Reference numbers

From `dart run benchmark/datum_benchmark.dart` (scale=1, Apple Silicon):

| Hot path | Throughput |
|---|---|
| `entity.toDatumMap` | ~1.8M ops/s |
| `entity.diff` (changed) | ~12M ops/s |
| `VectorClock.isConcurrent` | ~23M ops/s |
| `DatumQuery.toSql` | ~1.0M ops/s |
| Dataset hash, n=1000 | ~7–8 ms |
| Rolling hash update (set=1000) | ~17 µs |
| 3-step migration, 10k rows (map path) | ~72 ms one-off |
| `RgaText` keystroke insert (200-char doc) | ~26 µs |

## A tuned production config, assembled

```dart
final production = DatumConfig<Task>(
  autoStartSync: true,
  autoSyncInterval: Duration(minutes: 5),
  deleteBehavior: DeleteBehavior.softDelete, // tombstones ride incremental pulls
  enableMetadataHashCache: true,             // default; shown for clarity
  deltaSyncOverlap: Duration(minutes: 5),
  remoteSyncBatchSize: 100,
  remoteStreamBatchSize: 50,
  useIsolateSync: true,
  syncTimeout: Duration(seconds: 30),
);
```

Measure before and after every change: the
[`datum_test` performance report](/guides/testing) prints a self-verifying
ops/sec table for any adapter, and the benchmark suite catches engine-level
regressions.
