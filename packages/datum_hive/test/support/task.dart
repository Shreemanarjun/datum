import 'package:datum/datum.dart';

/// The shared test entity for datum_hive suites.
class Task extends DatumEntity {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    required this.priority,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  factory Task.fromMap(Map<String, dynamic> map) => Task(
    id: map['id'] as String? ?? '',
    userId: map['userId'] as String? ?? '',
    title: map['title'] as String? ?? '',
    priority: map['priority'] as int? ?? 0,
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(map['modifiedAt'] as int? ?? 0),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
    version: map['version'] as int? ?? 0,
    isDeleted: map['isDeleted'] as bool? ?? false,
  );

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final int priority;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'userId': userId,
    'title': title,
    'priority': priority,
    'modifiedAt': modifiedAt.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'version': version,
    'isDeleted': isDeleted,
  };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! Task) return toDatumMap(target: MapTarget.remote);
    final d = <String, dynamic>{};
    if (title != oldVersion.title) d['title'] = title;
    if (priority != oldVersion.priority) d['priority'] = priority;
    return d.isEmpty ? null : d;
  }
}
