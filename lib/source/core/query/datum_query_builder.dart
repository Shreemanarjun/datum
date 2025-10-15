import 'package:datum/source/core/query/datum_query.dart';

/// A fluent builder for creating [DatumQuery] objects with type-safe field access.
class DatumQueryBuilder<T> {
  final List<FilterCondition> _filters = [];
  final List<SortDescriptor> _sorting = [];
  int? _limit;
  int? _offset;

  /// The logical operator for combining filters at the root level.
  LogicalOperator logicalOperator = LogicalOperator.and;

  /// Adds a filter condition to the query.
  ///
  /// Supports dot notation for nested fields: 'user.profile.name'
  ///
  /// Example: `.where('age', isGreaterThan: 18)`
  DatumQueryBuilder<T> where(
    String field, {
    dynamic isEqualTo,
    dynamic isNotEqualTo,
    dynamic isGreaterThan,
    dynamic isGreaterThanOrEqualTo,
    dynamic isLessThan,
    dynamic isLessThanOrEqualTo,
    String? contains,
    String? containsIgnoreCase,
    String? startsWith,
    String? endsWith,
    List<dynamic>? isIn,
    List<dynamic>? isNotIn,
    dynamic arrayContains,
    List<dynamic>? arrayContainsAny,
    String? matches,
    List<dynamic>? between,
  }) {
    if (isEqualTo != null) {
      _filters.add(Filter(field, FilterOperator.equals, isEqualTo));
    }
    if (isNotEqualTo != null) {
      _filters.add(Filter(field, FilterOperator.notEquals, isNotEqualTo));
    }
    if (isGreaterThan != null) {
      _filters.add(Filter(field, FilterOperator.greaterThan, isGreaterThan));
    }
    if (isGreaterThanOrEqualTo != null) {
      _filters.add(
        Filter(
          field,
          FilterOperator.greaterThanOrEqual,
          isGreaterThanOrEqualTo,
        ),
      );
    }
    if (isLessThan != null) {
      _filters.add(Filter(field, FilterOperator.lessThan, isLessThan));
    }
    if (isLessThanOrEqualTo != null) {
      _filters.add(
        Filter(field, FilterOperator.lessThanOrEqual, isLessThanOrEqualTo),
      );
    }
    if (contains != null) {
      _filters.add(Filter(field, FilterOperator.contains, contains));
    }
    if (containsIgnoreCase != null) {
      _filters.add(
        Filter(field, FilterOperator.containsIgnoreCase, containsIgnoreCase),
      );
    }
    if (startsWith != null) {
      _filters.add(Filter(field, FilterOperator.startsWith, startsWith));
    }
    if (endsWith != null) {
      _filters.add(Filter(field, FilterOperator.endsWith, endsWith));
    }
    if (isIn != null) {
      _filters.add(Filter(field, FilterOperator.isIn, isIn));
    }
    if (isNotIn != null) {
      _filters.add(Filter(field, FilterOperator.isNotIn, isNotIn));
    }
    if (arrayContains != null) {
      _filters.add(Filter(field, FilterOperator.arrayContains, arrayContains));
    }
    if (arrayContainsAny != null) {
      _filters.add(
        Filter(field, FilterOperator.arrayContainsAny, arrayContainsAny),
      );
    }
    if (matches != null) {
      _filters.add(Filter(field, FilterOperator.matches, matches));
    }
    if (between != null) {
      assert(between.length == 2, 'between requires exactly 2 values');
      _filters.add(Filter(field, FilterOperator.between, between));
    }
    return this;
  }

  /// Adds a null check filter.
  DatumQueryBuilder<T> whereNull(String field) {
    _filters.add(Filter(field, FilterOperator.isNull, null));
    return this;
  }

  /// Adds a not-null check filter.
  DatumQueryBuilder<T> whereNotNull(String field) {
    _filters.add(Filter(field, FilterOperator.isNotNull, null));
    return this;
  }

  /// Adds a geographical distance filter.
  ///
  /// [center] should be a map with 'latitude' and 'longitude' keys.
  /// [radiusInMeters] is the maximum distance from the center.
  DatumQueryBuilder<T> whereWithinDistance(
    String field,
    Map<String, double> center,
    double radiusInMeters,
  ) {
    _filters.add(
      Filter(field, FilterOperator.withinDistance, {
        'center': center,
        'radius': radiusInMeters,
      }),
    );
    return this;
  }

  /// Adds a composite OR filter.
  ///
  /// Example:
  /// ```dart
  /// .or([
  ///   Filter('status', FilterOperator.equals, 'urgent'),
  ///   Filter('priority', FilterOperator.greaterThan, 5),
  /// ])
  /// ```
  DatumQueryBuilder<T> or(List<FilterCondition> conditions) {
    _filters.add(CompositeFilter(conditions, LogicalOperator.or));
    return this;
  }

  /// Adds a composite AND filter (explicit grouping).
  ///
  /// Useful when you need explicit grouping within OR conditions.
  DatumQueryBuilder<T> and(List<FilterCondition> conditions) {
    _filters.add(CompositeFilter(conditions, LogicalOperator.and));
    return this;
  }

  /// Adds a raw filter condition.
  ///
  /// Useful for custom filter types or when migrating from other query systems.
  DatumQueryBuilder<T> whereRaw(FilterCondition condition) {
    _filters.add(condition);
    return this;
  }

  /// Adds a sorting condition to the query.
  ///
  /// Supports dot notation for nested fields: 'user.profile.createdAt'
  DatumQueryBuilder<T> orderBy(
    String field, {
    bool descending = false,
    NullSortOrder nullSortOrder = NullSortOrder.last,
  }) {
    _sorting.add(
      SortDescriptor(
        field,
        descending: descending,
        nullSortOrder: nullSortOrder,
      ),
    );
    return this;
  }

  /// Sets the maximum number of items to return.
  DatumQueryBuilder<T> limit(int count) {
    assert(count > 0, 'limit must be positive');
    _limit = count;
    return this;
  }

  /// Sets the number of items to skip.
  DatumQueryBuilder<T> offset(int count) {
    assert(count >= 0, 'offset must be non-negative');
    _offset = count;
    return this;
  }

  /// Clears all filters.
  void clearFilters() {
    _filters.clear();
  }

  /// Clears all sorting.
  void clearSorting() {
    _sorting.clear();
  }

  /// Resets the entire query.
  void reset() {
    _filters.clear();
    _sorting.clear();
    _limit = null;
    _offset = null;
    logicalOperator = LogicalOperator.and;
  }

  /// Builds and returns the final [DatumQuery] object.
  DatumQuery build() {
    return DatumQuery(
      filters: List.unmodifiable(_filters),
      sorting: List.unmodifiable(_sorting),
      limit: _limit,
      offset: _offset,
      logicalOperator: logicalOperator,
    );
  }
}

/// Helper class for building complex queries with custom field definitions.
///
/// Example:
/// ```dart
/// class TaskQuery extends DatumCustomFieldQuery<Task> {
///   static const title = 'title';
///   static const completed = 'completed';
///   static const tags = 'tags';
///
///   TaskQuery whereCompleted(bool value) {
///     return this..where(completed, isEqualTo: value);
///   }
///
///   TaskQuery whereHasTag(String tag) {
///     return this..where(tags, arrayContains: tag);
///   }
/// }
/// ```
abstract class DatumCustomFieldQuery<T> extends DatumQueryBuilder<T> {
  /// Creates a new instance of [DatumCustomFieldQuery].
  DatumCustomFieldQuery() : super();
}
