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

## State in signals (`signals_core`), 2026-11-27

The engine's state holders (sync status, health, metadata, next sync time,
metrics) changed from rxdart subjects to `signals_core` signals. "Before" is
commit `c84704d`, the last one with subjects; "after" is the signals change on
top of it, nothing else. Apple M1 Pro, Dart 3.13.4, same `pubspec.lock` for
both.

```sh
RUNS=3,5,10 PKGS=datum tool/bench.sh c84704d
```

### 10 runs: mean / median / min / stdev, ms

| Case | Mode | Before | After | Median |
|---|---|---|---|---:|
| `push` x500 | JIT | 5.14 / 4.94 / 4.62 / 0.50 | 5.24 / 5.17 / 4.65 / 0.52 | +5% |
| `push` x500 | AOT | 5.61 / 5.48 / 5.11 / 0.52 | 5.75 / 5.60 / 5.27 / 0.46 | +2% |
| sync 500 queued creates, status watched | JIT | 6.58 / 6.64 / 6.18 / 0.20 | 6.66 / 6.67 / 6.49 / 0.10 | +0% |
| sync 500 queued creates, status watched | AOT | 6.69 / 6.63 / 6.57 / 0.15 | 6.65 / 6.61 / 6.49 / 0.16 | -0% |
| status written 10,000 times, watched | JIT | 3.78 / 3.72 / 3.65 / 0.17 | 16.24 / 16.31 / 15.28 / 0.61 | +338% |
| status written 10,000 times, watched | AOT | 4.77 / 4.75 / 4.73 / 0.07 | 6.22 / 6.11 / 5.86 / 0.34 | +29% |
| `watchAll` during a 500-write burst | JIT | 2.67 / 2.71 / 2.34 / 0.23 | 3.02 / 2.81 / 2.55 / 0.41 | +4% |
| `watchAll` during a 500-write burst | AOT | 2.61 / 2.53 / 2.34 / 0.15 | 2.62 / 2.70 / 1.31 / 0.54 | +7% |
| sync after 1 write, 5,000-item store | JIT | 33.69 / 34.19 / 31.10 / 1.89 | 35.59 / 34.95 / 31.89 / 2.73 | +2% |
| sync after 1 write, 5,000-item store | AOT | 37.38 / 37.42 / 35.80 / 1.20 | 37.71 / 37.75 / 35.84 / 1.13 | +1% |
| longest isolate stall in that sync | JIT | 10.90 / 10.51 / 10.03 / 1.15 | 13.25 / 12.29 / 11.54 / 1.81 | +17% |
| longest isolate stall in that sync | AOT | 14.51 / 14.37 / 14.07 / 0.53 | 16.89 / 14.73 / 14.32 / 6.48 | +3% |
| pull 2,000 remote items | JIT | 43.45 / 42.54 / 41.71 / 2.10 | 44.72 / 44.20 / 43.60 / 1.61 | +4% |
| pull 2,000 remote items | AOT | 44.69 / 44.75 / 43.63 / 0.68 | 46.85 / 46.86 / 45.75 / 0.69 | +5% |
| `Datum.synchronize`, 3 types x 1,000, 20 pending, 2 ms round-trip | JIT | 97.28 / 96.76 / 92.61 / 2.84 | 96.21 / 97.41 / 92.61 / 2.69 | +1% |
| `Datum.synchronize`, 3 types x 1,000, 20 pending, 2 ms round-trip | AOT | 97.91 / 97.92 / 93.99 / 2.45 | 98.97 / 99.02 / 95.30 / 2.03 | +1% |

### Median by run count (3 / 5 / 10 runs), ms

