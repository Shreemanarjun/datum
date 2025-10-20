import 'dart:async';

import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

/// Resolves conflicts by always preferring the local version of the entity.
/// If the local version does not exist, it will use the remote version.
class LocalPriorityResolver<T extends DatumEntity> implements DatumConflictResolver<T> {
  @override
  String get name => 'LocalPriority';

  @override
  FutureOr<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  }) {
    if (local != null) {
      return DatumConflictResolution.useLocal(local);
    }

    if (remote != null) {
      return DatumConflictResolution.useRemote(remote);
    }

    return const DatumConflictResolution.abort(
      'No data available to resolve conflict.',
    );
  }
}
