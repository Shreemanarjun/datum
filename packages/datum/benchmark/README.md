# Datum Benchmarks

Performance benchmarks for the `datum` core engine. Use these to **catch
regressions** between versions and to guide optimization — not as absolute
guarantees (numbers depend on the machine, Dart version, and JIT/AOT mode).

## Running

```bash
# From packages/datum
dart run benchmark/datum_benchmark.dart            # default
dart run benchmark/datum_benchmark.dart --scale=4  # 4x iterations (more stable)
dart run benchmark/datum_benchmark.dart --json     # machine-readable (for CI diffing)

# AOT is closer to release performance:
dart compile exe benchmark/datum_benchmark.dart -o build/bench && ./build/bench
```

## What is measured

### Tier A — micro-benchmarks (`datum_benchmark.dart`, implemented)

Isolated, CPU-bound hot paths the sync engine hits for every item. Pure Dart,
no Flutter, no I/O, no new dependencies.

| Group | Cases | Why it matters |
|-------|-------|----------------|
| Serialization | `toDatumMap` (local/remote), `fromMap`, `jsonEncode` | Runs once per entity, per push/pull |
| Change detection | `diff` (changed / no-change) | Runs on every update to compute the delta |
| Causality | `VectorClock` increment / merge / isConcurrent | Runs per write + per conflict check |
| Query | `DatumQueryBuilder.build`, `DatumQuery.toSql` (sqlite/postgres) | Runs per query against SQL adapters |
| Integrity | `DatumHashGenerator.hashEntities` (n=10/100/1000) | Runs per sync cycle to detect drift |
| Caching | `LRUCache` get/put | Relationship + query-result caching |

> **Observed hotspot (now addressed):** `hashEntities` is O(n) (sort + full
> `jsonEncode`) and was recomputed over the entire dataset each sync cycle — at
> n=1000, ~7.2 ms per cycle. The new `DatumRollingHash` maintains an
> order-independent XOR accumulator so a single-entity update is **O(1)**
> (~17 µs, ~420× faster) instead of a full rehash. `hashEntitiesUnordered` gives
> the same set hash without sorting, enabling that incremental maintenance.

### Tier B — end-to-end engine benchmarks (planned)

Throughput and latency through the full `DatumManager` + adapter stack, using
in-memory adapters so the numbers reflect engine overhead rather than disk/network.
See the test plan for the full matrix. Target cases:

- `push` throughput (create vs update path) — single and `saveMany` batches.
- `read` / `readAll` / `query` latency at 1k / 10k / 100k stored entities.
- Full `synchronize()` cycle: push N pending ops, pull M remote changes, including
  conflict detection + resolution (LWW vs CRDT vs merge).
- Reactive `watchAll` / `watchQuery` re-emission cost as the dataset grows.
- Cold-start hydration time vs entity count.

These reuse the in-memory `MockLocalAdapter` / `MockRemoteAdapter` in
`test/mocks/` (add a `silent`/no-print mode before using them for timing).

## Adding a benchmark

Add a `bench('name', iterations, () { ... })` call inside `run()` in
`datum_benchmark.dart`. The harness warms up (~10% of iterations) before timing.
Keep each case's body allocation-light and side-effect-free so repeated runs are
comparable.

## CI regression gate (planned)

Run `--json` on a fixed runner, store the baseline, and fail CI if any case
regresses beyond a threshold (e.g. >20% ns/op). Wire this into the workflow
alongside the test suite.
