import 'package:datum/datum.dart';
import 'package:flutter/material.dart';

/// Per-account preferences synced across devices. One row per user: the id
/// is the user id, so every device edits the same row (last write wins).
/// Hand-written, no codegen: `diff` and `props` come from the Datum mixin.
class UserSettings extends DatumEntity {
  const UserSettings({
    required this.userId,
    required this.themeMode,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  /// Fresh settings stamped now.
  factory UserSettings.of(String userId, ThemeMode themeMode) {
    final now = DateTime.now();
    return UserSettings(
        userId: userId, themeMode: themeMode, createdAt: now, modifiedAt: now);
  }

  /// These settings with [mode], stamped now as the next version.
  UserSettings withTheme(ThemeMode mode) => UserSettings(
      userId: userId,
      themeMode: mode,
      createdAt: createdAt,
      modifiedAt: DateTime.now(),
      version: version + 1);

  factory UserSettings.fromMap(Map<String, dynamic> map) => UserSettings(
        userId: (map['userId'] ?? map['user_id']) as String,
        themeMode: ThemeMode.values
                .asNameMap()[map['themeMode'] ?? map['theme_mode']] ??
            ThemeMode.system,
        createdAt: _date(map['createdAt'] ?? map['created_at']),
        modifiedAt: _date(map['modifiedAt'] ?? map['modified_at']),
        isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? false) as bool,
        version: (map['version'] ?? 1) as int,
      );

  @override
  String get id => userId;
  @override
  final String userId;
  final ThemeMode themeMode;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final bool isDeleted;
  @override
  final int version;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final remote = target == MapTarget.remote;
    return {
      'id': id,
      'userId': userId,
      'themeMode': themeMode.name,
      'isDeleted': isDeleted,
      'version': version,
      'createdAt': remote
          ? createdAt.toUtc().toIso8601String()
          : createdAt.millisecondsSinceEpoch,
      'modifiedAt': remote
          ? modifiedAt.toUtc().toIso8601String()
          : modifiedAt.millisecondsSinceEpoch,
    };
  }

  static DateTime _date(Object? value) => switch (value) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        final String s => DateTime.parse(s),
        _ => DateTime.fromMillisecondsSinceEpoch(0),
      };
}