| Case | Mode | Before | After |
|---|---|---|---|
| `push` x500 | JIT | 12.09 / 6.79 / 4.94 | 11.86 / 6.54 / 5.17 |
| `push` x500 | AOT | 5.44 / 5.75 / 5.48 | 6.75 / 5.89 / 5.60 |
| sync 500 queued creates, status watched | JIT | 11.00 / 7.82 / 6.64 | 9.87 / 7.83 / 6.67 |
| sync 500 queued creates, status watched | AOT | 7.25 / 6.67 / 6.63 | 7.08 / 6.47 / 6.61 |
| status written 10,000 times, watched | JIT | 4.75 / 3.79 / 3.72 | 16.40 / 16.15 / 16.31 |
| status written 10,000 times, watched | AOT | 5.63 / 4.93 / 4.75 | 7.30 / 6.08 / 6.11 |
| `watchAll` during a 500-write burst | JIT | 3.24 / 3.13 / 2.71 | 1.96 / 3.11 / 2.81 |
| `watchAll` during a 500-write burst | AOT | 2.88 / 2.77 / 2.53 | 2.76 / 2.77 / 2.70 |
| sync after 1 write, 5,000-item store | JIT | 33.97 / 33.75 / 34.19 | 35.17 / 35.73 / 34.95 |
| sync after 1 write, 5,000-item store | AOT | 37.38 / 37.88 / 37.42 | 37.72 / 38.57 / 37.75 |
| longest isolate stall in that sync | JIT | 10.86 / 10.69 / 10.51 | 11.97 / 11.84 / 12.29 |
| longest isolate stall in that sync | AOT | 15.14 / 14.88 / 14.37 | 15.48 / 15.37 / 14.73 |
| pull 2,000 remote items | JIT | 43.85 / 44.09 / 42.54 | 45.87 / 44.87 / 44.20 |
| pull 2,000 remote items | AOT | 46.07 / 45.13 / 44.75 | 45.14 / 45.79 / 46.86 |
| `Datum.synchronize`, 3 types x 1,000, 20 pending, 2 ms round-trip | JIT | 102.45 / 99.16 / 96.76 | 102.89 / 98.60 / 97.41 |
| `Datum.synchronize`, 3 types x 1,000, 20 pending, 2 ms round-trip | AOT | 101.56 / 100.45 / 97.92 | 101.09 / 97.44 / 99.02 |

### The two builds run alternately

The script runs one tree after the other, so a slow minute of the machine
lands on one side. Here the two builds took turns (before, after, before,
after, ...), three rounds of 10 runs each; the value is the mean of the three
medians, in ms.

| Case | JIT before | JIT after | | AOT before | AOT after | |
|---|---:|---:|---:|---:|---:|---:|
| `push` x500 | 9.59 | 9.50 | -1% | 5.96 | 5.57 | -6% |
| sync 500 queued creates, status watched | 8.72 | 8.84 | +1% | 6.87 | 6.76 | -2% |
| status written 10,000 times, watched | 3.96 | 15.65 | +295% | 5.29 | 6.35 | +20% |
| `watchAll` during a 500-write burst | 3.16 | 3.06 | -3% | 2.77 | 2.77 | +0% |
| sync after 1 write, 5,000-item store | 31.88 | 33.28 | +4% | 37.11 | 37.50 | +1% |
| longest isolate stall in that sync | 12.79 | 12.00 | -6% | 15.17 | 15.01 | -1% |
| pull 2,000 remote items | 43.31 | 44.17 | +2% | 45.56 | 45.92 | +1% |
| `Datum.synchronize`, 3 types x 1,000, 20 pending, 2 ms round-trip | 101.05 | 99.86 | -1% | 100.31 | 99.82 | -0% |

### Reading the numbers

- **A sync costs the same.** One sync cycle writes its state a handful of
  times (the sync of the 5,000-item store writes 5 signals, counted with a
  `SignalsObserver`), so the state holder is not on its path. Run alternately,
  every sync case is within 2% in AOT and 6% in JIT (`push`, a local write,
  is 6% faster in AOT), some faster and some
  slower. Larger differences in the first two tables change sign with the
  run order: the longest-stall case is +17% (JIT) there, where "after" ran
  first, and -6% where "before" did.
- **A status write costs about 0.1 µs more in a release build**: +20% to +29%
  (AOT) in the case that does nothing but write the status 10,000 times with
  a listener. A signal compares the new value with the old one before it
  tells anybody, and tells nobody when they are equal; a subject did neither.
- **In a debug build a write costs about 1.2 µs more.** `signals_core`
  reports every write to DevTools in debug mode, building a log line from
  the value. That is the JIT difference (+300%): with the observer off
  (`signalsDevToolsEnabled = false`), 10,000 writes with a stream listener
  take 1.5 ms instead of 11 ms (last table). Release builds do not contain
  it.

The state holders alone, 10,000 writes of a status snapshot, best of 12, ms:

| | JIT | JIT, DevTools observer off | AOT |
|---|---:|---:|---:|
| subject, no listener | 0.07 | | 0.14 |
| signal, no listener | 9.77 | 0.51 | 0.86 |
| subject, stream listener | 0.74 | | 0.83 |
| signal, `subscribe` callback | 10.23 | 0.97 | 0.99 |
| signal, stream view (`watchSignal`) | 11.13 | 1.51 | 1.37 |
| comparing two snapshots (`==`) | 0.29 | | 0.46 |

`tool/bench.sh` now copies `pubspec.lock` into the baseline worktree. The
lock file is not in git, so a baseline used to be measured with whatever
versions resolved that day (here `async` 2.13.1 against 2.13.0).
