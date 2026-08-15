import 'dart:io';

import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/src/auto_migration_conformance.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// HiveLocalAdapter certified by the auto-migration conformance suite —
/// the schemaless raw-map reconciliation path, with fingerprint run-once
/// across a simulated relaunch (same box reopened).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  var boxCounter = 0;
  late String boxName;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_auto_migration');
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

  runAutoMigrationConformanceTests(
    name: 'HiveLocalAdapter',
    createLocal: () async {
      boxName = 'auto_migration_${boxCounter++}';
      return open();
    },
    reopenLocal: open,
    destroyLocal: (adapter) => adapter.dispose(),
  );
}
