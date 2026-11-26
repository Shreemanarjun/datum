/// The pure, synchronous heart of auto-migration: compare a declared
/// [DatumSchema] against a store's observed [SchemaShape] and produce the
/// [ColumnOperation]s that reconcile them.
library;

import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:datum/source/core/migration/schema_migration.dart';
import 'package:datum/source/core/migration/sql_schema_migration.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query_sql_converter.dart';
import 'package:datum/source/core/schema/datum_field_spec.dart';
import 'package:datum/source/core/schema/datum_schema.dart';
import 'package:datum/source/core/migration/auto/schema_introspector.dart';

/// Column names auto-migration never adds, renames, or drops: the sync core
/// fields plus anything `__`-prefixed (engine-internal, e.g. `__typename`).
const Set<String> kReservedColumnNames = {'id', 'userId', 'modifiedAt', 'createdAt', 'version', 'isDeleted'};

/// One reconciliation step the differ decided on.
sealed class SchemaChange {
  const SchemaChange();
}

/// A declared field is missing from the store and will be added
/// (backfilled with its default / null).
final class SchemaColumnAdded extends SchemaChange {
  const SchemaColumnAdded(this.field);
  final DatumFieldSpec<dynamic, dynamic> field;

  @override
  String toString() => 'add "${field.name}"';
}

/// A stored column will be renamed to a declared field (via `renamedFrom:`).
final class SchemaColumnRenamed extends SchemaChange {
  const SchemaColumnRenamed(this.from, this.field);
  final String from;
  final DatumFieldSpec<dynamic, dynamic> field;

  @override
  String toString() => 'rename "$from" -> "${field.name}"';
}

/// A stored column not present in the declaration will be dropped
/// (only when `autoMigrateDropColumns` is on).
final class SchemaColumnRemoved extends SchemaChange {
  const SchemaColumnRemoved(this.name);
  final String name;

  @override
  String toString() => 'remove "$name"';
}

/// The differ's output: the decided [changes], the [operations] that execute
/// them (fed into the existing map / SQL migration machinery), and
/// human-readable [warnings] for everything noticed but deliberately not
/// touched.
typedef SchemaDiffResult = ({
  List<SchemaChange> changes,
  List<ColumnOperation> operations,
  List<String> warnings,
});

/// A rename that never clobbers: on the map path the value moves only when
/// the target key is absent (a partially-migrated row keeps its newer
/// value); on the SQL path it emits `ALTER TABLE … RENAME COLUMN` through
/// the [SqlConvertibleOperation] hook.
class SchemaRenameOperation extends ColumnOperation implements SqlConvertibleOperation {
  SchemaRenameOperation(this.from, {required this.to});

  final String from;
  final String to;

  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) {
    if (!row.containsKey(from)) return row;
    if (row.containsKey(to)) {
      row.remove(from);
      return row;
    }
    row[to] = row.remove(from);
    return row;
  }

  String _ident(String name) => '"${name.replaceAll('"', '""')}"';

  @override
  List<String> toSqlStatements(String table, SqlDialect dialect) => ['ALTER TABLE ${_ident(table)} RENAME COLUMN ${_ident(from)} TO ${_ident(to)}'];
}

/// Diffs [schema] against the observed [actual] shape.
///
/// Pure and synchronous. [sqlPath] tells the differ whether it is deciding
/// for a rigid SQL table (every row has every column; a rename with both
/// columns present is impossible) or for per-row maps (a rename is applied
/// row-by-row and skips already-migrated rows).
///
/// Throws [MigrationException] — before anything touches the store — when a
/// missing field is non-nullable and has no `defaultValue`, listing every
/// such field at once.
SchemaDiffResult diffSchema<E extends DatumEntityInterface>({
  required DatumSchema<E> schema,
  required SchemaShape actual,
  required bool dropRemovedColumns,
  required bool sqlPath,
  SqlDialect dialect = SqlDialect.sqlite,
}) {
  final (:changes, :operations, :renamedAway) = _diffDeclared(schema, actual, sqlPath, dialect);
  final warnings = <String>[];
  final declaredNames = schema.fields.map((f) => f.name).toSet();
  for (final key in actual.allKeys) {
    if (declaredNames.contains(key) || kReservedColumnNames.contains(key) || renamedAway.contains(key) || key.startsWith('__')) {
      continue;
    }
    if (dropRemovedColumns) {
      changes.add(SchemaColumnRemoved(key));
      operations.add(RemoveColumn(key));
    } else {
      warnings.add('Column "$key" is not in the "${schema.name}" schema; '
          'kept (autoMigrateDropColumns: false).');
    }
  }

  return (changes: changes, operations: operations, warnings: warnings);
}

/// Renames and adds for every declared field missing from the store, in
/// declaration order (operations: all renames, then all adds). Throws
/// [MigrationException] listing every non-nullable field that cannot be added.
({List<SchemaChange> changes, List<ColumnOperation> operations, Set<String> renamedAway}) _diffDeclared(
  DatumSchema<DatumEntityInterface> schema,
  SchemaShape actual,
  bool sqlPath,
  SqlDialect dialect,
) {
  final changes = <SchemaChange>[];
  final renames = <ColumnOperation>[];
  final adds = <ColumnOperation>[];
  final problems = <String>[];
  final renamedAway = <String>{};

  for (final field in schema.fields) {
    if (actual.universalKeys.contains(field.name)) continue;

    final from = _renameSource(field, actual, sqlPath);
    if (from != null) {
      changes.add(SchemaColumnRenamed(from, field));
      renames.add(SchemaRenameOperation(from, to: field.name));
      renamedAway.add(from);
      continue;
    }

    // Present on some rows only (map path): backfill via AddColumn below.
    // SQL columns exist on every row; nothing to do.
    if (sqlPath && actual.allKeys.contains(field.name)) continue;
    if (!field.isNullable && field.defaultValue == null) {
      problems.add('Cannot auto-add non-nullable "${field.name}" without a defaultValue — '
          'set defaultValue: on its DatumFieldSpec, or make the type nullable.');
      continue;
    }
    changes.add(SchemaColumnAdded(field));
    adds.add(AddColumn(
      field.name,
      defaultValue: field.defaultValue == null ? null : field.encode(field.defaultValue),
      sqlType: field.resolveSqlType(dialect: dialect),
    ));
  }

  if (problems.isNotEmpty) {
    throw MigrationException(
      code: DatumExceptionCode.schemaMismatch,
      message: 'Auto-migration for "${schema.name}" cannot proceed:\n${problems.join('\n')}',
    );
  }
  return (changes: changes, operations: [...renames, ...adds], renamedAway: renamedAway);
}

/// The stored column [field] should be renamed from, if any. On the SQL path
/// a declared column that already exists never reaches here (universalKeys ==
/// allKeys), so the `sqlPath` clause only guards inconsistent shapes; on the
/// map path a partially-renamed store still renames — SchemaRenameOperation
/// is row-safe.
String? _renameSource(DatumFieldSpec<dynamic, dynamic> field, SchemaShape actual, bool sqlPath) {
  final from = field.renamedFrom;
  if (from == null || !actual.allKeys.contains(from)) return null;
  return sqlPath && actual.allKeys.contains(field.name) ? null : from;
}
