import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Event emitted when the engine detects a
/// conflict between local and remote data.
class ConflictDetectedEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates a conflict detected event.
  ConflictDetectedEvent({
    required super.userId,
    required this.context,
    this.localData,
    this.remoteData,
    DateTime? timestamp,
  }) : super(timestamp: timestamp ?? DateTime.now());

  /// Context describing the conflict.
  final DatumConflictContext context;

  /// Local version of the data.
  final T? localData;

  /// Remote version of the data.
  final T? remoteData;

  @override
  String toString() => '${super.toString()}: ConflictDetectedEvent(context: $context, localData: $localData, remoteData: $remoteData)';
}
