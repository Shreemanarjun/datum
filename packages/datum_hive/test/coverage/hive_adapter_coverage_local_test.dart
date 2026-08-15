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
  final deadline = DateTime.now().add(const Duration(seconds: 5));
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
  late HiveLocalAdapter<Task> adapter;
  var counter = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_cov');
    Hive.init(dir.path);
    adapter = HiveLocalAdapter<Task>(entityBoxName: 'cov_tasks_${counter++}', fromMap: Task.fromMap);
    await adapter.initialize();
  });

  tearDown(() async {
    await adapter.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  group('CRUD', () {
    test('update persists new state', () async {
      await adapter.create(_task('t1'));
      await adapter.update(_task('t1', title: 'updated', priority: 9));

      final read = await adapter.read('t1', userId: 'u1');
      expect(read?.title, 'updated');
      expect(read?.priority, 9);
    });

    test('readByIds returns only entities found for the user', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2'));
      await adapter.create(_task('t3', user: 'u2'));

      final result = await adapter.readByIds(['t1', 't2', 't3', 'missing'], userId: 'u1');

      expect(result.keys, unorderedEquals(['t1', 't2']));
      expect(result['t1']?.title, 'Tt1');
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

  group('health and size', () {
    test('getStorageSize reflects stored data and returns 0 once the box is closed', () async {
      await adapter.create(_task('t1'));

      final size = await adapter.getStorageSize(userId: 'u1');
      expect(size, greaterThan(2));

      await adapter.dispose();
      expect(await adapter.getStorageSize(), 0);
    });

    test('checkHealth is healthy while boxes are open and unhealthy after dispose', () async {
      expect(await adapter.checkHealth(), AdapterHealthStatus.healthy);

      await adapter.dispose();
      expect(await adapter.checkHealth(), AdapterHealthStatus.unhealthy);
    });
  });

  group('pagination', () {
    test('readAllPaginated returns an empty page past the end of the data', () async {
      await adapter.create(_task('t1'));
      await adapter.create(_task('t2'));
      await adapter.create(_task('t3'));

      final page = await adapter.readAllPaginated(const PaginationConfig(pageSize: 2, currentPage: 5), userId: 'u1');

      expect(page.items, isEmpty);
      expect(page.totalCount, 3);
      expect(page.currentPage, 5);
      expect(page.totalPages, 2);
      expect(page.hasMore, isFalse);
    });
  });

  group('streams', () {
    test('changeStream emits update details for writes and delete details for removals', () async {
      final events = <DatumChangeDetail<Task>>[];
      final sub = adapter.changeStream()!.listen(events.add);
      addTearDown(sub.cancel);

      await adapter.create(_task('t1'));
      await _waitUntil(() => events.length == 1);

      expect(events.single.entityId, 't1');
      expect(events.single.userId, 'u1');
      expect(events.single.type, DatumOperationType.update);
      expect(events.single.data?.id, 't1');

      await adapter.delete('t1');
      await _waitUntil(() => events.length == 2);

      expect(events.last.entityId, 't1');
      // Hive delete events still carry the removed value, so the detail
      // resolves the entity (and its userId) from that final snapshot.
      expect(events.last.userId, 'u1');
      expect(events.last.type, DatumOperationType.delete);
      expect(events.last.data?.id, 't1');
    });

    test('watchAll emits the filtered entity list on every box event', () async {
      final emissions = <List<Task>>[];
      final sub = adapter.watchAll(userId: 'u1')!.listen(emissions.add);
      addTearDown(sub.cancel);

      // An initial snapshot precedes write-triggered emissions, so assert
      // on content rather than exact event counts.
      await adapter.create(_task('t1'));
      await _waitUntil(() => emissions.isNotEmpty && emissions.last.isNotEmpty);
      expect(emissions.last.map((t) => t.id), ['t1']);

      // A write for another user still triggers an emission, filtered to u1.
      final seen = emissions.length;
      await adapter.create(_task('t2', user: 'u2'));
      await _waitUntil(() => emissions.length > seen);
      expect(emissions.last.map((t) => t.id), ['t1']);
    });

    test('watchQuery applies the query to every emission', () async {
      final query = (DatumQueryBuilder<Task>()..where('priority', isGreaterThanOrEqualTo: 5)).build();
      final emissions = <List<Task>>[];
      final sub = adapter.watchQuery(query, userId: 'u1')!.listen(emissions.add);
      addTearDown(sub.cancel);

      // Initial snapshot + one emission per write; assert on content since
      // exact counts depend on snapshot timing.
      await adapter.create(_task('low', priority: 1));
      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions.last, isEmpty, reason: 'low priority is filtered out');

      await adapter.create(_task('high', priority: 9));
      await _waitUntil(() => emissions.isNotEmpty && emissions.last.isNotEmpty);
      expect(emissions.last.map((t) => t.id), ['high']);
    });
  });
}
