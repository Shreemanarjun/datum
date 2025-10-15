import 'package:datum/source/core/models/datum_entity.dart';

/// An example entity with fields that can be excluded from local/remote storage.
///
/// This class demonstrates how to use [MapTarget] in the `toMap` and `diff`
/// methods to control which fields are serialized for the local database versus
/// the remote server.
class ExcludableEntity implements DatumEntity {
  @override
  final String id;
  @override
  final String userId;

  /// A regular field that is always synchronized.
  final String name;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  /// A map of fields that should only be stored locally.
  final Map<String, dynamic>? localOnlyFields;

  /// A map of fields that should only be sent to the remote.
  final Map<String, dynamic>? remoteOnlyFields;

  /// Creates an instance of [ExcludableEntity].
  ExcludableEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
    this.localOnlyFields,
    this.remoteOnlyFields,
  });

  /// Creates an [ExcludableEntity] from a map (e.g., from JSON).
  factory ExcludableEntity.fromJson(Map<String, dynamic> json) {
    return ExcludableEntity(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int,
      isDeleted: json['isDeleted'] as bool? ?? false,
      localOnlyFields: json['localOnlyFields'] != null
          ? Map<String, dynamic>.from(json['localOnlyFields'] as Map)
          : null,
      remoteOnlyFields: json['remoteOnlyFields'] != null
          ? Map<String, dynamic>.from(json['remoteOnlyFields'] as Map)
          : null,
    );
  }

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) {
    final map = <String, dynamic>{
      'id': id,
      'userId': userId,
      'name': name,
      'modifiedAt': modifiedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
    };

    if (target == MapTarget.local) {
      if (localOnlyFields != null) map.addAll(localOnlyFields!);
    } else {
      if (remoteOnlyFields != null) map.addAll(remoteOnlyFields!);
    }
    return map;
  }

  @override
  ExcludableEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
    Map<String, dynamic>? localOnlyFields,
    Map<String, dynamic>? remoteOnlyFields,
  }) {
    return ExcludableEntity(
      id: id,
      userId: userId,
      name: name ?? this.name,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      localOnlyFields: localOnlyFields ?? this.localOnlyFields,
      remoteOnlyFields: remoteOnlyFields ?? this.remoteOnlyFields,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) {
    if (oldVersion is! ExcludableEntity) {
      return toMap(target: MapTarget.remote);
    }

    final remoteMap = toMap(target: MapTarget.remote);
    final oldRemoteMap = oldVersion.toMap(target: MapTarget.remote);
    final diff = <String, dynamic>{};

    for (final key in remoteMap.keys) {
      if (remoteMap[key] != oldRemoteMap[key]) diff[key] = remoteMap[key];
    }

    return diff.isEmpty ? null : diff;
  }
}
