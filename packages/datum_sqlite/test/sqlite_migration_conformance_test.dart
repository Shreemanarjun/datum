import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:datum_test/src/migration_conformance.dart';
import 'package:sqlite3/sqlite3.dart';

/// SqliteLocalAdapter certified by the datum_test migration conformance
/// suite on the SQL path: the chain runs as real ALTER TABLE/UPDATE
/// statements through SqlMigrationExecutor, with rollback provided by the
/// database transaction. Each test gets its own in-memory database, so no
/// reopenLocal (nothing persists across a relaunch anyway).
void main() {
  final databases = <Object, Database>{};

  runMigrationConformanceTests(
    name: 'SqliteLocalAdapter',
    createLocal: () async {
      final db = sqlite3.openInMemory();
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: db,
        table: 'conformance_migration',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT', 'value': 'INTEGER'},
      );
      databases[adapter] = db;
      await adapter.initialize();
      return adapter;
    },
    destroyLocal: (adapter) async => databases.remove(adapter)?.dispose(),
    sqlPath: true,
    table: 'conformance_migration',
  );
}
