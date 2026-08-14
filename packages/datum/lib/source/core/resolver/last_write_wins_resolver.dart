import 'dart:async';
import 'dart:convert';

import 'package:datum/datum.dart';

/// A simple conflict resolver that chooses the entity with the later `modifiedAt` timestamp.
class LastWriteWinsResolver<T extends DatumEntityInterface> implements DatumConflictResolver<T> {
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
    if (local.modifiedAt != remote.modifiedAt) {
      return remote.modifiedAt.isAfter(local.modifiedAt) ? DatumConflictResolution.useRemote(remote) : DatumConflictResolution.useLocal(local);
    }
    // Exact (version, modifiedAt) tie with divergent content. The tie must
    // break by a total order every replica computes identically — preferring
    // `local` would make each device elect itself and the replicas would
    // ping-pong resolution pushes forever. Comparing serialized payloads
    // crowns the same winner on both sides.
    final localEncoded = jsonEncode(local.toDatumMap(target: MapTarget.remote));
    final remoteEncoded = jsonEncode(remote.toDatumMap(target: MapTarget.remote));
    return localEncoded.compareTo(remoteEncoded) >= 0 ? DatumConflictResolution.useLocal(local) : DatumConflictResolution.useRemote(remote);
  }
}
