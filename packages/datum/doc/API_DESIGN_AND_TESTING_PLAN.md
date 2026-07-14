# Datum — API Design, Type-Safety, Extensibility & Performance Plan

**Scope:** Make the `datum` core engine (and its `datum_generator` / `datum_hive`
companions) present a well-designed, type-safe, extensible, easy-to-use API,
backed by a performance benchmark suite and a layered test strategy
(unit + integration).

**Status of this document:** living plan. **Phases 1–4 and 0 have now been
implemented** (additive, backward-compatible); the full suite is green
(datum: 1369 passing / 1 skipped; datum_hive: green) and `dart analyze
--fatal-infos --fatal-warnings lib test benchmark` is clean.

### Implementation status (landed)

| Phase | Item | Where |
|-------|------|-------|
| 1 | Sealed `DatumError` + `DatumError.from` mapping | `lib/source/core/errors/datum_error.dart` |
| 1 | `tryX` result API (`tryRead/tryReadAll/tryPush/tryQuery/tryDelete/trySynchronize`) | `datum_manager.dart` |
| 1 | Typed query field selectors (`DatumQueryField` + `whereField`/`orderByField`) | `datum_query_builder.dart` |
| 1 | Registry hardening (`tryGet`/`getByTypeOrNull`/`registerByType`; deprecated `operator []`/`[]=`) | `datum_core.dart` |
| 2 | `DatumLogSink` + `ConsoleLogSink` + `CollectingLogSink` | `datum_logger.dart` |
| 2 | Capability markers (`TransactionalAdapter`/`WatchableAdapter`/`PaginatedAdapter`/`RelationalAdapter`) | `adapter_capabilities.dart` |
| 2 | Shippable `InMemoryLocalAdapter` (reference minimal adapter) | `in_memory_local_adapter.dart` |
| 2/3 | Reusable in-memory `DatumQueryMatcher` | `datum_query_matcher.dart` |
| 3 | Generator round-trip fixes (snake-case timestamp keys, camelCase fallback, `diff` key) | `datum_generator` |
| 3 | `generateMixin` defaults to **true** (mixin-by-default, warning-suppressed) | `datum_generator` |
| 3 | Hive honors `DatumQuery` + real pagination + `watchQuery` | `datum_hive` |
| 4 | Order-independent hash + O(1) incremental `DatumRollingHash` (~420× faster updates) | `hash_generator.dart` |
| 0 | Public-API golden test | `test/public_api_test.dart` |
| 0 | CI workflow (analyze/format/generate-check/test/benchmark) | `.github/workflows/ci.yml` |

New tests: `test/unit/type_safety_test.dart`, `extensibility_test.dart`,
`rolling_hash_test.dart`, `public_api_test.dart`, and
`datum_hive/test/hive_query_test.dart`.

