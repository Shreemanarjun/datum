# Datum: API Usability & Real-Life Testing Review

Scope: what to improve next. Items already finished in `doc/UX_IMPROVEMENTS.md` and
`doc/API_DESIGN_AND_TESTING_PLAN.md` (sealed `DatumError`, `tryX`, typed query
fields, capability markers, non-null watch streams) are not repeated here.
Line numbers refer to the tree as of 2026-11-26. Other agents are refactoring `lib/`
right now, so a reference may have moved by a few lines.

Priority = impact × (1/effort). **B** = breaking, **NB** = non-breaking.

---

## P0: data loss / correctness under real conditions

### 1. Auth expiry or any non-retryable error permanently drops queued writes (NB)
- Evidence: `lib/source/core/engine/datum_sync_engine.dart:489-529`. Two cases
  dequeue the operation for good: an error that is not retryable, and an operation
  that has used up `maxRetries` (3, `datum_config.dart:286`). Default `shouldRetry`
  only returns true for `NetworkException.isRetryable` (`datum_config.dart:544-546`).
  A 401/403/429 arrives as `NetworkException(isRetryable: status >= 500)`
  (`datum_test/lib/src/http_remote_adapter.dart:94-97`), so it counts as non-retryable.
  A non-`DatumException` error (for example a raw `ClientException` from a custom
  adapter) is never retryable. The comments say "a dead-letter queue" but none exists.
- Real-life effect: a user edits offline for a day, the token expires, and every
  queued edit is silently deleted on the next sync.
- Change: never delete a failed op. Park it instead, and let auth failures pause sync.
  ```dart
  enum DatumFailureAction { retry, pauseSync, park }   // replaces bool shouldRetry
  typedef DatumFailurePolicy = FutureOr<DatumFailureAction> Function(Object error, DatumSyncOperation op);

  // manager
  Future<List<DatumSyncOperation<T>>> getParkedOperations(String userId);
  Future<void> retryParked(String userId, {Iterable<String>? ids});
  Future<void> discardParked(String userId, {Iterable<String>? ids});
  Stream<DatumAuthRequired> get onAuthRequired;   // sync stays paused until resumeSync()
  ```
  Default policy: 401/403 → `pauseSync`, 429/5xx/transport → `retry` with backoff
  and no cap on attempts, 4xx validation → `park`. Persist parked ops through the
  existing pending-op table with a `status` column, so the adapter interface does
  not grow.
- Test: run sync-stack conformance with a server that returns 401 for N requests.
  Assert 0 ops are lost, sync is paused, and after a token refresh +
  `resumeSync()` every op is delivered exactly once.

### 2. No `AuthError` case in the typed error model (NB, additive sealed case = B for exhaustive switches)
- Evidence: `lib/source/core/errors/datum_error.dart:76-81` maps
  `authenticationError`/`authorizationError` to `UnknownError`, so callers cannot
  catch "re-login needed". The HTTP status is also lost: `NetworkException`
  carries no `statusCode`.
- Change: add `final class AuthError extends DatumError` and give
  `NetworkException`/`NetworkError` an `int? statusCode`. Two hierarchies exist
  (`DatumException` with 16 subclasses, and `DatumError` with 6). Make adapters throw
  `DatumError` directly, and delete `DatumException` in the next major.

### 3. Remote writes carry no idempotency key (NB for adapters, opt-in)
- Evidence: `RemoteAdapter.create/update/delete(T)` (`remote_adapter.dart:52-82`)
  receive no operation id. Exactly-once delivery is only proven against the fake
  server's upsert semantics (`crash_recovery_conformance.dart:160`). A real
  `POST` create that times out after the server commits is replayed as a
  duplicate insert.
- Change: give writes an optional operation context. The default overloads
  delegate, so existing adapters still compile.
  ```dart
  Future<void> create(T entity, {DatumWriteContext? ctx});  // ctx.operationId, ctx.attempt
  ```
  Make `LocalSyncServer` honour an `Idempotency-Key` header, and add a chaos profile
  `ackLoss` (commit, then sever the response).

---

## P1: high-value real-life test gaps

