import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Event emitted whenever local or remote data changes.
class DataChangeEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates a data change event.
  DataChangeEvent({
    required super.userId,
    this.data,
    required this.changeType,
    required this.source,
    DateTime? timestamp,
  }) : super(timestamp: timestamp ?? DateTime.now());

  /// The changed data. This can be null for delete events.
  final T? data;

  /// Type of change that occurred.
  final ChangeType changeType;

  /// Source of the change.
  final DataSource source;

  @override
  String toString() => '${super.toString()}: DataChangeEvent(data: $data, changeType: $changeType, source: $source)';
}

/// Type of data change.
enum ChangeType {
  /// Data was created.
  created,

  /// Data was updated.
  updated,

  /// Data was deleted.
  deleted,
}

/// Source of data change.
enum DataSource {
  /// Change originated locally.
  local,

  /// Change came from remote source.
  remote,
}
