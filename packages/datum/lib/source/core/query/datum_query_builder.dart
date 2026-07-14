import 'package:datum/source/core/query/datum_query.dart';

/// A **type-safe field descriptor** for an entity of type [E] whose value type
/// is [V].
///
/// Used with [DatumQueryBuilder.whereField] / [DatumQueryBuilder.orderByField]
/// to get compile-time checking of both the field's existence (it must belong to
/// `E`) and the comparison value's type (it must be a [V]). The `datum_generator`
/// emits one descriptor per serializable field, e.g.:
///
/// ```dart
/// abstract class TaskFields {
///   static const title = DatumQueryField<Task, String>('title');
///   static const priority = DatumQueryField<Task, int>('priority');
/// }
///
/// // priority must be compared to an int — `isGreaterThan: 'x'` won't compile:
/// query.whereField(TaskFields.priority, isGreaterThan: 2);
/// ```
///
/// Named `DatumQueryField` (not `DatumField`) to avoid clashing with the
/// `@DatumField` annotation from `datum_generator`.
class DatumQueryField<E, V> {
  /// Creates a descriptor for the serialized [name] of a field on `E`.
  const DatumQueryField(this.name);

  /// The serialized field name (map key / column), supporting dot notation.
  final String name;

  /// `field == value`
  Filter equalTo(V value) => Filter(name, FilterOperator.equals, value);

  /// `field != value`
  Filter notEqualTo(V value) => Filter(name, FilterOperator.notEquals, value);

  /// `field > value`
  Filter greaterThan(V value) => Filter(name, FilterOperator.greaterThan, value);

  /// `field >= value`
  Filter greaterThanOrEqual(V value) => Filter(name, FilterOperator.greaterThanOrEqual, value);

  /// `field < value`
  Filter lessThan(V value) => Filter(name, FilterOperator.lessThan, value);

  /// `field <= value`
  Filter lessThanOrEqual(V value) => Filter(name, FilterOperator.lessThanOrEqual, value);

  /// `field IN values`
  Filter isIn(List<V> values) => Filter(name, FilterOperator.isIn, values);

  /// `field NOT IN values`
  Filter isNotIn(List<V> values) => Filter(name, FilterOperator.isNotIn, values);

  /// `field IS NULL`
  Filter get isNull => Filter(name, FilterOperator.isNull, null);

  /// `field IS NOT NULL`
  Filter get isNotNull => Filter(name, FilterOperator.isNotNull, null);
}

/// A fluent builder for creating [DatumQuery] objects with type-safe field access.
class DatumQueryBuilder<T> {
  final List<FilterCondition> _filters = [];
  final List<SortDescriptor> _sorting = [];
  int? _limit;
  int? _offset;
  final List<String> _withRelated = [];

  /// The logical operator for combining filters at the root level.
  LogicalOperator logicalOperator = LogicalOperator.and;

  DatumQueryBuilder<T> withRelated(List<String> relations) {
    _withRelated.addAll(relations);
    return this;
  }

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

  /// Type-safe variant of [where] using a [DatumQueryField] descriptor.
  ///
  /// The [field] must belong to entity `T`, and equality/ordering values must
  /// match the field's value type `V` — both checked at compile time. String
  /// operators ([contains]/[startsWith]/…) and [matches] remain `String?`
  /// because they are only meaningful for string fields.
  DatumQueryBuilder<T> whereField<V>(
    DatumQueryField<T, V> field, {
    V? isEqualTo,
    V? isNotEqualTo,
    V? isGreaterThan,
    V? isGreaterThanOrEqualTo,
    V? isLessThan,
    V? isLessThanOrEqualTo,
    String? contains,
    String? containsIgnoreCase,
    String? startsWith,
    String? endsWith,
    List<V>? isIn,
    List<V>? isNotIn,
    V? arrayContains,
    List<V>? arrayContainsAny,
    String? matches,
    List<V>? between,
  }) {
    return where(
      field.name,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      contains: contains,
      containsIgnoreCase: containsIgnoreCase,
      startsWith: startsWith,
      endsWith: endsWith,
      isIn: isIn,
      isNotIn: isNotIn,
      arrayContains: arrayContains,
      arrayContainsAny: arrayContainsAny,
      matches: matches,
      between: between,
    );
  }

  /// Type-safe variant of [orderBy] using a [DatumQueryField] descriptor.
  DatumQueryBuilder<T> orderByField<V>(
    DatumQueryField<T, V> field, {
    bool descending = false,
    NullSortOrder nullSortOrder = NullSortOrder.last,
  }) {
    return orderBy(
      field.name,
      descending: descending,
      nullSortOrder: nullSortOrder,
    );
  }

  /// Type-safe null-check using a [DatumQueryField] descriptor.
  DatumQueryBuilder<T> whereFieldNull<V>(DatumQueryField<T, V> field) => whereNull(field.name);

  /// Type-safe not-null-check using a [DatumQueryField] descriptor.
  DatumQueryBuilder<T> whereFieldNotNull<V>(DatumQueryField<T, V> field) => whereNotNull(field.name);

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
      withRelated: List.unmodifiable(_withRelated),
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
