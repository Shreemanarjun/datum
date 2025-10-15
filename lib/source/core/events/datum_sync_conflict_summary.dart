import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// A summary of a conflict that was encountered and resolved during a sync.
class DatumSyncConflictSummary<T extends DatumEntity> {
  /// How the conflict was resolved.
  final DatumConflictResolution<T> resolution;

  /// The ID of the entity that was involved in the conflict.
  final String entityId;

  /// Creates a conflict summary.
  const DatumSyncConflictSummary({
    required this.resolution,
    required this.entityId,
  });
}
