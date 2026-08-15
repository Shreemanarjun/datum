import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// SqliteLocalAdapter certified by the typed-query conformance suite — the
/// typed path must produce identical results through real SQL push-down.
void main() {
  Database? db;

  tearDownAll(() {
    db?.dispose();
    db = null;
  });

  runTypedQueryConformanceTests(
    name: 'SqliteLocalAdapter',
    createLocal: () async {
      db?.dispose();
      db = sqlite3.openInMemory();
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: db!,
        table: 'entities',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT', 'value': 'INTEGER'},
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
