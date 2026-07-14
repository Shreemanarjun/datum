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
