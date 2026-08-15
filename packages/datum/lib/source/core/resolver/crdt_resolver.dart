import 'dart:async';

import 'package:datum/datum.dart';

/// A resolver that use the entity's built-in merge logic.
///
/// This is specifically designed for entities with CRDT fields that handle
/// their own merge logic, allowing for merge-less conflict resolution.
///
/// **The entity must override `merge`.** `DatumEntityMixin.merge` defaults to
/// `=> other` (take-remote); an entity that forgets the override silently
/// loses its concurrent local edits on every conflict. When that shape is
/// detected the resolution carries a warning message.
///
/// **Deletion conflicts** (one side missing) cannot run a CRDT merge — the
/// content-preserving choice is made instead: the surviving copy wins. A
/// remote deletion therefore does NOT delete the local CRDT document; the
/// local copy is re-pushed so both sides converge on the content. Aborting
/// here (the old behavior) left the same conflict re-firing on every sync
/// cycle forever.
class CRDTResolver<T extends DatumEntityInterface> implements DatumConflictResolver<T> {
  const CRDTResolver();

  @override
  String get name => 'CRDTMerge';

  @override
  Future<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  }) async {
    if (local == null && remote == null) {
      return DatumConflictResolution.abort(
        'No entities supplied to CRDT resolver.',
      );
    }

    // A deletion conflict has no second state to merge with — preserve the
    // content that still exists so the document cannot be lost, and let the
    // engine converge the other side.
    if (remote == null) {
      return DatumConflictResolution.useLocal(local as T);
    }
    if (local == null) {
      return DatumConflictResolution.useRemote(remote);
    }

    final merged = local.merge(remote) as T;

    // `DatumEntityMixin.merge` defaults to `=> other`. If the "merge" is
    // literally the remote instance while the two sides differ, the entity
    // almost certainly never implemented CRDT merging — surface it instead
    // of silently discarding the local edits.
    if (identical(merged, remote) && local != remote) {
      return DatumConflictResolution.merge(
        merged,
        message: 'Entity ${context.entityId} resolved with the DEFAULT merge (=> other): '
            'the entity type does not override merge(), so CRDTResolver degraded '
            'to take-remote and any concurrent local edits were discarded. '
            'Override merge() to combine CRDT fields.',
      );
    }

    return DatumConflictResolution.merge(merged);
  }
}
