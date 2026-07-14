# Developer-Experience (UX) Review

A survey of remaining friction in the developer-facing API, with what was fixed
in this pass and what is still worth doing (prioritized).

## ✅ Landed in this pass (with tests)

- **Broken onboarding example** — the README's `Datum.initialize` snippet used
  `datumEither.isFailure` / `.failure!` / `.success!`, none of which existed
  (wouldn't compile). Added `DatumEither.success` / `.failure` getter aliases
  and fixed the README (`isFailure()`).
- **`manager.exists(id)` / `manager.count({query})`** — replaces the
  `read() != null` and `readAll().length` boilerplate.
- **Typed relation accessors** — `entity.relatedList<Post>('posts')` /
  `entity.relatedOne<User>('author')` replace the unsafe
  `(entity.relations['posts'] as HasMany).value` cast.
- **CHANGELOG** — the 1.1.0 entry now documents every fix/feature added this
  cycle, so users can actually discover them.
- **Relation-caching footgun mitigated** — added a `MemoizedRelations` mixin.
  Hand-written entities `with MemoizedRelations` define `buildRelations()` and
  get automatic memoization, so eager loading works without remembering to store
  a `late final _relations` field. (Opt-in; a base-level auto-cache still can't
  be forced because it conflicts with `const` entities.)
- **`HasOne` / `ManyToMany` eager loading** — `withRelated` now stitches all
  four relation kinds (previously only `BelongsTo`/`HasMany`); also fixed a
  latent crash where related entities were assumed relational.
- **Reactive eager loading** — `watchAll` / `watchQuery` accept `withRelated`.
- **`query` defaults to `source: DataSource.local`** — no mandatory `source:`.
- **Presets** — `DatumConfigPresets.custom(...)` now exposes `enableQueryCache`,
  `detectRemoteDeletions`, and `excludedSyncUserIds`.

## ◼ Medium (still open)

- **Non-null reactive streams** — `watchAll`/`watchById`/`watchQuery`/
  `watchAllPaginated` now return non-null `Stream`s (an empty stream when the
  adapter isn't watchable, with a debug hint to mix in `WatchableAdapter`). No
  more null-checks at call sites.
- **Typed `Datum.initialize` error** — returns
  `DatumEither<DatumError, Datum>` (was `Object`); `DatumError implements
  Exception`, so a failed init can be pattern-matched or rethrown.
- **`trySaveMany` + `deleteMany`** batch conveniences.
- **`DatumSyncResult.describe()` / `DatumHealth.describe()` + `toString`** —
  human-readable, multi-line summaries for logging.

- **Manual typed query selectors documented** — `doc/API_GUIDE.md` shows the
  `DatumQueryField` constant pattern for hand-written (non-generator) entities.
- **`tryX` coverage completed** — added `trySaveMany`, `trySwitchUser`,
  `tryCascadeDelete` (alongside `tryRead/Push/Query/Delete/Synchronize`).
- **Export gap fixed** — `CascadeDeleteResult` / `CascadeResult` /
  `CascadeDeleteBuilder` (public return types of `cascadeDelete` &co.) are now
  exported and nameable.
- **Docs alignment content** — `doc/API_GUIDE.md` captures the shipped API
  surface (querying, relations, results/errors, config) for porting to the site.

## Status

The full UX backlog is now cleared. Remaining work is external only: porting
`doc/API_GUIDE.md` into the hosted docs site.
