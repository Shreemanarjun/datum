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

/// LIKE patterns treat `%`/`_` as wildcards; user values are literals.
const _likeEscapeClause = r" ESCAPE '\'";

String _escapeLike(String value) => value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Per-call conversion state shared by the condition renderers. [next] yields
/// the next dialect placeholder; renderers append bound values to [params].
typedef _SqlCtx = ({
  SqlDialect dialect,
  List<Object?> params,
  String Function() next,
  DatumCustomSqlBuilder? custom,
});

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

    var placeholderIndex = 1;
    String next() {
      if (placeholderBuilder != null) return placeholderBuilder(placeholderIndex++);
      return dialect == SqlDialect.postgresql ? '\$${placeholderIndex++}' : '?';
    }

    final _SqlCtx ctx = (dialect: dialect, params: <Object?>[], next: next, custom: customBuilder);
    final whereClauses = [for (final f in filters) _conditionSql(f, ctx)];

    // SQLite (and MySQL) reject OFFSET without LIMIT; -1 means unlimited.
    final effectiveLimit = limit ?? (offset != null && dialect != SqlDialect.postgresql ? -1 : null);

    final sql = [
      'SELECT * FROM "$tableName"',
      if (whereClauses.isNotEmpty) 'WHERE ${whereClauses.join(' ${logicalOperator.name.toUpperCase()} ')}',
      if (sorting.isNotEmpty) 'ORDER BY ${sorting.map(_orderTermSql).join(', ')}',
      if (effectiveLimit != null) 'LIMIT $effectiveLimit',
      if (offset != null) 'OFFSET ${offset!}',
    ].join(' ');

    return (sql: sql, params: ctx.params);
  }
}

String _orderTermSql(SortDescriptor s) {
  final direction = s.descending ? 'DESC' : 'ASC';
  final nulls = 'NULLS ${s.nullSortOrder == NullSortOrder.first ? "FIRST" : "LAST"}';
  return '"${s.field}" $direction $nulls';
}

String _conditionSql(FilterCondition condition, _SqlCtx ctx) => switch (condition) {
      // Allow the custom builder to handle the filter first.
      Filter() => ctx.custom?.call(condition, ctx.next, ctx.params) ?? _filterSql(condition, ctx),
      // `()` is a SQL syntax error. Mirror the matcher's vacuous semantics:
      // an empty AND is true, an empty OR is false.
      CompositeFilter(conditions: []) => condition.operator == LogicalOperator.and ? '1=1' : '0=1',
      CompositeFilter() => '(${condition.conditions.map((c) => _conditionSql(c, ctx)).join(' ${condition.operator.name.toUpperCase()} ')})',
      _ => throw UnsupportedError('Unsupported filter condition: $condition'),
    };

String _filterSql(Filter filter, _SqlCtx ctx) {
  // Assuming field names are safe and don't need escaping here.
  // In a production adapter, you might want to validate field names.
  final field = '"${filter.field}"';
  final operator = _sqlOperator(filter.operator, ctx.dialect);

  switch (filter.operator) {
    case FilterOperator.isNull || FilterOperator.isNotNull:
      return '$field $operator';
    case FilterOperator.isIn || FilterOperator.isNotIn:
      final values = filter.value;
      // `IN ()` is a syntax error: an empty list is always false for `IN`
      // and always true for `NOT IN`.
      if (values is! List || values.isEmpty) {
        return filter.operator == FilterOperator.isIn ? '0=1' : '1=1';
      }
      final placeholders = values.map((_) => ctx.next()).join(', ');
      ctx.params.addAll(values);
      return '$field $operator ($placeholders)';
    case FilterOperator.between:
      final placeholder1 = ctx.next();
      final placeholder2 = ctx.next();
      ctx.params.addAll(filter.value as List);
      return '$field $operator $placeholder1 AND $placeholder2';
    default:
      final (:expression, :value, :escape) = _scalarOperand(filter, field, ctx.dialect);
      ctx.params.add(value);
      return '$expression $operator ${ctx.next()}$escape';
  }
}

/// The left-hand expression, bound value and ESCAPE clause for a scalar
/// filter. LIKE values are LITERALS (the in-memory matcher uses
/// String.contains), so their `%`/`_` are escaped rather than acting as
/// wildcards.
({String expression, Object? value, String escape}) _scalarOperand(
  Filter filter,
  String field,
  SqlDialect dialect,
) {
  final raw = filter.value;
  return switch (filter.operator) {
    FilterOperator.contains => (expression: field, value: '%${_escapeLike('$raw')}%', escape: _likeEscapeClause),
    FilterOperator.startsWith => (expression: field, value: '${_escapeLike('$raw')}%', escape: _likeEscapeClause),
    FilterOperator.endsWith => (expression: field, value: '%${_escapeLike('$raw')}', escape: _likeEscapeClause),
    // SQLite uses LIKE with LOWER() for case-insensitivity.
    FilterOperator.containsIgnoreCase when dialect == SqlDialect.sqlite => (
        expression: 'LOWER($field)',
        value: '%${_escapeLike('$raw')}%'.toLowerCase(),
        escape: _likeEscapeClause,
      ),
    FilterOperator.containsIgnoreCase => (expression: field, value: '%${_escapeLike('$raw')}%', escape: _likeEscapeClause),
    _ => (expression: field, value: raw, escape: ''),
  };
}

String _sqlOperator(FilterOperator operator, SqlDialect dialect) => switch (operator) {
      FilterOperator.equals => '=',
      FilterOperator.notEquals => '!=',
      FilterOperator.greaterThan => '>',
      FilterOperator.greaterThanOrEqual => '>=',
      FilterOperator.lessThan => '<',
      FilterOperator.lessThanOrEqual => '<=',
      FilterOperator.contains || FilterOperator.startsWith || FilterOperator.endsWith => 'LIKE',
      FilterOperator.containsIgnoreCase => dialect == SqlDialect.postgresql ? 'ILIKE' : 'LIKE',
      FilterOperator.isIn => 'IN',
      FilterOperator.isNotIn => 'NOT IN',
      FilterOperator.isNull => 'IS NULL',
      FilterOperator.isNotNull => 'IS NOT NULL',
      FilterOperator.between => 'BETWEEN',
      FilterOperator.matches when dialect == SqlDialect.sqlite => 'REGEXP',
      FilterOperator.matches when dialect == SqlDialect.postgresql => '~',
      FilterOperator.matches => throw UnsupportedError('Unsupported operator $operator for dialect $dialect'),
      FilterOperator.arrayContains || FilterOperator.arrayContainsAny || FilterOperator.withinDistance => throw UnsupportedError(
          '$operator is not supported by the generic SQL helper. '
          'It requires database-specific functions (e.g., JSON or PostGIS).',
        ),
    };
