import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Describes the synchronization state for a single entity type.
@immutable
class DatumEntitySyncDetails {
  /// Creates details for an entity's sync state.
  const DatumEntitySyncDetails({required this.count, this.hash});

  /// Creates [DatumEntitySyncDetails] from a map (JSON).
  factory DatumEntitySyncDetails.fromJson(Map<String, dynamic> json) {
    return DatumEntitySyncDetails(
      count: json['count'] as int,
      hash: json['hash'] as String?,
    );
  }

  /// The total number of items for this entity.
  final int count;

  /// An optional hash of this entity's data for integrity checking.
  final String? hash;

  /// Converts to a map for JSON serialization.
  Map<String, dynamic> toMap() => {
        'count': count,
        if (hash != null) 'hash': hash,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DatumEntitySyncDetails && other.count == count && other.hash == hash;
  }

  @override
  int get hashCode => Object.hash(count, hash);

  @override
  String toString() => 'DatumEntitySyncDetails(count: $count, hash: $hash)';
}

/// Metadata describing the synchronization state for a specific user.
@immutable
class DatumSyncMetadata extends Equatable {
  /// Creates sync metadata.
  const DatumSyncMetadata({
    required this.userId,
    this.lastSyncTime,
    this.dataHash,
    this.deviceId,
    this.customMetadata,
    this.entityCounts,
  });

  /// Creates SyncMetadata from JSON.
  factory DatumSyncMetadata.fromMap(Map<String, dynamic> json) {
    return DatumSyncMetadata(
      userId: json['userId'] as String,
      lastSyncTime: json['lastSyncTime'] != null ? DateTime.parse(json['lastSyncTime'] as String) : null,
      dataHash: json['dataHash'] as String?,
      deviceId: json['deviceId'] as String?,
      customMetadata: json['customMetadata'] as Map<String, dynamic>?,
      entityCounts: json['entityCounts'] != null
          ? (json['entityCounts'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(
                key,
                DatumEntitySyncDetails.fromJson(value as Map<String, dynamic>),
              ),
            )
          : null,
    );
  }

  /// User ID for this metadata.
  final String userId;

  /// Timestamp of last synchronization.
  final DateTime? lastSyncTime;

  /// An optional global hash of all data for high-level integrity checking.
  final String? dataHash;

  /// Optional device identifier.
  final String? deviceId;

  /// Custom metadata fields.
  final Map<String, dynamic>? customMetadata;

  /// A map of counts for different entity types, allowing tracking of multiple
  /// "tables" or data collections.
  final Map<String, DatumEntitySyncDetails>? entityCounts;

  /// Creates a copy with modified fields.
  DatumSyncMetadata copyWith({
    DateTime? lastSyncTime,
    String? dataHash,
    String? deviceId,
    Map<String, dynamic>? customMetadata,
    Map<String, DatumEntitySyncDetails>? entityCounts,
  }) {
    return DatumSyncMetadata(
      userId: userId,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      dataHash: dataHash ?? this.dataHash,
      deviceId: deviceId ?? this.deviceId,
      customMetadata: customMetadata ?? this.customMetadata,
      entityCounts: entityCounts ?? this.entityCounts,
    );
  }

  /// Converts to a map.
  Map<String, dynamic> toMap() => {
        'userId': userId,
        if (lastSyncTime != null) 'lastSyncTime': lastSyncTime!.toUtc().toIso8601String(),
        if (dataHash != null) 'dataHash': dataHash,
        if (deviceId != null) 'deviceId': deviceId,
        if (customMetadata != null) 'customMetadata': customMetadata,
        if (entityCounts != null)
          'entityCounts': entityCounts!.map(
            (key, value) => MapEntry(key, value.toMap()),
          ),
      };

  @override
  List<Object?> get props => [
        userId,
        lastSyncTime,
        dataHash,
        deviceId,
        customMetadata,
        entityCounts,
      ];
}
