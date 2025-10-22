import 'package:datum/datum.dart';

/// Orchestrates the execution of schema migrations.
class MigrationExecutor<T extends DatumEntity> {
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
  /// This method snapshots the adapter's raw data and stored schema version before
  /// attempting migrations and will restore them if any error occurs.
  Future<void> execute() async {
    // Snapshot current adapter state so we can restore on failure.
    final originalData = await localAdapter.getAllRawData();
    final originalStoredVersion = await localAdapter.getStoredSchemaVersion();

    try {
      // Run the full migration sequence inside a transaction when possible.
      await localAdapter.transaction(() async {
        var currentVersion = await localAdapter.getStoredSchemaVersion();
        logger.info('Starting schema migration from version $currentVersion to $targetVersion...');

        while (currentVersion < targetVersion) {
          final migration = _findMigration(currentVersion);

          logger.info('Running migration from v${migration.fromVersion} to v${migration.toVersion}...');

          // Retrieve current raw data and produce migrated maps.
          final rawData = await localAdapter.getAllRawData();
          final migratedData = rawData.map(migration.migrate).toList();

          // Persist migrated data and update stored schema version.
          await localAdapter.overwriteAllRawData(migratedData);
          await localAdapter.setStoredSchemaVersion(migration.toVersion);

          currentVersion = migration.toVersion;
          logger.info('Migration to v$currentVersion successful.');
        }

        logger.info('Schema migration completed. Current version: $currentVersion');
      });
    } catch (error, stack) {
      logger.error('Migration failed, attempting to restore original state: $error', stack);
      // Attempt to restore the adapter to its original state to ensure tests
      // (and real environments without adapter-level transactional rollback)
      // don't end up in a partially-migrated state.
      try {
        await localAdapter.overwriteAllRawData(originalData);
        await localAdapter.setStoredSchemaVersion(originalStoredVersion);
        logger.info('Restored original data and schema version after migration failure.');
      } catch (restoreError, restoreStack) {
        // If restoration fails, log both errors and rethrow the original error.
        logger.error('Failed to restore original state after migration failure: $restoreError', restoreStack);
        // Prefer rethrowing the original migration error for caller semantics.
        rethrow;
      }

      // Re-throw the original migration error to preserve semantics expected by callers/tests.
      rethrow;
    }
  }

  /// Finds the next migration to run from the current version.
  Migration _findMigration(int fromVersion) {
    try {
      return migrations.firstWhere((m) => m.fromVersion == fromVersion);
    } on StateError {
      throw MigrationException(
        'Migration path broken: No migration found from version $fromVersion. Please provide a migration that starts at this version.',
      );
    }
  }
}
