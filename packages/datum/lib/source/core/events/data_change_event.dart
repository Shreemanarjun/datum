import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/models/data_source.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Event emitted whenever local or remote data changes.
class DataChangeEvent<T extends DatumEntityInterface> extends DatumSyncEvent<T> {
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

/// Event fired after a batch of changes received from the remote adapter's
/// change stream (e.g. a realtime feed) was applied to the local store. The
/// echo of this device's own writes is not a received change and is not
/// reported.
///
/// No sync cycle runs for these changes, so no `DatumSyncCompletedEvent`
/// follows: this is how an app learns that live updates arrived, how many,
/// and how fast.
class LiveChangesAppliedEvent<T extends DatumEntityInterface> extends DatumSyncEvent<T> {
  /// Creates a live-changes-applied event.
  LiveChangesAppliedEvent({
    required super.userId,
    required this.count,
    required this.duration,
    this.lastChangedAt,
    super.timestamp,
  });

  /// How many changes were applied.
  final int count;

  /// How long applying them to the local store took.
  final Duration duration;

  /// When the most recent of them was made, by its author's clock
  /// (`DatumChangeDetail.timestamp`). `timestamp - lastChangedAt` is how long
  /// the change took to get here, as far as the two devices' clocks agree.
  final DateTime? lastChangedAt;

  @override
  String toString() => '${super.toString()}: LiveChangesAppliedEvent(count: $count, duration: $duration)';
}
