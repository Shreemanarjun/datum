// Pure-Dart SQLite adapter benchmarks (file database, real fsyncs).
//   dart run benchmark/sqlite_benchmark.dart --runs 3,10
// The src import keeps these runnable against older checkouts whose
// datum_test barrel predates bench.dart (see tool/bench.sh).
// ignore_for_file: implementation_imports, avoid_print, unnecessary_import, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:datum_test/src/bench.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Duration> withAdapter(Future<Duration> Function(SqliteLocalAdapter<ConformanceEntity> a) body) async {
  final dir = Directory.systemTemp.createTempSync('datum_sqlite_bench');
  final db = sqlite3.open('${dir.path}/bench.db');
  final a = SqliteLocalAdapter<ConformanceEntity>(
    database: db,
    table: 'items',
    fromMap: ConformanceEntity.fromMap,
    columns: const {'name': 'TEXT', 'value': 'INTEGER'},
  );
  await a.initialize();
  try {
    return await body(a);
  } finally {
    db.dispose();
    dir.deleteSync(recursive: true);
  }
}

List<ConformanceEntity> items(int n) => [for (var i = 0; i < n; i++) ConformanceEntity.make('e$i', userId: i % 10 == 0 ? 'u1' : 'u2', name: 'n$i', value: i)];

DatumSyncOperation<ConformanceEntity> op(int i) => DatumSyncOperation(
      id: 'op$i',
      userId: 'u1',
      entityId: 'e$i',
      type: DatumOperationType.create,
      timestamp: DateTime.utc(2026),
      data: ConformanceEntity.make('e$i', userId: 'u1', name: 'n$i'),
    );

Future<Duration> timed(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  return sw.elapsed;
}

Future<void> main(List<String> args) async {
  await runBenchSuite('datum_sqlite', args, {
    'createAll 3000': () => withAdapter((a) => timed(() => a.createAll(items(3000)))),
    'readAll(u1) x50, 10% of 20000 rows': () => withAdapter((a) async {
          await a.createAll(items(20000));
          return timed(() async {
            for (var i = 0; i < 50; i++) {
              await a.readAll(userId: 'u1');
            }
          });
        }),
    'watchCount, 200-write burst': () => withAdapter((a) async {
          final sub = a.watchCount(userId: 'u1')!.listen((_) {});
          await Future<void>.delayed(Duration.zero);
          final d = await timed(() async {
            await Future.wait([for (final e in items(200)) a.create(e)]);
            await Future<void>.delayed(const Duration(milliseconds: 1));
          });
          await sub.cancel();
          return d;
        }),
    'enqueue 1000 ops + dequeue all': () => withAdapter((a) => timed(() async {
          for (var i = 0; i < 1000; i++) {
            await a.addPendingOperation('u1', op(i));
          }
          for (var i = 0; i < 1000; i++) {
            await a.removePendingOperation('op$i');
          }
        })),
  });
  exit(0);
}
