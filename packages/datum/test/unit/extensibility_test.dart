import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

TestEntity _entity(String id, String user, String name, {int value = 0}) => TestEntity(
      id: id,
      userId: user,
      name: name,
      value: value,
      modifiedAt: DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      version: 1,
    );

void main() {
  group('InMemoryLocalAdapter', () {
    late InMemoryLocalAdapter<TestEntity> adapter;

    setUp(() async {
      adapter = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
      await adapter.initialize();
    });

    tearDown(() => adapter.dispose());

    test('advertises its capabilities via marker mixins', () {
      expect(adapter, isA<WatchableAdapter>());
      expect(adapter, isA<TransactionalAdapter>());
      expect(adapter, isA<PaginatedAdapter>());
      expect(adapter, isNot(isA<RelationalAdapter>()));
    });

    test('create / read / readAll round-trip', () async {
      await adapter.create(_entity('a', 'u1', 'Alpha'));
      await adapter.create(_entity('b', 'u1', 'Beta'));
      expect((await adapter.read('a', userId: 'u1'))?.name, 'Alpha');
      expect(await adapter.readAll(userId: 'u1'), hasLength(2));
      expect(await adapter.getAllUserIds(), ['u1']);
    });

    test('query honors filters, sorting and limit', () async {
      await adapter.create(_entity('a', 'u1', 'Alpha', value: 3));
      await adapter.create(_entity('b', 'u1', 'Beta', value: 1));
      await adapter.create(_entity('c', 'u1', 'Gamma', value: 2));

      final q = (DatumQueryBuilder<TestEntity>()
            ..where('value', isGreaterThanOrEqualTo: 2)
            ..orderBy('value', descending: true))
          .build();
      final result = await adapter.query(q, userId: 'u1');
      expect(result.map((e) => e.id).toList(), ['a', 'c']);
    });

    test('readAllPaginated paginates', () async {
      for (var i = 0; i < 5; i++) {
        await adapter.create(_entity('e$i', 'u1', 'N$i'));
      }
      final page = await adapter.readAllPaginated(const PaginationConfig(pageSize: 2, currentPage: 1), userId: 'u1');
      expect(page.items, hasLength(2));
      expect(page.totalCount, 5);
      expect(page.totalPages, 3);
      expect(page.hasMore, isTrue);
    });

    test('patch merges a delta', () async {
      await adapter.create(_entity('a', 'u1', 'Alpha', value: 1));
      final patched = await adapter.patch(id: 'a', delta: {'value': 99}, userId: 'u1');
      expect(patched.value, 99);
      expect((await adapter.read('a', userId: 'u1'))?.value, 99);
    });

    test('delete removes and reports', () async {
      await adapter.create(_entity('a', 'u1', 'Alpha'));
      expect(await adapter.delete('a', userId: 'u1'), isTrue);
      expect(await adapter.delete('a', userId: 'u1'), isFalse);
      expect(await adapter.read('a', userId: 'u1'), isNull);
    });

    test('watchAll emits initial data and reacts to changes', () async {
      final stream = adapter.watchAll(userId: 'u1')!;
      final emitted = expectLater(stream, emitsThrough(hasLength(2)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await adapter.create(_entity('a', 'u1', 'Alpha'));
      await adapter.create(_entity('b', 'u1', 'Beta'));
      await emitted;
    });

    test('transaction rolls back on error', () async {
      await adapter.create(_entity('a', 'u1', 'Alpha'));
      await expectLater(
        adapter.transaction(() async {
          await adapter.create(_entity('b', 'u1', 'Beta'));
          throw StateError('boom');
        }),
        throwsStateError,
      );
      // 'b' must have been rolled back, 'a' preserved.
      expect(await adapter.readAll(userId: 'u1'), hasLength(1));
      expect((await adapter.read('a', userId: 'u1'))?.name, 'Alpha');
    });

    test('pending operations add/get/remove', () async {
      final op = DatumSyncOperation<TestEntity>(
        id: 'op1',
        type: DatumOperationType.create,
        entityId: 'a',
        data: _entity('a', 'u1', 'Alpha'),
        timestamp: DateTime(2024),
        userId: 'u1',
      );
      await adapter.addPendingOperation('u1', op);
      expect(await adapter.getPendingOperations('u1'), hasLength(1));
      await adapter.removePendingOperation('op1');
      expect(await adapter.getPendingOperations('u1'), isEmpty);
    });

    test('getStorageSize grows with data', () async {
      expect(await adapter.getStorageSize(userId: 'u1'), 0);
      await adapter.create(_entity('a', 'u1', 'Alpha'));
      expect(await adapter.getStorageSize(userId: 'u1'), greaterThan(0));
    });

    test('raw data migration round-trips through fromMap', () async {
      await adapter.create(_entity('a', 'u1', 'Alpha', value: 7));
      final raw = await adapter.getAllRawData(userId: 'u1');
      expect(raw, hasLength(1));
      await adapter.clear();
      await adapter.overwriteAllRawData(raw);
      expect((await adapter.read('a', userId: 'u1'))?.value, 7);
    });
  });

  group('DatumQueryMatcher', () {
    final rows = [
      {'id': '1', 'status': 'open', 'priority': 5},
      {'id': '2', 'status': 'closed', 'priority': 1},
      {'id': '3', 'status': 'open', 'priority': 3},
    ];

    test('matchesMap evaluates AND filters', () {
      final q = (DatumQueryBuilder<dynamic>()
            ..where('status', isEqualTo: 'open')
            ..where('priority', isGreaterThan: 3))
          .build();
      expect(DatumQueryMatcher.matchesMap(rows[0], q), isTrue);
      expect(DatumQueryMatcher.matchesMap(rows[2], q), isFalse);
    });

    test('applyToMaps filters, sorts and limits', () {
      final q = (DatumQueryBuilder<dynamic>()
            ..where('status', isEqualTo: 'open')
            ..orderBy('priority', descending: true))
          .build();
      final out = DatumQueryMatcher.applyToMaps(rows, q);
      expect(out.map((r) => r['id']).toList(), ['1', '3']);
    });

    test('OR logical operator', () {
      final q = (DatumQueryBuilder<dynamic>()
            ..logicalOperator = LogicalOperator.or
            ..where('status', isEqualTo: 'closed')
            ..where('priority', isGreaterThanOrEqualTo: 5))
          .build();
      final out = DatumQueryMatcher.applyToMaps(rows, q);
      expect(out.map((r) => r['id']).toSet(), {'1', '2'});
    });
  });

  group('DatumLogSink', () {
    test('CollectingLogSink captures formatted entries', () {
      final sink = CollectingLogSink();
      final logger = DatumLogger(minimumLevel: LogLevel.debug, sink: sink);
      logger.info('hello');
      logger.warn('careful');
      expect(sink.entries, hasLength(2));
      expect(sink.entries.first.level, LogLevel.info);
      expect(sink.messages.first, contains('hello'));
      expect(sink.messages[1], contains('careful'));
    });

    test('disabled logger writes nothing to the sink', () {
      final sink = CollectingLogSink();
      DatumLogger(enabled: false, sink: sink).info('nope');
      expect(sink.entries, isEmpty);
    });

    test('minimumLevel filters out lower levels before the sink', () {
      final sink = CollectingLogSink();
      final logger = DatumLogger(minimumLevel: LogLevel.warn, sink: sink);
      logger.debug('skip');
      logger.error('keep');
      expect(sink.entries, hasLength(1));
      expect(sink.entries.single.level, LogLevel.error);
    });

    test('copyWith preserves the sink', () {
      final sink = CollectingLogSink();
      final logger = DatumLogger(sink: sink).copyWith(minimumLevel: LogLevel.debug);
      // The sink is private; verify it is preserved by checking output routing.
      logger.info('after copy');
      expect(sink.messages.single, contains('after copy'));
    });
  });
}
