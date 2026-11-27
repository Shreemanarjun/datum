import 'dart:async';

import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

/// Resolves conflicts by always preferring the remote version of the entity.
/// If the remote version does not exist, it will use the local version.
///
/// It never looks at timestamps, so it is the choice when device clocks
/// cannot be trusted. Which concurrent edit survives then depends on the
/// sync direction: with `pullThenPush` (the default) the first device to
/// push wins and the later edit is dropped; with `pushThenPull` the last one
/// to push wins.
class RemotePriorityResolver<T extends DatumEntityInterface> implements DatumConflictResolver<T> {
  @override
  String get name => 'RemotePriority';

  @override
  FutureOr<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  }) {
    if (remote != null) {
      return DatumConflictResolution.useRemote(remote);
    }

    if (local != null) {
      return DatumConflictResolution.useLocal(local);
    }

    return const DatumConflictResolution.abort(
      'No data available to resolve conflict.',
    );
  }
}
