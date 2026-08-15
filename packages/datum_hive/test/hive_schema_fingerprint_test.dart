import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// SchemaFingerprintCapable on the Hive adapters: the auto-migration fast
/// path persists across a simulated relaunch (same box reopened).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_fingerprint');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('fingerprint round-trips and survives a box reopen', () async {
    final adapter = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: 'fp_box',
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    expect(adapter, isA<SchemaFingerprintCapable>());
    expect(await adapter.getStoredSchemaFingerprint(), isNull);
    await adapter.setStoredSchemaFingerprint('deadbeef');
    expect(await adapter.getStoredSchemaFingerprint(), 'deadbeef');
    await adapter.dispose();

    final reopened = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: 'fp_box',
      fromMap: ConformanceEntity.fromMap,
    );
    await reopened.initialize();
    expect(await reopened.getStoredSchemaFingerprint(), 'deadbeef');
    await reopened.dispose();
  });

  test('auto-migration over a Hive store reconciles rows and stamps', () async {
    final adapter = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: 'auto_box',
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    await adapter.overwriteAllRawData([
      {
        'id': 'a',
        'userId': 'u1',
        'name': 'Ada',
        'legacy': true,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'modifiedAt': '2026-01-01T00:00:00.000Z',
        'version': 1,
        'isDeleted': false,
      },
    ]);

    final declared = DatumSchema<ConformanceEntity>(
      name: 'auto_box',
      fields: [
        ...datumCoreFieldSpecs<ConformanceEntity>().all,
        DatumFieldSpec<ConformanceEntity, String>('title', renamedFrom: 'name', defaultValue: ''),
        DatumFieldSpec<ConformanceEntity, int>('score', defaultValue: 5),
      ],
    );
    final outcome = await AutoMigrationExecutor<ConformanceEntity>(
      localAdapter: adapter,
      schema: declared,
      dropRemovedColumns: true,
      logger: DatumLogger(enabled: false),
    ).execute();
    expect(outcome.success, isTrue, reason: '${outcome.error}');

    final row = (await adapter.getAllRawData()).single;
    expect(row['title'], 'Ada');
    expect(row['score'], 5);
    expect(row.containsKey('name'), isFalse);
    expect(row.containsKey('legacy'), isFalse);
    expect(await adapter.getStoredSchemaFingerprint(), declared.fingerprint);
    await adapter.dispose();
  });
}
