import 'dart:io';

import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/datum_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Boxes written before composite `(userId, id)` keying stored rows under the
/// bare entity id. Opening the adapter must migrate them in place: every row
/// survives, scoped reads find it, and a second user can then own the same id
/// without clobbering the first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_key_migration');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Map<String, dynamic> row(String id, String userId, {String name = '', int value = 0}) => ConformanceEntity.make(id, userId: userId, name: name, value: value).toDatumMap();

  test('legacy id-keyed rows are re-keyed on initialize and fully preserved', () async {
    // Seed a legacy box: keys are bare entity ids, as the old adapter wrote.
    final legacy = await Hive.openBox<Map<dynamic, dynamic>>('legacy_box');
    await legacy.put('settings', row('settings', 'u1', name: 'keep-me', value: 41));
    await legacy.put('note-1', row('note-1', 'u2', name: 'other-user-row', value: 7));
    await legacy.close();

    final adapter = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: 'legacy_box',
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();

    // Every legacy row survives and is found by its owner's scoped read.
    final u1Row = await adapter.read('settings', userId: 'u1');
    expect(u1Row?.name, 'keep-me');
    expect(u1Row?.value, 41);
    expect((await adapter.read('note-1', userId: 'u2'))?.name, 'other-user-row');
    expect((await adapter.readAll()).length, 2);

    // Post-migration, a second user can own the migrated id independently.
    await adapter.create(ConformanceEntity.make('settings', userId: 'u2', name: 'second-owner'));
    expect((await adapter.read('settings', userId: 'u1'))?.name, 'keep-me');
    expect((await adapter.read('settings', userId: 'u2'))?.name, 'second-owner');

    await adapter.dispose();
  });

  test('migration is idempotent across reopen', () async {
    final adapter = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: 'idempotent_box',
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    await adapter.create(ConformanceEntity.make('a', userId: 'u1', value: 1));
    await adapter.create(ConformanceEntity.make('a', userId: 'u2', value: 2));
    await adapter.dispose();

    final reopened = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: 'idempotent_box',
      fromMap: ConformanceEntity.fromMap,
    );
    await reopened.initialize();
    expect((await reopened.read('a', userId: 'u1'))?.value, 1);
    expect((await reopened.read('a', userId: 'u2'))?.value, 2);
    expect((await reopened.readAll()).length, 2);
    await reopened.dispose();
  });

  test('ids and userIds containing the separator characters stay distinct', () async {
    final adapter = HiveLocalAdapter<ConformanceEntity>(
      entityBoxName: 'separator_box',
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();

    // A crafted pair that would collide under naive '::' joining:
    // ('a::b', 'c') vs ('a', 'b::c').
    await adapter.create(ConformanceEntity.make('c', userId: 'a::b', value: 1));
    await adapter.create(ConformanceEntity.make('b::c', userId: 'a', value: 2));

    expect((await adapter.read('c', userId: 'a::b'))?.value, 1);
    expect((await adapter.read('b::c', userId: 'a'))?.value, 2);
    expect((await adapter.readAll()).length, 2);

    await adapter.dispose();
  });
}
