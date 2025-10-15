import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/core/models/datum_exception.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:datum/source/core/migration/migration.dart';

/// Orchestrates the execution of schema migrations.
class MigrationExecutor {
  final LocalAdapter localAdapter;
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

  /// Executes the migration process.
  Future<void> execute() async {
    var currentVersion = await localAdapter.getStoredSchemaVersion();
    logger.info(
      'Starting schema migration from version $currentVersion to $targetVersion...',
    );

    while (currentVersion < targetVersion) {
      final migration = _findMigration(currentVersion);

      logger.info(
        'Running migration from v${migration.fromVersion} to v${migration.toVersion}...',
      );

      // Perform migration in a transaction to ensure atomicity.
      await localAdapter.transaction(() async {
        final rawData = await localAdapter.getAllRawData();
        final migratedData = rawData.map(migration.migrate).toList();
        await localAdapter.overwriteAllRawData(migratedData);
        await localAdapter.setStoredSchemaVersion(migration.toVersion);
      });

      currentVersion = migration.toVersion;
      logger.info('Migration to v$currentVersion successful.');
    }

    logger.info('Schema migration completed. Current version: $currentVersion');
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
