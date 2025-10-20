import 'package:datum/source/core/query/datum_query.dart';

/// Defines the SQL dialect to be used for generating queries.
enum SqlDialect {
  /// SQLite dialect, which uses '?' for parameter placeholders.
  sqlite,

  /// PostgreSQL dialect, which uses '$1', '$2', etc., for placeholders.
  postgresql,

  /// A custom dialect, which requires providing a `placeholderBuilder`.
  custom,
}

/// A record holding the generated SQL string and its corresponding parameters.
typedef DatumSqlQueryResult = ({String sql, List<Object?> params});

/// A builder function for custom SQL operator logic.
///
/// It receives the [Filter] and a function to get the next placeholder.
/// It must add its own values to the [params] list.
/// It should return the full SQL condition string (e.g., `ST_Distance(location, ?) < ?`).
typedef DatumCustomSqlBuilder = String? Function(
  Filter filter,
  String Function() getPlaceholder,
  List<Object?> params,
);

/// A builder function for custom SQL placeholder logic.
///
/// It receives the 1-based index of the placeholder.
typedef DatumPlaceholderBuilder = String Function(int index);

/// An extension on [DatumQuery] to provide SQL conversion capabilities.
extension DatumQuerySqlConverter on DatumQuery {
  /// Converts this [DatumQuery] into a parameterized SQL query string.
  ///
  /// - [tableName]: The name of the SQL table to query.
  /// - [dialect]: The SQL dialect to use for placeholder syntax.
  ///
  /// Returns a [DatumSqlQueryResult] containing the SQL string and a list of
  /// parameters, ready to be executed by a database driver.
  DatumSqlQueryResult toSql(
    String tableName, {
    SqlDialect dialect = SqlDialect.sqlite,
    DatumCustomSqlBuilder? customBuilder,
    DatumPlaceholderBuilder? placeholderBuilder,
  }) {
    if (dialect == SqlDialect.custom && placeholderBuilder == null) {
      throw ArgumentError(
        'A placeholderBuilder must be provided when using a custom dialect.',
      );
    }

    final params = <Object?>[];
    var placeholderIndex = 1;

    String getPlaceholder() {
      if (placeholderBuilder != null) {
        return placeholderBuilder(placeholderIndex++);
      }
      if (dialect == SqlDialect.postgresql) {
        return '\$${placeholderIndex++}';
      }
      return '?';
    }

    String processCondition(FilterCondition condition) {
      if (condition is Filter) {
        // Allow custom builder to handle the filter first.
        final customSql = customBuilder?.call(
          condition,
          getPlaceholder,
          params,
        );
        if (customSql != null) {
          return customSql;
        }

        // Assuming field names are safe and don't need escaping here.
        // In a production adapter, you might want to validate field names.
        final field = '"${condition.field}"';
        final operator = _getSqlOperator(condition.operator, dialect);

        if (condition.operator == FilterOperator.isNull || condition.operator == FilterOperator.isNotNull) {
          return '$field $operator';
        }

        if (condition.operator == FilterOperator.isIn || condition.operator == FilterOperator.isNotIn) {
          if (condition.value is! List || (condition.value as List).isEmpty) {
            // An empty IN list is problematic in SQL.
            // `IN ()` is a syntax error. We can return a condition that is
            // always false for `IN` and always true for `NOT IN`.
            return condition.operator == FilterOperator.isIn ? '0=1' : '1=1';
          }
          final placeholders = (condition.value as List).map((_) => getPlaceholder()).join(', ');
          params.addAll(condition.value as List);
          return '$field $operator ($placeholders)';
        }

        if (condition.operator == FilterOperator.between) {
          final placeholder1 = getPlaceholder();
          final placeholder2 = getPlaceholder();
          params.addAll(condition.value as List);
          return '$field $operator $placeholder1 AND $placeholder2';
        }

        var value = condition.value;
        var fieldExpression = field;

        // Handle LIKE/ILIKE operators and value wrapping
        switch (condition.operator) {
          case FilterOperator.contains:
            value = '%$value%';
            break;
          case FilterOperator.startsWith:
            value = '$value%';
            break;
          case FilterOperator.endsWith:
            value = '%$value';
            break;
          case FilterOperator.containsIgnoreCase:
            value = '%$value%';
            if (dialect == SqlDialect.sqlite) {
              // SQLite uses LIKE with LOWER() for case-insensitivity
              fieldExpression = 'LOWER($field)';
              value = (value as String).toLowerCase();
            }
          default:
            break;
        }

        params.add(value);
        return '$fieldExpression $operator ${getPlaceholder()}';
      }

      if (condition is CompositeFilter) {
        final clauses = condition.conditions.map(processCondition).join(' ${condition.operator.name.toUpperCase()} ');
        return '($clauses)';
      }

      throw UnsupportedError('Unsupported filter condition: $condition');
    }

    final whereClauses = filters.map(processCondition).toList();

    final whereSql = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' ${logicalOperator.name.toUpperCase()} ')}' : '';

    final sortingSql = sorting.isNotEmpty
        ? 'ORDER BY ${sorting.map((s) {
            final direction = s.descending ? 'DESC' : 'ASC';
            final nulls = 'NULLS ${s.nullSortOrder == NullSortOrder.first ? "FIRST" : "LAST"}';
            return '"${s.field}" $direction $nulls';
          }).join(', ')}'
        : '';

    final limitSql = limit != null ? 'LIMIT ${limit!}' : '';
    final offsetSql = offset != null ? 'OFFSET ${offset!}' : '';

    final sql = [
      'SELECT * FROM "$tableName"',
      whereSql,
      sortingSql,
      limitSql,
      offsetSql,
    ].where((s) => s.isNotEmpty).join(' ');

    return (sql: sql, params: params);
  }

  String _getSqlOperator(FilterOperator operator, SqlDialect dialect) {
    switch (operator) {
      case FilterOperator.equals:
        return '=';
      case FilterOperator.notEquals:
        return '!=';
      case FilterOperator.greaterThan:
        return '>';
      case FilterOperator.greaterThanOrEqual:
        return '>=';
      case FilterOperator.lessThan:
        return '<';
      case FilterOperator.lessThanOrEqual:
        return '<=';
      case FilterOperator.contains:
      case FilterOperator.startsWith:
      case FilterOperator.endsWith:
        return 'LIKE';
      case FilterOperator.containsIgnoreCase:
        return dialect == SqlDialect.postgresql ? 'ILIKE' : 'LIKE';
      case FilterOperator.isIn:
        return 'IN';
      case FilterOperator.isNotIn:
        return 'NOT IN';
      case FilterOperator.isNull:
        return 'IS NULL';
      case FilterOperator.isNotNull:
        return 'IS NOT NULL';
      case FilterOperator.between:
        return 'BETWEEN';
      case FilterOperator.matches:
        switch (dialect) {
          case SqlDialect.sqlite:
            return 'REGEXP';
          case SqlDialect.postgresql:
            return '~';
          case SqlDialect.custom:
            break; // Fall through to throw
        }
      case FilterOperator.arrayContains:
      case FilterOperator.arrayContainsAny:
      case FilterOperator.withinDistance:
        throw UnsupportedError(
          '$operator is not supported by the generic SQL helper. '
          'It requires database-specific functions (e.g., JSON or PostGIS).',
        );
    }
    // This line should be unreachable if all cases are handled, but it
    // satisfies the non-nullable return type requirement.
    throw UnsupportedError('Unsupported operator $operator for dialect $dialect');
  }
}
