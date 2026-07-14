/// An adapter-aware **raw query** for projections, aggregations, and joins that
/// bypass full entity hydration (#11).
///
/// Unlike [DatumQuery] (which returns hydrated entities), a raw query returns
/// raw rows (`List<Map<String, dynamic>>`) so screens can select specific
/// columns or compute `COUNT`/`SUM`/`GROUP BY` without materializing models.
///
/// It carries fields for both worlds; each adapter reads the ones it supports:
///
/// ```dart
/// // Local SQL adapter (e.g. Drift/SQLite):
/// final rows = await manager.rawQuery(
///   const DatumRawQuery(sql: 'SELECT id, name FROM users WHERE age > ?', args: [18]),
///   source: DataSource.local,
/// );
///
/// // Remote adapter (e.g. Supabase/REST):
/// final rows = await manager.rawQuery(
///   const DatumRawQuery(table: 'users', select: 'id, name', filters: {'age': {'gt': 18}}),
///   source: DataSource.remote,
/// );
/// ```
class DatumRawQuery {
  const DatumRawQuery({
    this.sql,
    this.args = const [],
    this.table,
    this.select,
    this.filters,
    this.count = false,
    this.metadata = const {},
  });

  /// Raw SQL for local SQL adapters. Ignored by non-SQL adapters.
  final String? sql;

  /// Positional arguments bound to [sql] placeholders.
  final List<Object?> args;

  /// Target table/collection for remote adapters.
  final String? table;

  /// Column projection for remote adapters (e.g. `'id, name'`).
  final String? select;

  /// Structured filters for remote adapters (e.g. `{'age': {'gt': 18}}`).
  final Map<String, dynamic>? filters;

  /// Whether this is a count aggregation (adapters return a single row).
  final bool count;

  /// Adapter-specific extra options (grouping, ordering, limits, …).
  final Map<String, dynamic> metadata;

  @override
  String toString() => 'DatumRawQuery(sql: $sql, table: $table, select: $select, count: $count)';
}

/// A single raw result row.
typedef DatumRawRow = Map<String, dynamic>;
