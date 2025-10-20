import 'dart:async';

import 'package:datum/source/core/models/conflict_context.dart';

import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// A simple conflict resolver that chooses the entity with the later `modifiedAt` timestamp.
class LastWriteWinsResolver<T extends DatumEntity> implements DatumConflictResolver<T> {
  @override
  String get name => 'LastWriteWins';

  @override
  FutureOr<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  }) {
    if (local == null && remote == null) {
      return const DatumConflictResolution.abort('No data available for resolution.');
    }

    if (local == null) {
      return DatumConflictResolution.useRemote(remote!);
    }

    if (remote == null) {
      return DatumConflictResolution.useLocal(local);
    }

    // Prioritize the entity with the higher version number.
    if (local.version != remote.version) {
      return local.version > remote.version ? DatumConflictResolution.useLocal(local) : DatumConflictResolution.useRemote(remote);
    }
    // If versions are the same, fall back to the most recent modification time.
    return remote.modifiedAt.isAfter(local.modifiedAt) ? DatumConflictResolution.useRemote(remote) : DatumConflictResolution.useLocal(local);
  }
}
