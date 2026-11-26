import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/core/migration/migration.dart';
import 'package:datum/source/core/migration/migration_plan.dart';
import 'package:datum/source/core/models/migration_record.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/utils/datum_logger.dart';

/// A record representing the outcome of a migration execution.
typedef MigrationResult = ({
  bool success,
  Object? migrationError,
  StackTrace? migrationStack,
});

/// Orchestrates the execution of schema migrations.
class MigrationExecutor<T extends DatumEntityInterface> {
  final LocalAdapter<T> localAdapter;
  final List<Migration> migrations;
  final int targetVersion;
  final DatumLogger logger;

  MigrationExecutor({
    required this.localAdapter,
    required this.migrations,
    required this.targetVersion,
    required this.logger,
  });

  /// Checks if a migration is necessary by comparing the stored version
  /// with the target version from the config.
  Future<bool> needsMigration() async {
    final storedVersion = await localAdapter.getStoredSchemaVersion();
    return storedVersion < targetVersion;
  }

  /// Executes the migration process from the adapter's stored version up to [targetVersion].
  ///
  /// The full chain is resolved and validated with [MigrationPlan] before any
  /// data is read or written, so configuration errors (gaps, duplicates,
  /// backwards steps) fail without touching the store. The method then
  /// snapshots the adapter's raw data and stored schema version before
  /// attempting migrations and will restore them if any error occurs,
  /// returning a [MigrationResult].
  Future<MigrationResult> execute() async {
    // Validate the whole chain up front — no store access has happened yet.
    final List<Migration> plannedSteps;
    try {
      plannedSteps = MigrationPlan.resolve(
        migrations,
        fromVersion: await localAdapter.getStoredSchemaVersion(),
        toVersion: targetVersion,
      ).steps;
    } catch (planError, planStack) {
      logger.error('Migration plan invalid, nothing was modified: $planError');
      return (success: false, migrationError: planError, migrationStack: planStack);
    }

    // Snapshot current adapter state so we can restore on failure.
    final originalData = await localAdapter.getAllRawData(userId: null);
    final originalStoredVersion = await localAdapter.getStoredSchemaVersion();
    logger.info('Starting schema migration from version $originalStoredVersion to $targetVersion...');

    return runMigrationSteps<T, Migration>(
      localAdapter: localAdapter,
      steps: plannedSteps,
      logger: logger,
      apply: (migration) async {
        final rawData = await localAdapter.getAllRawData();
        await localAdapter.overwriteAllRawData(rawData.map(migration.migrate).toList());
        return rawData.length;
      },
      // Stores without transactional rollback need the snapshot put back.
      restore: () async {
        await localAdapter.overwriteAllRawData(originalData);
        await localAdapter.setStoredSchemaVersion(originalStoredVersion);
      },
    );
  }
}

/// Runs [steps] in order inside the adapter's transaction. [apply] performs
/// one step and returns the number of rows it rewrote (null if unknown); the
/// stored schema version is stamped after each step.
///
/// The migration history gets one row per applied step once the whole chain
/// has committed (a rolled-back chain leaves no "applied" rows), or one
/// failed row for the step that threw, written after [restore] ran.
Future<MigrationResult> runMigrationSteps<T extends DatumEntityInterface, M extends Migration>({
  required LocalAdapter<T> localAdapter,
  required List<M> steps,
  required Future<int?> Function(M step) apply,
  required DatumLogger logger,
  Future<void> Function()? restore,
}) async {
  final applied = <MigrationRecord>[];
  final watch = Stopwatch();
  M? running;
  MigrationRecord record(M step, int? rowCount, {String? error}) => MigrationRecord(
        name: step.name,
        fromVersion: step.fromVersion,
        toVersion: step.toVersion,
        appliedAt: DateTime.now().toUtc(),
        duration: watch.elapsed,
        rowCount: rowCount,
        error: error,
      );

  try {
    await localAdapter.transaction<void>(() async {
      for (final step in steps) {
        logger.info('Running migration ${step.name} (v${step.fromVersion} -> v${step.toVersion})...');
        running = step;
        watch
          ..reset()
          ..start();
        final rowCount = await apply(step);
        await localAdapter.setStoredSchemaVersion(step.toVersion);
        applied.add(record(step, rowCount));
      }
    });
  } catch (migrationError, migrationStack) {
    logger.error('Migration failed, attempting to restore original state: $migrationError', migrationStack);
    try {
      await restore?.call();
    } catch (restoreError, restoreStack) {
      // The original migration error stays the one reported.
      logger.error('Failed to restore original state after migration failure: $restoreError', restoreStack);
    }
    final failed = running;
    if (failed != null) await localAdapter.recordMigration(record(failed, null, error: '$migrationError'));
    return (success: false, migrationError: migrationError, migrationStack: migrationStack);
  }

  for (final entry in applied) {
    await localAdapter.recordMigration(entry);
  }
  logger.info('Schema migration completed (${applied.length} step(s)).');
  return (success: true, migrationError: null, migrationStack: null);
}
