import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumQueryField', () {
    // Built from a runtime value so the (normally const-canonicalized)
    // constructor actually executes at runtime and is recorded by coverage.
    final valueField = DatumQueryField<TestEntity, int>(['value'].first);

    bool matches(Map<String, dynamic> row, Filter filter) => DatumQueryMatcher.matchesMap(row, DatumQuery(filters: [filter]));

    test('constructor stores the serialized field name', () {
      expect(valueField.name, 'value');
    });

    test('equalTo builds an equals filter with matching semantics', () {
      final filter = valueField.equalTo(5);
      expect(filter.field, 'value');
      expect(filter.operator, FilterOperator.equals);
      expect(filter.value, 5);
      expect(matches({'value': 5}, filter), isTrue);
      expect(matches({'value': 6}, filter), isFalse);
    });

    test('notEqualTo builds a notEquals filter with matching semantics', () {
      final filter = valueField.notEqualTo(5);
      expect(filter.operator, FilterOperator.notEquals);
      expect(matches({'value': 6}, filter), isTrue);
      expect(matches({'value': 5}, filter), isFalse);
    });

    test('greaterThan builds a greaterThan filter with matching semantics', () {
      final filter = valueField.greaterThan(5);
      expect(filter.operator, FilterOperator.greaterThan);
      expect(matches({'value': 6}, filter), isTrue);
      expect(matches({'value': 5}, filter), isFalse);
    });

    test('greaterThanOrEqual builds an inclusive lower-bound filter', () {
      final filter = valueField.greaterThanOrEqual(5);
      expect(filter.operator, FilterOperator.greaterThanOrEqual);
      expect(matches({'value': 5}, filter), isTrue);
      expect(matches({'value': 6}, filter), isTrue);
      expect(matches({'value': 4}, filter), isFalse);
    });

    test('lessThan builds a lessThan filter with matching semantics', () {
      final filter = valueField.lessThan(5);
      expect(filter.operator, FilterOperator.lessThan);
      expect(matches({'value': 4}, filter), isTrue);
      expect(matches({'value': 5}, filter), isFalse);
    });

    test('lessThanOrEqual builds an inclusive upper-bound filter', () {
      final filter = valueField.lessThanOrEqual(5);
      expect(filter.operator, FilterOperator.lessThanOrEqual);
      expect(matches({'value': 5}, filter), isTrue);
      expect(matches({'value': 4}, filter), isTrue);
      expect(matches({'value': 6}, filter), isFalse);
    });

    test('isIn builds an isIn filter with matching semantics', () {
      final filter = valueField.isIn([1, 2, 3]);
      expect(filter.operator, FilterOperator.isIn);
      expect(matches({'value': 2}, filter), isTrue);
      expect(matches({'value': 4}, filter), isFalse);
    });

    test('isNotIn builds an isNotIn filter with matching semantics', () {
      final filter = valueField.isNotIn([1, 2, 3]);
      expect(filter.field, 'value');
      expect(filter.operator, FilterOperator.isNotIn);
      expect(filter.value, [1, 2, 3]);
      expect(matches({'value': 4}, filter), isTrue);
      expect(matches({'value': 2}, filter), isFalse);
    });

    test('isNull / isNotNull build null-check filters', () {
      expect(valueField.isNull.operator, FilterOperator.isNull);
      expect(matches({'value': null}, valueField.isNull), isTrue);
      expect(matches({'value': 1}, valueField.isNull), isFalse);

      expect(valueField.isNotNull.operator, FilterOperator.isNotNull);
      expect(matches({'value': 1}, valueField.isNotNull), isTrue);
      expect(matches({'value': null}, valueField.isNotNull), isFalse);
    });
  });

  group('DatumQueryBuilder.withRelated', () {
    test('adds relations to the built query and returns the builder', () {
      final builder = DatumQueryBuilder<TestEntity>();
      final returned = builder.withRelated(['posts', 'comments']);
      expect(returned, same(builder));

      final query = builder.build();
      expect(query.withRelated, ['posts', 'comments']);
    });

    test('accumulates relations across multiple calls', () {
      final query = DatumQueryBuilder<TestEntity>().withRelated(['posts']).withRelated(['author']).build();
      expect(query.withRelated, ['posts', 'author']);
    });

    test('unrelated builds default to no relations', () {
      final query = DatumQueryBuilder<TestEntity>().build();
      expect(query.withRelated, isEmpty);
    });
  });

  group('DatumRawQuery.toString', () {
    test('reports sql, table, select and count for a SQL query', () {
      const query = DatumRawQuery(sql: 'SELECT id FROM users WHERE age > ?', args: [18]);
      expect(
        query.toString(),
        'DatumRawQuery(sql: SELECT id FROM users WHERE age > ?, table: null, select: null, count: false)',
      );
    });

    test('reports table-based projection and count aggregation', () {
      const query = DatumRawQuery(table: 'users', select: 'id, name', count: true);
      expect(
        query.toString(),
        'DatumRawQuery(sql: null, table: users, select: id, name, count: true)',
      );
    });
  });
}
