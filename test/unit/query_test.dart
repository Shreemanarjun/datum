import 'package:flutter_test/flutter_test.dart';
import 'package:datum/datum.dart';

import '../mocks/test_entity.dart';

/// A dummy class to test unsupported filter conditions.
class UnsupportedFilter extends FilterCondition {}

void main() {
  group('DatumQuerySqlConverter', () {
    const tableName = 'items';

    test('converts a simple "where equals" query to SQLite SQL', () {
      final query =
          (DatumQueryBuilder<TestEntity>()
                ..where('completed', isEqualTo: false))
              .build();

      final result = query.toSql(tableName);

      expect(result.sql, 'SELECT * FROM "$tableName" WHERE "completed" = ?');
      expect(result.params, [false]);
    });

    test('converts a query with multiple "where" clauses (AND)', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('priority', isGreaterThan: 2)
          .where('status', isNotEqualTo: 'archived')
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "priority" > ? AND "status" != ?',
      );
      expect(result.params, [2, 'archived']);
    });

    test('converts a query with OR logical operator', () {
      final query =
          (DatumQueryBuilder<TestEntity>()
                ..logicalOperator = LogicalOperator.or)
              .where('priority', isGreaterThan: 4)
              .where('status', isEqualTo: 'urgent')
              .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "priority" > ? OR "status" = ?',
      );
      expect(result.params, [4, 'urgent']);
    });

    test('converts a query with sorting, limit, and offset', () {
      final query = DatumQueryBuilder<TestEntity>()
          .orderBy('createdAt', descending: true)
          .limit(10)
          .offset(20)
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" ORDER BY "createdAt" DESC NULLS LAST LIMIT 10 OFFSET 20',
      );
      expect(result.params, isEmpty);
    });

    test('converts a query to PostgreSQL dialect with placeholders', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('name', contains: 'test')
          .where('value', isLessThanOrEqualTo: 100)
          .build();

      final result = query.toSql(tableName, dialect: SqlDialect.postgresql);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "name" LIKE \$1 AND "value" <= \$2',
      );
      expect(result.params, ['%test%', 100]);
    });

    test('handles "IN" and "NOT IN" clauses correctly', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('status', isIn: ['new', 'open'])
          .where('id', isNotIn: ['id1', 'id2'])
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "status" IN (?, ?) AND "id" NOT IN (?, ?)',
      );
      expect(result.params, ['new', 'open', 'id1', 'id2']);
    });

    test('handles empty "IN" list to prevent SQL errors', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('status', isIn: [])
          .build();
      final result = query.toSql(tableName);
      expect(result.sql, 'SELECT * FROM "$tableName" WHERE 0=1');
    });

    test('handles empty "NOT IN" list to prevent SQL errors', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('status', isNotIn: [])
          .build();
      final result = query.toSql(tableName);
      // `NOT IN ()` is always true, so the condition should be `1=1`.
      expect(result.sql, 'SELECT * FROM "$tableName" WHERE 1=1');
    });

    test('handles "BETWEEN" clause correctly', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('createdAt', between: [DateTime(2023), DateTime(2024)])
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "createdAt" BETWEEN ? AND ?',
      );
      expect(result.params, [DateTime(2023), DateTime(2024)]);
    });

    test('handles "IS NULL" and "IS NOT NULL" clauses', () {
      final query = DatumQueryBuilder<TestEntity>()
          .whereNull('deletedAt')
          .whereNotNull('updatedAt')
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "deletedAt" IS NULL AND "updatedAt" IS NOT NULL',
      );
      expect(result.params, isEmpty);
    });

    test('handles "startsWith" and "endsWith" clauses', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('name', startsWith: 'prefix')
          .where('path', endsWith: '.txt')
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "name" LIKE ? AND "path" LIKE ?',
      );
      expect(result.params, ['prefix%', '%.txt']);
    });

    test('converts a query with >= and < operators', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('value', isGreaterThanOrEqualTo: 10)
          .where('priority', isLessThan: 3)
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "value" >= ? AND "priority" < ?',
      );
      expect(result.params, [10, 3]);
    });

    test('handles "containsIgnoreCase" for SQLite and PostgreSQL', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('name', containsIgnoreCase: 'Case')
          .build();

      // SQLite
      final sqliteResult = query.toSql(tableName);
      expect(
        sqliteResult.sql,
        'SELECT * FROM "$tableName" WHERE LOWER("name") LIKE ?',
      );
      expect(sqliteResult.params, ['%case%']);

      // PostgreSQL
      final pgResult = query.toSql(tableName, dialect: SqlDialect.postgresql);
      expect(pgResult.sql, 'SELECT * FROM "$tableName" WHERE "name" ILIKE \$1');
      expect(pgResult.params, ['%Case%']);
    });

    test('handles composite "OR" filter', () {
      final query =
          DatumQueryBuilder<TestEntity>().where('category', isEqualTo: 'A').or([
            const Filter('status', FilterOperator.equals, 'new'),
            const Filter('priority', FilterOperator.greaterThan, 3),
          ]).build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "category" = ? AND ("status" = ? OR "priority" > ?)',
      );
      expect(result.params, ['A', 'new', 3]);
    });

    test('handles composite "AND" filter for explicit grouping', () {
      final query =
          (DatumQueryBuilder<TestEntity>()
                ..logicalOperator = LogicalOperator.or)
              .where('category', isEqualTo: 'A')
              .and([
                const Filter('status', FilterOperator.equals, 'active'),
                const Filter('priority', FilterOperator.lessThan, 2),
              ])
              .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "category" = ? OR ("status" = ? AND "priority" < ?)',
      );
      expect(result.params, ['A', 'active', 2]);
    });

    test('handles multiple sorting conditions', () {
      final query = DatumQueryBuilder<TestEntity>()
          .orderBy('priority', descending: true)
          .orderBy('createdAt', nullSortOrder: NullSortOrder.first)
          .build();

      final result = query.toSql(tableName);

      expect(
        result.sql,
        'SELECT * FROM "$tableName" ORDER BY "priority" DESC NULLS LAST, "createdAt" ASC NULLS FIRST',
      );
    });

    test('throws for arrayContains operator without a custom builder', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('tags', arrayContains: 'urgent')
          .build();

      expect(() => query.toSql(tableName), throwsA(isA<UnsupportedError>()));
    });

    test('throws for arrayContainsAny operator without a custom builder', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('tags', arrayContainsAny: ['urgent'])
          .build();

      expect(() => query.toSql(tableName), throwsA(isA<UnsupportedError>()));
    });

    test('throws for withinDistance operator without a custom builder', () {
      final query = DatumQueryBuilder<TestEntity>().whereWithinDistance(
        'location',
        {'latitude': 0, 'longitude': 0},
        100,
      ).build();

      expect(() => query.toSql(tableName), throwsA(isA<UnsupportedError>()));
    });

    test(
      'throws for "matches" operator with custom dialect without custom builder',
      () {
        final query = DatumQueryBuilder<TestEntity>()
            .where('name', matches: 'pattern')
            .build();

        expect(
          () => query.toSql(
            tableName,
            dialect: SqlDialect.custom,
            placeholderBuilder: (i) => '?',
          ),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test('throws for unsupported FilterCondition types', () {
      final query = DatumQuery(filters: [UnsupportedFilter()]);
      expect(() => query.toSql(tableName), throwsA(isA<UnsupportedError>()));
    });

    test('throws when using custom dialect without a placeholderBuilder', () {
      final query = DatumQueryBuilder<TestEntity>().build();
      expect(
        () => query.toSql(tableName, dialect: SqlDialect.custom),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('uses customBuilder for unsupported operators', () {
      final query =
          (DatumQueryBuilder<TestEntity>().where(
                'location',
                matches: 'some_pattern',
              )) // REGEXP is dialect-specific
              .build();

      final result = query.toSql(
        tableName,
        customBuilder: (filter, getPlaceholder, params) {
          if (filter.operator == FilterOperator.matches) {
            params.add(filter.value);
            return '"${filter.field}" REGEXP ${getPlaceholder()}';
          }
          return null;
        },
      );

      expect(
        result.sql,
        'SELECT * FROM "$tableName" WHERE "location" REGEXP ?',
      );
      expect(result.params, ['some_pattern']);
    });

    test('uses custom placeholderBuilder for custom dialect', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('name', isEqualTo: 'test')
          .build();

      final result = query.toSql(
        tableName,
        dialect: SqlDialect.custom,
        placeholderBuilder: (index) => '@p$index',
      );

      expect(result.sql, 'SELECT * FROM "$tableName" WHERE "name" = @p1');
      expect(result.params, ['test']);
    });
  });

  group('DatumQueryBuilder functionality', () {
    test('builds a query with arrayContains and arrayContainsAny', () {
      final query = DatumQueryBuilder<TestEntity>()
          .where('tags', arrayContains: 'urgent')
          .where('labels', arrayContainsAny: ['a', 'b'])
          .build();

      expect(query.filters, hasLength(2));
      final filter1 = query.filters[0] as Filter;
      expect(filter1.operator, FilterOperator.arrayContains);
      expect(filter1.value, 'urgent');

      final filter2 = query.filters[1] as Filter;
      expect(filter2.operator, FilterOperator.arrayContainsAny);
      expect(filter2.value, ['a', 'b']);
    });

    test('builds a query with whereWithinDistance', () {
      final center = {'latitude': 40.7128, 'longitude': -74.0060};
      final query = DatumQueryBuilder<TestEntity>()
          .whereWithinDistance('location', center, 1000)
          .build();

      expect(query.filters, hasLength(1));
      final filter = query.filters.first as Filter;
      expect(filter.operator, FilterOperator.withinDistance);
      expect(filter.value, {'center': center, 'radius': 1000});
    });

    test('builds a query with whereRaw', () {
      const rawCondition = Filter('customField', FilterOperator.equals, true);
      final query = DatumQueryBuilder<TestEntity>()
          .whereRaw(rawCondition)
          .build();

      expect(query.filters, hasLength(1));
      expect(query.filters.first, same(rawCondition));
    });

    test('clearFilters removes all filters', () {
      final builder = DatumQueryBuilder<TestEntity>()
          .where('name', isEqualTo: 'test')
          .where('value', isGreaterThan: 10);

      expect(builder.build().filters, isNotEmpty);

      builder.clearFilters();
      expect(builder.build().filters, isEmpty);
    });

    test('clearSorting removes all sorting', () {
      final builder = DatumQueryBuilder<TestEntity>()
          .orderBy('name')
          .orderBy('value', descending: true);

      expect(builder.build().sorting, isNotEmpty);

      builder.clearSorting();
      expect(builder.build().sorting, isEmpty);
    });

    test('reset clears all filters, sorting, limit, and offset', () {
      final builder =
          DatumQueryBuilder<TestEntity>()
              .where('name', isEqualTo: 'test')
              .orderBy('name')
              .limit(10)
              .offset(5)
            ..logicalOperator = LogicalOperator.or;

      final initialQuery = builder.build();
      expect(initialQuery.filters, isNotEmpty);
      expect(initialQuery.sorting, isNotEmpty);
      expect(initialQuery.limit, 10);
      expect(initialQuery.offset, 5);
      expect(initialQuery.logicalOperator, LogicalOperator.or);

      builder.reset();
      final resetQuery = builder.build();

      expect(resetQuery.filters, isEmpty);
      expect(resetQuery.sorting, isEmpty);
      expect(resetQuery.limit, isNull);
      expect(resetQuery.offset, isNull);
      expect(resetQuery.logicalOperator, LogicalOperator.and);
    });
  });

  group('DatumQuery', () {
    test(
      'copyWith creates an identical copy when no arguments are provided',
      () {
        final original = DatumQuery(
          filters: const [Filter('name', FilterOperator.equals, 'test')],
          sorting: const [SortDescriptor('createdAt')],
          limit: 10,
          offset: 5,
          logicalOperator: LogicalOperator.or,
        );

        final copy = original.copyWith();

        expect(copy.filters, original.filters);
        expect(copy.sorting, original.sorting);
        expect(copy.limit, original.limit);
        expect(copy.offset, original.offset);
        expect(copy.logicalOperator, original.logicalOperator);
      },
    );

    test('copyWith updates only the specified fields', () {
      const original = DatumQuery(
        filters: [Filter('name', FilterOperator.equals, 'test')],
        sorting: [],
        limit: 10,
      );

      const newFilters = [Filter('value', FilterOperator.greaterThan, 100)];
      const newSorting = [SortDescriptor('value', descending: true)];

      final copy = original.copyWith(
        filters: newFilters,
        sorting: newSorting,
        limit: 20,
        offset: 5,
        logicalOperator: LogicalOperator.or,
      );

      expect(copy.filters, newFilters);
      expect(copy.sorting, newSorting);
      expect(copy.limit, 20);
      expect(copy.offset, 5);
      expect(copy.logicalOperator, LogicalOperator.or);
    });

    test('copyWith can add a filter to an existing list', () {
      const original = DatumQuery(
        filters: [Filter('name', FilterOperator.equals, 'test')],
      );

      final copy = original.copyWith(
        filters: [
          ...original.filters,
          const Filter('status', FilterOperator.equals, 'active'),
        ],
      );

      expect(copy.filters, hasLength(2));
      expect((copy.filters.last as Filter).field, 'status');
    });
  });

  group('DatumQuery component toString()', () {
    test('Filter.toString() returns a readable representation', () {
      const filter = Filter('name', FilterOperator.equals, 'test');
      expect(filter.toString(), 'Filter(name equals test)');
    });

    test('CompositeFilter.toString() returns a readable representation', () {
      const filter1 = Filter('status', FilterOperator.equals, 'active');
      const filter2 = Filter('priority', FilterOperator.greaterThan, 3);
      const composite = CompositeFilter([filter1, filter2], LogicalOperator.or);
      expect(
        composite.toString(),
        'CompositeFilter(or: [Filter(status equals active), Filter(priority greaterThan 3)])',
      );
    });

    test('SortDescriptor.toString() returns a readable representation', () {
      const sortAsc = SortDescriptor('name');
      const sortDesc = SortDescriptor('age', descending: true);
      const sortNullsFirst = SortDescriptor(
        'createdAt',
        nullSortOrder: NullSortOrder.first,
      );

      expect(sortAsc.toString(), 'SortDescriptor(name, ASC, nulls: last)');
      expect(sortDesc.toString(), 'SortDescriptor(age, DESC, nulls: last)');
      expect(
        sortNullsFirst.toString(),
        'SortDescriptor(createdAt, ASC, nulls: first)',
      );
    });

    test('DatumQuery.toString() returns a readable representation', () {
      final query = DatumQuery(
        filters: const [
          Filter('name', FilterOperator.equals, 'test'),
          CompositeFilter([
            Filter('status', FilterOperator.equals, 'active'),
          ], LogicalOperator.and),
        ],
        sorting: const [SortDescriptor('createdAt', descending: true)],
        limit: 10,
        offset: 5,
        logicalOperator: LogicalOperator.or,
      );

      const expected =
          'DatumQuery(filters: [Filter(name equals test), CompositeFilter(and: [Filter(status equals active)])], '
          'sorting: [SortDescriptor(createdAt, DESC, nulls: last)], limit: 10, offset: 5, operator: or)';
      expect(query.toString(), expected);
    });
  });

  group('DatumCustomFieldQuery', () {
    // A concrete implementation for testing purposes.

    test('builds a query using custom field methods', () {
      // Arrange
      final customQuery = TestEntityQuery()
          .whereNameIs('test')
          .whereValueIsGreaterThan(10)
          .orderBy(TestEntityQuery.nameField);

      // Act
      final query = customQuery.build();

      // Assert
      expect(query.filters, hasLength(2));
      final filter1 = query.filters[0] as Filter;
      expect(filter1.field, 'name');
      expect(filter1.operator, FilterOperator.equals);
      expect(filter1.value, 'test');

      final filter2 = query.filters[1] as Filter;
      expect(filter2.field, 'value');
      expect(filter2.operator, FilterOperator.greaterThan);
      expect(filter2.value, 10);

      expect(query.sorting, hasLength(1));
      expect(query.sorting.first.field, 'name');
    });
  });
}

class TestEntityQuery extends DatumCustomFieldQuery<TestEntity> {
  static const nameField = 'name';
  static const valueField = 'value';

  TestEntityQuery whereNameIs(String name) {
    return this..where(nameField, isEqualTo: name);
  }

  TestEntityQuery whereValueIsGreaterThan(int value) {
    return this..where(valueField, isGreaterThan: value);
  }
}
