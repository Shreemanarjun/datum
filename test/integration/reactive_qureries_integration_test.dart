import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:datum/datum.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  group('Reactive Queries Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUp(() async {
      localAdapter = MockLocalAdapter<TestEntity>(
        fromJson: TestEntity.fromJson,
      );
      remoteAdapter = MockRemoteAdapter<TestEntity>(
        fromJson: TestEntity.fromJson,
      );
      connectivityChecker = MockConnectivityChecker();

      // CRITICAL: Set the mock adapter to silent mode. This prevents it from
      // firing its own change events when the manager calls create/update/delete,
      // which would cause a feedback loop and test timeouts.
      localAdapter.silent = true;

      // Create the manager first to get access to its event stream.
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        datumConfig: const DatumConfig(),
        connectivity: connectivityChecker,
      );
      // Wire up the manager's data change events to the mock adapter's stream.
      localAdapter.externalChangeStream = manager.onDataChange;

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('watchAll emits updated lists on data changes', () async {
      final entity1 = TestEntity.create('entity1', 'user1', 'Item 1');
      final entity2 = TestEntity.create('entity2', 'user1', 'Item 2');

      final stream = manager.watchAll(userId: 'user1');

      final completer = Completer<List<List<TestEntity>>>();
      final receivedEvents = <List<TestEntity>>[];

      final subscription = stream?.listen((items) {
        receivedEvents.add(items);
        if (receivedEvents.length == 4) {
          completer.complete(receivedEvents);
        }
      });

      await manager.push(item: entity1, userId: 'user1');
      await manager.push(item: entity2, userId: 'user1');
      await manager.delete(id: entity1.id, userId: 'user1');

      final allEvents = await completer.future;

      expect(allEvents[0], isEmpty);
      expect(allEvents[1], hasLength(1));
      expect(allEvents[1].first.id, 'entity1');
      expect(allEvents[2], hasLength(2));
      expect(allEvents[3], hasLength(1));
      expect(allEvents[3].first.id, 'entity2');

      await subscription?.cancel();
    });

    test('watchById emits updated entity and null on deletion', () async {
      final entity = TestEntity.create('entity1', 'user1', 'Item 1');
      final updatedEntity = entity.copyWith(name: 'Updated Item');

      final stream = manager.watchById('entity1', 'user1');

      final completer = Completer<List<TestEntity?>>();
      final receivedEvents = <TestEntity?>[];

      final subscription = stream?.listen((item) {
        receivedEvents.add(item);
        if (receivedEvents.length == 4) {
          completer.complete(receivedEvents);
        }
      });

      await manager.push(item: entity, userId: 'user1');
      await manager.push(item: updatedEntity, userId: 'user1');
      await manager.delete(id: entity.id, userId: 'user1');

      final allEvents = await completer.future;

      expect(allEvents[0], isNull);
      expect(allEvents[1]?.name, 'Item 1');
      expect(allEvents[2]?.name, 'Updated Item');
      expect(allEvents[3], isNull);

      await subscription?.cancel();
    });

    test('watchAllPaginated emits updated paginated results', () async {
      final entities = List.generate(
        3,
        (i) => TestEntity.create('entity$i', 'user1', 'Item $i'),
      );

      const config = PaginationConfig(pageSize: 2);
      final stream = manager.watchAllPaginated(config, userId: 'user1');

      final completer = Completer<List<PaginatedResult<TestEntity>>>();
      final receivedEvents = <PaginatedResult<TestEntity>>[];

      final subscription = stream?.listen((result) {
        receivedEvents.add(result);
        if (receivedEvents.length == 5) {
          completer.complete(receivedEvents);
        }
      });

      await manager.push(item: entities[0], userId: 'user1');
      await manager.push(item: entities[1], userId: 'user1');
      await manager.push(item: entities[2], userId: 'user1');
      await manager.delete(id: entities[0].id, userId: 'user1');

      final allEvents = await completer.future;

      expect(allEvents[0].items, isEmpty);
      expect(allEvents[1].items, hasLength(1));
      expect(allEvents[2].items, hasLength(2));
      expect(allEvents[2].hasMore, isFalse);
      expect(allEvents[3].items, hasLength(2));
      expect(allEvents[3].hasMore, isTrue);
      expect(allEvents[4].items, hasLength(2));
      expect(allEvents[4].hasMore, isFalse);

      await subscription?.cancel();
    });

    test('watchQuery emits filtered lists on data changes', () async {
      final pendingEntity1 = TestEntity.create('pending1', 'user1', 'Pending');
      final completedEntity = TestEntity.create(
        'completed1',
        'user1',
        'Done',
      ).copyWith(completed: true);

      final query =
          (DatumQueryBuilder<TestEntity>()
                ..where('completed', isEqualTo: false))
              .build();
      final stream = manager.watchQuery(query, userId: 'user1');

      final completer = Completer<List<List<TestEntity>>>();
      final receivedEvents = <List<TestEntity>>[];

      final subscription = stream?.listen((items) {
        receivedEvents.add(items);
        if (receivedEvents.length == 4) {
          completer.complete(receivedEvents);
        }
      });

      await manager.push(item: pendingEntity1, userId: 'user1');
      await manager.push(item: completedEntity, userId: 'user1');
      await manager.push(
        item: pendingEntity1.copyWith(completed: true),
        userId: 'user1',
      );

      final allEvents = await completer.future;

      expect(allEvents[0], isEmpty);
      expect(allEvents[1], hasLength(1));
      expect(allEvents[2], hasLength(1));
      expect(allEvents[3], isEmpty);

      await subscription?.cancel();
    });

    test('watchQuery with sorting emits correctly ordered lists', () async {
      final entity1 = TestEntity.create(
        'e1',
        'user1',
        'Item A',
      ).copyWith(value: 10);
      final entity2 = TestEntity.create(
        'e2',
        'user1',
        'Item B',
      ).copyWith(value: 20);
      final entity3 = TestEntity.create(
        'e3',
        'user1',
        'Item C',
      ).copyWith(value: 5);

      final query =
          (DatumQueryBuilder<TestEntity>()..orderBy('value', descending: true))
              .build();

      final stream = manager.watchQuery(query, userId: 'user1');

      expect(
        stream,
        emitsInOrder([
          isEmpty,
          (List<TestEntity> list) =>
              [10].every((v) => list.map((e) => e.value).contains(v)),
          (List<TestEntity> list) =>
              list.map((e) => e.value).toList().toString() == '[20, 10]',
          (List<TestEntity> list) =>
              list.map((e) => e.value).toList().toString() == '[20, 10, 5]',
        ]),
      );

      await manager.push(item: entity1, userId: 'user1');
      await manager.push(item: entity2, userId: 'user1');
      await manager.push(item: entity3, userId: 'user1');
    });

    test('watchQuery with filter and sorting works correctly', () async {
      final entity1 = TestEntity.create(
        'e1',
        'user1',
        'A',
      ).copyWith(value: 10, completed: true);
      final entity2 = TestEntity.create(
        'e2',
        'user1',
        'B',
      ).copyWith(value: 20, completed: false);
      final entity3 = TestEntity.create(
        'e3',
        'user1',
        'C',
      ).copyWith(value: 5, completed: false);

      final query =
          (DatumQueryBuilder<TestEntity>()
                ..where('completed', isEqualTo: false)
                ..orderBy('value'))
              .build();

      final stream = manager.watchQuery(query, userId: 'user1');

      expect(
        stream,
        emitsInOrder([
          isEmpty,
          isEmpty, // After pushing completed item
          (List<TestEntity> list) =>
              [20].every((v) => list.map((e) => e.value).contains(v)),
          (List<TestEntity> list) =>
              list.map((e) => e.value).toList().toString() == '[5, 20]',
        ]),
      );

      await manager.push(item: entity1, userId: 'user1');
      await manager.push(item: entity2, userId: 'user1');
      await manager.push(item: entity3, userId: 'user1');
    });

    test('watchQuery with OR logic emits correct results', () async {
      final entity1 = TestEntity.create(
        'e1',
        'user1',
        'High Prio',
      ).copyWith(value: 10);
      final entity2 = TestEntity.create(
        'e2',
        'user1',
        'Completed',
      ).copyWith(completed: true);
      final entity3 = TestEntity.create(
        'e3',
        'user1',
        'Low Prio',
      ).copyWith(value: 1);

      final query =
          (DatumQueryBuilder<TestEntity>()
                ..logicalOperator = LogicalOperator.or
                ..where('completed', isEqualTo: true)
                ..where('value', isGreaterThan: 5))
              .build();

      final stream = manager.watchQuery(query, userId: 'user1');

      expect(
        stream,
        emitsInOrder([
          isEmpty,
          // Pushing e1 (value > 5)
          (List<TestEntity> list) => list.length == 1 && list.first.id == 'e1',
          // Pushing e2 (completed)
          (List<TestEntity> list) =>
              list.length == 2 && list.any((e) => e.id == 'e2'),
          // Pushing e3 (neither condition met)
          (List<TestEntity> list) => list.length == 2,
        ]),
      );

      await manager.push(item: entity1, userId: 'user1');
      await manager.push(item: entity2, userId: 'user1');
      await manager.push(item: entity3, userId: 'user1');
    });

    test('watchAll stream is user-specific and does not mix data', () async {
      final user1Entity = TestEntity.create('entity1', 'user1', 'User1 Item');
      final user2Entity = TestEntity.create('entity2', 'user2', 'User2 Item');

      final user1Stream = manager.watchAll(userId: 'user1');
      final user2Stream = manager.watchAll(userId: 'user2');

      // Expect user1's stream to only ever see user1's data
      expect(
        user1Stream,
        emitsInOrder([
          isEmpty,
          (List<TestEntity> list) =>
              list.length == 1 && list.first.id == 'entity1',
        ]),
      );

      // Expect user2's stream to only ever see user2's data
      expect(
        user2Stream,
        emitsInOrder([
          isEmpty,
          (List<TestEntity> list) =>
              list.length == 1 && list.first.id == 'entity2',
        ]),
      );

      await manager.push(item: user1Entity, userId: 'user1');
      await manager.push(item: user2Entity, userId: 'user2');
    });
  });
}
