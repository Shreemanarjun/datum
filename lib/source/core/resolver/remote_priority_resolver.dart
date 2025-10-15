import 'dart:async';

import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

/// Resolves conflicts by always preferring the remote version of the entity.
/// If the remote version does not exist, it will use the local version.
class RemotePriorityResolver<T extends DatumEntity>
    implements DatumConflictResolver<T> {
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

    return DatumConflictResolution.abort(
      'No data available to resolve conflict.',
    );
  }
}
