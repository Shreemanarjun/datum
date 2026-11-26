import 'package:datum/datum.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Bulk writes (the sync engine's pull path), count/first pushdown and the
/// pending-op queue order — the production hot paths of the adapter.
void main() {
  late Database db;
  late SqliteLocalAdapter<ConformanceEntity> adapter;

  ConformanceEntity entity(String id, {String user = 'u1', int value = 0, int version = 1}) => ConformanceEntity(
        id: id,
        userId: user,
        name: id,
        value: value,
        modifiedAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
        version: version,
      );

  setUp(() async {
    db = sqlite3.openInMemory();
    adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'bulk',
      fromMap: ConformanceEntity.fromMap,
      columns: const {'name': 'TEXT', 'value': 'INTEGER'},
    );
    await adapter.initialize();
  });

  tearDown(() => db.dispose());

  test('createAll/updateAll write atomically, notify per row, and join an outer transaction', () async {
    final changes = <DatumChangeDetail<ConformanceEntity>>[];
    final sub = adapter.changeStream()!.listen(changes.add);
    addTearDown(sub.cancel);

    await adapter.createAll([for (var i = 0; i < 50; i++) entity('e$i', value: i, user: i.isEven ? 'u1' : 'u2')]);
    expect(db.autocommit, isTrue, reason: 'bulk write commits its own transaction');
    expect((await adapter.readAll()).length, 50);
    expect((await adapter.readAll(userId: 'u1')).length, 25);

    await adapter.updateAll([entity('e0', value: 100, version: 2), entity('e1', value: 101, version: 2, user: 'u2')]);
    expect((await adapter.read('e0', userId: 'u1'))!.value, 100);
    expect((await adapter.read('e1', userId: 'u2'))!.value, 101);

    await adapter.createAll(const []);
    await Future<void>.delayed(Duration.zero);
    expect(changes.where((c) => c.type == DatumOperationType.create).length, 50);
    expect(changes.where((c) => c.type == DatumOperationType.update).map((c) => c.entityId), ['e0', 'e1']);

    // Inside an outer transaction the bulk write joins it, so an outer
    // rollback discards the rows too.
    await expectLater(
      adapter.transaction(() async {
        await adapter.createAll([entity('x1'), entity('x2')]);
        throw StateError('abort');
      }),
      throwsStateError,
    );
    expect(await adapter.read('x1', userId: 'u1'), isNull);
    expect(db.autocommit, isTrue);
  });

  test('watchCount and watchFirst push down to SQL and coalesce bursts', () async {
    final counts = <int>[];
    final firsts = <String?>[];
    final query = (DatumQueryBuilder<ConformanceEntity>()..where('value', isGreaterThanOrEqualTo: 10)).build();
    final s1 = adapter.watchCount(query: query, userId: 'u1')!.listen(counts.add);
    final s2 = adapter.watchFirst(userId: 'u1')!.listen((e) => firsts.add(e?.id));
    addTearDown(s1.cancel);
    addTearDown(s2.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(counts, [0]);
    expect(firsts, [null]);

    for (var i = 0; i < 20; i++) {
      await adapter.create(entity('c$i', value: i));
    }
    await adapter.create(entity('other', value: 99, user: 'u2'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(counts.last, 10);
    expect(counts.length, lessThan(20), reason: 'a write burst is coalesced');
    expect(firsts.last, isNotNull);
  });

  test('pending ops keep insertion order, and a retried op keeps its position', () async {
    DatumSyncOperation<ConformanceEntity> op(String id, {int retries = 0}) => DatumSyncOperation<ConformanceEntity>(
          id: id,
          userId: 'u1',
          entityId: 'e-$id',
          type: DatumOperationType.create,
          timestamp: DateTime.utc(2026),
          data: entity('e-$id'),
          retryCount: retries,
        );

    for (final id in ['a', 'b', 'c', 'd']) {
      await adapter.addPendingOperation('u1', op(id));
    }
    await adapter.addPendingOperation('u2', op('z'));
    await adapter.addPendingOperation('u1', op('b', retries: 1));

    final pending = await adapter.getPendingOperations('u1');
    expect(pending.map((o) => o.id), ['a', 'b', 'c', 'd']);
    expect(pending[1].retryCount, 1);

    await adapter.removePendingOperation('a');
    expect((await adapter.getPendingOperations('u1')).map((o) => o.id), ['b', 'c', 'd']);
    expect((await adapter.getPendingOperations('u2')).map((o) => o.id), ['z']);
  });
}
