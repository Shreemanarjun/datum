/// Opt-in capability markers for adapters.
///
/// The base [LocalAdapter] / [RemoteAdapter] contracts declare optional methods
/// (reactive `watch*`, `transaction`, pagination, relational fetch) that default
/// to `null` or throw [UnimplementedError]. These mixins let an adapter
/// *advertise* which optional capabilities it genuinely supports, so the engine
/// and callers can branch on `adapter is WatchableAdapter` instead of probing
/// for a null stream or catching an exception at runtime.
///
/// Most are pure markers (no members) so applying one is free and
/// backward-compatible. [RawQueryCapable] additionally declares the `rawQuery`
/// method — kept off the base adapter interfaces so adding it never breaks
/// existing `implements LocalAdapter`/`RemoteAdapter` implementations.
library;

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_scope.dart';
import 'package:datum/source/core/query/datum_raw_query.dart';

/// The adapter implements real ACID-style [transaction] semantics (atomic
/// commit/rollback), not just a pass-through.
mixin TransactionalAdapter {}

/// The adapter supports reactive queries (`watchAll`/`watchById`/`watchQuery`
/// return live, non-null streams).
mixin WatchableAdapter {}

/// The adapter natively supports pagination (`readAllPaginated` /
/// `watchAllPaginated`) rather than throwing or loading everything.
mixin PaginatedAdapter {}

/// The adapter can resolve relationships at the storage layer
/// (`fetchRelated` / `watchRelated`).
mixin RelationalAdapter {}

/// The adapter supports raw queries for projections/aggregations without full
/// entity hydration (#11).
///
/// This declares the [rawQuery] method itself (rather than adding it to the base
/// adapter contracts) so opting in is non-breaking for existing adapters. Apply
/// it with `class MyAdapter extends LocalAdapter<T> with RawQueryCapable` and
/// implement [rawQuery].
mixin RawQueryCapable {
  /// Executes a raw query returning raw rows instead of hydrated entities.
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId});
}

/// The remote adapter can serve **incremental pulls**: instead of returning
/// the full dataset every cycle, it returns only entities modified at or
/// after a watermark (typically `WHERE modified_at >= ?` on the backend).
///
/// When a remote adapter mixes this in (and
/// `DatumConfig.enableDeltaSync` is true, its default), the sync engine's
/// pull phase calls [readSince] with the last sync watermark minus
/// `DatumConfig.deltaSyncOverlap` (clock-skew tolerance; re-delivered rows
/// are skipped by the strictly-newer check, so the overlap is idempotent).
/// The engine still falls back to a full `readAll` for the first sync of a
/// user and for cycles that need the complete remote id set
/// (`detectRemoteDeletions`).
///
/// Soft deletions (`isDeleted` flips bump `modifiedAt`) propagate through
/// deltas naturally. **Hard** remote deletions are invisible to an
/// incremental pull — keep using soft deletes, or enable
/// `detectRemoteDeletions` for full-scan cycles.
///
/// **Which column to compare:** prefer a *server-maintained* received-at
/// timestamp (set by the backend on every write, e.g. a `server_updated_at`
/// trigger column) over the entity's client-set `modifiedAt`. A device that
/// reconnects after a week pushes rows whose `modifiedAt` is a week old —
/// older than every other device's watermark — so a `modifiedAt` comparison
/// would silently miss them, while a server received-at is always newer than
/// any previously issued watermark.
mixin DeltaSyncCapable<T extends DatumEntityInterface> {
  /// Returns entities modified at or after [since], honoring [userId] and
  /// [scope] the same way `readAll` does.
  Future<List<T>> readSince(DateTime since, {String? userId, DatumSyncScope? scope});
}

/// The result of one [CursorSyncCapable.readChanges] page: the changed
/// entities plus the opaque cursor to pass on the next call.
typedef CursorPage<T> = ({List<T> items, String nextCursor});

/// The remote adapter serves incremental pulls from an **opaque change
/// cursor** — the natural fit for changes-feed backends (Firestore snapshot
/// tokens, DynamoDB streams, CouchDB `since` sequences, or a plain
/// monotonically increasing change counter).
///
/// This is the generalization of [DeltaSyncCapable]: a timestamp watermark is
/// just one cursor encoding, but an opaque cursor also fits backends that
/// hand out tokens instead of clocks, and it sidesteps clock skew entirely —
/// no overlap window needed.
///
/// Engine behavior (when `DatumConfig.enableDeltaSync` is true, its
/// default): a `null` cursor means "from the beginning" — the adapter
/// returns the full dataset plus the current cursor, so even a user's first
/// sync goes through [readChanges]. The returned [CursorPage.nextCursor] is
/// persisted in the local sync metadata (`customMetadata`, key
/// `__sync_cursor__`) and handed back on the next cycle. When an adapter
/// mixes in both capabilities, the cursor path wins. Cycles that need the
/// complete remote id set (`detectRemoteDeletions`) still use a full
/// `readAll` and leave the cursor untouched.
///
/// The same soft-delete guidance as [DeltaSyncCapable] applies: `isDeleted`
/// flips must appear in the feed; hard deletions are invisible unless the
/// backend emits tombstones into the feed itself.
mixin CursorSyncCapable<T extends DatumEntityInterface> {
  /// Returns entities changed since [cursor] (`null` = from the beginning)
  /// and the cursor for the next call, honoring [userId] and [scope] the
  /// same way `readAll` does.
  Future<CursorPage<T>> readChanges(String? cursor, {String? userId, DatumSyncScope? scope});
}
