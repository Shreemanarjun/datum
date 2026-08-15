/// Reconciles a store's actual shape with its declared [DatumSchema] —
/// the executable half of auto-migration.
///
/// This runs **beside** the manual `SchemaMigration` version chain, never
/// inside it: the stored int schema version is exclusively owned by
/// `MigrationExecutor` / `SqlMigrationExecutor`, so existing chains keep
/// their exact semantics. Progress is tracked with the schema
/// [DatumSchema.fingerprint] instead (via [SchemaFingerprintCapable], when
/// the adapter opts in).
library;

import 'package:datum/source/adapter/adapter_capabilities.dart';
import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/core/migration/auto/schema_diff.dart';
import 'package:datum/source/core/migration/auto/schema_introspector.dart';
import 'package:datum/source/core/migration/schema_migration.dart';
import 'package:datum/source/core/migration/sql_schema_migration.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query_sql_converter.dart';
import 'package:datum/source/core/query/datum_raw_query.dart';
import 'package:datum/source/core/schema/datum_schema.dart';
import 'package:datum/source/utils/datum_logger.dart';

/// What one auto-migration pass did (or failed to do).
typedef AutoMigrationOutcome = ({
  bool success,
  Object? error,
  StackTrace? stackTrace,
  List<SchemaChange> applied,
  List<String> warnings,
});

/// Introspects, diffs, and applies the reconciliation for one entity store.
class AutoMigrationExecutor<T extends DatumEntityInterface> {
  AutoMigrationExecutor({
    required this.localAdapter,
    required this.schema,
    required this.logger,
    this.dropRemovedColumns = false,
  });

  final LocalAdapter<T> localAdapter;
  final DatumSchema<T> schema;
  final DatumLogger logger;

  /// Whether undeclared columns are dropped (default: kept + warned).
  final bool dropRemovedColumns;

  /// The value stamped after a successful pass: the schema fingerprint plus
  /// the drop policy. Turning [dropRemovedColumns] on later therefore
  /// invalidates the fast path and re-runs the pass once; turning it off
  /// still fast-paths (a drop-mode pass reconciled a superset).
  String get appliedStamp => dropRemovedColumns ? '${schema.fingerprint}+drop' : schema.fingerprint;

  Future<bool> _alreadyApplied() async {
    final stored = await _storedFingerprint();
    if (stored == appliedStamp) return true;
    return !dropRemovedColumns && stored == '${schema.fingerprint}+drop';
  }

  bool get _sqlPath {
    final adapter = localAdapter;
    return adapter is RawQueryCapable && adapter is SqlSchemaCapable && (adapter as SqlSchemaCapable).sqlDialect != SqlDialect.custom;
  }

  Future<String?> _storedFingerprint() async {
    if (localAdapter case final SchemaFingerprintCapable capable) {
      return capable.getStoredSchemaFingerprint();
    }
    return null;
  }

  Future<void> _stamp() async {
    if (localAdapter case final SchemaFingerprintCapable capable) {
      await capable.setStoredSchemaFingerprint(appliedStamp);
    }
  }

  Future<SchemaShape> _introspect() {
    if (_sqlPath) {
      final sql = localAdapter as SqlSchemaCapable;
      return SqlSchemaIntrospector(
        adapter: localAdapter as RawQueryCapable,
        table: sql.sqlTable,
        dialect: sql.sqlDialect,
      ).introspect();
    }
    return RawDataSchemaIntrospector<T>(localAdapter).introspect();
  }

  /// Whether a reconciliation pass would change anything (fingerprint fast
  /// path first, then a real introspection + diff).
  Future<bool> needsMigration() async {
    if (await _alreadyApplied()) return false;
    final shape = await _introspect();
    if (!_sqlPath && shape.rowCount == 0) return false;
    final result = diffSchema<T>(
      schema: schema,
      actual: shape,
      dropRemovedColumns: dropRemovedColumns,
      sqlPath: _sqlPath,
      dialect: _dialect,
    );
    return result.operations.isNotEmpty;
  }

  SqlDialect get _dialect => _sqlPath ? (localAdapter as SqlSchemaCapable).sqlDialect : SqlDialect.sqlite;

  /// Runs one reconciliation pass. Never throws — failures come back in the
  /// outcome, with the store restored to its pre-pass state.
  Future<AutoMigrationOutcome> execute() async {
    try {
      if (await _alreadyApplied()) {
        return _success(const [], const []);
      }
      final shape = await _introspect();
      if (!_sqlPath && shape.rowCount == 0) {
        // Fresh install: rows written from now on carry the declared shape.
        await _stamp();
        return _success(const [], const []);
      }
      final diff = diffSchema<T>(
        schema: schema,
        actual: shape,
        dropRemovedColumns: dropRemovedColumns,
        sqlPath: _sqlPath,
        dialect: _dialect,
      );
      for (final warning in diff.warnings) {
        logger.warn('[AutoMigration:${schema.name}] $warning');
      }
      if (diff.operations.isEmpty) {
        await _stamp();
        return _success(const [], diff.warnings);
      }
      logger.info('[AutoMigration:${schema.name}] applying: ${diff.changes.join(', ')}');
      if (_sqlPath) {
        await _executeSql(diff);
      } else {
        await _executeRawData(diff);
      }
      await _stamp();
      return _success(diff.changes, diff.warnings);
    } on Object catch (error, stackTrace) {
      logger.error('[AutoMigration:${schema.name}] failed: $error', stackTrace);
      return (
        success: false,
        error: error,
        stackTrace: stackTrace,
        applied: const <SchemaChange>[],
        warnings: const <String>[],
      );
    }
  }

  AutoMigrationOutcome _success(List<SchemaChange> applied, List<String> warnings) => (success: true, error: null, stackTrace: null, applied: applied, warnings: warnings);

  Future<void> _executeSql(SchemaDiffResult diff) async {
    final sql = localAdapter as SqlSchemaCapable;
    final raw = localAdapter as RawQueryCapable;
    // The generator resolves SqlConvertibleOperation first, so
    // SchemaRenameOperation emits its own RENAME COLUMN.
    final statements = SqlMigrationGenerator(dialect: sql.sqlDialect).statementsFor(
      SchemaMigration(fromVersion: 0, toVersion: 1, operations: diff.operations),
      table: sql.sqlTable,
    );
    await localAdapter.transaction(() async {
      for (final statement in statements) {
        await raw.rawQuery(DatumRawQuery(sql: statement));
      }
    });
  }

  Future<void> _executeRawData(SchemaDiffResult diff) async {
    final snapshot = await localAdapter.getAllRawData();
    try {
      await localAdapter.transaction(() async {
        final rows = await localAdapter.getAllRawData();
        final migrated = [
          for (final row in rows) diff.operations.fold(Map<String, dynamic>.from(row), (acc, op) => op.apply(acc)),
        ];
        await localAdapter.overwriteAllRawData(migrated);
      });
    } on Object {
      // Mirror MigrationExecutor: restore for adapters whose transaction is a
      // pass-through rather than a real rollback.
      await localAdapter.overwriteAllRawData(snapshot);
      rethrow;
    }
  }
}
