# Benchmarks

Pure-Dart benchmarks for `datum`, `datum_sqlite` and `datum_hive`. They run
under the JIT VM (`dart run`) and as AOT executables (`dart compile exe`), with
no Flutter.

```sh
tool/bench.sh                         # working tree, 3 and 10 runs per case
RUNS=3,5,10 tool/bench.sh main        # compare against a git ref
PKGS="datum datum_sqlite" tool/bench.sh main
```

- Every case does one untimed warm-up run, then N timed runs. The report gives
  the mean, median, min and sample stdev.
- Each run builds its own fixtures, and only the code under test is timed.
- `tool/bench.sh` checks each git ref out into a temporary worktree and copies
  today's benchmark sources into it, so old code is measured with the same
  harness.

| Suite | Source |
|---|---|
| sync engine | [`sync_benchmark.dart`](sync_benchmark.dart) |
| SQLite adapter (file database) | [`../../datum_sqlite/benchmark/sqlite_benchmark.dart`](../../datum_sqlite/benchmark/sqlite_benchmark.dart) |
| Hive adapter (file boxes) | [`../../datum_hive/benchmark/hive_benchmark.dart`](../../datum_hive/benchmark/hive_benchmark.dart) |

## Results, 2026-11-26

Measured on an Apple Silicon Mac, Dart 3.13.4. Values are the mean of 10 runs,
in ms. The before column is `main`.

### Sync engine (in-memory local adapter, mock remote)

| Case | JIT before | JIT after | AOT before | AOT after |
|---|---:|---:|---:|---:|
| `push` ×500 | 50.6 | 8.1 | 29.0 | 9.0 |
| `watchAll` during a 500-write burst | 230.6 | 3.3 | 348.0 | 2.5 |
| Pull 2,000 remote items | 101.9 | 44.3 | 68.0 | 46.2 |
| Longest isolate stall in a sync after 1 write (5,000-item store) | 30.2 | 13.1 | 33.9 | 15.0 |
| Wall time of that same sync | 30.1 | 33.9 | 33.5 | 37.6 |
| `Datum.synchronize`, 3 types ×1,000 items, 20 pending, 2 ms remote round-trip | 106.6 | 100.2 | 105.3 | 101.1 |

### SQLite adapter

| Case | JIT before | JIT after | AOT before | AOT after |
|---|---:|---:|---:|---:|
| `createAll` 3,000 | 1010.4 | 23.0 | 1038.7 | 26.8 |
| `readAll(userId)` ×50 (user owns 10% of 20,000 rows) | 465.1 | 443.5 | 485.2 | 462.1 |
| `watchCount` during a 200-write burst | 79.5 | 75.4 | 66.7 | 66.5 |
| Enqueue 1,000 pending ops, then dequeue all | 762.2 | 770.9 | 691.8 | 730.6 |

### Hive adapter

`datum_hive` became pure Dart in this change, so `main` can't run under the
Dart VM. To compare like with like, the first two columns were both measured
with `flutter test` (mean of 5 runs).

| Case | Before (`flutter test`) | After (`flutter test`) | After (Dart VM, JIT) | After (AOT) |
|---|---:|---:|---:|---:|
| Enqueue 1,000 ops | 2093.4 | 171.2 | 23.7 | 24.1 |
| Dequeue 1,000 ops | 2034.8 | 131.2 | 24.5 | 24.8 |

### Reading the numbers

- **Stall versus wall time.** The content rehash for stores of 500 or more
  items now runs on a background isolate. That halves the longest freeze of the
  calling (UI) isolate. Copying the data to the isolate adds about 4 ms of wall
  time, which is the deliberate trade.
- **Global sync.** The saving is per-manager metadata round-trips: one cycle
  per manager instead of two. It grows with real network latency and with the
  number of registered types.
- **AOT can be slower than JIT** here. Cases dominated by JSON and SHA-256
  work benefit from the JIT's runtime-specialized code. Compare like with like.
- **SQLite pending-queue cost** is dominated by JSON-encoding each op's payload.
  Its slower AOT mean (691.8 → 730.6) is within the run-to-run spread for that
  case (up to 54 ms stdev).
