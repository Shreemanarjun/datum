import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:meta/meta.dart';

/// Represents a change that occurred in a data source.
/// This is used by adapters to notify the engine about external changes.
@immutable
class DatumChangeDetail<T extends DatumEntity> {
  /// Creates a change detail object.
  const DatumChangeDetail({
    required this.type,
    required this.entityId,
    required this.userId,
    required this.timestamp,
    this.data,
    this.sourceId,
  });

  /// The type of change operation that occurred.
  final DatumOperationType type;

  /// The ID of the entity that changed.
  final String entityId;

  /// The ID of the user who owns the entity.
  final String userId;

  /// The new entity data (null for delete operations).
  final T? data;

  /// The timestamp of when the change occurred.
  final DateTime timestamp;

  /// An optional identifier for the source of the change
  /// (e.g., device ID, session ID). This can be used by the engine
  /// to avoid processing changes that originated from the same instance.
  final String? sourceId;

  /// Creates a copy of this object with modified fields.
  DatumChangeDetail<T> copyWith({
    DatumOperationType? type,
    String? entityId,
    String? userId,
    T? data,
    DateTime? timestamp,
    String? sourceId,
  }) {
    return DatumChangeDetail<T>(
      type: type ?? this.type,
      entityId: entityId ?? this.entityId,
      userId: userId ?? this.userId,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      sourceId: sourceId ?? this.sourceId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DatumChangeDetail<T> &&
        other.type == type &&
        other.entityId == entityId &&
        other.userId == userId &&
        other.timestamp == timestamp &&
        other.sourceId == sourceId;
  }

  @override
  int get hashCode {
    return Object.hash(type, entityId, userId, timestamp, sourceId);
  }

  @override
  String toString() {
    return 'DatumChangeDetail(type: ${type.name}, entityId: $entityId, userId: '
        '$userId, timestamp: $timestamp, sourceId: $sourceId)';
  }
}
