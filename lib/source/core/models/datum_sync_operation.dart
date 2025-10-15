// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:flutter/foundation.dart';

/// Represents a single pending operation to be synchronized.
@immutable
class DatumSyncOperation<T extends DatumEntity> {
  /// A unique identifier for this operation.
  final String id;

  /// The ID of the user this operation belongs to.
  final String userId;

  /// The ID of the entity this operation targets.
  final String entityId;

  /// The type of operation (create, update, delete).
  final DatumOperationType type;

  /// The timestamp when the operation was created.
  final DateTime timestamp;

  /// The full data payload of the entity.
  ///
  /// For `create` and `update`, this holds the complete entity state.
  /// For `delete`, this may be null.
  final T? data;

  /// A map of only the fields that have changed for an `update` operation.
  ///
  /// If this is not null, the sync engine can attempt a partial "patch"
  /// update instead of pushing the full entity.
  final Map<String, dynamic>? delta;

  /// The number of times this operation has been retried.
  final int retryCount;

  /// Creates a [DatumSyncOperation].
  const DatumSyncOperation({
    required this.id,
    required this.userId,
    required this.entityId,
    required this.type,
    required this.timestamp,
    this.data,
    this.delta,
    this.retryCount = 0,
  }) : assert(retryCount >= 0, 'retryCount cannot be negative');

  /// Creates a [DatumSyncOperation] from a map.
  ///
  /// Requires a `fromJsonT` function to deserialize the nested entity data.
  factory DatumSyncOperation.fromMap(
    Map<String, dynamic> map,
    T Function(Map<String, dynamic> json) fromJsonT,
  ) {
    return DatumSyncOperation<T>(
      id: map['id'] as String,
      userId: map['userId'] as String,
      entityId: map['entityId'] as String,
      type: DatumOperationType.values.byName(map['type'] as String),
      data: map['data'] != null
          ? fromJsonT(map['data'] as Map<String, dynamic>)
          : null,
      delta: map['delta'] != null
          ? Map<String, dynamic>.from(map['delta'] as Map<String, dynamic>)
          : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      retryCount: map['retryCount'] as int? ?? 0,
    );
  }

  /// Creates a copy of this operation with updated fields.
  DatumSyncOperation<T> copyWith({
    String? id,
    String? userId,
    String? entityId,
    DatumOperationType? type,
    T? data,
    Map<String, dynamic>? delta,
    DateTime? timestamp,
    int? retryCount,
  }) {
    return DatumSyncOperation<T>(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      entityId: entityId ?? this.entityId,
      type: type ?? this.type,
      data: data ?? this.data,
      delta: delta ?? this.delta,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  /// Converts the operation to a map representation.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'userId': userId,
      'entityId': entityId,
      'type': type.name,
      'data': data?.toMap(),
      'delta': delta,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'retryCount': retryCount,
    };
  }

  /// Converts the operation to a JSON string.
  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'DatumSyncOperation(id: $id, userId: $userId, entityId: $entityId, type: ${type.name}, timestamp: $timestamp, data: $data, delta: $delta, retryCount: $retryCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DatumSyncOperation<T> &&
        other.id == id &&
        other.userId == userId &&
        other.entityId == entityId &&
        other.type == type &&
        other.timestamp == timestamp &&
        other.data == data &&
        mapEquals(other.delta, delta) &&
        other.retryCount == retryCount;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      userId,
      entityId,
      type,
      timestamp,
      data,
      delta,
      retryCount,
    );
  }
}
