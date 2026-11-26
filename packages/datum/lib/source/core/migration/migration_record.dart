import 'package:equatable/equatable.dart';

/// One row of a store's migration history: a migration step that was applied
/// to it, or that failed and was rolled back.
///
/// Adapters persist these (`LocalAdapter.recordMigration`) next to the data,
/// so a production store can always answer "which migrations ran here, when,
/// over how many rows, and did any fail?".
class MigrationRecord extends Equatable {
  const MigrationRecord({
    required this.name,
    required this.fromVersion,
    required this.toVersion,
    required this.appliedAt,
    required this.duration,
    this.rowCount,
    this.error,
  });

  factory MigrationRecord.fromMap(Map<String, dynamic> map) => MigrationRecord(
        name: map['name'] as String,
        fromVersion: map['fromVersion'] as int,
        toVersion: map['toVersion'] as int,
        appliedAt: DateTime.parse(map['appliedAt'] as String),
        duration: Duration(microseconds: map['durationMicros'] as int),
        rowCount: map['rowCount'] as int?,
        error: map['error'] as String?,
      );

  /// The migration class name, or `auto: …` for an auto-migration pass.
  final String name;
  final int fromVersion;
  final int toVersion;

  /// When the step finished (UTC).
  final DateTime appliedAt;
  final Duration duration;

  /// Rows the step rewrote; null when the store migrated them in place
  /// (SQL statements) without reading them.
  final int? rowCount;

  /// Why the step failed; null when it was applied.
  final String? error;

  bool get succeeded => error == null;

  Map<String, dynamic> toMap() => {
        'name': name,
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'appliedAt': appliedAt.toUtc().toIso8601String(),
        'durationMicros': duration.inMicroseconds,
        if (rowCount != null) 'rowCount': rowCount,
        if (error != null) 'error': error,
      };

  @override
  List<Object?> get props => [name, fromVersion, toVersion, appliedAt, duration, rowCount, error];
}