Already covered (checked with grep): crash/restart with a persistent adapter,
including a crash in the middle of a sync, on SQLite only
(`datum_sqlite/test/sqlite_crash_recovery_test.dart:49`). Also covered: chaos
profiles flaky3G/unstableSocket/proxyCorruption/captivePortal/offlineWindows
(`datum_test/lib/src/chaos_profiles.dart`), a two-device convergence fuzz over HTTP
(`datum_test/test/convergence_fuzz_self_test.dart`), the delta watermark being
immune to local clock skew (`test/unit/sync_engine_correctness_test.dart:135`),
and isolate sync on mocks (`test/coverage/manager_coverage_isolate_sync_test.dart`).

| # | Gap | Evidence | Proposed test | Effort |
|---|-----|----------|---------------|--------|
| 4 | Hive has no crash-recovery run | only `datum_sqlite` calls `runCrashRecoveryConformanceTests` | `datum_hive/test/hive_crash_recovery_test.dart` reopening the box path | S |
| 5 | Chaos only over `InMemoryLocalAdapter` | `datum_test/test/chaos_self_test.dart:19` | run `runChaosConformanceTests` from sqlite + hive test dirs (file-backed) | S |
| 6 | Schema upgrade **with pending ops** never tested | no hit for `migrat.*pending` in any test dir | migration conformance: queue ops at v1, crash, reopen at v2 with a column add + rename, assert the queued payloads are migrated and pushed | M |
| 7 | Auth expiry mid-sync | `LocalSyncServer` can return 401 (`local_sync_server.dart:55`), but no suite asserts no-loss | see item 1 | S (after 1) |
| 8 | Long offline / large queue | no test with >1k pending ops; largest is `remoteSyncBatchSize: 10000` pull (`test/core/batch_operations_test.dart:707`) | 20k queued ops across creates/updates/deletes of the same ids; assert coalescing, ordering, peak RSS, time budget | M |
| 9 | 50k+ rows memory | none | `datum_test` bench: 50k rows sqlite + hive; `watchAll`, `count`, full sync, `ProcessInfo.currentRss` ceiling recorded in `performance_report.dart` | M |
| 10 | Cross-device clock skew for LWW | the skew test covers only the delta watermark; LWW uses device `modifiedAt` | two devices with clocks ±10 min; concurrent edit; assert the resolver uses server/HLC order, not wall clock (likely exposes a bug → consider HLC in `VectorClock`) | M |
| 11 | Watermark fallback uses device clock | `datum_sync_engine.dart:727` falls back to `lastSyncTime` = `DateTime.now()` (`:1150`) when the remote never reports `serverTimestamp` | test the delta adapter without server timestamps + device clock ahead; fix: no delta without `serverTimestamp` | S |
| 12 | Partial batch failure | `createAll/updateAll` default loops (`remote_adapter.dart:58-70`), no per-item result | chaos `failEveryNth` inside a batch; assert the succeeded items are dequeued and the failed ones are kept | S |
| 13 | Real isolate sync with a persistent adapter | isolate tests use mocks only | `useIsolateSync: true` over sqlite file + HTTP server, interleaved with UI-isolate writes | M |
| 14 | Multi-device + realtime stream over a real socket under chaos | `local_server_streams_stability_test.dart` has no fault injection | add chaos to the subscription channel; assert no missed/duplicated change after reconnect | M |

---

## P2: API usability

### 15. `userId` placement is inconsistent (B, mechanical)
- `push({item, userId?})` (`datum_manager.dart:619`) uses the item's own id when
  `userId` is omitted. `saveMany({items, required userId})` (`:812`),
  `delete({required id, required userId})` (`:1275`) and
  `deleteMany(ids, {required userId})` (`:2682`) require it. `synchronize(userId)`
  (`:1854`), `startAutoSync(userId)` (`:2160`), `getPendingCount(userId)` (`:2433`)
  and `getLastSyncResult(userId)` (`:2457`) take it positionally. `read(id, {userId?})`
  (`:841`) takes it as an optional named parameter.
  `executeCascadeDeleteWithOptions(entityId, userId, options)` (`:1486`) makes all
  three positional.
- The example still passes the redundant id: `push(item: canvas, userId: canvas.userId)`
  (`example/lib/features/paint/view/paint_canvas_list.dart:222,265`).
