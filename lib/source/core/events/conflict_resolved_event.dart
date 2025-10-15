import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

/// Event emitted after a conflict has been successfully resolved.
class ConflictResolvedEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates a conflict resolved event.
  ConflictResolvedEvent({
    required super.userId,
    required this.entityId,
    required this.resolution,
    DateTime? timestamp,
  }) : super(timestamp: timestamp ?? DateTime.now());

  /// The ID of the entity that was involved in the conflict.
  final String entityId;

  /// The resolution that was applied.
  final DatumConflictResolution<T> resolution;

  @override
  String toString() =>
      '${super.toString()}: ConflictResolvedEvent(entityId: $entityId, resolution: $resolution)';
}
