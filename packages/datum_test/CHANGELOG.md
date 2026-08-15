## 0.1.0

- Initial release.
- `runAutoMigrationConformanceTests` — certifies the `DatumSchema` auto-migration contract against any local adapter: legacy-store reconciliation (rename-with-hint keeps values, adds backfill defaults), kept-vs-dropped undeclared columns, and fingerprint run-once across a simulated relaunch.
- `runSyncStackConformanceTests` — the full engine behavior matrix (push/pull round-trips, two-device convergence, offline queue replay, LWW conflict resolution with winner push-back, soft-delete propagation, stale-write protection, user isolation, no-op cycles, batch pushes, metadata beacons, incremental pulls) over ANY local/remote adapter pair: passing it certifies the pair as a compatible sync stack.
- `TestConnectivityChecker` — flippable connectivity for offline/replay scenarios.
- `CursorHttpRemoteAdapter` — reference implementation of cursor-based incremental pull (`CursorSyncCapable`) against the server's `/changes` feed.
- `LocalSyncServer` gained a cursor **change feed** (`GET /changes?cursor=`) and periodic chaos knobs (`failEveryNth`, `dropEveryNth`, `corruptEveryNth`, `jitter`) alongside the one-shot faults.
- `runChaosConformanceTests` + five stock `ChaosProfile`s (flaky3G, unstableSocket, proxyCorruption, captivePortal, offlineWindows) — certifies eventual convergence, drained queues, and zero loss/duplication once faults clear, with provable per-profile fault counts.
- `runCrashRecoveryConformanceTests` — persistent-storage contract: queued ops survive a crash and deliver exactly once after reopen; mid-sync severed-socket crashes recover; schema version/metadata/last-result survive.
- `runConvergenceFuzzTests` — seeded multi-device randomized workloads (create/update/soft-delete, random sync interleavings) asserting fleet-wide convergence after quiescence, in both full-pull and cursor-feed modes; failure messages carry the seed for reproduction. **The fuzz found and drove the fix for two real engine bugs** (equal-version concurrent-edit detection and the LWW tie-break split-brain).
- `runMigrationConformanceTests` — the standard migration chain over map-based or SQL executors: stamping, fail-fast on invalid chains, mid-chain rollback, resume, and relaunch run-once semantics.
- `measureAdapterPerformance` / `runAdapterPerformanceTests` — self-verifying ops/sec report per CRUD phase with optional thresholds (report-only by default).
- `runLocalAdapterConformanceTests` — 25-test behavioral contract for `LocalAdapter` implementations (CRUD, user scoping, queries, pending operations, sync state, migration raw-data fidelity, storage size, capability checks for watch/transaction/pagination).
- `runRemoteAdapterConformanceTests` — 10-test contract for `RemoteAdapter` implementations, including the `DeltaSyncCapable.readSince` watermark contract.
- `ConformanceEntity` — the standard entity adapters are certified against.
- `LocalSyncServer` — real `dart:io` HTTP sync server with fault injection (latency, failure codes, offline windows, severed sockets, version conflicts, response corruption).
- `HttpRemoteAdapter` — reference REST adapter with production-grade error mapping and incremental pull.
