import 'dart:io';

import 'package:datum_test/datum_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:datum_hive/datum_hive.dart';

/// HiveLocalAdapter certified by the official datum_test conformance kit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  var boxCounter = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_conformance');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  runLocalAdapterConformanceTests(
    name: 'HiveLocalAdapter',
    create: () async {
      final adapter = HiveLocalAdapter<ConformanceEntity>(
        entityBoxName: 'conformance_${boxCounter++}',
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
