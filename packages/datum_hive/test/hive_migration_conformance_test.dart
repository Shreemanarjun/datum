import 'dart:io';

import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:datum_test/src/migration_conformance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// HiveLocalAdapter certified by the datum_test migration conformance suite
/// (map path). `reopenLocal` reopens the SAME box, so the suite also proves
/// migrations are run-once across a simulated app relaunch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  var boxCounter = 0;
  late String boxName;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_migration_conformance');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<HiveLocalAdapter<ConformanceEntity>> open() async {
    final adapter = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: boxName,
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    return adapter;
  }

  runMigrationConformanceTests(
    name: 'HiveLocalAdapter',
    createLocal: () async {
      // Fresh box per test for isolation; reopenLocal reuses the same name.
      boxName = 'migration_conformance_${boxCounter++}';
      return open();
    },
    reopenLocal: open,
  );
}