The remaining, larger refactors below (e.g. fully splitting the `LocalAdapter`
god-interface into required-core + capability mixins, symmetric `changeStream`
shapes, `DatumEither` on `initialize`'s error side) are intentionally deferred
as breaking-change work; the additive foundations for them (capability markers,
`BaseLocalAdapter`-style defaults via `InMemoryLocalAdapter`) are in place.

**Baseline (measured 2026-07):** core lib ≈ 14k LOC; 105 test files, ~1,324
`test()` cases across 331 groups; suite is green; pure-Dart core (no Flutter
import in `lib/`). No benchmark harness existed before this plan.

---

## 1. Design goals & principles

The target API should satisfy five properties. Each is concrete and testable:

1. **Type-safe** — entity, query, registry, and error paths carry their types to
   compile time. `dynamic` / `Object?` / `as T` confined to clearly-marked
   serialization boundaries, never in everyday call sites.
2. **Extensible** — adding a storage backend, remote backend, resolver,
   middleware, or logger means implementing one small, focused contract (or a
   capability mixin), not a 28-method god-interface.
3. **Easy to use** — the 80% case (one entity, Hive + REST/Supabase, default
   conflict policy) is a few lines with no hand-written serialization boilerplate.
4. **Performant & measured** — hot paths have benchmarks; a CI gate catches
   regressions; known O(n)-per-cycle costs are addressed.
5. **Backward-compatible** — every change ships behind a deprecation window;
   existing apps compile against the next minor without edits.

Guiding rules: prefer compile-time errors over runtime `StateError`; prefer
defaults + opt-in capability over required boilerplate; keep one obvious way to
do each thing; never widen a public type to `dynamic` to "make it work."

---

## 2. Current-state assessment (grounded)

### 2.1 What is already good (keep / build on)

- **Clean small extension points:** `DatumConflictResolver<T>` (2 members),
  `DatumMiddleware<T>` (0 required / 2 default), `DatumObserver<T>` (all default),
  `DatumConnectivityChecker` (2 getters), `Migration` (3 members). These are the
  model to copy.
- **Generated type-safe query surface exists:** `datum_generator` emits
  `extension <Entity>Query on DatumQueryBuilder<Entity>` with per-field
  `whereTitle(...)`, `orderByPriority(...)`, and `withRelation()` — i.e. a typed
  path is already possible; it just isn't the default and isn't enforced.
- **Config ergonomics:** `DatumConfigPresets` (development/production/
  highPerformance/lowMemory/testing/offlineFirst/realTime + `custom`) is a strong
  ease-of-use foundation.
- **Rich query operators:** equals/gt/lt/in/between/contains/startsWith/
  arrayContains/withinDistance/raw — broad and well-tested.
- **Error-as-value type exists:** `DatumEither<L,R>` (Success/Failure, fold, etc.).
- **Well-typed value objects:** `VectorClock`, `CRDT<T>` (PNCounter, ORSet).
- **Substantial test base** and a working pure-Dart core.

### 2.2 Type-safety gaps

| # | Gap | Evidence | Impact |
|---|-----|----------|--------|
| T1 | Query field names are raw strings; builder generic `T` is a phantom type; `Filter.value` is `dynamic` | `datum_query.dart` `Filter(String field, …, dynamic value)`; `DatumQueryBuilder<T>.where(String field, {dynamic isEqualTo, …})` | Typos & type mismatches are runtime errors; doc comments overstate "type-safe" |
| T2 | `TypeSafeManagerRegistry` is runtime `Map<Type, Object>` with `as` casts + runtime-throwing lookups, and leaks `operator []`/`[]=(Type, Object)` | `datum_core.dart:149-210` | "Type-safe" in name only; unregistered type fails at runtime |
| T3 | `DatumEither` used by exactly one method (`initialize`), and its error side is untyped `Object`; all CRUD/query/sync **throw** instead | `datum_core.dart:280`; manager/adapters | Inconsistent error model; callers can't exhaustively handle failures |
| T4 | Entity contract is asymmetric: `toDatumMap` exists but there is **no `fromMap` in the contract**; `copyWith` deliberately excluded | `datum_entity.dart:48-58,109,221` | Deserialization unenforced; `copyWith` can't carry domain fields |
| T5 | `incrementClock`/`merge` return base `DatumEntityInterface`, forcing `as T` at call sites | `datum_manager.dart:577` | Downcasts sprinkled through the engine |
| T6 | Relations expose `dynamic` (`Relation.value`, `setRaw(dynamic)`, `value as T`), pivot is a raw `Type` | `relational_datum_entity.dart` | Relationship wiring is runtime-checked |
| T7 | SQL converter interpolates field names unvalidated into SQL | `datum_query_sql_converter.dart:82,153` | Injection surface if field names ever come from untrusted input |

### 2.3 Extensibility gaps

| # | Gap | Evidence | Impact |
|---|-----|----------|--------|
| E1 | `LocalAdapter<T>` is a god-interface: **28 required** members spanning CRUD, pagination, native-query translation, pending-op queue, sync metadata, schema versioning, raw-data migration, transactions, sizing, last-sync caching | `local_adapter.dart` | Writing a backend is a huge undertaking; discourages contributions |
| E2 | `DatumPersistence` has **19 required / 0 default** members, heavily `dynamic`-typed, with three near-duplicate save/get/delete/watch triplets | `datum_persistence.dart` | All-or-nothing boilerplate; no type safety |
| E3 | `LocalAdapter` and `RemoteAdapter` are **asymmetric & inconsistent**: `changeStream` is a method on one, a getter on the other; reactive `watch*` return **nullable** `Stream?` everywhere | both adapter files | Null-handling burden on every consumer; confusing parity |
| E4 | "Optional" capabilities signaled via runtime `UnimplementedError` / nullable returns (`fetchRelated`, `watchRelated`, `getStorageStats`) instead of capability interfaces | adapters, persistence | Capabilities undiscoverable at compile time |
| E5 | No abstract `Logger` interface — output hardcoded to `print()` inside `DatumLogger` | `datum_logger.dart` | Can't cleanly redirect logs without subclassing a concrete class |
| E6 | No Dart `sealed`/`base`/`interface` modifiers on extension points; `GlobalDatumObserver` re-declares 6 empty overrides | multiple | Weaker invariants; boilerplate |

### 2.4 Ease-of-use gaps

| # | Gap | Evidence | Impact |
|---|-----|----------|--------|
| U1 | Generator `generateMixin` defaults to **false**, so each entity hand-writes 6–10 delegating overrides (`toDatumMap`, `diff`, `fromMap` factory, `copyWith`, `relations`, `==`, `hashCode`) | `generator_test.dart`, `relationship_generation_test.dart` | High per-entity boilerplate in the default path |
| U2 | Two `fromMap` call-site styles (hand-written `X.fromMap` vs mixin `XFactory.fromMap`) because extensions can't add constructors | example wiring mixes both | Inconsistent, confusing |
| U3 | Generator round-trip key bugs: `datumToMap` writes camelCase keys but `_$XFromMap` reads snake_case; `map['x'] ?? map['x']` redundant OR; `datumDiff` ignores `MapTarget` | generator output | Latent correctness bugs; relies on parse fallbacks |
| U4 | `push(item, userId)` takes `userId` separately though the entity already has `userId` | `datum_manager.dart:563` | Redundant / mismatch risk |
| U5 | `datum_hive` `query()` ignores the `DatumQuery` and returns `readAll()`; `readAllPaginated` throws; `transaction` is a no-op; example ships a **divergent newer copy** of the adapter | `hive_local_adapter.dart` | The typed query builder isn't actually honored on Hive; docs/реальность drift |
| U6 | Naming inconsistencies (`datumToMap`/`datumDiff` prefixed, `copyWith` not; `DatumConnectivityChecker` class vs `ConnectivityChecker` in its own doc) | generator, connectivity | Cognitive overhead |

### 2.5 Performance status

- No benchmark harness existed; added in Phase 0 (`benchmark/`).
- **Confirmed hotspot:** `DatumHashGenerator.hashEntities` sorts and
  `jsonEncode`s the **entire** dataset every call; measured ≈ 7.6 ms for 1,000
  entities and it is recomputed per sync cycle (O(n) per sync). Candidate for an
  incremental/rolling hash.
- `datum_hive.query` falls back to `readAll` then (in the example) client-side
  filtering — no native pushdown; scales poorly with dataset size.
- Reactive `watchAll` in the Hive adapter re-reads and re-emits the whole box on
  every change (no diffing).

---

## 3. Improvement roadmap (phased)

Each phase is independently shippable, additive-first, and gated by tests +
benchmarks. Order optimizes for "guardrails first, then safe refactors."

### Phase 0 — Guardrails & baseline  ✅ (this change)

- [x] Add `benchmark/` Tier-A micro-benchmark harness (pure Dart, no new deps).
- [ ] Add a **public-API surface test** (golden list of exported symbols) so any
      addition/removal is a reviewed diff. Today `datum.dart` re-exports 60+
      files including internal-looking paths (`_internal.dart`); audit and curate.
- [ ] Add CI jobs: `dart test`, `dart analyze --fatal-infos`, `dart format
      --set-exit-if-changed`, generator build check, and `benchmark --json`
      baseline capture.
- **Acceptance:** benchmark runs in CI; exported-symbol golden exists; CI green.

### Phase 1 — Type safety (additive)

1. **Typed result/error model.** Introduce `DatumError` (sealed: `NotFound`,
   `Conflict`, `Network`, `Validation`, `Storage`, `Unknown`) and adopt
   `DatumEither<DatumError, T>` on a new, **non-breaking** result-returning API
   surface (e.g. `manager.tryRead`, `tryPush`, `trySync`) while the throwing
   methods remain and delegate. Type `initialize`'s error side from `Object` →
   `DatumError`.
2. **Typed query field selectors.** Promote the generator's typed query
   extension to first-class: generate a `<Entity>Fields` descriptor
   (`const title = DatumField<BenchTask, String>('title')`) so
   `query.whereField(BenchTask$.title, isEqualTo: …)` is type-checked on both
   field existence and value type. Keep the string `where('title', …)` path for
   dynamic use, but make the typed path the documented default.
3. **Registry hardening.** Keep `register<T>` / `get<T>()`; **remove** the leaky
   `operator []`/`[]=(Type, Object)` map-compat surface (deprecate first).
   Provide `tryGet<T>() → DatumManager<T>?` for the no-throw path.
4. **Tighten covariant returns.** Where feasible, make `incrementClock`/`merge`
   return `Self`/`T` via the generator's generated overrides to delete `as T`
   call sites in the engine.
- **Acceptance:** new typed APIs covered by unit tests; `dart analyze` clean; no
  behavior change for existing callers; benchmark neutral.

### Phase 2 — Extensibility (decompose the heavy contracts)

1. **Split `LocalAdapter` into a core + capability mixins.** Required core:
   CRUD + `query` + `initialize`/`dispose` (≈10 methods). Move the rest into
   opt-in mixins: `PendingOperationStore`, `SyncMetadataStore`,
   `SchemaVersioned`, `RawDataMigratable`, `Transactional`, `StorageSized`,
   `Watchable` (reactive). Provide `BaseLocalAdapter<T>` with sensible defaults
   (e.g. `createAll` looping `create`) so a minimal backend overrides ~10
   methods, not 28. The engine checks `adapter is Transactional` etc. instead of
   catching `UnimplementedError`.
2. **Make adapters symmetric.** Unify `changeStream` shape (getter on both),
   and replace nullable `Stream?` reactive returns with a non-null
   `Stream.empty()`/explicit `supportsWatch` capability so consumers stop
   null-checking.
3. **Reduce `DatumPersistence` boilerplate.** Factor the metadata/config/data
   triplets into one generic `KeyValueStore` contract + a `BasePersistence`
   with defaults; keep the existing interface as a thin facade for compat.
4. **Introduce a `DatumLogSink` interface** (`void write(LogEntry)`); make
   `DatumLogger` delegate to a sink (default = print sink). Honor `colors`.
5. **Apply class modifiers** (`interface`/`base`/`sealed`) where they encode real
   invariants; collapse `GlobalDatumObserver`'s redundant overrides.
- **Acceptance:** existing adapters/persistence keep working (compat shims);
  a new "minimal in-memory LocalAdapter" example implements <12 methods; tests
  cover capability detection; benchmark neutral or better.

### Phase 3 — Ease of use

1. **Default to `generateMixin: true`** (or a new `@DatumEntity` class annotation
   that implies it) so entities get `toDatumMap`/`diff`/`fromMap`/`copyWith`/
   `==`/`hashCode` with **zero** hand-written overrides. Resolve the
   "unused mixin warning" with an `// ignore` in generated code, not by shifting
   work to users.
2. **Unify `fromMap`.** One documented constructor style; generator emits a
   consistent factory wiring. Fix U3 key bugs (camelCase/snake_case round-trip,
   redundant `?? same`, `MapTarget` in `datumDiff`) — these get golden tests.
3. **Honor the query builder in `datum_hive`** (translate `DatumQuery` to a Hive
   scan/index lookup) and delete the divergent example copy in favor of the
   package adapter; implement `readAllPaginated`.
4. **Trim redundant params** (e.g. derive `userId` from the entity in `push`,
   keeping an optional override) behind deprecations.
5. **Naming pass** for consistency (generated method prefixes; connectivity doc).
- **Acceptance:** a "hello world" entity + sync is ≤ ~30 lines with no manual
  serialization; generator golden tests pass; Hive query test proves filters are
  applied at the adapter.

### Phase 4 — Performance

1. **Incremental data hash.** Replace full-set `jsonEncode`+SHA per cycle with a
   rolling/merkle hash updated on write, or hash only the changed delta. Target:
   sync-cycle hashing cost independent of total dataset size.
2. **Native query pushdown** in `datum_hive` (and document the contract so other
   adapters can do the same); avoid full-box re-emits in `watchAll` via keyed
   diffing.
3. **Batch path review** for `saveMany`/sync batches against `remoteSyncBatchSize`.
- **Acceptance:** Tier-B benchmarks show the targeted improvements; no
  correctness regressions; CI perf gate updated.

---

## 4. Performance benchmark plan

### 4.1 Tiers

- **Tier A — micro-benchmarks (landed):** `benchmark/datum_benchmark.dart`.
  Covers serialization, diff, vector clock, query build + SQL convert, hashing,
  LRU. Pure Dart, `dart run`, `--scale`/`--json` flags.
- **Tier B — end-to-end engine benchmarks (planned):** throughput/latency
  through `DatumManager` + in-memory adapters (reuse `test/mocks/`, add a
  no-print/silent mode):
  - `push` create vs update; `saveMany` batch sizes.
  - `read`/`readAll`/`query` at 1k / 10k / 100k stored entities.
  - full `synchronize()`: N pending + M remote changes, with conflict
    detection + each resolver (LWW / CRDT / merge / local / remote / prompt).
  - reactive `watchAll`/`watchQuery` re-emission cost vs dataset size.
  - cold-start hydration vs entity count.
- **Tier C — adapter benchmarks (planned):** real `datum_hive` (and any SQLite
  adapter) read/write/query at scale, run under `flutter test` on device/CI.

### 4.2 Methodology & targets

- Warm up, then measure fixed iterations; report ops/sec + ns/op; prefer AOT
  (`dart compile exe`) for release-representative numbers.
- **Regression gate:** store a `--json` baseline; fail CI when any case regresses
  > 20% ns/op (tunable). Track the `hashEntities` O(n) item as an explicit
  improvement target with a before/after number.

---

## 5. Test plan

Layered: **unit** (pure, fast, deterministic) → **integration** (engine +
in-memory adapters, multi-component flows) → **property/fuzz** (invariants) →
**golden** (generator output) → **example app** (widget/E2E). Existing ~1,324
tests are the regression floor; new work must not reduce coverage.

### 5.1 Unit tests (per module)

Target ≥ 90% line coverage on core, 100% on pure value types. New/expanded:

- **Types & errors:** `DatumError` hierarchy + `DatumEither` combinators
  (`fold`, `map`, `flatMap`, `getOrElse`); every `tryX` method's Success/Failure
  branches.
- **Typed query selectors:** field descriptor → filter equivalence with the
  string path; value-type mismatches fail to compile (compile-time negative
  tests via `// expect: compile-error` analyzer fixtures).
- **Registry:** `register`/`get`/`tryGet`/`getByType`; unregistered → typed
  failure; `DatumEntityInterface` direct-use guard.
- **Query → SQL:** every `FilterOperator` × dialect (sqlite/postgres/custom);
  placeholder indexing; field-name validation (post-fix for T7); ordering +
  null-sort + limit/offset.
- **Serialization:** `toDatumMap` local vs remote; `fromMap` round-trip;
  `diff` changed/no-change/foreign-type; `MapTarget` honored in `diff`.
- **Vector clock / CRDT:** increment/merge/compare/isConcurrent laws;
  PNCounter/ORSet merge commutativity & idempotence.
- **Resolvers:** LWW (version-then-time), CRDT merge, local/remote priority,
  custom merge fn, user-prompt strategies — each with tie/edge cases.
- **Adapter capabilities (post Phase 2):** capability detection
  (`adapter is Transactional`), `BaseLocalAdapter` defaults, symmetric
  `changeStream`.
- **Utilities:** `LRUCache` eviction/order, hash stability/order-independence,
  duration formatter, logger sink dispatch + sampling.

### 5.2 Integration tests (engine + in-memory adapters)

Extend the existing `test/integration/` suite (already ~25 files). Each scenario
asserts final local **and** remote state, emitted events, and metrics:

- **Offline → online sync:** queue writes offline, reconnect, assert push/pull
  convergence and pending-op drain.
- **Conflict resolution end-to-end:** concurrent local+remote edits per resolver;
  assert winner + `onConflictResolved` + version/clock progression.
- **Multi-entity & relational sync:** parents+children, cascade delete (incl.
  mixin path), `fetchRelated`/`watchRelated`, many-to-many via pivot.
- **Partial / scoped / paginated sync** and `DatumSyncScope` (minModifiedDate).
- **User switch** strategies (syncThenSwitch / clearAndFetch /
  promptIfUnsynced / keepLocal) including unsynced-data guard.
- **Migration:** v0→v1 raw-data migration via `getAllRawData`/`overwriteAllRawData`
  within a transaction; rollback on failure.
- **Cold start** hydration and status/health stream emission.
- **Reactive queries:** `watchQuery`/`watchAll` re-emit on create/update/delete
  and on `refreshStreams()`; `userChangeStream` drives re-query.
- **Typed-result API:** `trySync`/`tryPush` Failure paths (network down,
  validation) return the right `DatumError` subtype.
- **Connectivity-driven auto-sync** start/stop/pause/resume.

### 5.3 Property / fuzz tests

- **Serialization round-trip:** `fromMap(toDatumMap(e)) == e` over generated
  random entities (incl. special types: enum, DateTime, Duration, Uri, BigInt,
  Color, List<Offset>).
- **Conflict-resolution convergence:** randomized concurrent edit sequences on
  two replicas converge to the same state regardless of delivery order
  (CRDT/LWW invariants).
- **Vector clock laws** under random op sequences.

### 5.4 Generator golden tests

- Pin `.g.dart` output for representative inputs (basic, relational, ignored
  fields, custom field transforms, mixin on/off). Diff-on-change in CI.
- Regression tests for the U3 bugs (key casing round-trip, redundant `??`,
  `MapTarget` in diff).

### 5.5 Coverage, CI & quality gates

- `dart test --coverage` with a floor (e.g. fail < 90% core lines).
- `dart analyze --fatal-infos --fatal-warnings`; `dart format` check.
- Generator `build_runner` smoke build on every CI run.
- Benchmark `--json` regression gate (Section 4.2).
- Public-API golden (Phase 0) to prevent accidental surface changes.

---

## 6. Definition of done (per the goal)

- **Good API design:** curated public surface (golden list); consistent naming;
  one obvious way per task; redundant params removed (deprecation window).
- **Type-safe:** typed errors + `tryX` result API; typed query field selectors as
  the default; registry without the leaky map surface; `dynamic` confined to
  serialization boundaries with tests.
- **Extensible:** minimal core adapter (<12 methods) + capability mixins +
  `Base*` defaults; symmetric adapters; `DatumLogSink`; class modifiers applied.
- **Easy to use:** zero hand-written serialization (mixin-by-default); unified
  `fromMap`; Hive honors queries; ≤ ~30-line hello-world.
- **Performance benchmark:** Tier-A landed and runnable; Tier-B/C specified and
  wired into a CI regression gate; `hashEntities` hotspot addressed with a
  before/after number.
- **Tests:** unit + integration + property + generator-golden suites green;
  coverage floor enforced in CI.

## 7. Risks & compatibility

- **Breaking-change risk:** mitigate with additive-first APIs, deprecation
  windows, and compat shims (old adapter/persistence interfaces delegate to the
  new decomposed ones). Ship the public-API golden in Phase 0 so every later
  change is a visible, reviewed diff.
- **Generator churn:** golden tests + `build_runner` CI catch output regressions
  before publish.
- **Benchmark noise:** use `--scale`, AOT, and percentage thresholds; treat Tier-A
  numbers as relative, not absolute.

---

## 8. Suggested execution order (first PRs)

1. Phase 0: CI + public-API golden + benchmark in CI (small, high leverage).
2. Phase 1.1–1.2: `DatumError` + `tryX` result API + typed query selectors.
3. Phase 3.1–3.2: mixin-by-default + generator round-trip bug fixes (golden).
4. Phase 2.1: decompose `LocalAdapter` (+ `BaseLocalAdapter`, capability mixins).
5. Phase 4.1: incremental hash; Tier-B benchmarks to prove it.

Each PR carries its own unit + integration tests and updates this document's
checkboxes.
