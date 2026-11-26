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
    // Serialize each entity once; the sort comparator reuses the maps.
    final byJson = <Map<String, dynamic>, T>{for (final item in items) item.toDatumMap(): item};
    return [for (final json in applyToMaps(byJson.keys.toList(), query)) byJson[json] as T];
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
      final c = _compareKey(a[sort.field], b[sort.field], sort);
      if (c != 0) return c;
    }
    return 0;
  }
}

/// Booleans don't implement [Comparable] in Dart, but SQL stores them as
/// 0/1 and sorts/compares them — normalize so both paths agree.
Comparable? _asComparable(dynamic value) => switch (value) {
      bool b => b ? 1 : 0,
      Comparable c => c,
      _ => null,
    };

bool _ordering(dynamic value, dynamic bound, bool Function(int) test) {
  final a = _asComparable(value);
  final b = _asComparable(bound);
  if (a == null || b == null) return false;
  return test(a.compareTo(b));
}

/// One sort key's ordering of two values; 0 means "tie, try the next key"
/// (including values that are not mutually comparable).
int _compareKey(dynamic valA, dynamic valB, SortDescriptor sort) {
  if (valA == null || valB == null) {
    if (valA == valB) return 0;
    final nullFirst = sort.nullSortOrder == NullSortOrder.first ? -1 : 1;
    return valA == null ? nullFirst : -nullFirst;
  }
  final compA = _asComparable(valA);
  final compB = _asComparable(valB);
  if (compA == null || compB == null) return 0;
  final c = compA.compareTo(compB);
  return sort.descending ? -c : c;
}

bool _matches(Map<String, dynamic> json, FilterCondition condition) => switch (condition) {
      Filter() => _matchesFilter(json[condition.field], condition.operator, condition.value),
      CompositeFilter(operator: LogicalOperator.and) => condition.conditions.every((c) => _matches(json, c)),
      CompositeFilter() => condition.conditions.any((c) => _matches(json, c)),
      _ => false,
    };

/// Per-row filter kernel: whether a row's field [value] satisfies [operator]
/// against the filter's [operand].
bool _matchesFilter(dynamic value, FilterOperator operator, dynamic operand) {
  if (value == null) return operator == FilterOperator.isNull;
  return switch (operator) {
    FilterOperator.equals => value == operand,
    FilterOperator.notEquals => value != operand,
    FilterOperator.greaterThan => _ordering(value, operand, (c) => c > 0),
    FilterOperator.greaterThanOrEqual => _ordering(value, operand, (c) => c >= 0),
    FilterOperator.lessThan => _ordering(value, operand, (c) => c < 0),
    FilterOperator.lessThanOrEqual => _ordering(value, operand, (c) => c <= 0),
    FilterOperator.contains => value is String && value.contains(operand as String),
    FilterOperator.isIn => operand is List && operand.contains(value),
    FilterOperator.isNotIn => operand is List && !operand.contains(value),
    FilterOperator.isNull => false,
    FilterOperator.isNotNull => true,
    FilterOperator.containsIgnoreCase => value is String && operand is String && value.toLowerCase().contains(operand.toLowerCase()),
    FilterOperator.startsWith => value is String && operand is String && value.startsWith(operand),
    FilterOperator.endsWith => value is String && operand is String && value.endsWith(operand),
    FilterOperator.arrayContains => value is List && value.contains(operand),
    FilterOperator.arrayContainsAny => value is List && operand is List && operand.any(value.toSet().contains),
    FilterOperator.matches => value is String && operand is String && RegExp(operand).hasMatch(value),
    FilterOperator.withinDistance => value is Map && operand is Map && _withinDistance(value, operand),
    FilterOperator.between => value is Comparable && operand is List && _between(value, operand),
  };
}

bool _withinDistance(Map<dynamic, dynamic> value, Map<dynamic, dynamic> operand) {
  final point = value as Map<String, dynamic>;
  final params = operand as Map<String, dynamic>;
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
}

bool _between(Comparable<dynamic> value, List<dynamic> bounds) => bounds.length == 2 && value.compareTo(bounds[0]) >= 0 && value.compareTo(bounds[1]) <= 0;

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
