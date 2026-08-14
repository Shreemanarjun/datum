import '../errors/datum_exception.dart';
import 'migration.dart';

/// Resolves and validates the chain of [Migration]s needed to move a store
/// from one schema version to another, before any data is touched.
class MigrationPlan {
  MigrationPlan._(this.steps);

  /// The ordered migrations to execute. Empty when already at the target.
  final List<Migration> steps;

  /// Builds the ordered chain from [fromVersion] to [toVersion] out of
  /// [migrations].
  ///
  /// Throws a [MigrationException] describing every problem found — a
  /// duplicate starting version (ambiguous path), a step that does not move
  /// forward, a gap in the chain, or a step that overshoots the target —
  /// so misconfiguration fails fast instead of mid-migration.
  factory MigrationPlan.resolve(
    List<Migration> migrations, {
    required int fromVersion,
    required int toVersion,
  }) {
    if (fromVersion >= toVersion) return MigrationPlan._(const []);

    final problems = <String>[];
    final byFromVersion = <int, Migration>{};
    for (final migration in migrations) {
      if (migration.toVersion <= migration.fromVersion) {
        problems.add(
          'Migration v${migration.fromVersion} -> v${migration.toVersion} does not move forward.',
        );
        continue;
      }
      final existing = byFromVersion[migration.fromVersion];
      if (existing != null) {
        problems.add(
          'Two migrations start at v${migration.fromVersion} '
          '(to v${existing.toVersion} and to v${migration.toVersion}); the path is ambiguous.',
        );
        continue;
      }
      byFromVersion[migration.fromVersion] = migration;
    }

    final steps = <Migration>[];
    var currentVersion = fromVersion;
    while (problems.isEmpty && currentVersion < toVersion) {
      final next = byFromVersion[currentVersion];
      if (next == null) {
        problems.add(
          'Migration path broken: no migration starts at v$currentVersion '
          '(migrating v$fromVersion -> v$toVersion).',
        );
        break;
      }
      if (next.toVersion > toVersion) {
        problems.add(
          'Migration v${next.fromVersion} -> v${next.toVersion} overshoots the target version $toVersion.',
        );
        break;
      }
      steps.add(next);
      currentVersion = next.toVersion;
    }

    if (problems.isNotEmpty) {
      throw MigrationException(
        message: 'Invalid migration configuration:\n- ${problems.join('\n- ')}',
        code: DatumExceptionCode.migrationError,
      );
    }
    return MigrationPlan._(List.unmodifiable(steps));
  }
}
