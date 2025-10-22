---
title: Entity Define
---
First, you need to define your data models by extending `DatumEntity`. This class provides the core structure for your entities, including properties like `id`, `userId`, `createdAt`, `modifiedAt`, `isDeleted`, and `version`.

Below is an example of a `Task` entity. Your entities will likely have more specific fields relevant to your application.

```dart
import 'package:datum/datum.dart';
import 'dart:convert'; // For json.encode and json.decode
import 'dart:math'; // For Random
import 'package:supabase_flutter/supabase_flutter.dart'; // Example for userId

class Task extends DatumEntity {
  @override
  final String id;

  @override
  final String userId;

  final String title;

  final String? description;

  final bool isCompleted;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final bool isDeleted;

  @override
  final int version;
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  @override
  Task copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isDeleted,
    int? version,
  }) {
    // Determine if any field is being changed.
    final bool hasChanges = id != null ||
        userId != null ||
        title != null ||
        description != null ||
        isCompleted != null ||
        createdAt != null ||
        modifiedAt != null ||
        isDeleted != null;

    return Task(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      // Always update modifiedAt if there are changes.
      modifiedAt: (modifiedAt ?? this.modifiedAt),
      isDeleted: isDeleted ?? this.isDeleted,
      // If a version is explicitly passed, use it. Otherwise, increment if there are changes.
      version: version ?? (hasChanges ? this.version + 1 : this.version),
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) {
    if (oldVersion is! Task) return toDatumMap();

    final diff = <String, dynamic>{};

    if (title != oldVersion.title) {
      diff['title'] = title;
    }
    if (description != oldVersion.description) {
      diff['description'] = description;
    }
    if (isCompleted != oldVersion.isCompleted) {
      diff['isCompleted'] = isCompleted;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    // Only include modification details if there are other changes
    if (diff.isNotEmpty) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
      diff['version'] = version;
    }

    return diff.isEmpty ? null : diff;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = {
      'id': id,
      'userId': userId,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'isDeleted': isDeleted,
      'version': version,
    };

    if (target == MapTarget.remote) {
      map['createdAt'] = createdAt.toIso8601String();
      map['modifiedAt'] = modifiedAt.toIso8601String();
    } else {
      map['createdAt'] = createdAt.millisecondsSinceEpoch;
      map['modifiedAt'] = modifiedAt.millisecondsSinceEpoch;
    }
    return map;
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: (map['id'] ?? '') as String,
      userId: (map['userId'] ?? map['user_id'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      description: map['description'] as String?,
      isCompleted: (map['isCompleted'] ?? map['is_completed'] ?? false) as bool,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']),
      modifiedAt: _parseDate(map['modifiedAt'] ?? map['modified_at']),
      isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? false) as bool,
      version: (map['version'] ?? 1) as int,
    );
  }

  static DateTime _parseDate(dynamic dateValue) {
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    if (dateValue is String) {
      return DateTime.tryParse(dateValue) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Task create({required String title, String? description}) {
    final now = DateTime.now();
    // This is an example using Supabase for user ID. Adjust as per your auth solution.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Cannot create task: user is not logged in.');
    }
    return Task(
      id: '${now.millisecondsSinceEpoch}${Random().nextInt(9999)}',
      userId: userId,
      title: title,
      description: description,
      isCompleted: false,
      createdAt: now,
      modifiedAt: now,
    );
  }

  String toJson() => json.encode(toDatumMap());

  factory Task.fromJson(String source) =>
      Task.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Task(id: $id, userId: $userId, title: $title, description: $description, isCompleted: $isCompleted, createdAt: $createdAt, modifiedAt: $modifiedAt, isDeleted: $isDeleted, version: $version)';
  }

  @override
  bool operator ==(covariant Task other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.userId == userId &&
        other.title == title &&
        other.isCompleted == isCompleted &&
        other.description == description &&
        other.createdAt == createdAt &&
        other.modifiedAt == modifiedAt &&
        other.isDeleted == isDeleted &&
        other.version == version;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        title.hashCode ^
        isCompleted.hashCode ^
        description.hashCode ^
        createdAt.hashCode ^
        modifiedAt.hashCode ^
        isDeleted.hashCode ^
        version.hashCode;
  }
}
```