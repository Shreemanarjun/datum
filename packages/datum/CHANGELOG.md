# 1.1.0

All changes below are additive and backward compatible unless noted.

## 🧬 Typed schemas & auto-migration (no codegen)

- **`DatumFieldSpec<E, V>`**: a full runtime field descriptor that IS-A
  `DatumQueryField` — typed query refs (`whereField`/`orderByField`/Filter
  helpers) plus a `codec`, `sqlType`, `defaultValue`, and a `renamedFrom`
  rename hint. `DatumFieldCodec` ships inferred primitive codecs, lenient
  DateTime (ISO-8601 and epoch-ms decode), `durationMicros`, `uri`,
  `bigInt`, `enumByName`, `jsonObject`, and a `.nullable` wrapper.
- **`DatumSchema<E>`**: declare each entity's serialized shape once
  (`datumCoreFieldSpecs<E>()` provides the six sync fields with overridable
  keys). Powers cast-free map reads (`schema.reader(map)` /
  `schema.decode` with field-named `SchemaReadException`s), optional
  `toMap` delegation, derived SQLite columns (`sqlColumns()`), and a
  stable declaration `fingerprint`.
- **Auto-migration**: `DatumConfig(schema:, autoMigrate: true)` reconciles
  the store's actual shape with the declaration during `initialize()` —
  after the manual `SchemaMigration` chain, never touching the stored int
  schema version. Missing fields are added and backfilled with their
  defaults (fail-fast when a non-nullable field has none), renames follow
  `renamedFrom:` hints without data loss, and undeclared columns are kept
  and warned about unless `autoMigrateDropColumns: true`. Real
  `ALTER TABLE`/`UPDATE` in one transaction on SQL adapters (introspected
  via `PRAGMA table_info` through `rawQuery`); snapshot-protected raw-map
  rewrites on schemaless stores. A stored fingerprint
  (`SchemaFingerprintCapable`) makes unchanged launches skip the pass
  entirely.
- **Schema-driven `diffOf` / `propsOf`**: the schema also replaces the
  hand-written `diff` and `props` boilerplate — `schema.diffOf(old, new)`
  emits a payload-only delta through the field codecs (stamping the new
  `modifiedAt`/`version`), and `schema.propsOf(entity)` feeds `Equatable`.
  Core sync fields are marked via `DatumFieldSpec.coreRole`.
- **Typed queries certified across adapters**: `whereField`/`orderByField`
  with specs produce results identical to string queries and a reference
  evaluation on every adapter (see `runTypedQueryConformanceTests` in
  `datum_test`); micro-benchmarks show ~80 ns per query build over the
  string path. The auto-migration stamp includes the drop policy, so
  enabling `autoMigrateDropColumns` later re-runs the pass instead of
  being silently ignored.
- **Typed relations**: `DatumRelationSpec<E, R>` declares `belongsTo` /
  `hasOne` / `hasMany` / `manyToMany` (via a registered pivot entity, both
  pivot keys as its field specs) with the relation name, both entity types,
  the foreign key (as a `DatumFieldSpec`), and cascade behavior bound at
  compile time. `buildRelations()` becomes `datumRelationsFor(this, [specs])`;
  eager loading uses `withRelated: [spec].names`; typed access via
  `spec.listOf`/`spec.oneOf`; typed lazy fetching via `spec.fetchListFor`/
  `spec.fetchOneFor` — resolved through the registered managers, identical
  on every adapter.
- **New capability mixins**: `SchemaFingerprintCapable` and
  `SqlSchemaCapable` (additive; existing adapters unaffected). New
  `AutoMigrationExecutor`, `diffSchema`, `SchemaRenameOperation`, and
  introspectors are exported for direct use.

## ⚡ Sync performance & scale

- **cursor-based incremental pull (delta v2)**: `CursorSyncCapable` —
  `readChanges(cursor)` returns `(items, nextCursor)` with an **opaque
  cursor**, the natural fit for changes-feed backends (Firestore tokens,
  DynamoDB streams, CouchDB sequences, monotonic counters) and immune to
  clock skew. A `null` cursor means "from the beginning", so even first
  syncs ride the feed; the cursor persists per **device** in local sync
  metadata (`customMetadata['__sync_cursor__']`) and is deliberately
  stripped from the remote metadata beacon — a foreign device adopting
  another's cursor would silently skip changes. When an adapter advertises
  both capabilities, the cursor path wins over the timestamp path.
- **incremental pull (delta sync)**: remote adapters can mix in
  `DeltaSyncCapable` and implement `readSince(since)`; the pull phase then
  fetches only rows modified since the last sync watermark instead of the
  full dataset — the biggest scalability lever for large stores. Enabled by
  default when the adapter is capable (`DatumConfig.enableDeltaSync`), with
  `deltaSyncOverlap` clock-skew tolerance (re-delivered rows are dropped by
  the strictly-newer check). The engine still pulls full for a user's first
  sync and for `detectRemoteDeletions` cycles, which need the complete
  remote id set. Prefer a server-maintained received-at column over the
  client's `modifiedAt` — see the `DeltaSyncCapable` docs.
