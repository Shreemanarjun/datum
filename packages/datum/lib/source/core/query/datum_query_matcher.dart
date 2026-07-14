import 'dart:math';

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query.dart';

/// In-memory evaluation of a [DatumQuery] against entities and raw maps.
///
/// This is the reference query engine used by adapters that do not push
/// filtering down to a native store (e.g. [InMemoryLocalAdapter], the Hive
/// adapter). It supports every [FilterOperator], composite AND/OR filters,
/// multi-key sorting with null ordering, and offset/limit pagination.
///
/// Adapters backed by SQL should instead translate the query with
/// `DatumQuerySqlConverter` and let the database do the work.
abstract final class DatumQueryMatcher {
  /// Applies [query]'s filters, sorting, offset and limit to [items].
  static List<T> apply<T extends DatumEntityInterface>(
    List<T> items,
    DatumQuery query,
  ) {
    var filtered = items.where((item) {
      final json = item.toDatumMap();
      return matchesMap(json, query);
    }).toList();

    if (query.sorting.isNotEmpty) {
      filtered.sort((a, b) => _compare(a.toDatumMap(), b.toDatumMap(), query.sorting));
    }

    if (query.offset != null) {
      filtered = filtered.skip(query.offset!).toList();
    }
    if (query.limit != null) {
      filtered = filtered.take(query.limit!).toList();
    }
    return filtered;
  }

  /// Applies [query] to a list of raw maps (used when an adapter stores rows as
  /// `Map<String, dynamic>` rather than entity instances).
  static List<Map<String, dynamic>> applyToMaps(
    List<Map<String, dynamic>> rows,
    DatumQuery query,
  ) {
    var filtered = rows.where((row) => matchesMap(row, query)).toList();
    if (query.sorting.isNotEmpty) {
      filtered.sort((a, b) => _compare(a, b, query.sorting));
    }
    if (query.offset != null) {
      filtered = filtered.skip(query.offset!).toList();
    }
    if (query.limit != null) {
      filtered = filtered.take(query.limit!).toList();
    }
    return filtered;
  }

  /// Returns whether a single serialized [json] row satisfies [query]'s root
  /// filters (combined using the query's [DatumQuery.logicalOperator]).
  static bool matchesMap(Map<String, dynamic> json, DatumQuery query) {
    if (query.filters.isEmpty) return true;
    if (query.logicalOperator == LogicalOperator.and) {
      return query.filters.every((f) => _matches(json, f));
    }
    return query.filters.any((f) => _matches(json, f));
  }

  static int _compare(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    List<SortDescriptor> sorting,
  ) {
    for (final sort in sorting) {
      final valA = a[sort.field];
      final valB = b[sort.field];

      if (valA == null && valB == null) continue;
      if (valA == null) {
        return sort.nullSortOrder == NullSortOrder.first ? -1 : 1;
      }
      if (valB == null) {
        return sort.nullSortOrder == NullSortOrder.first ? 1 : -1;
      }
      if (valA is Comparable && valB is Comparable) {
        final c = valA.compareTo(valB);
        if (c != 0) return sort.descending ? -c : c;
      }
    }
    return 0;
  }
}

bool _matches(Map<String, dynamic> json, FilterCondition condition) {
  if (condition is Filter) {
    final value = json[condition.field];
    if (value == null && condition.operator != FilterOperator.isNull && condition.operator != FilterOperator.isNotNull) {
      return false;
    }

    switch (condition.operator) {
      case FilterOperator.equals:
        return value == condition.value;
      case FilterOperator.notEquals:
        return value != condition.value;
      case FilterOperator.greaterThan:
        return value is Comparable && value.compareTo(condition.value) > 0;
      case FilterOperator.greaterThanOrEqual:
        return value is Comparable && value.compareTo(condition.value) >= 0;
      case FilterOperator.lessThan:
        return value is Comparable && value.compareTo(condition.value) < 0;
      case FilterOperator.lessThanOrEqual:
        return value is Comparable && value.compareTo(condition.value) <= 0;
      case FilterOperator.contains:
        return value is String && value.contains(condition.value as String);
      case FilterOperator.isIn:
        return condition.value is List && (condition.value as List).contains(value);
      case FilterOperator.isNotIn:
        return condition.value is List && !(condition.value as List).contains(value);
      case FilterOperator.isNull:
        return value == null;
      case FilterOperator.isNotNull:
        return value != null;
      case FilterOperator.containsIgnoreCase:
        return value is String && condition.value is String && value.toLowerCase().contains((condition.value as String).toLowerCase());
      case FilterOperator.startsWith:
        return value is String && condition.value is String && value.startsWith(condition.value as String);
      case FilterOperator.endsWith:
        return value is String && condition.value is String && value.endsWith(condition.value as String);
      case FilterOperator.arrayContains:
        return value is List && value.contains(condition.value);
      case FilterOperator.arrayContainsAny:
        if (value is! List || condition.value is! List) return false;
        final valueSet = value.toSet();
        return (condition.value as List).any(valueSet.contains);
      case FilterOperator.matches:
        return value is String && condition.value is String && RegExp(condition.value as String).hasMatch(value);
      case FilterOperator.withinDistance:
        if (value is! Map || condition.value is! Map) return false;
        final point = value as Map<String, dynamic>;
        final params = condition.value as Map<String, dynamic>;
        final center = params['center'] as Map<String, double>?;
        final radius = params['radius'] as double?;
        if (point['latitude'] == null || point['longitude'] == null || center == null || radius == null) {
          return false;
        }
        final distance = _haversineDistance(
          point['latitude'] as double,
          point['longitude'] as double,
          center['latitude']!,
          center['longitude']!,
        );
        return distance <= radius;
      case FilterOperator.between:
        if (value is! Comparable || condition.value is! List) return false;
        final bounds = condition.value as List;
        if (bounds.length != 2) return false;
        return value.compareTo(bounds[0]) >= 0 && value.compareTo(bounds[1]) <= 0;
    }
  } else if (condition is CompositeFilter) {
    if (condition.operator == LogicalOperator.and) {
      return condition.conditions.every((c) => _matches(json, c));
    }
    return condition.conditions.any((c) => _matches(json, c));
  }
  return false;
}

double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371e3; // Earth's radius in metres
  final phi1 = lat1 * pi / 180;
  final phi2 = lat2 * pi / 180;
  final deltaPhi = (lat2 - lat1) * pi / 180;
  final deltaLambda = (lon2 - lon1) * pi / 180;

  final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}
