// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:convert';

import 'package:datum/datum.dart';

class UserEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const UserEntity({
    required this.userId,
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) {
    if (oldVersion is! UserEntity) return toDatumMap();

    final Map<String, dynamic> diffMap = {};

    if (name != oldVersion.name) {
      diffMap['name'] = name;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diffMap['isDeleted'] = isDeleted;
    }

    // Always include modifiedAt and version in a diff.
    diffMap['modifiedAt'] = modifiedAt.millisecondsSinceEpoch;
    diffMap['version'] = version;

    return diffMap;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return <String, dynamic>{
      'id': id,
      'userId': userId,
      'name': name,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'version': version,
      'isDeleted': isDeleted,
    };
  }

  @override
  UserEntity copyWith({
    String? id,
    String? userId,
    String? name,
    DateTime? modifiedAt,
    DateTime? createdAt,
    int? version,
    bool? isDeleted,
  }) {
    return UserEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  factory UserEntity.fromMap(Map<String, dynamic> map) {
    return UserEntity(
      id: (map['id'] ?? '') as String,
      userId: (map['userId'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['modifiedAt'] ?? 0) as int,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] ?? 0) as int,
      ),
      version: (map['version'] ?? 0) as int,
      isDeleted: (map['isDeleted'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toDatumMap());

  factory UserEntity.fromJson(String source) =>
      UserEntity.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'User(id: $id, userId: $userId, name: $name, modifiedAt: $modifiedAt, createdAt: $createdAt, version: $version, isDeleted: $isDeleted)';
  }

  @override
  bool operator ==(covariant UserEntity other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.userId == userId &&
        other.name == name &&
        other.modifiedAt == modifiedAt &&
        other.createdAt == createdAt &&
        other.version == version &&
        other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        name.hashCode ^
        modifiedAt.hashCode ^
        createdAt.hashCode ^
        version.hashCode ^
        isDeleted.hashCode;
  }
}