- Rule: entities carry `userId`, so writes infer it. User-scoped operations take
  `{String? userId}` and default to `Datum.instance.currentUserId`.
  ```dart
  Future<T> save(T item, {DataSource source = DataSource.local});
  Future<bool> delete(String id, {String? userId});
  Future<DatumSyncResult<T>> synchronize({String? userId, DatumSyncOptions<T>? options});
  ```

### 16. Generic type of `DatumSyncOptions` is erased (B, small)
- `synchronize` takes `DatumSyncOptions<DatumEntityInterface>?` (`datum_manager.dart:1856`),
  while `saveMany` takes `DatumSyncOptions<T>?` (`:818`). As a result,
  `conflictResolver: MyResolver<Task>()` is not type-checked at the call site.
  Use `DatumSyncOptions<T>` everywhere.

### 17. Batch helpers are N sequential round-trips with no atomicity (NB)
- `saveMany` (`:812-829`) and `deleteMany` (`:2682`) loop over `push`/`delete`.
  Each iteration repeats the user-switch check, a local read, a queue write and an
  event. A failure part-way leaves the batch half applied.
- Change: wrap the loop in `localAdapter.transaction` and call
  `createAll/updateAll` + one bulk enqueue. Return
  `DatumBatchResult<T>(saved, failed)` so callers do not need the separate `trySaveMany`.

### 18. Synonyms and internals leak into the public surface (B, deletion)
- Synonyms: `pushAndSync` = `updateAndSync` (`:776,797`), `cascadeDelete` /
  `deleteCascade` builder / `executeCascadeDeleteWithOptions`
  (`:1414,1481,1486`), and `query` / `fetch(localOnly)` (`:1090,1155`).
  Keep one of each: `save`, `saveAndSync`, `delete(cascade: …)`, `fetch(strategy)`.
- Leaks: `performDeleteWithoutEvents` (`:1773`) is public, ignores the `userId`
  scope and deletes rows of any user (`localAdapter.read(id)` with no userId).
  `invalidateMetadataHash` (`:131`) is also public, and `datum.dart:12` exports
  `source/core/engine/_internal.dart`. Fix: make them private or annotate them
  `@internal`, and drop the `_internal` export.

### 19. `DatumSyncScope` duplicates `DatumSyncOptions.query` (B, small)
- `datum_sync_scope.dart:18-29` wraps a single `DatumQuery`, and `synchronize`
  accepts both a scope and `options.query`. The engine treats the two differently:
  deletion detection is disabled for each by separate checks
  (`datum_sync_engine.dart:546-552`). Delete `DatumSyncScope` and keep `options.query`.

### 20. Adapter-author boilerplate (B for LocalAdapter, staged)
- `LocalAdapter` still requires roughly 25 members (`local_adapter.dart:12-287`),
  including the queue, sync metadata, schema version, raw data and last-sync-result
  storage. Every backend has to re-implement these with identical semantics.
- Change: move the queue, metadata and last-sync-result storage into a
  `DatumSyncStore` that the core owns. The core would implement it once on top of a
  tiny KV contract (`get/put/delete/scan(prefix)`). Entity adapters then only do
  CRUD + query + transaction. This removes about 10 members from each backend and
  makes item 1's `status` column a single change.

### 21. Change streams are asymmetric (B, trivial)
- `LocalAdapter.changeStream()` is a method (`local_adapter.dart:18`), while
  `RemoteAdapter.changeStream` is a nullable getter (`remote_adapter.dart:15`).
  Make both non-null getters that default to `Stream.empty()`.

### 22. Remote delta is opt-in by runtime type test (NB)
- `remote is CursorSyncCapable` / `DeltaSyncCapable` (`datum_sync_engine.dart:712,723`).
  An adapter that forgets the mixin falls back to a full `readAll` each cycle with no
  warning. Log a one-time warning when `enableDeltaSync` is true and neither mixin
  is present.

---

## Suggested order
1 → 2 → 7 (one PR: failure policy + AuthError + 401 suite), then 4/5/12 (cheap
conformance reuse), then 3, then 6/8/9/10/11, then the breaking API batch 15-21
in one major release with a migration note.
