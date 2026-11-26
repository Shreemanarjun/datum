import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/datum_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:test/test.dart';

/// HiveLocalAdapter over FILE boxes through the full sync-stack suite against
/// every bundled remote, plus chaos and crash recovery. Each device gets its
/// own box set; a "crash" closes the boxes and reopens them by name.
void main() {
  late Directory dir;
  var counter = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_matrix');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<LocalAdapter<ConformanceEntity>> openBox(String box) async {
    final adapter = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: box,
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    return adapter;
  }

  Future<LocalAdapter<ConformanceEntity>> createLocal() =>
      openBox('device_${counter++}');

  runSyncConformanceMatrix(
    name: 'HiveLocalAdapter (file)',
    createLocal: createLocal,
    reopenLocal: (crashed) =>
        openBox((crashed as HiveLocalAdapter<ConformanceEntity>).entityBoxName),
  );

  runChaosConformanceTests(
    name: 'HiveLocalAdapter (file)',
    createLocal: createLocal,
  );

  const crashBox = 'crash_recovery';
  runCrashRecoveryConformanceTests(
    name: 'HiveLocalAdapter (file boxes)',
    openLocal: () => openBox(crashBox),
    wipeStorage: () async {
      for (final suffix in ['', '_pending_queue', '_metadata']) {
        await Hive.deleteBoxFromDisk('$crashBox$suffix');
      }
    },
  );
}
