import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:datum_test/datum_test.dart';
import 'package:test/test.dart';
import 'package:hive_ce/hive_ce.dart';

/// The pending-op queue: per-user isolation, insertion order (also across a
/// reopen), retries keeping their position, user clears, and migration of the
/// legacy one-List-per-user `<box>_pending_ops` layout.
void main() {

  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_pending_queue');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  DatumSyncOperation<ConformanceEntity> op(String id, String userId, {int retries = 0}) => DatumSyncOperation<ConformanceEntity>(
        id: id,
        userId: userId,
        entityId: 'e-$id',
        type: DatumOperationType.create,
        timestamp: DateTime.utc(2026),
        data: ConformanceEntity.make('e-$id', userId: userId, name: id),
        retryCount: retries,
      );

  HiveLocalAdapter<ConformanceEntity> adapterFor(String box) => HiveLocalAdapter<ConformanceEntity>(entityBoxName: box, fromMap: ConformanceEntity.fromMap);

  test('ordered per-user queue survives reopen, retries keep position, clears are scoped', () async {
    var adapter = adapterFor('queue_box');
    await adapter.initialize();

    for (var i = 0; i < 200; i++) {
      await adapter.addPendingOperation(i.isEven ? 'u1' : 'u2', op('op$i', i.isEven ? 'u1' : 'u2'));
    }
    await adapter.addPendingOperation('u1', op('op2', 'u1', retries: 3));

    var u1 = await adapter.getPendingOperations('u1');
    expect(u1.length, 100);
    expect(u1.take(3).map((o) => o.id), ['op0', 'op2', 'op4']);
    expect(u1[1].retryCount, 3);
    expect(u1[1].data?.name, 'op2', reason: 'entity payload round-trips');

    await adapter.removePendingOperation('op0');
    await adapter.removePendingOperation('missing');
    await adapter.dispose();

    adapter = adapterFor('queue_box');
    await adapter.initialize();
    u1 = await adapter.getPendingOperations('u1');
    expect(u1.length, 99);
    expect(u1.first.id, 'op2');
    expect(u1.last.id, 'op198');
    await adapter.addPendingOperation('u1', op('late', 'u1'));
    expect((await adapter.getPendingOperations('u1')).last.id, 'late', reason: 'new ops queue after reopened ones');

    await adapter.clearUserData('u1');
    expect(await adapter.getPendingOperations('u1'), isEmpty);
    expect((await adapter.getPendingOperations('u2')).length, 100);
    await adapter.dispose();
  });

  test('legacy List-per-user queue is migrated in order and the old box removed', () async {
    final legacy = await Hive.openBox<List<dynamic>>('old_box_pending_ops');
    await legacy.put('u1', [op('a', 'u1').toMap(), op('b', 'u1').toMap(), op('c', 'u1').toMap()]);
    await legacy.put('u2', [op('z', 'u2').toMap()]);
    await legacy.close();

    final adapter = adapterFor('old_box');
    await adapter.initialize();

    expect((await adapter.getPendingOperations('u1')).map((o) => o.id), ['a', 'b', 'c']);
    expect((await adapter.getPendingOperations('u2')).map((o) => o.id), ['z']);
    expect(await Hive.boxExists('old_box_pending_ops'), isFalse);

    await adapter.removePendingOperation('b');
    expect((await adapter.getPendingOperations('u1')).map((o) => o.id), ['a', 'c']);
    await adapter.dispose();
  });
}
