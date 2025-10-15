import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Event emitted when event listeners are attached for a user and the
/// full dataset snapshot needs to be delivered.
class InitialSyncEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates an initial sync event.
  InitialSyncEvent({
    required super.userId,
    required List<T> data,
    DateTime? timestamp,
  }) : data = List<T>.unmodifiable(data),
       super(timestamp: timestamp ?? DateTime.now());

  /// Complete snapshot of the user's dataset at the time of subscription.
  final List<T> data;

  @override
  String toString() => '${super.toString()}: InitialSyncEvent(data: $data)';
}
