import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// SqliteLocalAdapter over FILE databases through the full sync-stack suite
/// against every bundled remote, plus chaos. Each device gets its own file;
/// a "crash" disposes the handle and reopens the same file.
void main() {
  final tempDir = Directory.systemTemp.createTempSync('datum_sqlite_matrix_');
  final open = <LocalAdapter<ConformanceEntity>, (Database, String)>{};
  var counter = 0;

  tearDownAll(() {
    for (final (db, _) in open.values) {
      db.dispose();
    }
    open.clear();
    tempDir.deleteSync(recursive: true);
  });

  runKeyNamingConformanceTests(
    name: 'SqliteLocalAdapter',
    create: () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final adapter = SqliteLocalAdapter<SnakeKeyedEntity>(
        database: db,
        table: 'snake',
        fromMap: SnakeKeyedEntity.fromMap,
        columns: const {'user_id': 'TEXT', 'name': 'TEXT', 'is_deleted': 'INTEGER'},
      );
      await adapter.initialize();
      return adapter;
    },
  );

  Future<LocalAdapter<ConformanceEntity>> openAt(String path) async {
    final db = sqlite3.open(path);
    final adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'conformance',
      fromMap: ConformanceEntity.fromMap,
      columns: const {'name': 'TEXT', 'value': 'INTEGER'},
    );
    await adapter.initialize();
    open[adapter] = (db, path);
    return adapter;
  }

  // SqliteLocalAdapter.dispose() never closes the caller-owned Database.
  String close(LocalAdapter<ConformanceEntity> adapter) {
    final (db, path) = open.remove(adapter)!;
    db.dispose();
    return path;
  }

  Future<LocalAdapter<ConformanceEntity>> createLocal() =>
      openAt('${tempDir.path}/device_${counter++}.db');

  runSyncConformanceMatrix(
    name: 'SqliteLocalAdapter (file)',
    createLocal: createLocal,
    reopenLocal: (crashed) => openAt(close(crashed)),
    destroyLocal: (adapter) async {
      if (open.containsKey(adapter)) close(adapter);
    },
  );

  runChaosConformanceTests(
    name: 'SqliteLocalAdapter (file)',
    createLocal: createLocal,
    destroyLocal: (adapter) async => close(adapter),
  );
}
