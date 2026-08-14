import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

/// A filter condition the matcher does not recognise (neither [Filter] nor
/// [CompositeFilter]) — used to prove the matcher's final fallback.
class _UnknownCondition extends FilterCondition {
  const _UnknownCondition();
}

TestEntity _entity(String id, {int value = 0, String name = '', bool completed = false}) => TestEntity(
      id: id,
      userId: 'u1',
      name: name,
      value: value,
      modifiedAt: DateTime.utc(2024, 1, 1),
      createdAt: DateTime.utc(2024, 1, 1),
      version: 1,
      completed: completed,
    );

bool _match(Map<String, dynamic> row, FilterCondition condition) => DatumQueryMatcher.matchesMap(row, DatumQuery(filters: [condition]));

void main() {
  group('DatumQueryMatcher.apply pagination', () {
    final entities = [
      _entity('a', value: 1),
      _entity('b', value: 2),
      _entity('c', value: 3),
      _entity('d', value: 4),
      _entity('e', value: 5),
    ];

    test('offset skips leading items', () {
      const query = DatumQuery(sorting: [SortDescriptor('value')], offset: 2);
      final result = DatumQueryMatcher.apply(entities, query);
      expect(result.map((e) => e.value), [3, 4, 5]);
    });

    test('limit truncates the result set', () {
      const query = DatumQuery(sorting: [SortDescriptor('value')], limit: 2);
      final result = DatumQueryMatcher.apply(entities, query);
      expect(result.map((e) => e.value), [1, 2]);
    });

    test('offset and limit combine into a page', () {
      const query = DatumQuery(sorting: [SortDescriptor('value')], offset: 1, limit: 2);
      final result = DatumQueryMatcher.apply(entities, query);
      expect(result.map((e) => e.value), [2, 3]);
    });

    test('offset beyond length yields empty list', () {
      const query = DatumQuery(offset: 10);
      expect(DatumQueryMatcher.apply(entities, query), isEmpty);
    });
  });

  group('DatumQueryMatcher.applyToMaps pagination', () {
    final rows = [
      {'value': 1},
      {'value': 2},
      {'value': 3},
      {'value': 4},
    ];

    test('offset skips rows', () {
      const query = DatumQuery(sorting: [SortDescriptor('value')], offset: 3);
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['value']), [4]);
    });

    test('limit truncates rows', () {
      const query = DatumQuery(sorting: [SortDescriptor('value')], limit: 1);
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['value']), [1]);
    });

    test('offset and limit page through rows', () {
      const query = DatumQuery(sorting: [SortDescriptor('value')], offset: 1, limit: 2);
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['value']), [2, 3]);
    });
  });

  group('sorting with null values', () {
    test('nullSortOrder.first puts null before values (null first in input)', () {
      final rows = [
        {'v': null},
        {'v': 1},
      ];
      const query = DatumQuery(sorting: [SortDescriptor('v', nullSortOrder: NullSortOrder.first)]);
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['v']), [null, 1]);
    });

    test('nullSortOrder.first puts null before values (null last in input)', () {
      final rows = [
        {'v': 1},
        {'v': null},
      ];
      const query = DatumQuery(sorting: [SortDescriptor('v', nullSortOrder: NullSortOrder.first)]);
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['v']), [null, 1]);
    });

    test('nullSortOrder.last puts null after values (null first in input)', () {
      final rows = [
        {'v': null},
        {'v': 2},
      ];
      const query = DatumQuery(sorting: [SortDescriptor('v')]);
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['v']), [2, null]);
    });

    test('nullSortOrder.last puts null after values (null last in input)', () {
      final rows = [
        {'v': 2},
        {'v': null},
      ];
      const query = DatumQuery(sorting: [SortDescriptor('v')]);
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['v']), [2, null]);
    });

    test('rows that are both null keep relative order and sort as equal', () {
      final rows = [
        {'v': null, 'w': 2},
        {'v': null, 'w': 1},
      ];
      const query = DatumQuery(
        sorting: [SortDescriptor('v'), SortDescriptor('w')],
      );
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['w']), [1, 2]);
    });

    test('descending sort with interleaved nulls (nulls first)', () {
      final rows = [
        {'v': 1},
        {'v': null},
        {'v': 3},
        {'v': 2},
      ];
      const query = DatumQuery(
        sorting: [SortDescriptor('v', descending: true, nullSortOrder: NullSortOrder.first)],
      );
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['v']), [null, 3, 2, 1]);
    });
  });

  group('null guard for non-null operators (line 96)', () {
    test('missing field fails equals', () {
      expect(_match({'name': 'x'}, const Filter('missing', FilterOperator.equals, 1)), isFalse);
    });

    test('explicit null value fails greaterThan', () {
      expect(_match({'value': null}, const Filter('value', FilterOperator.greaterThan, 1)), isFalse);
    });

    test('missing field still matches isNull', () {
      expect(_match({'name': 'x'}, const Filter('missing', FilterOperator.isNull, null)), isTrue);
    });

    test('missing field fails isNotNull', () {
      expect(_match({'name': 'x'}, const Filter('missing', FilterOperator.isNotNull, null)), isFalse);
    });
  });

  group('comparison operators', () {
    test('notEquals: different value matches', () {
      expect(_match({'v': 1}, const Filter('v', FilterOperator.notEquals, 2)), isTrue);
    });

    test('notEquals: same value does not match', () {
      expect(_match({'v': 2}, const Filter('v', FilterOperator.notEquals, 2)), isFalse);
    });

    test('lessThan: smaller value matches', () {
      expect(_match({'v': 1}, const Filter('v', FilterOperator.lessThan, 2)), isTrue);
    });

    test('lessThan: equal value does not match', () {
      expect(_match({'v': 2}, const Filter('v', FilterOperator.lessThan, 2)), isFalse);
    });

    test('lessThan: non-Comparable value does not match', () {
      expect(
        _match({
          'v': [1]
        }, const Filter('v', FilterOperator.lessThan, 2)),
        isFalse,
      );
    });

    test('lessThanOrEqual: equal value matches', () {
      expect(_match({'v': 2}, const Filter('v', FilterOperator.lessThanOrEqual, 2)), isTrue);
    });

    test('lessThanOrEqual: greater value does not match', () {
      expect(_match({'v': 3}, const Filter('v', FilterOperator.lessThanOrEqual, 2)), isFalse);
    });

    test('between: value inside bounds matches (inclusive)', () {
      expect(_match({'v': 5}, const Filter('v', FilterOperator.between, [1, 10])), isTrue);
      expect(_match({'v': 1}, const Filter('v', FilterOperator.between, [1, 10])), isTrue);
      expect(_match({'v': 10}, const Filter('v', FilterOperator.between, [1, 10])), isTrue);
    });

    test('between: value outside bounds does not match', () {
      expect(_match({'v': 0}, const Filter('v', FilterOperator.between, [1, 10])), isFalse);
      expect(_match({'v': 11}, const Filter('v', FilterOperator.between, [1, 10])), isFalse);
    });

    test('between: non-Comparable value does not match', () {
      expect(
        _match({
          'v': [5]
        }, const Filter('v', FilterOperator.between, [1, 10])),
        isFalse,
      );
    });

    test('between: non-list condition value does not match', () {
      expect(_match({'v': 5}, const Filter('v', FilterOperator.between, 5)), isFalse);
    });

    test('between: bounds list of wrong length does not match', () {
      expect(_match({'v': 5}, const Filter('v', FilterOperator.between, [1])), isFalse);
      expect(_match({'v': 5}, const Filter('v', FilterOperator.between, [1, 5, 10])), isFalse);
    });
  });

  group('string operators', () {
    test('contains: substring matches', () {
      expect(_match({'s': 'hello world'}, const Filter('s', FilterOperator.contains, 'lo w')), isTrue);
    });

    test('contains: absent substring does not match', () {
      expect(_match({'s': 'hello'}, const Filter('s', FilterOperator.contains, 'xyz')), isFalse);
    });

    test('contains: non-string value does not match', () {
      expect(_match({'s': 42}, const Filter('s', FilterOperator.contains, '4')), isFalse);
    });

    test('containsIgnoreCase: differing case matches', () {
      expect(_match({'s': 'HeLLo'}, const Filter('s', FilterOperator.containsIgnoreCase, 'hell')), isTrue);
    });

    test('containsIgnoreCase: absent substring does not match', () {
      expect(_match({'s': 'HeLLo'}, const Filter('s', FilterOperator.containsIgnoreCase, 'bye')), isFalse);
    });

    test('containsIgnoreCase: non-string value or condition does not match', () {
      expect(_match({'s': 7}, const Filter('s', FilterOperator.containsIgnoreCase, '7')), isFalse);
      expect(_match({'s': 'abc'}, const Filter('s', FilterOperator.containsIgnoreCase, 7)), isFalse);
    });

    test('startsWith: prefix matches', () {
      expect(_match({'s': 'flutter'}, const Filter('s', FilterOperator.startsWith, 'flu')), isTrue);
    });

    test('startsWith: non-prefix does not match', () {
      expect(_match({'s': 'flutter'}, const Filter('s', FilterOperator.startsWith, 'utter')), isFalse);
    });

    test('startsWith: non-string value or condition does not match', () {
      expect(_match({'s': 5}, const Filter('s', FilterOperator.startsWith, '5')), isFalse);
      expect(_match({'s': 'abc'}, const Filter('s', FilterOperator.startsWith, 5)), isFalse);
    });

    test('endsWith: suffix matches', () {
      expect(_match({'s': 'flutter'}, const Filter('s', FilterOperator.endsWith, 'ter')), isTrue);
    });

    test('endsWith: non-suffix does not match', () {
      expect(_match({'s': 'flutter'}, const Filter('s', FilterOperator.endsWith, 'flu')), isFalse);
    });

    test('endsWith: non-string value or condition does not match', () {
      expect(_match({'s': 5}, const Filter('s', FilterOperator.endsWith, '5')), isFalse);
      expect(_match({'s': 'abc'}, const Filter('s', FilterOperator.endsWith, 5)), isFalse);
    });

    test('matches: regex pattern matches', () {
      expect(_match({'s': 'abbbc'}, const Filter('s', FilterOperator.matches, r'^ab+c$')), isTrue);
    });

    test('matches: regex pattern does not match', () {
      expect(_match({'s': 'ac'}, const Filter('s', FilterOperator.matches, r'^ab+c$')), isFalse);
    });

    test('matches: non-string value or condition does not match', () {
      expect(_match({'s': 5}, const Filter('s', FilterOperator.matches, r'\d')), isFalse);
      expect(_match({'s': 'abc'}, const Filter('s', FilterOperator.matches, 5)), isFalse);
    });
  });

  group('membership operators', () {
    test('isNotIn: value absent from list matches', () {
      expect(_match({'v': 4}, const Filter('v', FilterOperator.isNotIn, [1, 2, 3])), isTrue);
    });

    test('isNotIn: value present in list does not match', () {
      expect(_match({'v': 2}, const Filter('v', FilterOperator.isNotIn, [1, 2, 3])), isFalse);
    });

    test('isNotIn: non-list condition value does not match', () {
      expect(_match({'v': 4}, const Filter('v', FilterOperator.isNotIn, 4)), isFalse);
    });

    test('isNull: present value does not match', () {
      expect(_match({'v': 1}, const Filter('v', FilterOperator.isNull, null)), isFalse);
    });

    test('isNotNull: present value matches', () {
      expect(_match({'v': 1}, const Filter('v', FilterOperator.isNotNull, null)), isTrue);
    });

    test('arrayContains: element in list matches', () {
      expect(
        _match({
          'tags': ['a', 'b']
        }, const Filter('tags', FilterOperator.arrayContains, 'b')),
        isTrue,
      );
    });

    test('arrayContains: element absent does not match', () {
      expect(
        _match({
          'tags': ['a', 'b']
        }, const Filter('tags', FilterOperator.arrayContains, 'z')),
        isFalse,
      );
    });

    test('arrayContains: non-list value does not match', () {
      expect(_match({'tags': 'ab'}, const Filter('tags', FilterOperator.arrayContains, 'a')), isFalse);
    });

    test('arrayContainsAny: overlapping lists match', () {
      expect(
        _match({
          'tags': ['a', 'b', 'c']
        }, const Filter('tags', FilterOperator.arrayContainsAny, ['x', 'b'])),
        isTrue,
      );
    });

    test('arrayContainsAny: disjoint lists do not match', () {
      expect(
        _match({
          'tags': ['a', 'b']
        }, const Filter('tags', FilterOperator.arrayContainsAny, ['x', 'y'])),
        isFalse,
      );
    });

    test('arrayContainsAny: non-list value does not match', () {
      expect(_match({'tags': 'a'}, const Filter('tags', FilterOperator.arrayContainsAny, ['a'])), isFalse);
    });

    test('arrayContainsAny: non-list condition value does not match', () {
      expect(
        _match({
          'tags': ['a']
        }, const Filter('tags', FilterOperator.arrayContainsAny, 'a')),
        isFalse,
      );
    });
  });

  group('withinDistance', () {
    const center = {'latitude': 0.0, 'longitude': 0.0};

    test('point at the center matches (distance 0)', () {
      expect(
        _match(
          {
            'loc': {'latitude': 0.0, 'longitude': 0.0}
          },
          const Filter('loc', FilterOperator.withinDistance, {'center': center, 'radius': 10.0}),
        ),
        isTrue,
      );
    });

    test('point at a known haversine distance: inside vs outside radius', () {
      // 1 degree of longitude at the equator ~= 111,195 m.
      const point = {
        'loc': {'latitude': 0.0, 'longitude': 1.0}
      };
      expect(
        _match(point, const Filter('loc', FilterOperator.withinDistance, {'center': center, 'radius': 112000.0})),
        isTrue,
      );
      expect(
        _match(point, const Filter('loc', FilterOperator.withinDistance, {'center': center, 'radius': 111000.0})),
        isFalse,
      );
    });

    test('non-map value does not match', () {
      expect(
        _match({'loc': 'nowhere'}, const Filter('loc', FilterOperator.withinDistance, {'center': center, 'radius': 10.0})),
        isFalse,
      );
    });

    test('non-map condition value does not match', () {
      expect(
        _match({
          'loc': {'latitude': 0.0, 'longitude': 0.0}
        }, const Filter('loc', FilterOperator.withinDistance, 5)),
        isFalse,
      );
    });

    test('point missing latitude or longitude does not match', () {
      expect(
        _match(
          {
            'loc': {'longitude': 0.0}
          },
          const Filter('loc', FilterOperator.withinDistance, {'center': center, 'radius': 10.0}),
        ),
        isFalse,
      );
      expect(
        _match(
          {
            'loc': {'latitude': 0.0}
          },
          const Filter('loc', FilterOperator.withinDistance, {'center': center, 'radius': 10.0}),
        ),
        isFalse,
      );
    });

    test('params missing center or radius do not match', () {
      const point = {
        'loc': {'latitude': 0.0, 'longitude': 0.0}
      };
      expect(
        _match(point, const Filter('loc', FilterOperator.withinDistance, {'radius': 10.0})),
        isFalse,
      );
      expect(
        _match(point, const Filter('loc', FilterOperator.withinDistance, {'center': center})),
        isFalse,
      );
    });

    test('builder whereWithinDistance filters entities end to end', () {
      final rows = [
        {
          'id': 'near',
          'loc': {'latitude': 0.0, 'longitude': 0.001}
        },
        {
          'id': 'far',
          'loc': {'latitude': 10.0, 'longitude': 10.0}
        },
      ];
      final query = DatumQueryBuilder<TestEntity>().whereWithinDistance('loc', {'latitude': 0.0, 'longitude': 0.0}, 500).build();
      final result = DatumQueryMatcher.applyToMaps(rows, query);
      expect(result.map((r) => r['id']), ['near']);
    });
  });

  group('composite filters', () {
    test('AND composite: all conditions true matches', () {
      const composite = CompositeFilter(
        [
          Filter('a', FilterOperator.equals, 1),
          Filter('b', FilterOperator.equals, 2),
        ],
        LogicalOperator.and,
      );
      expect(_match({'a': 1, 'b': 2}, composite), isTrue);
    });

    test('AND composite: one condition false does not match', () {
      const composite = CompositeFilter(
        [
          Filter('a', FilterOperator.equals, 1),
          Filter('b', FilterOperator.equals, 2),
        ],
        LogicalOperator.and,
      );
      expect(_match({'a': 1, 'b': 99}, composite), isFalse);
    });

    test('OR composite: one condition true matches', () {
      const composite = CompositeFilter(
        [
          Filter('a', FilterOperator.equals, 1),
          Filter('b', FilterOperator.equals, 2),
        ],
        LogicalOperator.or,
      );
      expect(_match({'a': 99, 'b': 2}, composite), isTrue);
    });

    test('OR composite: no condition true does not match', () {
      const composite = CompositeFilter(
        [
          Filter('a', FilterOperator.equals, 1),
          Filter('b', FilterOperator.equals, 2),
        ],
        LogicalOperator.or,
      );
      expect(_match({'a': 99, 'b': 99}, composite), isFalse);
    });

    test('nested composite inside composite is evaluated recursively', () {
      const composite = CompositeFilter(
        [
          Filter('kind', FilterOperator.equals, 'x'),
          CompositeFilter(
            [
              Filter('v', FilterOperator.lessThan, 0),
              Filter('v', FilterOperator.greaterThan, 10),
            ],
            LogicalOperator.or,
          ),
        ],
        LogicalOperator.and,
      );
      expect(_match({'kind': 'x', 'v': 20}, composite), isTrue);
      expect(_match({'kind': 'x', 'v': 5}, composite), isFalse);
    });

    test('unknown filter condition type never matches', () {
      expect(_match({'a': 1}, const _UnknownCondition()), isFalse);
    });
  });

  group('end-to-end apply with entities', () {
    test('filter + sort + paginate on TestEntity list', () {
      final entities = [
        _entity('a', value: 5, completed: true),
        _entity('b', value: 3, completed: true),
        _entity('c', value: 9, completed: false),
        _entity('d', value: 1, completed: true),
        _entity('e', value: 7, completed: true),
      ];
      const query = DatumQuery(
        filters: [Filter('completed', FilterOperator.equals, true)],
        sorting: [SortDescriptor('value', descending: true)],
        offset: 1,
        limit: 2,
      );
      final result = DatumQueryMatcher.apply(entities, query);
      expect(result.map((e) => e.value), [5, 3]);
    });
  });
}
