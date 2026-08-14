import 'migration.dart';

/// A single declarative transformation applied to one raw entity map during a
/// schema migration.
///
/// Use the factory shorthands for the common cases:
///
/// ```dart
/// ColumnOperation.add('priority', defaultValue: 0);
/// ColumnOperation.add('slug', compute: (row) => (row['title'] as String).toLowerCase());
/// ColumnOperation.rename('title', to: 'name');
/// ColumnOperation.remove('legacyField');
/// ColumnOperation.transform('createdAt', (value, row) => DateTime.parse(value as String).toUtc().toIso8601String());
/// ColumnOperation.row((row) => {...row, 'fullName': '${row['first']} ${row['last']}'});
/// ```
///
/// Implement this class directly for reusable custom operations.
abstract class ColumnOperation {
  const ColumnOperation();

  /// Adds a column named [name].
  ///
  /// The value is [defaultValue], or the result of [compute] (which receives
  /// the full row) when provided. Provide exactly one of the two.
  /// If the column already exists it is left untouched unless [overwrite]
  /// is true.
  factory ColumnOperation.add(
    String name, {
    Object? defaultValue,
    Object? Function(Map<String, dynamic> row)? compute,
    bool overwrite = false,
  }) =>
      AddColumn(name, defaultValue: defaultValue, compute: compute, overwrite: overwrite);

  /// Moves the value under [from] to the key [to]. Rows without [from] are
  /// left unchanged.
  factory ColumnOperation.rename(String from, {required String to}) = RenameColumn;

  /// Removes the column named [name] if present.
  factory ColumnOperation.remove(String name) = RemoveColumn;

  /// Replaces the value of [name] with `transform(value, row)`.
  ///
  /// Rows that do not contain [name] are skipped unless [applyIfAbsent] is
  /// true (in which case the transform receives `null` as the value).
  factory ColumnOperation.transform(
    String name,
    Object? Function(Object? value, Map<String, dynamic> row) transform, {
    bool applyIfAbsent = false,
  }) =>
      TransformColumn(name, transform, applyIfAbsent: applyIfAbsent);

  /// Applies an arbitrary whole-row rewrite. The returned map replaces the
  /// row entirely, so spread the input to keep untouched columns:
  /// `ColumnOperation.row((row) => {...row, 'v': 2})`.
  factory ColumnOperation.row(
    Map<String, dynamic> Function(Map<String, dynamic> row) transform,
  ) = RowTransform;

  /// Applies this operation to [row] and returns the resulting row.
  ///
  /// [row] is a private copy owned by the migration pipeline; implementations
  /// may mutate and return it, or return a new map.
  Map<String, dynamic> apply(Map<String, dynamic> row);
}

/// See [ColumnOperation.add].
class AddColumn extends ColumnOperation {
  AddColumn(this.name, {this.defaultValue, this.compute, this.overwrite = false})
      : assert(
          defaultValue == null || compute == null,
          'Provide either defaultValue or compute for "$name", not both.',
        );

  final String name;
  final Object? defaultValue;
  final Object? Function(Map<String, dynamic> row)? compute;
  final bool overwrite;

  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) {
    if (!overwrite && row.containsKey(name)) return row;
    row[name] = compute != null ? compute!(row) : defaultValue;
    return row;
  }
}

/// See [ColumnOperation.rename].
class RenameColumn extends ColumnOperation {
  RenameColumn(this.from, {required this.to});

  final String from;
  final String to;

  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) {
    if (!row.containsKey(from)) return row;
    row[to] = row.remove(from);
    return row;
  }
}

/// See [ColumnOperation.remove].
class RemoveColumn extends ColumnOperation {
  RemoveColumn(this.name);

  final String name;

  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) {
    row.remove(name);
    return row;
  }
}

/// See [ColumnOperation.transform].
class TransformColumn extends ColumnOperation {
  TransformColumn(this.name, this.transform, {this.applyIfAbsent = false});

  final String name;
  final Object? Function(Object? value, Map<String, dynamic> row) transform;
  final bool applyIfAbsent;

  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) {
    if (!applyIfAbsent && !row.containsKey(name)) return row;
    row[name] = transform(row[name], row);
    return row;
  }
}

/// See [ColumnOperation.row].
class RowTransform extends ColumnOperation {
  RowTransform(this.transform);

  final Map<String, dynamic> Function(Map<String, dynamic> row) transform;

  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) => transform(row);
}

/// A [Migration] described as a list of [ColumnOperation]s instead of
/// hand-written map surgery.
///
/// ```dart
/// SchemaMigration(
///   fromVersion: 1,
///   toVersion: 2,
///   operations: [
///     ColumnOperation.add('priority', defaultValue: 0),
///     ColumnOperation.rename('title', to: 'name'),
///   ],
/// )
/// ```
///
/// Rows can be scoped with [entityType] (matched against the row's
/// `__typename`) or an arbitrary [where] predicate; rows that don't match
/// pass through untouched. Unlike a hand-written [Migration.migrate],
/// [migrate] never mutates its input map — matched rows are copied before
/// operations run, which keeps the executor's rollback snapshot intact even
/// for adapters that hand out live map references.
class SchemaMigration extends Migration {
  SchemaMigration({
    required int fromVersion,
    required int toVersion,
    required List<ColumnOperation> operations,
    this.entityType,
    this.where,
  })  : assert(toVersion > fromVersion, 'toVersion must be greater than fromVersion'),
        _fromVersion = fromVersion,
        _toVersion = toVersion,
        operations = List.unmodifiable(operations);

  final int _fromVersion;
  final int _toVersion;

  /// The operations applied, in order, to every matching row.
  final List<ColumnOperation> operations;

  /// When set, only rows whose `__typename` equals this value are migrated.
  final String? entityType;

  /// When set, only rows for which this predicate returns true are migrated.
  /// Combined with [entityType] when both are given.
  final bool Function(Map<String, dynamic> row)? where;

  @override
  int get fromVersion => _fromVersion;

  @override
  int get toVersion => _toVersion;

  bool _matches(Map<String, dynamic> row) {
    if (entityType != null && row['__typename'] != entityType) return false;
    if (where != null && !where!(row)) return false;
    return true;
  }

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    if (!_matches(oldData)) return oldData;
    var row = Map<String, dynamic>.of(oldData);
    for (final operation in operations) {
      row = operation.apply(row);
    }
    return row;
  }
}
