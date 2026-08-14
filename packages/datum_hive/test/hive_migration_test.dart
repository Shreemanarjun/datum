import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'support/task.dart';

Task _task(String id, int priority) => Task(
  id: id,
  userId: 'u1',
  title: 'T$id',
  priority: priority,
  modifiedAt: DateTime(2024),
  createdAt: DateTime(2024),
  version: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  var counter = 0;
  late String boxName;
  final logger = DatumLogger(enabled: false);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_migration_test');
    Hive.init(dir.path);
    boxName = 'tasks_${counter++}';
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<HiveLocalAdapter<Task>> open() async {
    final adapter = HiveLocalAdapter<Task>(entityBoxName: boxName, fromMap: Task.fromMap);
    await adapter.initialize();
    return adapter;
  }

  test('schema version survives an adapter restart (app relaunch)', () async {
    final first = await open();
    expect(await first.getStoredSchemaVersion(), 0);
    await first.setStoredSchemaVersion(3);
    await first.dispose();

    final second = await open();
    expect(
      await second.getStoredSchemaVersion(),
      3,
      reason: 'version must come from the box, not the constructor default',
    );
    await second.dispose();
  });

  test('overwriteAllRawData preserves columns the entity does not know about', () async {
    final adapter = await open();
    await adapter.overwriteAllRawData([
      {..._task('a', 1).toDatumMap(), 'archived': true, 'migratedBy': 'v2'},
    ]);

    final raw = (await adapter.getAllRawData()).single;
    expect(raw, containsPair('archived', true));
    expect(raw, containsPair('migratedBy', 'v2'));
    // The entity read path still works, ignoring the extra columns.
    expect((await adapter.read('a', userId: 'u1'))?.priority, 1);
    await adapter.dispose();
  });

  test('MigrationExecutor migrates Hive data once, not on every launch', () async {
    var adapter = await open();
    await adapter.create(_task('a', 1));
    await adapter.create(_task('b', 2));

    final migrations = [
      SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        operations: [ColumnOperation.transform('priority', (v, _) => (v as int) + 100)],
      ),
      SchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        operations: [ColumnOperation.add('archived', defaultValue: false)],
      ),
    ];

    MigrationExecutor<Task> executor() => MigrationExecutor<Task>(
      localAdapter: adapter,
      migrations: migrations,
      targetVersion: 2,
      logger: logger,
    );

    expect(await executor().needsMigration(), isTrue);
    final result = await executor().execute();
    expect(result.success, isTrue);

    final raw = await adapter.getAllRawData();
    expect(raw.map((r) => r['priority']).toSet(), {101, 102});
    expect(raw.every((r) => r['archived'] == false), isTrue, reason: 'added column persisted in the box');

    // Simulated relaunch: a fresh adapter over the same box must NOT re-run
    // the chain (the historical bug: version lived only in memory, so
    // priority would gain another +100 on every app start).
    await adapter.dispose();
    adapter = await open();
    expect(await executor().needsMigration(), isFalse);
    final rerun = await executor().execute();
    expect(rerun.success, isTrue);
    expect(
      (await adapter.getAllRawData()).map((r) => r['priority']).toSet(),
      {101, 102},
      reason: 'a second launch must be a no-op',
    );
    await adapter.dispose();
  });
}
