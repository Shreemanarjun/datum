import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// SqliteLocalAdapter certified by the auto-migration conformance suite —
/// the SQL introspection (PRAGMA) + real-DDL reconciliation path.
void main() {
  Database? db;

  tearDownAll(() {
    db?.dispose();
    db = null;
  });

  runAutoMigrationConformanceTests(
    name: 'SqliteLocalAdapter',
    createLocal: () async {
      db?.dispose();
      db = sqlite3.openInMemory();
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: db!,
        table: 'entities',
        fromMap: ConformanceEntity.fromMap,
        // The suite seeds a legacy shape; declare its columns so the seed
        // rows land in real columns.
        columns: const {'name': 'TEXT', 'legacy': 'INTEGER'},
      );
      await adapter.initialize();
      return adapter;
    },
    // Same database and table — a simulated relaunch.
    reopenLocal: () async {
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: db!,
        table: 'entities',
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
