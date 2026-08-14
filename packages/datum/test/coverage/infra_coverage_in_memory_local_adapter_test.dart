import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

TestEntity _entity(
  String id,
  String userId, {
  String name = 'name',
  int value = 0,
  bool completed = false,
}) =>
    TestEntity(
      id: id,
      userId: userId,
      name: name,
      value: value,
      modifiedAt: DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      version: 1,
      completed: completed,
    );

/// Waits for pending microtasks/events so that async stream emissions settle.
Future<void> _pump([int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('InMemoryLocalAdapter', () {
    late InMemoryLocalAdapter<TestEntity> adapter;

    setUp(() async {
      adapter = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
      await adapter.initialize();
    });

    tearDown(() async {
      await adapter.dispose();
    });

    group('read without userId', () {
      test('scans across all users and finds the entity', () async {
        await adapter.create(_entity('a', 'user-1', name: 'alpha'));
        await adapter.create(_entity('b', 'user-2', name: 'beta'));

        final found = await adapter.read('b');

        expect(found, isNotNull);
        expect(found!.name, 'beta');
        expect(found.userId, 'user-2');
      });

      test('returns null when the id exists for no user', () async {
        await adapter.create(_entity('a', 'user-1'));

        final found = await adapter.read('missing');

        expect(found, isNull);
      });
    });

    group('readAllPaginated out-of-range page', () {
      test('returns an empty page when start >= totalCount', () async {
        await adapter.create(_entity('1', 'user-1'));
        await adapter.create(_entity('2', 'user-1'));
        await adapter.create(_entity('3', 'user-1'));

        final page = await adapter.readAllPaginated(
          const PaginationConfig(pageSize: 2, currentPage: 3),
          userId: 'user-1',
        );

        expect(page.items, isEmpty);
        expect(page.totalCount, 3);
        expect(page.currentPage, 3);
        expect(page.totalPages, 2);
        expect(page.hasMore, isFalse);
      });

      test('returns an empty page for an empty store', () async {
        final page = await adapter.readAllPaginated(
          const PaginationConfig(pageSize: 5, currentPage: 1),
          userId: 'user-1',
        );

        expect(page.items, isEmpty);
        expect(page.totalCount, 0);
        expect(page.totalPages, 0);
        expect(page.hasMore, isFalse);
      });
    });

    test('patch throws EntityNotFoundException for a missing entity', () async {
      await expectLater(
        adapter.patch(id: 'ghost', delta: {'name': 'x'}, userId: 'user-1'),
        throwsA(
          isA<EntityNotFoundException>().having(
            (e) => e.message,
            'message',
            contains('ghost'),
          ),
        ),
      );
    });

    test('clearUserData removes only the given user\'s state', () async {
      await adapter.create(_entity('1', 'user-1'));
      await adapter.create(_entity('2', 'user-2'));
      await adapter.addPendingOperation(
        'user-1',
        DatumSyncOperation<TestEntity>(
          id: 'op-1',
          userId: 'user-1',
          entityId: '1',
          type: DatumOperationType.create,
          timestamp: DateTime(2024, 1, 1),
          data: _entity('1', 'user-1'),
        ),
      );
      await adapter.updateSyncMetadata(
        const DatumSyncMetadata(userId: 'user-1'),
        'user-1',
      );
      await adapter.saveLastSyncResult(
        'user-1',
        const DatumSyncResult<TestEntity>(
          userId: 'user-1',
          duration: Duration.zero,
          syncedCount: 1,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        ),
      );

      await adapter.clearUserData('user-1');

      expect(await adapter.readAll(userId: 'user-1'), isEmpty);
      expect(await adapter.getPendingOperations('user-1'), isEmpty);
      expect(await adapter.getSyncMetadata('user-1'), isNull);
      expect(await adapter.getLastSyncResult('user-1'), isNull);
      // Other users are unaffected.
      expect(await adapter.readAll(userId: 'user-2'), hasLength(1));
    });

    group('reactive watch methods', () {
      test('watchById emits initial value, updates and deletion', () async {
        await adapter.create(_entity('1', 'user-1', name: 'first'));

        final emissions = <TestEntity?>[];
        final sub = adapter.watchById('1', userId: 'user-1')!.listen(emissions.add);
        await _pump();

        expect(emissions, hasLength(1));
        expect(emissions.single!.name, 'first');

        await adapter.update(_entity('1', 'user-1', name: 'renamed'));
        await _pump();
        expect(emissions.last!.name, 'renamed');

        await adapter.delete('1', userId: 'user-1');
        await _pump();
        expect(emissions.last, isNull);

        await sub.cancel();
      });

      test('watchAllPaginated re-emits pages when data changes', () async {
        await adapter.create(_entity('1', 'user-1'));
        await adapter.create(_entity('2', 'user-1'));
        await adapter.create(_entity('3', 'user-1'));

        final emissions = <PaginatedResult<TestEntity>>[];
        final sub = adapter
            .watchAllPaginated(
              const PaginationConfig(pageSize: 2, currentPage: 1),
              userId: 'user-1',
            )!
            .listen(emissions.add);
        await _pump();

        expect(emissions, hasLength(1));
        expect(emissions.first.items, hasLength(2));
        expect(emissions.first.totalCount, 3);
        expect(emissions.first.hasMore, isTrue);

        await adapter.create(_entity('4', 'user-1'));
        await _pump();

        expect(emissions.last.totalCount, 4);
        expect(emissions.last.totalPages, 2);

        await sub.cancel();
      });

      test('watchCount emits counts with and without a query', () async {
        await adapter.create(_entity('1', 'user-1', completed: true));
        await adapter.create(_entity('2', 'user-1'));

        final allCounts = <int>[];
        final completedCounts = <int>[];
        final completedQuery = DatumQueryBuilder<TestEntity>().where('completed', isEqualTo: true).build();

        final allSub = adapter.watchCount(userId: 'user-1')!.listen(allCounts.add);
        final querySub = adapter.watchCount(query: completedQuery, userId: 'user-1')!.listen(completedCounts.add);
        await _pump();

        expect(allCounts, [2]);
        expect(completedCounts, [1]);

        await adapter.create(_entity('3', 'user-1', completed: true));
        await _pump();

        expect(allCounts.last, 3);
        expect(completedCounts.last, 2);

        await allSub.cancel();
        await querySub.cancel();
      });

      test('watchFirst emits null when empty, then the first match', () async {
        final emissions = <TestEntity?>[];
        final sub = adapter.watchFirst(userId: 'user-1')!.listen(emissions.add);
        await _pump();

        expect(emissions, [isNull]);

        await adapter.create(_entity('1', 'user-1', name: 'only'));
        await _pump();

        expect(emissions.last, isNotNull);
        expect(emissions.last!.name, 'only');

        await sub.cancel();
      });

      test('watchFirst with a query emits the first matching entity', () async {
        await adapter.create(_entity('1', 'user-1'));
        await adapter.create(_entity('2', 'user-1', completed: true, name: 'done'));

        final completedQuery = DatumQueryBuilder<TestEntity>().where('completed', isEqualTo: true).build();

        final emissions = <TestEntity?>[];
        final sub = adapter.watchFirst(query: completedQuery, userId: 'user-1')!.listen(emissions.add);
        await _pump();

        expect(emissions, hasLength(1));
        expect(emissions.single!.name, 'done');

        await sub.cancel();
      });
    });

    test('overwriteAllRawData for one user replaces only that user\'s data', () async {
      await adapter.create(_entity('1', 'user-1', name: 'old-1'));
      await adapter.create(_entity('2', 'user-1', name: 'old-2'));
      await adapter.create(_entity('3', 'user-2', name: 'other'));

      await adapter.overwriteAllRawData(
        [_entity('9', 'user-1', name: 'fresh').toDatumMap()],
        userId: 'user-1',
      );

      final userOne = await adapter.readAll(userId: 'user-1');
      expect(userOne, hasLength(1));
      expect(userOne.single.id, '9');
      expect(userOne.single.name, 'fresh');

      final userTwo = await adapter.readAll(userId: 'user-2');
      expect(userTwo, hasLength(1));
      expect(userTwo.single.name, 'other');
    });

    test('checkHealth reports healthy', () async {
      expect(await adapter.checkHealth(), AdapterHealthStatus.healthy);
    });
  });
}
