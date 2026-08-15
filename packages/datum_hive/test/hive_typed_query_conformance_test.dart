import 'dart:io';

import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:datum_test/src/typed_query_conformance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// HiveLocalAdapter certified by the typed-query conformance suite — the
/// typed path must produce identical results through map matching.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  var boxCounter = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_typed_query');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  runTypedQueryConformanceTests(
    name: 'HiveLocalAdapter',
    createLocal: () async {
      final adapter = HiveLocalAdapter<ConformanceEntity>(
        entityBoxName: 'typed_query_${boxCounter++}',
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
    destroyLocal: (adapter) => adapter.dispose(),
  );
}
