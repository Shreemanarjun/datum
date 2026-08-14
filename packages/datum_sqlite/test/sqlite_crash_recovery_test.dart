import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:datum_test/src/crash_recovery_conformance.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// SqliteLocalAdapter over a FILE database certified by the datum_test crash
/// recovery conformance suite: queued ops, entity rows, sync metadata, and
/// the schema version must all survive a "crash" (dispose + reopen of the
/// same database file), and recovery syncs must deliver exactly once.
void main() {
  final tempDir = Directory.systemTemp.createTempSync('datum_sqlite_crash_');
  final dbPath = '${tempDir.path}/crash_recovery.db';
  Database? db;

  tearDownAll(() {
    db?.dispose();
    db = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<LocalAdapter<ConformanceEntity>> openLocal() async {
    // SqliteLocalAdapter.dispose() never closes the caller-owned Database, so
    // the previous handle to the file is closed here before reopening it.
    db?.dispose();
    db = sqlite3.open(dbPath);
    final adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db!,
      table: 'conformance',
      fromMap: ConformanceEntity.fromMap,
      columns: const {'name': 'TEXT', 'value': 'INTEGER'},
    );
    await adapter.initialize();
    return adapter;
  }

  Future<void> wipeStorage() async {
    db?.dispose();
    db = null;
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final file = File('$dbPath$suffix');
      if (file.existsSync()) file.deleteSync();
    }
  }

  runCrashRecoveryConformanceTests(
    name: 'SqliteLocalAdapter (file database)',
    openLocal: openLocal,
    wipeStorage: wipeStorage,
  );
}
