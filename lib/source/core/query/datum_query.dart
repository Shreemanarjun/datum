/// Defines a query for filtering and sorting items from a data source.
///
/// This is used with `watchQuery` and other query methods to retrieve a subset
/// of data. It's recommended to build queries using the [DatumQueryBuilder] for
/// a more expressive and type-safe API.
class DatumQuery {
  /// A list of filter conditions to apply.
  final List<FilterCondition> filters;

  /// A list of sorting descriptors to apply.
  final List<SortDescriptor> sorting;

  /// The maximum number of items to return.
  final int? limit;

  /// The number of items to skip from the beginning of the result set.
  final int? offset;

  /// The logical operator to combine filters (AND/OR).
  final LogicalOperator logicalOperator;

  /// Creates a query with a list of filters and sorting criteria.
  const DatumQuery({
    this.filters = const [],
    this.sorting = const [],
    this.limit,
    this.offset,
    this.logicalOperator = LogicalOperator.and,
  });

  /// Creates a copy of this query with updated fields.
  DatumQuery copyWith({
    List<FilterCondition>? filters,
    List<SortDescriptor>? sorting,
    int? limit,
    int? offset,
    LogicalOperator? logicalOperator,
  }) {
    return DatumQuery(
      filters: filters ?? this.filters,
      sorting: sorting ?? this.sorting,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      logicalOperator: logicalOperator ?? this.logicalOperator,
    );
  }

  @override
  String toString() {
    final parts = [
      if (filters.isNotEmpty) 'filters: $filters',
      if (sorting.isNotEmpty) 'sorting: $sorting',
      if (limit != null) 'limit: $limit',
      if (offset != null) 'offset: $offset',
      'operator: ${logicalOperator.name}',
    ];
    return 'DatumQuery(${parts.join(', ')})';
  }
}

/// Represents a filter condition (can be simple or composite).
abstract class FilterCondition {
  /// Creates a new instance of [FilterCondition].
  const FilterCondition();
}

/// Represents a single filter condition in a [DatumQuery].
class Filter extends FilterCondition {
  /// The field to filter on. Supports dot notation for nested fields.
  /// Example: 'user.profile.name'
  final String field;

  /// The comparison operator.
  final FilterOperator operator;

  /// The value to compare against.
  final dynamic value;

  /// Creates a filter condition.
  const Filter(this.field, this.operator, this.value);

  @override
  String toString() => 'Filter($field ${operator.name} $value)';
}

/// Represents a composite filter with AND/OR logic.
class CompositeFilter extends FilterCondition {
  /// The list of conditions to combine.
  final List<FilterCondition> conditions;

  /// The logical operator to combine conditions.
  final LogicalOperator operator;

  /// Creates a composite filter.
  const CompositeFilter(this.conditions, this.operator);

  @override
  String toString() => 'CompositeFilter(${operator.name}: $conditions)';
}

/// Defines logical operators for combining filters.
enum LogicalOperator {
  /// All conditions must be true (default).
  and,

  /// At least one condition must be true.
  or,
}

/// Defines the available comparison operators for filters.
enum FilterOperator {
  /// Equal to
  equals,

  /// Not equal to
  notEquals,

  /// Greater than
  greaterThan,

  /// Greater than or equal to
  greaterThanOrEqual,

  /// Less than
  lessThan,

  /// Less than or equal to
  lessThanOrEqual,

  /// Contains the substring (case-sensitive).
  contains,

  /// Contains the substring (case-insensitive).
  containsIgnoreCase,

  /// Starts with the prefix.
  startsWith,

  /// Ends with the suffix.
  endsWith,

  /// Value is in the provided list.
  isIn,

  /// Value is not in the provided list.
  isNotIn,

  /// Value is null.
  isNull,

  /// Value is not null.
  isNotNull,

  /// Array contains the value.
  arrayContains,

  /// Array contains any of the values.
  arrayContainsAny,

  /// Matches a regular expression pattern.
  matches,

  /// For geographical queries - within distance.
  withinDistance,

  /// Between two values (inclusive).
  between,
}

/// Defines sorting for a field in a [DatumQuery].
class SortDescriptor {
  /// The field to sort by. Supports dot notation for nested fields.
  final String field;

  /// Whether to sort in descending order.
  final bool descending;

  /// How to handle null values in sorting.
  final NullSortOrder nullSortOrder;

  /// Creates a sort descriptor.
  const SortDescriptor(
    this.field, {
    this.descending = false,
    this.nullSortOrder = NullSortOrder.last,
  });

  @override
  String toString() =>
      'SortDescriptor($field, ${descending ? "DESC" : "ASC"}, nulls: ${nullSortOrder.name})';
}

/// Defines how null values are sorted.
enum NullSortOrder {
  /// Null values appear first.
  first,

  /// Null values appear last (default).
  last,
}