- **metadata hash cache**: stamping sync metadata no longer re-reads and
  re-hashes the whole local dataset on cycles where nothing changed locally
  — a per-user `(hash, count)` cache is invalidated by every write
  chokepoint (manager CRUD, engine pull application, external changes,
  migrations, clears) and reused otherwise. Escape hatch:
  `DatumConfig.enableMetadataHashCache: false`.

## 🧹 CRDT compaction

- **RgaList/RgaText**: added `compacted()`/`compact()` and
  `tombstoneCount`. Compaction purges deletion tombstones (which otherwise
  accumulate forever), preserving element ids — cursor anchors stay valid —
  and the visible order exactly. Compact only at a synchronization barrier;
  the coordination contract (and the stale-replica resurrection hazard it
  prevents) is documented on `RgaList.compacted` and pinned by tests.

## ✨ Realtime / collaborative editing

- **crdt**: added `RgaList<T>` — a Replicated Growable Array (convergent
  ordered-sequence CRDT) — and `RgaText`, a collaborative text type built on
  it. Concurrent inserts/deletes on different devices merge deterministically
  (commutative, associative, idempotent), contiguous runs never interleave,
  and element/character ids provide stable anchors for remote cursors.
  Combine with `CRDTResolver`, per-device `deviceId`, and vector clocks for
  editor-grade multi-device sync; see
  `test/integration/collaborative_editor_test.dart` for the end-to-end
  reference pattern (two devices editing offline and converging, including
  the backend).

## 🗂️ Schema migrations

- **migration**: added `SchemaMigration` — declare a migration as a list of
  `ColumnOperation`s (`add` with default or computed value, `rename`,
  `remove`, `transform`, arbitrary `row` rewrite) instead of hand-written map
  surgery. Rows can be scoped by `entityType` (`__typename`) or a `where`
  predicate, and `migrate` never mutates its input, keeping the executor's
  rollback snapshot intact even for adapters that hand out live references.
- **migration**: added a native SQL migration path. `SqlMigrationGenerator`
  translates the same `ColumnOperation`s into dialect-aware DDL/DML
  (`ALTER TABLE ADD/RENAME/DROP COLUMN`, backfilling `UPDATE`s; sqlite +
  postgresql, with type inference from `defaultValue` and `sqlType`/
  `sqlExpression`/`sqlWhere` overrides), and `SqlMigrationExecutor` runs the
  chain through any `RawQueryCapable` adapter inside its transaction — every
  statement is generated and validated before anything touches the database.
  Custom operations join in by implementing `SqlConvertibleOperation`.
- **migration**: added `MigrationPlan.resolve` — validates the whole
  version chain (gaps, duplicate starting versions, backwards steps,
  overshoot) and reports every problem in one `MigrationException`.
  `MigrationExecutor.execute()` now resolves the plan up front, so a
  misconfigured chain fails fast **before** any data is read or written
  instead of mid-migration.

## 🐛 Bug fixes (sync-engine hardening)

- **soft delete is real now**: tombstones (`isDeleted: true`) are invisible
  to every default read path — `read`/`readAll`/`query`/`watchAll`/
  `watchQuery`/`watchById` (which emits null) — while the row survives
  underneath for sync; `includeDeleted: true` opts back in, and a query
  explicitly filtering on `isDeleted` is never rewritten. Tombstone
  exclusion is query PUSHDOWN, so `limit`/`offset` count live rows only.
  The tombstone delta also bumps `version` (conflict detection must see
  the delete as newer) and only carries `vectorClock` for entities that
  serialize one (a phantom clock column threw under `strictColumns`).
- **delta-sync watermark derives from the data, not the clock**: the pull
  phase stages the newest remote `modifiedAt` it saw and persists it as
  `serverTimestamp` (previously never populated — the effective watermark
  was this device's wall clock stamped at END of cycle, so clock skew or a
  long push phase silently and permanently skipped rows).
- **per-entity push ordering barrier**: a retryably-failed operation now
  blocks later queued operations for the same entity within the cycle —
  previously newer ops overtook the failed one and its replay next cycle
  regressed the remote (lost updates) or resurrected deleted entities.
- **batch push failures fall back to per-operation processing**: one
  already-deleted id (`EntityNotFound`) or one rejected entity no longer
  discards sibling operations that were never individually attempted.
- **staged pull state can't outlive an aborted cycle**: an incremental-pull
  cursor (and watermark) staged by a pull that failed or was interrupted is
  discarded, and a push-only cycle never persists staged pull state — the
  rows behind a stale cursor would never have been fetched again.
- **change-echo dedupe keys on content, not entity id**: the manager now
  fingerprints its own writes (id + version + modifiedAt) so the adapter's
  echo is dropped (no re-run of pre-save middleware — non-idempotent
  transforms double-encrypted — and no duplicate queue ops), while a
  genuine external change arriving within the cache window is applied
  instead of being discarded as a "duplicate".
