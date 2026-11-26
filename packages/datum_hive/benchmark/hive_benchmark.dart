// Pure-Dart Hive adapter benchmarks (file boxes).
//   dart run benchmark/hive_benchmark.dart --runs 3,10
// The src import keeps these runnable against older checkouts whose
// datum_test barrel predates bench.dart (see tool/bench.sh).
// ignore_for_file: implementation_imports, avoid_print, unnecessary_import, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/datum_test.dart';
import 'package:datum_test/src/bench.dart';
import 'package:hive_ce/hive_ce.dart';

var _box = 0;

Future<Duration> withAdapter(Future<Duration> Function(HiveLocalAdapter<ConformanceEntity> a) body) async {
  final dir = Directory.systemTemp.createTempSync('datum_hive_bench');
  Hive.init(dir.path);
  final a = HiveLocalAdapter<ConformanceEntity>(entityBoxName: 'bench${_box++}', fromMap: ConformanceEntity.fromMap);
  await a.initialize();
  try {
    return await body(a);
  } finally {
    await a.dispose();
    await Hive.close();
    dir.deleteSync(recursive: true);
  }
}

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
  await runBenchSuite('datum_hive', args, {
    'enqueue 1000 ops': () => withAdapter((a) => timed(() async {
          for (var i = 0; i < 1000; i++) {
            await a.addPendingOperation('u1', op(i));
          }
        })),
    'dequeue 1000 ops': () => withAdapter((a) async {
          for (var i = 0; i < 1000; i++) {
            await a.addPendingOperation('u1', op(i));
          }
          return timed(() async {
            for (var i = 0; i < 1000; i++) {
              await a.removePendingOperation('op$i');
            }
          });
        }),
    'watchAll, 200-write burst': () => withAdapter((a) async {
          final sub = a.watchAll(userId: 'u1')!.listen((_) {});
          await Future<void>.delayed(Duration.zero);
          final d = await timed(() async {
            for (var i = 0; i < 200; i++) {
              await a.create(ConformanceEntity.make('e$i', userId: 'u1', name: 'n$i'));
            }
            await Future<void>.delayed(const Duration(milliseconds: 1));
          });
          await sub.cancel();
          return d;
        }),
  });
  exit(0);
}
