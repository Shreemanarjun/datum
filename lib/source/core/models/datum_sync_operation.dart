// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:equatable/equatable.dart';

/// Represents a single pending operation to be synchronized.
class DatumSyncOperation<T extends DatumEntity> extends Equatable {
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

  /// The size of the data payload in bytes.
  final int sizeInBytes;

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
    this.sizeInBytes = 0,
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
      data: map['data'] == null
          ? null
          : fromJsonT(
              Map<String, dynamic>.from(map['data'] as Map),
            ),
      delta: map['delta'] == null
          ? null
          : Map<String, dynamic>.from(
              map['delta'] as Map,
            ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      retryCount: map['retryCount'] as int? ?? 0,
      sizeInBytes: map['sizeInBytes'] as int? ?? 0,
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
    int? sizeInBytes,
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
      sizeInBytes: sizeInBytes ?? this.sizeInBytes,
    );
  }

  /// Converts the operation to a map representation.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'userId': userId,
      'entityId': entityId,
      'type': type.name,
      'data': data?.toDatumMap(),
      'delta': delta,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'retryCount': retryCount,
      'sizeInBytes': sizeInBytes,
    };
  }

  /// Converts the operation to a JSON string.
  String toJson() => json.encode(toMap());

  @override
  List<Object?> get props => [
        id,
        userId,
        entityId,
        type,
        timestamp,
        data,
        delta,
        retryCount,
        sizeInBytes,
      ];

  @override
  bool get stringify => true;
}
