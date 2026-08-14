import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../support/task.dart';

Task _task(String id, {String user = 'u1', int priority = 1, String? title}) => Task(
  id: id,
  userId: user,
  title: title ?? 'T$id',
  priority: priority,
  modifiedAt: DateTime(2024),
  createdAt: DateTime(2024),
  version: 1,
);

DatumSyncOperation<Task> _op(
  String opId, {
  String user = 'u1',
  String entityId = 't1',
  int retryCount = 0,
  Map<String, dynamic>? delta,
}) => DatumSyncOperation<Task>(
  id: opId,
  userId: user,
  entityId: entityId,
  type: DatumOperationType.create,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  data: _task(entityId, user: user),
  delta: delta,
  retryCount: retryCount,
);

/// Polls [condition] until it is true or the timeout elapses.
Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late IsolatedHiveLocalAdapter<Task> adapter;
  var counter = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_iso_cov');
    await IsolatedHive.init(dir.path);
  });

  tearDownAll(() async {
    await IsolatedHive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async {
    adapter = IsolatedHiveLocalAdapter<Task>(entityBoxName: 'iso_tasks_${counter++}', fromMap: Task.fromMap);
    await adapter.initialize();
  });

  tearDown(() async {
    await adapter.dispose();
  });

  group('lifecycle', () {
    test('initialize opens the boxes and dispose closes them', () async {
      expect(await adapter.checkHealth(), AdapterHealthStatus.healthy);

      await adapter.dispose();

      expect(await adapter.checkHealth(), AdapterHealthStatus.unhealthy);
    });
  });

  group('CRUD', () {
    test('create then read round-trips an entity', () async {
      await adapter.create(_task('t1', priority: 4));

      final read = await adapter.read('t1');
      expect(read?.id, 't1');
      expect(read?.userId, 'u1');
      expect(read?.title, 'Tt1');
      expect(read?.priority, 4);
    });

    test('read returns null for a missing id or a mismatched userId', () async {
      await adapter.create(_task('t1'));

      expect(await adapter.read('missing'), isNull);
      expect(await adapter.read('t1', userId: 'u2'), isNull);
      expect((await adapter.read('t1', userId: 'u1'))?.id, 't1');
    });

    test('readAll returns all entities or only those of the given user', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2', user: 'u2'));

      expect((await adapter.readAll()).map((t) => t.id), unorderedEquals(['t1', 't2']));
      expect((await adapter.readAll(userId: 'u2')).map((t) => t.id), ['t2']);
    });

    test('readByIds returns only entities found for the user', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2'));
      await adapter.create(_task('t3', user: 'u2'));

      final result = await adapter.readByIds(['t1', 't2', 't3', 'missing'], userId: 'u1');

      expect(result.keys, unorderedEquals(['t1', 't2']));
      expect(result['t2']?.title, 'Tt2');
    });

    test('update persists new state', () async {
      await adapter.create(_task('t1'));
      await adapter.update(_task('t1', title: 'updated', priority: 9));

      final read = await adapter.read('t1');
      expect(read?.title, 'updated');
      expect(read?.priority, 9);
    });

    test('patch merges delta into the stored entity and persists it', () async {
      await adapter.create(_task('t1'));

      final patched = await adapter.patch(id: 't1', delta: {'title': 'patched', 'priority': 7});

      expect(patched.title, 'patched');
      expect(patched.priority, 7);
      final read = await adapter.read('t1');
      expect(read?.title, 'patched');
      expect(read?.priority, 7);
    });

    test('patch throws EntityNotFoundException for a missing id', () async {
      await expectLater(
        adapter.patch(id: 'nope', delta: {'title': 'x'}),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('delete returns true when the entity exists and false otherwise', () async {
      await adapter.create(_task('t1'));

      expect(await adapter.delete('t1'), isTrue);
      expect(await adapter.read('t1'), isNull);
      expect(await adapter.delete('t1'), isFalse);
    });

    test('clear removes every stored entity', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2', user: 'u2'));

      await adapter.clear();

      expect(await adapter.readAll(), isEmpty);
    });
  });

  group('clearUserData', () {
    test('removes pending ops, metadata and last sync result when the user has no stored entities', () async {
      await adapter.create(_task('other', user: 'u2'));
      await adapter.addPendingOperation('u1', _op('op1'));
      await adapter.updateSyncMetadata(const DatumSyncMetadata(userId: 'u1', dataHash: 'h1'), 'u1');
      await adapter.saveLastSyncResult(
        'u1',
        const DatumSyncResult<Task>(
          userId: 'u1',
          duration: Duration(milliseconds: 5),
          syncedCount: 1,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        ),
      );

      await adapter.clearUserData('u1');

      expect(await adapter.getPendingOperations('u1'), isEmpty);
      expect(await adapter.getSyncMetadata('u1'), isNull);
      expect(await adapter.getLastSyncResult('u1'), isNull);
      // Data of other users is untouched.
      expect((await adapter.readAll(userId: 'u2')).map((t) => t.id), ['other']);
    });

    test('deletes exactly the user\'s stored entities, leaving other users intact', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2'));
      await adapter.create(_task('other', user: 'u2'));

      await adapter.clearUserData('u1');

      expect(await adapter.readAll(userId: 'u1'), isEmpty);
      expect((await adapter.readAll(userId: 'u2')).map((t) => t.id), ['other']);
    });
  });

  group('pending operations', () {
    test('addPendingOperation appends new operations and round-trips them', () async {
      await adapter.addPendingOperation('u1', _op('op1', delta: {'title': 'x'}));
      await adapter.addPendingOperation('u1', _op('op2', entityId: 't2'));

      final ops = await adapter.getPendingOperations('u1');
      expect(ops, hasLength(2));
      final op1 = ops.firstWhere((o) => o.id == 'op1');
      expect(op1.userId, 'u1');
      expect(op1.entityId, 't1');
      expect(op1.type, DatumOperationType.create);
      expect(op1.timestamp, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(op1.data?.id, 't1');
      expect(op1.delta, {'title': 'x'});
    });

    test('addPendingOperation replaces an existing operation with the same id', () async {
      await adapter.addPendingOperation('u1', _op('op1'));
      await adapter.addPendingOperation('u1', _op('op1', retryCount: 3));

      final ops = await adapter.getPendingOperations('u1');
      expect(ops, hasLength(1));
      expect(ops.single.retryCount, 3);
    });

    test('getPendingOperations returns an empty list for an unknown user', () async {
      expect(await adapter.getPendingOperations('ghost'), isEmpty);
    });

    test('removePendingOperation removes only the matching operation', () async {
      await adapter.addPendingOperation('u1', _op('op1'));
      await adapter.addPendingOperation('u2', _op('op2', user: 'u2', entityId: 't2'));

      await adapter.removePendingOperation('op2');

      expect((await adapter.getPendingOperations('u1')).map((o) => o.id), ['op1']);
      expect(await adapter.getPendingOperations('u2'), isEmpty);
    });

    test('removePendingOperation is a no-op for an unknown operation id', () async {
      await adapter.addPendingOperation('u1', _op('op1'));

      await adapter.removePendingOperation('does-not-exist');

      expect((await adapter.getPendingOperations('u1')).map((o) => o.id), ['op1']);
    });
  });

  group('raw data and user ids', () {
    test('getAllUserIds returns the distinct set of user ids', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2'));
      await adapter.create(_task('t3', user: 'u2'));

      expect(await adapter.getAllUserIds(), unorderedEquals(['u1', 'u2']));
    });

    test('getAllRawData returns raw maps, optionally scoped to a user', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2', user: 'u2'));

      final all = await adapter.getAllRawData();
      expect(all.map((m) => m['id']), unorderedEquals(['t1', 't2']));

      final scoped = await adapter.getAllRawData(userId: 'u2');
      expect(scoped.map((m) => m['id']), ['t2']);
    });

    test('overwriteAllRawData without a userId replaces the whole box', () async {
      await adapter.create(_task('old'));

      await adapter.overwriteAllRawData([
        _task('n1').toDatumMap(),
        _task('n2', user: 'u2').toDatumMap(),
      ]);

      expect((await adapter.readAll()).map((t) => t.id), unorderedEquals(['n1', 'n2']));
    });

    test('overwriteAllRawData scoped to a userId clears that user and stores the new data', () async {
      // The target user has metadata but no entities, so clearUserData succeeds.
      await adapter.create(_task('keep', user: 'u2'));
      await adapter.updateSyncMetadata(const DatumSyncMetadata(userId: 'u1', dataHash: 'h1'), 'u1');

      await adapter.overwriteAllRawData([_task('t9').toDatumMap()], userId: 'u1');

      expect(await adapter.getSyncMetadata('u1'), isNull);
      expect((await adapter.readAll(userId: 'u1')).map((t) => t.id), ['t9']);
      expect((await adapter.readAll(userId: 'u2')).map((t) => t.id), ['keep']);
    });

    test('getAllRawData normalizes nested maps and lists of maps', () async {
      await adapter.overwriteAllRawData([
        {
          'id': 't1',
          'userId': 'u1',
          'nested': {'a': 1},
          'items': [
            {'b': 2},
            'plain',
          ],
        },
      ]);

      final raw = await adapter.getAllRawData();
      expect(raw, hasLength(1));
      expect(raw.single['nested'], isA<Map<String, dynamic>>());
      expect((raw.single['nested'] as Map)['a'], 1);
      final items = raw.single['items'] as List;
      expect(items.first, isA<Map<String, dynamic>>());
      expect((items.first as Map)['b'], 2);
      expect(items.last, 'plain');
    });
  });

  group('schema version', () {
    test('getStoredSchemaVersion falls back to the constructor baseline', () async {
      expect(await adapter.getStoredSchemaVersion(), 0);
    });

    test('setStoredSchemaVersion persists the version for later reads', () async {
      await adapter.setStoredSchemaVersion(4);

      expect(adapter.schemaVersion, 4);
      expect(await adapter.getStoredSchemaVersion(), 4);
    });
  });

  group('sync metadata and results', () {
    test('getSyncMetadata returns null when nothing is stored', () async {
      expect(await adapter.getSyncMetadata('u1'), isNull);
    });

    test('updateSyncMetadata stores metadata that getSyncMetadata round-trips', () async {
      const metadata = DatumSyncMetadata(
        userId: 'u1',
        dataHash: 'hash-1',
        deviceId: 'device-1',
        customMetadata: {'flavor': 'test'},
      );

      await adapter.updateSyncMetadata(metadata, 'u1');
      final restored = await adapter.getSyncMetadata('u1');

      expect(restored?.userId, 'u1');
      expect(restored?.dataHash, 'hash-1');
      expect(restored?.deviceId, 'device-1');
      expect(restored?.customMetadata, {'flavor': 'test'});
      expect(restored?.syncStatus, SyncStatus.neverSynced);
    });

    test('getLastSyncResult returns null when nothing is stored', () async {
      expect(await adapter.getLastSyncResult('u1'), isNull);
    });

    test('saveLastSyncResult stores a result that getLastSyncResult round-trips', () async {
      const result = DatumSyncResult<Task>(
        userId: 'u1',
        duration: Duration(milliseconds: 250),
        syncedCount: 3,
        failedCount: 1,
        conflictsResolved: 2,
        pendingOperations: [],
        totalBytesPushed: 10,
        totalBytesPulled: 20,
      );

      await adapter.saveLastSyncResult('u1', result);
      final restored = await adapter.getLastSyncResult('u1');

      expect(restored?.userId, 'u1');
      expect(restored?.duration, const Duration(milliseconds: 250));
      expect(restored?.syncedCount, 3);
      expect(restored?.failedCount, 1);
      expect(restored?.conflictsResolved, 2);
      expect(restored?.totalBytesPushed, 10);
      expect(restored?.totalBytesPulled, 20);
    });
  });

  group('transaction, health and size', () {
    test('transaction runs the action and returns its result', () async {
      final result = await adapter.transaction(() async {
        await adapter.create(_task('t1'));
        return 42;
      });

      expect(result, 42);
      expect((await adapter.read('t1'))?.id, 't1');
    });

    test('getStorageSize reflects stored data and returns 0 once the box is closed', () async {
      await adapter.create(_task('t1'));

      final size = await adapter.getStorageSize(userId: 'u1');
      expect(size, greaterThan(2));

      await adapter.dispose();
      expect(await adapter.getStorageSize(), 0);
    });
  });

  group('pagination and queries', () {
    test('readAllPaginated returns pages with hasMore flags', () async {
      for (var i = 0; i < 5; i++) {
        await adapter.create(_task('e$i', priority: i));
      }

      final first = await adapter.readAllPaginated(const PaginationConfig(pageSize: 2, currentPage: 1), userId: 'u1');
      expect(first.items, hasLength(2));
      expect(first.totalCount, 5);
      expect(first.totalPages, 3);
      expect(first.hasMore, isTrue);

      final last = await adapter.readAllPaginated(const PaginationConfig(pageSize: 2, currentPage: 3), userId: 'u1');
      expect(last.items, hasLength(1));
      expect(last.hasMore, isFalse);
    });

    test('readAllPaginated returns an empty page past the end of the data', () async {
      await adapter.create(_task('t1'));

      final page = await adapter.readAllPaginated(const PaginationConfig(pageSize: 2, currentPage: 9), userId: 'u1');

      expect(page.items, isEmpty);
      expect(page.totalCount, 1);
      expect(page.currentPage, 9);
      expect(page.totalPages, 1);
      expect(page.hasMore, isFalse);
    });

    test('query honors filters and sorting', () async {
      await adapter.create(_task('a', priority: 5));
      await adapter.create(_task('b', priority: 1));
      await adapter.create(_task('c', priority: 3));

      final result = await adapter.query(
        (DatumQueryBuilder<Task>()
              ..where('priority', isGreaterThanOrEqualTo: 3)
              ..orderBy('priority', descending: true))
            .build(),
        userId: 'u1',
      );

      expect(result.map((t) => t.id).toList(), ['a', 'c']);
    });
  });

  group('streams', () {
    test('changeStream emits details for writes and removals', () async {
      final events = <DatumChangeDetail<Task>>[];
      final sub = adapter.changeStream()!.listen(events.add);
      addTearDown(sub.cancel);

      await adapter.create(_task('t1'));
      await _waitUntil(() => events.isNotEmpty);

      expect(events.first.entityId, 't1');
      expect(events.first.userId, 'u1');
      expect(events.first.type, DatumOperationType.update);
      expect(events.first.data?.id, 't1');

      await adapter.delete('t1');
      await _waitUntil(() => events.length >= 2);

      expect(events.last.entityId, 't1');
      expect(events.last.type, DatumOperationType.delete);
    });

    test('watchAll with includeInitialData emits the current list first', () async {
      await adapter.create(_task('t1'));

      final emissions = <List<Task>>[];
      final sub = adapter.watchAll(userId: 'u1')!.listen(emissions.add);
      addTearDown(sub.cancel);

      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions.first.map((t) => t.id), ['t1']);

      await adapter.create(_task('t2'));
      await _waitUntil(() => emissions.length >= 2);
      expect(emissions.last.map((t) => t.id), unorderedEquals(['t1', 't2']));
    });

    test('watchAll without initial data only emits on box events', () async {
      await adapter.create(_task('t1'));

      final emissions = <List<Task>>[];
      final sub = adapter.watchAll(userId: 'u1', includeInitialData: false)!.listen(emissions.add);
      addTearDown(sub.cancel);

      // No initial emission; the first one arrives with the next write.
      await adapter.create(_task('t2'));
      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions.first.map((t) => t.id), unorderedEquals(['t1', 't2']));
    });

    test('watchQuery applies the query to every emission', () async {
      final query = (DatumQueryBuilder<Task>()..where('priority', isGreaterThanOrEqualTo: 5)).build();
      final emissions = <List<Task>>[];
      final sub = adapter.watchQuery(query, userId: 'u1')!.listen(emissions.add);
      addTearDown(sub.cancel);

      await _waitUntil(() => emissions.isNotEmpty); // initial (empty) data
      expect(emissions.first, isEmpty);

      await adapter.create(_task('high', priority: 9));
      await _waitUntil(() => emissions.length >= 2);
      expect(emissions.last.map((t) => t.id), ['high']);
    });
  });
}