- **CRDT convergence hardening**: `RgaList.merge` resolves same-id node
  collisions deterministically (compaction against a stale replica, or two
  devices editing a document deserialized without their own `replicaId`,
  previously diverged PERMANENTLY); `toMap` serializes nodes in canonical
  order and no longer smuggles the creator's `replicaId` (converged
  replicas now serialize byte-identically, ending conflict-detection
  ping-pong); `ORSet` gains a faithful format-2 wire encoding (the legacy
  format stringified elements into JSON keys — non-String types crashed or
  collided; legacy payloads still decode); `PNCounter.fromMap` tolerates
  doubles; `CRDTResolver` resolves deletion conflicts content-preservingly
  instead of aborting forever, and flags a degraded default merge
  (`=> other`) in the resolution message.
- **relation stitching integrity**: `InMemoryLocalAdapter` returns fresh
  instances per read, so `withRelated` stitching can no longer write
  relation state into the stored copy (stale memoized `fetch()` lists);
  `RelationLoader` falls back to the parent entity's userId when the caller
  passed none, so stitching never attaches other users' rows.
- **per-listener watch semantics**: `watchAll`/`watchQuery`/`watchById` on
  the in-memory adapter (and SQLite/Hive — see their changelogs) deliver a
  current snapshot to EVERY listener, honor `includeInitialData: false`,
  and no longer starve a second concurrent listener; certified by the new
  `runWatchConformanceTests` kit in `datum_test`.
- **cascade planning is user-scoped**: relation traversal queried across
  ALL users, so another user's rows sharing foreign-key values could
  restrict-block a delete of data they don't own, and entered plans whose
  execution (correctly user-scoped) then failed spuriously. All four
  relation branches now scope by the requesting user.
- **`CascadeOptions.timeout` actually fires**: the elapsed-time check
  compared a start time captured the same instant inside the loop
  (always ≈ 0), so the timeout could never trigger.
- **in-memory matcher handles `bool` like SQL (0/1)**: Dart's `bool` isn't
  `Comparable`, so sorting by a bool field silently no-oped and ordering
  filters (`isGreaterThan` etc.) excluded every row — while SQLite sorted
  and compared 0/1. Matcher and SQL paths now agree.
- **SQL converter correctness**: LIKE values are escaped (`%`/`_` in a
  `contains:` value matched as wildcards instead of literals, with an
  `ESCAPE` clause now declared), `OFFSET` without `LIMIT` no longer emits
  invalid SQLite syntax (`LIMIT -1` is added), and an empty
  `CompositeFilter` renders `1=1`/`0=1` instead of the syntax error `()`.
- **query cache keys are collision-free**: the key ignored the query's
  `logicalOperator`, the CONTENTS of nested `CompositeFilter`s, and
  `nullSortOrder` — with `enableQueryCache: true`, an OR query could be
  served the cached results of the AND query over the same filters.
- **vector clocks only advance for local edits**: `push()` incremented
  this device's clock component even for `DataSource.remote` saves (the
  realtime change-stream path), so merely observing another device's edit
  claimed a causal step and made every later legitimate remote update look
  concurrent — spurious conflicts, and lost updates under local-leaning
  resolvers.
- **cascade delete honors `setNull` on the plain path**: `cascadeDelete()`
  hard-deleted `HasMany`/`HasOne` children marked
  `CascadeDeleteBehavior.setNull` instead of patching their foreign key to
  null — only the fluent `deleteCascade(...).execute()` path handled the
  update steps. Both paths now detach identically, and detached rows are
  no longer counted in `deletedEntities`.
