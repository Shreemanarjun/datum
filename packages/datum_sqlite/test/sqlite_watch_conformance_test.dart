import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// SqliteLocalAdapter certified by the datum_test watch-stream conformance
/// suite (initial snapshots per listener, includeInitialData, watchById,
/// user scoping).
void main() {
  var counter = 0;
  final databases = <Object, Database>{};

  runWatchConformanceTests(
    name: 'SqliteLocalAdapter',
    create: () async {
      final db = sqlite3.openInMemory();
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: db,
        table: 'watch_${counter++}',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT', 'value': 'INTEGER'},
      );
      databases[adapter] = db;
      await adapter.initialize();
      return adapter;
    },
    destroy: (adapter) async => databases.remove(adapter)?.dispose(),
  );
}
