import 'package:equatable/equatable.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Description of a conflict encountered during a sync.
class DatumSyncConflictSummary<T extends DatumEntity> extends Equatable {
  /// How the conflict was resolved.
  final DatumConflictResolution<T> resolution;

  /// ID of the entity involved in the conflict.
  final String entityId;

  /// Creates a conflict summary.
  const DatumSyncConflictSummary({
    required this.resolution,
    required this.entityId,
  });

  @override
  String toString() => 'DatumSyncConflictSummary(resolution: $resolution, entityId: $entityId)';

  @override
  List<Object?> get props => [resolution, entityId];
}