- **cascade plans no longer read stale relationship caches**: the
  relationship-query cache can't observe writes made through *other*
  managers (its keys don't reference child ids), so a `restrict` blocker
  that was deleted through its own manager still blocked the retry, and
  cascades could plan against rows that no longer existed. Every
  `buildCascadeDeletePlan` now starts from a fresh view; the cache still
  dedupes lookups within a single plan build.
- **conflict detection**: equal-version concurrent edits are now detected.
  Two devices that each bumped the same ancestor (v1 → v2) produce identical
  version numbers with divergent content — the most common concurrency
  signature when entities carry no vector clocks. Previously this returned
  "no conflict", the pull path kept the local silently, and the LWW winner
  was stranded on its own device forever (permanent split-brain, found by
  the `datum_test` convergence fuzz suite). The detector now flags it as
  `bothModified`; identical re-delivered rows short-circuit cheaply.
- **LastWriteWinsResolver**: exact `(version, modifiedAt)` ties with
  divergent content now break by a deterministic payload comparison instead
  of preferring `local` — the old bias made each device elect ITSELF,
  resolution pushes ping-ponged between replicas, and the fleet never
  converged (also found by the convergence fuzz suite).
- **in-memory adapter**: fixed a race in the `watch*` streams — the change
  subscription attached only after the awaited initial read, so a write
  landing in that window was silently missed by new watchers. The
  subscription now attaches synchronously on listen.
- **isolate sync**: `useIsolateSync: true` never actually worked — the
  `Isolate.run` closure referenced the manager's class type parameter, and
  Dart closures capture `this` to reach instance type arguments, so the send
  always failed with `ArgumentError` (unsendable stream controllers) before
  the isolate spawned. The spawn now goes through a top-level trampoline
  whose own type parameter carries `T`, and isolate sync completes with
  sendable adapters. Note that `Isolate.run` deep-copies the adapter graph:
  in-memory adapters' writes stay in the isolate; storage-backed adapters
  (Hive/SQLite/network) persist normally.

- **metadata**: replaced the hardcoded `'testhash'` placeholder with a real
  order-independent content hash. The sync-skip check had degraded to a bare
  count comparison, so a remote content change that kept the entity count
  identical was never pulled and devices diverged permanently.
- **request strategy**: rewrote `SequentialRequestStrategy` without
  `async_queue`. The old implementation assumed `queue.retry()` throws on
  exhaustion (it doesn't), could hang `synchronize()` futures forever, shared
  one global queue across every default-config manager (const canonicalization)
  and stopped it for everyone on `dispose()`. `retryCount` now actually works
  and defaults to 0 (matching real shipped behavior).
- **cancellation**: pausing mid-sync now returns `wasCancelled: true`, keeps
  the `paused` status, and skips the metadata stamp — a truncated cycle was
  previously reported as a fully successful sync.
- **timeout**: `config.syncTimeout` / `options.timeout` is now enforced (it was
  configured everywhere but never applied); a hung remote surfaces a typed
  `DatumExceptionCode.timeout` and fails the status.
- **conflicts**: `takeLocal`/`merge` resolutions now queue a push of the winner
  so the remote converges (the same conflict previously re-fired forever and
  merged values never reached other devices); `takeRemote` honors a
  resolver-transformed `resolvedData`; `abort`/`askUser` are no longer counted
  and reported as resolved; deletion-conflict resolutions increment
  `conflictsResolved`.
- **batching**: a retryable batch failure re-queues its operations with
  `retryCount + 1` instead of permanently dropping the whole batch (a single
  offline blip during a batched push previously lost every operation in it).
- **isolate sync**: `useIsolateSync` config sanitization actually clears
  unsendable callbacks now (`copyWith(x: null)` keeps the old value) via
  `DatumConfig.sanitizedForIsolate`.
- **testing**: added a real local HTTP sync-server harness
  (`test/harness/local_sync_server.dart` + reference `HttpRemoteAdapter`) with
  fault injection (latency, 5xx/4xx, severed sockets, offline, version
  conflicts, corrupted payloads) and 28 scenarios covering transport edge
  cases, multi-stream consistency, leak/timer hygiene, cache boundedness, and
  soak/lifecycle-churn stability.
- **sync**: the metadata skip pre-check now degrades to a full sync when the
  remote metadata fetch fails transiently (previously an unprotected read
  failed the whole cycle before it started).
- **sync**: a failed **remote** metadata beacon write no longer fails an
  otherwise-successful cycle (it is an optimization rewritten by the next
  successful sync); a failed **local** metadata write still surfaces.
- **relations**: `HasOne.fetch()` now queries the child by its **foreign key**
  (mirroring `HasMany` and the eager-loading stitcher); it previously looked
  the child up by primary id equal to the parent's key, returning null unless
  the ids coincidentally matched.
- **metadata**: a push-only sync no longer stamps the local metadata with its
  own content hash (which fabricated a "local == remote" match and caused the
  next sync to skip unpulled remote changes); the remote still receives the
  change beacon so other devices pull.
- **strategy**: `ParallelStrategy(failFast: true)` now waits for
  already-dispatched sibling operations to settle before rethrowing, so no
  writes continue in the background after a sync reports failure.
- **errors**: the manager's sync error path delegates to
  `SyncErrorHandler.handleManagerSyncErrorSync`, preserving the original stack
  trace (previously dropped by a bare `throw e.originalError`).
- **misc**: global sync result accumulates pull failures/conflicts uniformly
  across directions; `DatumSyncStartedEvent` reports the fresh pending count;
  global observers receive `onSyncEnd` on failed syncs; `ExponentialBackoff`
  clamps instead of overflowing negative; `ParallelStrategy(batchSize <= 0)` no
  longer loops forever; cold-start guard is claimed before its awaited check
  (TOCTOU); `pauseSync`/`resumeSync` hardened; `CascadeDeleteResult`/
  `ColdStartConfig`/`ColdStartStrategy` are now exported (public API types that
  were unnameable).

## 🐛 Bug fixes

- **config**: `DatumConfig.copyWith<T>()` no longer drops the global
  `defaultConflictResolver` (and `defaultSyncOptions`) when deriving a
  per-entity config. A base-typed resolver is now adapted via
  `TypeAdaptedConflictResolver` instead of being silently nulled.
- **read**: `read()` no longer caches negative (absent) results, so data that
  arrives later via sync/realtime is observed instead of returning a stale null.
- **query**: local query caching is now **off by default** (`enableQueryCache`),
  fixing stale/mutated results and broken reactive updates. Opt in if needed.
- **sync**: the pull phase no longer blindly overwrites local data when a
  `vectorClock` is null — it falls back to version, then `modifiedAt`, avoiding
  redundant writes and sync noise.
- **sync**: `pauseSync()`/`resumeSync()` reliably restore auto-sync timers
  (hardened against the `stopAutoSync()` clear side-effect).
- **generator**: fixed `fromMap` timestamp key mismatch (snake_case with a
  camelCase fallback) and removed the redundant duplicate key lookup.
- **generator**: `copyWithAll` and `fromMap` now only pass real constructor
  parameters, so entities with initializer-derived fields (e.g. `: userId = id`)
  generate valid code.

## ✨ Features

### Merged from the unpublished 1.0.5

- **generator**: granular `@DatumIgnore` flags — `copyWith:`, `equality:`,
  `fromMap:`/`toMap:` let runtime-only state (e.g. a `ValueNotifier`) live
  inside entities without breaking immutability or equality. Backward
  compatible with bare `@DatumIgnore()`.
- **relations** *(breaking vs 1.0.4)*: `ManyToMany` takes a `Type` for the
  pivot entity instead of an instance, removing the const zero-argument
  constructor requirement on pivot entities.

- **query**: `DataFetchStrategy` (`localOnly`/`remoteOnly`/`localFirst`/
  `remoteFirst`) via `manager.fetch(...)` and `manager.fetchById(...)`, with an
  optional `persistRemoteResults` cache-fill.
- **relations**: nested eager loading with dot notation, e.g.
  `withRelated: ['posts.author']`.
- **relations**: instance-free relation schema (`DatumRelationSchema` +
  `RelationDescriptor`) so adapters can traverse relations by type alone.
- **relations**: `relatedList<R>('posts')` / `relatedOne<R>('author')` typed
  accessors, and `preserveRelationsFrom(...)` to keep in-memory relation
  references across a `copyWith`.
- **query**: adapter-aware raw queries (`DatumRawQuery` + `RawQueryCapable` +
  `manager.rawQuery(...)`) for projections/aggregations without hydration.
- **manager**: `exists(id)` and `count({query})` convenience methods.
- **errors**: sealed `DatumError` type + `tryRead`/`tryPush`/`tryQuery`/
  `tryDelete`/`trySynchronize` result-returning API (no try/catch needed).
- **query**: type-safe field selectors (`DatumQueryField` +
  `whereField`/`orderByField`).
- **logging**: pluggable `DatumLogSink` (redirect logs without subclassing).
- **adapters**: shipped `InMemoryLocalAdapter`, a reusable `DatumQueryMatcher`,
  and capability markers (`WatchableAdapter`, `TransactionalAdapter`,
  `RawQueryCapable`, …).
- **sync**: opt-in remote-deletion detection (`detectRemoteDeletions`) with a
  `DatumConflictResolution.deleteLocal()` resolution.
- **sync**: `excludedSyncUserIds` to keep local-only/system users out of sync.
- **sync**: `DatumSyncOperation.entityTable` for deterministic multi-entity
  pending stores.
- **generator**: `@DatumSerializable(strictNullChecks: true)` opt-in so missing
  non-nullable primitives surface instead of being silently defaulted;
  `generateMixin` now defaults to `true`.
- **perf**: order-independent `hashEntitiesUnordered` + O(1) incremental
  `DatumRollingHash` (~420× faster set-hash updates than a full rehash).
- **relations**: `withRelated` now eager-loads all four relation kinds
  (`HasOne`/`ManyToMany` added); reactive `watchAll`/`watchQuery` accept
  `withRelated`; hand-written entities can use the `MemoizedRelations` mixin.
- **manager**: `exists`, `count`, `deleteMany`, `trySaveMany` conveniences;
  `query` now defaults to `source: DataSource.local`.
- **streams**: reactive `watch*` methods return **non-null** streams (empty when
  the adapter isn't watchable).
- **errors**: `Datum.initialize` returns `DatumEither<DatumError, Datum>`
  (typed failure); `DatumError implements Exception`; `DatumEither` gains
  `success`/`failure` getters.
- **debug**: `DatumSyncResult.describe()` and `DatumHealth.describe()`
  for readable logging; `DatumConfigPresets.custom(...)` exposes the newer flags;
  typed relation accessors `relatedList<R>()` / `relatedOne<R>()`.
- **manager**: `trySwitchUser` / `tryCascadeDelete` result-returning variants.
- **exports**: `CascadeDeleteResult` / `CascadeResult` / `CascadeDeleteBuilder`
  are now exported (public return types were previously unnameable).
- **docs**: new `doc/API_GUIDE.md` covering querying, relations, results/errors,
  and configuration.

See `doc/ADAPTERS_AND_MIGRATIONS_GUIDE.md` (Drift/Isar/migrations) and
`doc/API_DESIGN_AND_TESTING_PLAN.md` for details.


# 1.0.4

## 🐛 Bug Fixes

- **auto-sync**: fix stopAutoSync() incorrectly clearing _pausedAutoSyncUserIds
  - Fixed an issue where `stopAutoSync()` was incorrectly clearing the `_pausedAutoSyncUserIds` set, which prevented auto-sync restoration after pause/resume cycles
  - This ensures that paused user IDs are properly maintained when stopping auto-sync, allowing correct restoration of auto-sync state when resumed
  - Thanks to [@vipwpcom](https://github.com/vipwpcom) for the bug report and test

## 📚 Documentation

- **dartdoc**: fix unresolved documentation references
  - Fixed `remoteAdapter.getSyncMetadata` → `RemoteAdapter.getSyncMetadata`
  - Fixed `resubscribeToRemoteChanges` → `DatumManager.resubscribeToRemoteChanges`
  - Fixed `unsubscribeFromRemoteChanges` → `DatumManager.unsubscribeFromRemoteChanges`
  - Fixed `AdapterHealthStatus.ok` → `AdapterHealthStatus.healthy` (2 instances)
  - All dartdoc warnings resolved (0 warnings, 0 errors)

## ⚡ Improvements

- **dependencies**: move flutter_test to dev_dependencies
  - Moved `flutter_test` from dependencies to dev_dependencies in pubspec.yaml
  - Improves package compatibility and pub.dev score (now 150/160 points)
  - Package can now be analyzed without requiring Flutter SDK for consumers

# 1.0.3

## 🚀 Relational Data Enhancements
- **Eager Loading**: Support `withRelated` in `read()` and `readAll()` to solve N+1 query problems.
- **Advanced Cascade Controls**: More granular deletion behaviors (e.g., `SetNull`) and visualization of delete plans.
- **Transactional Relationships**: Atomic saves for entities and their pivot/related records.

## ⚡ Performance & Scaling
- **Batch Operations**: Support for batch push/pull in adapters and sync engine (Includes comprehensive test suite with 14 edge case scenarios and 100% pass rate)
- **LRU Cache**: Size-limited caching in `DatumManager` to prevent memory bloat.
- **Full Isolate Syncing**: Offloading the entire synchronizer to a background Isolate.

## 🔄 Advanced Sync Logic
- **Conflict Resolution Strategies**: Initial support for CRDT-based merging implemented via `VectorClock` and `DatumEntityInterface.merge()`.
- **Vector Clocks**: Implemented for complex multi-device conflict detection and causality tracking (moving beyond simple version numbers).

## 🛠 Developer Experience (DX)
- **Code Generation**: Automated `toDatumMap`, `fromMap`, `diff`, and `copyWith` using `datum_generator`.

# 1.0.2

## 🐛 Bug Fixes

- **core**: prevent direct usage of DatumEntityInterface
  - add checks to prevent using DatumEntityInterface directly in manager and query methods
  - throw ArgumentError with a descriptive message if DatumEntityInterface is used directly
  - add test cases to ensure ArgumentError is thrown when using DatumEntityInterface directly

- **datum-manager**: add error handling to post-fetch transforms
  - Prevent entire read/watch operations from failing when individual entity transforms throw errors. Log errors and use original entities instead, improving robustness in DatumManager methods like readAll, watchAll, watchById, and watchQuery.

## ✨ Features

- **core**: add refreshStreams method to Datum singleton
  - Add refreshStreams() method to Datum.instance that clears caches and forces all reactive streams across all managers to re-evaluate their data. This ensures streams show the most current data after external state changes like user switches. Includes proper logging and error handling.

- **datum-manager**: add refreshStreams method to DatumManager
  - Add refreshStreams() method to DatumManager that clears internal caches (query, relationship, entity existence) and forces reactive streams to emit fresh data. Useful for cache invalidation when external systems modify data that Datum isn't aware of. Includes proper logging and cache management.

- **core**: add userChangeStream to Datum singleton
  - Add userChangeStream property to Datum.instance that emits when the active user changes. This enables reactive queries and UI updates when users switch in multi-tenant applications. The stream emits the new user ID or null when logging out.

- **adapter**: add realtime watch methods for Supabase adapter
  - Implement watchAll and watchById methods to enable real-time data watching via Supabase RealtimeChannel. These methods allow subscribing to changes in the table, fetching initial data, and emitting updates on changes, improving data synchronization for user-specific or all records. Includes proper error handling, logging, and channel management

- **hive_adapter**: add reactive user change support to watchAll method
  - Add optional userChangeStream parameter to HiveLocalAdapter constructor and enhance watchAll method to emit updated data when the active user changes. This enables reactive queries that filter and refresh data based on user ID switches, improving app responsiveness in multi-user environments. Includes error handling and proper stream management.

# 1.0.1

## ✨ Features

- **core**: add connectivity monitoring and auto-sync
  - Introduces a new feature that monitors the device's connectivity status and automatically triggers a sync when connectivity is restored.
  - This ensures that any pending operations that were queued while offline are automatically synchronized once the device is back online.
  - Fixes an issue where users had to manually trigger a sync after regaining connectivity.
  - Adds a new deleteBehavior option to the DatumConfig to allow developers to choose between soft and hard deletes. Soft deletes mark items as deleted locally and queue a delete operation, while hard deletes immediately remove the item from local storage.
  - Adds a HiveDatumPersistence class to the example app to demonstrate how to use Hive for data persistence.

- **delete**: add optional behavior parameter to delete methods
  - added DeleteBehavior? behavior parameter to delete and deleteAndSync methods in Datum class, allowing per-operation override of global delete behavior
  - updated method documentation to explain the new parameter
  - improved dispose method to safely handle instance checks and nullify the singleton instance
  - enhanced test setup in background_sync_test.dart with proper mocking of ConnectivityChecker
  - added error handling in integration test for Datum.initialize to catch and report failures

## 🐛 Bug Fixes

- **datum**: revert default delete behavior to hard delete
  - revert default deleteBehavior to hardDelete in DatumConfig
  - update tests to explicitly use soft delete where needed

# 1.0.0

## 🗑️ Breaking Changes
- **core**: Removed deprecated `pause()` and `resume()` methods from `DatumManager` and `Datum` classes - use `unsubscribeFromRemoteChanges()` and `resubscribeToRemoteChanges()` instead

## ✨ Core Library Features
- **Entity System**: Enhanced entity definitions with interfaces and mixins for more flexible implementations
- **Sync Engine**: Added initial sync on user authentication, metadata comparison for optimized syncing, device tracking, and improved error handling
- **Auto-sync**: Enhanced auto-sync functionality with better scheduling and management
- **Configuration**: Added default sync options and remote metadata access
- **Logging**: Advanced logging features with performance monitoring and sampling
- **Cold Start Manager**: Major architectural improvements to cold start synchronization including per-user state isolation, configurable retry logic with exponential backoff, pluggable persistence interface, enhanced error handling and recovery, and comprehensive testing. Replaced static state with instance-level per-user state management to prevent race conditions and enable proper multi-user support. Added retry policies, error recovery mechanisms, and extensible persistence layer for custom storage solutions.
- **Cascading Delete**: Major enhancements to cascading delete functionality including dry-run mode, progress callbacks, cancellation support, timeout protection, and improved error handling. Added comprehensive dry-run capabilities for safely previewing deletion operations before execution. Enhanced cascading delete integration tests with 48 total test cases covering complex relationship scenarios, mixin usage patterns, restrict violations, and edge cases.

## ♻️ Refactors
- **Entity Handling**: Improved entity mixins and relational detection
- **Sync Performance**: Batch processing, performance monitoring, and enhanced error boundaries
- **Concurrent Operations**: Better handling of concurrent sync operations

## 🐛 Bug Fixes
- **Sync Engine**: Fixed return values and unused variables in tests
- **Cascading Delete**: Removed unused `_CascadeDeleteStep` and `_CascadeDeletePlan` classes and fixed method call in `CascadeDeleteBuilder.execute()`

## 📖 Documentation
- **API Documentation**: Enhanced documentation for Datum singleton API, sync patterns, and troubleshooting guides

_Medium Priority (Next Release):_

1. Parallel execution
2. Progress callbacks
3. Relationship caching
4. Rollback capability

# 0.0.13
- fixed type casting error in `initialize()` method in Datum


# 0.0.12

## ✨ Features

- **core**: Add stacktrace to DatumEither
  - The `Failure` class now includes an optional `StackTrace` property.
  - The `fold` method in `DatumEither` now passes the `StackTrace` to the `onFailure` callback.
  - The `onFailure` method now accepts a `StackTrace` parameter.
  - The `getError` method now returns a tuple containing the error value and the stack trace.

- **core**: Bring back getSuccess method
  - Added the `getSuccess` method back to the `DatumEither` class.
  - This method returns the success value if the `DatumEither` is a `Success`, otherwise it throws a `StateError`.

## ♻️ Refactors

- **core**: Remove isSuccess and isFailure methods
  - Removed the `isSuccess` and `isFailure` methods from the `DatumEither` class.

- **core**: Use switch statement instead of if statement
  - Refactor the `onSuccess`, `onFailure`, `getSuccess`, `getError`, `successOrNull`, and `errorOrNull` methods to use switch statement instead of if statement.

# 0.0.11

## ✨ Features

- **core**: introduce DatumEither for initialization result
  - Use DatumEither to handle potential errors during Datum initialization
  - Return Success or Failure based on the outcome of the initialization process
  - Update related code to handle the new DatumEither return type
  - Add DatumEither model for typing success or failure.

# 0.0.10

## ✨ Features

- **Batch Operations**: Added `createMany` and `updateMany` methods for performing batch create and update operations.
- **Lifecycle Management**: Implemented `DatumProviderWithLifecycle` widget to manage Datum's lifecycle based on app state.
- **Flexible Entity Implementation**: Introduced `DatumEntityMixin` and `RelationalDatumEntityMixin` to allow for more flexible entity implementation without requiring inheritance from a base class.
- **Schema Versioning**: Added `schemaVersion` property to `IsolatedHiveLocalAdapter` for easier schema migration.
- **Type Comparison**: Added a `sameTypes` method for type comparison.
- **Dependencies**: Added `equatable` dependency for easier object comparison.

## 🐛 Bug Fixes

- **Logging**: Removed unnecessary debug logs from `tasksStreamProvider`.
- **Initialization**: Ensured managers are initialized before `saveMany` operations.
- **Memory Leaks**: Improved stream handling in `SupabaseRemoteAdapter` to prevent memory leaks.
- **Error Handling**: Improved type safety and error handling in `fetchRelated` methods.

## ♻️ Refactors

- **Background Sync**: Enhanced `SupabaseRemoteAdapter` with `resubscribeToChanges` and `unsubscribeFromChanges` methods for better background sync and lifecycle management.
- **Entity Handling**: Updated `DatumEntityBase` and related classes for better sync and versioning.
- **Adapters**: Updated `HiveLocalAdapter` and `SupabaseRemoteAdapter` to use `DatumEntityBase` instead of `DatumEntity`.
- **Task Entity**: Refactored the `Task` entity to use `DatumEntityMixin`.
- **Sync Execution**: Updated the default sync execution strategy to `parallel`.
- **Data Serialization**: Enhanced data serialization for local and remote persistence.

## 📖 Documentation

- **Datum Class**: Enhanced `Datum` class documentation for clarity and improved usage examples.
- **Sync Options**: Enhanced `DatumSyncOptions` documentation for better clarity.
- **General**: Improved overall documentation for clarity.

## ✅ Tests

- **Background Sync**: Added tests for background sync functionality.

# 0.0.9

## ✨ Features

### Core

- **Implement Sync Request Strategies**: Introduced a new system to control how concurrent calls to the `synchronize` method are handled, preventing race conditions and improving data consistency.
  - Added `DatumSyncRequestStrategy` as the base for defining execution behavior.
  - Implemented `SequentialRequestStrategy` to queue and process all `synchronize` calls in the order they are received. This is the new default behavior.
  - Implemented `SkipConcurrentStrategy` as an alternative strategy to ignore new `synchronize` calls if a sync is already in progress.
  - Added `syncRequestStrategy` to `DatumConfig` to allow global configuration of this behavior.
  - Added an `isSyncing` getter to `DatumSyncEngine` to check the current sync status.

## 🐛 Bug Fixes

### Build

- **Correct Conditional Imports**: Fixed conditional imports to ensure compatibility across both `dart:io` and `dart:html` environments.


## 0.0.8
- fix conditional import for web and io

## 0.0.7

### 🐛 Bug Fixes

- **🐛 Isolate Error Handling & Web Compatibility**:
  - Ensured errors during isolate operations are properly caught and sent back to the main thread.
  - Enhanced web compatibility by using `compute` function for isolate operations.
  - Removed unnecessary newline at end of file for consistency.
  - Removed unused import in `supabase_security_dialog.dart`.

## 0.0.6

### 🚀 Features

- **🚀 Isolate Sync Strategy**: Introduced a new `IsolateStrategy` that runs data synchronization in a background isolate for improved performance and UI responsiveness. This includes platform-specific runners for both mobile/desktop (`dart:io`) and web (`dart:html`) via conditional imports, ensuring broad platform support.
- **✨ Sealed Class Migration**: Migrated `DatumEntity` and `RelationalDatumEntity` to a `DatumEntityBase` sealed class for enhanced type safety and to remove the need for `sampleInstance`.
- **🚀 New Facade Methods**: Added a suite of new methods to the global `Datum` facade for easier data interaction:
  - **Reactive Watching**: `watchAll`, `watchById`, `watchQuery`, `watchRelated`.
  - **One-time Fetching**: `query`, `fetchRelated`.
  - **Data & Sync Management**: `getPendingCount`, `getPendingOperations`, `getStorageSize`, `watchStorageSize`, `getLastSyncResult`, `checkHealth`.
  - **Sync Control**: `pauseSync`, `resumeSync`.

### ✅ Tests

- **🧪 Enhanced Core Tests**: Added test cases for uninitialized state errors, `statusForUser`, `allHealths`, and relational method behavior. Introduced a `CustomManagerConfig` for easier mock manager injection in tests.

### ♻️ Refactors & 🧹 Chores

- **♻️ Isolate Helper Improvements**:
  - Replaced conditional imports with platform-specific implementations.
  - Removed `isolate_helper.dart` and `isolate_helper_unsupported.dart`.
  - Added `_isolate_helper_io.dart` for IO platforms.
  - Updated `_isolate_helper_web.dart` to use synchronous JSON encoding.
  - Updated `datum_sync_engine.dart` to use the new isolate helper.
  - Removed unused imports in `test.dart`, `adapter_test.dart`, `relational_data_test.dart`, `relational_data_integration_test.dart`, `mock_adapters.dart`, and `test_entity.dart`.
  - Updated `isolate_helper_test.dart` to use the new isolate helper.
- **🗑️ Removed `sampleInstance`**: The `sampleInstance` property on `LocalAdapter` is no longer needed due to the sealed class migration and has been removed.
- **🩺 Renamed `AdapterHealthStatus.ok`** to `AdapterHealthStatus.healthy` for better clarity.
- **📦 Refactored internal imports** to use the `datum` package consistently.
- **⚙️ Made `MigrationExecutor` generic** to improve type safety during migrations.
- **🗺️ Added `DataSource` enum** to explicitly specify the source for query operations.

## 0.0.5
- Add docs link



## 0.0.4

### Features

- Added support for funding and contributions.

### Documentation

- Added `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
- Updated `README.md` with funding and contribution sections.
- Updated `README.md` to mention future support for multiple adapters for a single entity.

### Chores

- ✨ chore(analysis): apply linter and formatter rules
- enable recommended linter rules for code quality
- set formatter rules for consistent code style
- ignore non_constant_identifier_names error

## 0.0.3
- 📝 docs(readme): enhance architecture diagrams in README

- update architecture diagrams for better clarity
- improve image display using <p> tag for alignment


## 0.0.2
- Update readme to add images correctly


## 0.0.1
- Initial release 🎉
