/// Regression tests for deep engine bugs found in the 2026-08 audit:
///
/// 1. The in-memory matcher silently ignored `bool` fields in sorting and
///    ordering comparisons (bool is not Comparable in Dart) while SQLite
///    sorts/compares them as 0/1 — adapters diverged.
/// 2. The SQL converter interpolated LIKE values without escaping `%`/`_`,
///    so `contains: '100%'` matched a superset of the matcher's literal
///    semantics.
/// 3. `OFFSET` without `LIMIT` produced a SQLite syntax error.
/// 4. An empty `CompositeFilter` rendered `()` — a SQL syntax error.
/// 5. The query cache key ignored `logicalOperator`, composite-filter
///    contents, and `nullSortOrder` — colliding queries served each other's
///    cached results.
/// 6. `push()` incremented the local vector clock even for
///    `DataSource.remote` saves, making a device claim causal edits it
///    only observed (spurious concurrency conflicts ever after).
library;

import 'package:datum/datum.dart';
import 'package:datum/source/core/manager/manager_cache_coordinator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../mocks/mock_adapters.dart';
import '../../mocks/mock_connectivity_checker.dart';
import '../../test_utils/test_datum_entity.dart';

void main() {
  group('matcher treats bool like SQL does (0/1)', () {
    final done = TestDatumEntity(id: 'a', userId: 'u1', value: 'x', isDeleted: true);
    final open = TestDatumEntity(id: 'b', userId: 'u1', value: 'y');

    test('sorting by a bool field orders false before true', () {
      final sorted = DatumQueryMatcher.apply(
        [done, open],
        const DatumQuery(sorting: [SortDescriptor('isDeleted')]),
      );
      expect(sorted.map((e) => e.id).toList(), ['b', 'a']);

      final descending = DatumQueryMatcher.apply(
        [open, done],
        const DatumQuery(sorting: [SortDescriptor('isDeleted', descending: true)]),
      );
      expect(descending.map((e) => e.id).toList(), ['a', 'b']);
    });

    test('ordering comparisons work on bool fields', () {
      final result = DatumQueryMatcher.apply(
        [done, open],
        const DatumQuery(filters: [Filter('isDeleted', FilterOperator.greaterThan, false)]),
      );
      expect(result.map((e) => e.id).toList(), ['a']);
    });
  });

  group('SQL converter', () {
    test('escapes LIKE wildcards so values stay literal', () {
      final (:sql, :params) = const DatumQuery(
        filters: [Filter('title', FilterOperator.contains, '100%_a')],
      ).toSql('t');
      expect(sql, contains(r"ESCAPE '\'"));
      expect(params.single, r'%100\%\_a%');
    });

    test('escapes the escape character itself', () {
      final (:params, sql: _) = const DatumQuery(
        filters: [Filter('path', FilterOperator.startsWith, r'C:\tmp')],
      ).toSql('t');
      expect(params.single, r'C:\\tmp%');
    });

    test('offset without limit emits LIMIT -1 on SQLite', () {
      final (:sql, :params) = const DatumQuery(offset: 5).toSql('t');
      expect(sql, contains('LIMIT -1 OFFSET 5'));
      expect(params, isEmpty);
    });

    test('empty composite filters render vacuous truth, not ()', () {
      final andSql = const DatumQuery(
        filters: [CompositeFilter([], LogicalOperator.and)],
      ).toSql('t').sql;
      expect(andSql, contains('1=1'));
      expect(andSql, isNot(contains('()')));

      final orSql = const DatumQuery(
        filters: [CompositeFilter([], LogicalOperator.or)],
      ).toSql('t').sql;
      expect(orSql, contains('0=1'));
    });
  });

  group('query cache key', () {
    final coordinator = ManagerCacheCoordinator<TestDatumEntity>(
      maxRelationshipQueryCacheSize: 10,
      maxEntityExistenceCacheSize: 10,
      maxQueryCacheSize: 10,
      logger: DatumLogger(enabled: false),
    );

    String key(DatumQuery q) => coordinator.createQueryCacheKey(q, DataSource.local, 'u1');

    test('differs when only the logical operator differs', () {
      const filters = [
        Filter('a', FilterOperator.equals, 1),
        Filter('b', FilterOperator.equals, 2),
      ];
      expect(
        key(const DatumQuery(filters: filters)),
        isNot(key(const DatumQuery(filters: filters, logicalOperator: LogicalOperator.or))),
      );
    });

    test('differs when composite-filter contents differ', () {
      expect(
        key(const DatumQuery(filters: [
          CompositeFilter([Filter('status', FilterOperator.equals, 'a')], LogicalOperator.or),
        ])),
        isNot(key(const DatumQuery(filters: [
          CompositeFilter([Filter('title', FilterOperator.equals, 'x')], LogicalOperator.or),
        ]))),
      );
    });

    test('differs when only nullSortOrder differs', () {
      expect(
        key(const DatumQuery(sorting: [SortDescriptor('a')])),
        isNot(key(const DatumQuery(sorting: [SortDescriptor('a', nullSortOrder: NullSortOrder.first)]))),
      );
    });
  });

  group('vector clock provenance', () {
    late DatumManager<TestDatumEntity> manager;

    setUp(() async {
      final connectivity = MockConnectivityChecker();
      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
      manager = DatumManager<TestDatumEntity>(
        localAdapter: MockLocalAdapter<TestDatumEntity>(fromJson: TestDatumEntity.fromMap),
        remoteAdapter: MockRemoteAdapter<TestDatumEntity>(fromJson: TestDatumEntity.fromMap),
        connectivity: connectivity,
        deviceId: 'device-A',
        datumConfig: const DatumConfig(enableLogging: false),
      );
      await manager.initialize();
    });

    tearDown(() => manager.dispose());

    test('a local push increments this device\'s clock component', () async {
      final saved = await manager.push(
        item: TestDatumEntity(id: 'e1', userId: 'u1', value: 'v'),
        userId: 'u1',
      );
      expect(saved.vectorClock?.toMap(), {'device-A': 1});
    });

    test('a remote-sourced push never claims a local causal edit', () async {
      final saved = await manager.push(
        item: TestDatumEntity(
          id: 'e2',
          userId: 'u1',
          value: 'v',
          vectorClock: const VectorClock({'device-B': 3}),
        ),
        userId: 'u1',
        source: DataSource.remote,
      );
      expect(saved.vectorClock?.toMap(), {'device-B': 3}, reason: 'observing another device\'s edit must not advance our own clock');
    });
  });
}
