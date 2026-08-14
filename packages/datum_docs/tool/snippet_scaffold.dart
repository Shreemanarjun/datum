// Shared scaffold every verified docs snippet compiles against.
//
// Fragment snippets (usage code without their own declarations) are wrapped
// by tool/snippet_check.dart into a function that receives these bindings as
// typed parameters, so docs can reference `manager`, `datum`, `task`, … the
// way a real app would without every snippet re-declaring the world.
//
// If a docs page needs a new well-known binding, add it here AND to the
// wrapper parameter list in snippet_check.dart.
// ignore_for_file: unused_import

import 'package:datum/datum.dart';

export 'package:datum/datum.dart';
export 'package:datum_sqlite/datum_sqlite.dart';
export 'package:datum_test/datum_test.dart';
export 'package:sqlite3/sqlite3.dart' show Database, sqlite3;

/// The entity every docs example uses.
class Task extends DatumEntity {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.isCompleted = false,
    this.priority = 0,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  factory Task.fromMap(Map<String, dynamic> map) => Task(
    id: map['id'] as String? ?? '',
    userId: map['userId'] as String? ?? '',
    title: map['title'] as String? ?? '',
    description: map['description'] as String?,
    isCompleted: map['isCompleted'] as bool? ?? false,
    priority: (map['priority'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime(2000),
    modifiedAt: DateTime.tryParse(map['modifiedAt'] as String? ?? '') ?? DateTime(2000),
    version: (map['version'] as num?)?.toInt() ?? 1,
    isDeleted: map['isDeleted'] as bool? ?? false,
  );

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final String? description;
  final bool isCompleted;
  final int priority;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'userId': userId,
    'title': title,
    'description': description,
    'isCompleted': isCompleted,
    'priority': priority,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'version': version,
    'isDeleted': isDeleted,
  };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! Task) return toDatumMap(target: MapTarget.remote);
    final delta = <String, dynamic>{};
    if (title != oldVersion.title) delta['title'] = title;
    if (description != oldVersion.description) delta['description'] = description;
    if (isCompleted != oldVersion.isCompleted) delta['isCompleted'] = isCompleted;
    if (priority != oldVersion.priority) delta['priority'] = priority;
    if (delta.isEmpty) return null;
    delta['modifiedAt'] = modifiedAt.toIso8601String();
    delta['version'] = version;
    return delta;
  }

  /// Returns an updated copy with a bumped version.
  Task copyWith({String? title, String? description, bool? isCompleted, int? priority, bool? isDeleted}) => Task(
    id: id,
    userId: userId,
    title: title ?? this.title,
    description: description ?? this.description,
    isCompleted: isCompleted ?? this.isCompleted,
    priority: priority ?? this.priority,
    createdAt: createdAt,
    modifiedAt: DateTime.now(),
    version: version + 1,
    isDeleted: isDeleted ?? this.isDeleted,
  );

  @override
  List<Object?> get props => [...super.props, title, description, isCompleted, priority];
}

/// Always-online connectivity for snippet contexts.
class SnippetConnectivity implements DatumConnectivityChecker {
  const SnippetConnectivity();
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
