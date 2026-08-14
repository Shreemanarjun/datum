import '../../adapter/adapter_capabilities.dart';
import '../../adapter/local_adapter.dart';
import '../../utils/datum_logger.dart';
import '../errors/datum_exception.dart';
import '../models/datum_entity.dart';
import '../query/datum_query_sql_converter.dart';
import '../query/datum_raw_query.dart';
import 'migration_executor.dart';
import 'migration_plan.dart';
import 'schema_migration.dart';

/// Implemented by custom [ColumnOperation]s that know their own SQL form.
///
/// [SqlMigrationGenerator] checks for this interface before the built-in
/// operation types, so a user-defined operation (or a built-in one wrapped in
/// a subclass) can take full control of the emitted statements.
abstract interface class SqlConvertibleOperation {
  /// The SQL statements equivalent to this operation, run in order.
  List<String> toSqlStatements(String table, SqlDialect dialect);
}

/// Translates a [SchemaMigration] into SQL statements for a given [dialect].
///
/// Mapping:
///
/// | Operation                      | SQL                                          |
/// |--------------------------------|----------------------------------------------|
/// | `add` (defaultValue)           | `ALTER TABLE t ADD COLUMN c <type> DEFAULT v`|
/// | `add` (sqlExpression backfill) | `... ADD COLUMN` + `UPDATE t SET c = expr`   |
/// | `rename`                       | `ALTER TABLE t RENAME COLUMN a TO b`         |
/// | `remove`                       | `ALTER TABLE t DROP COLUMN c`                |
/// | `transform` (sqlExpression)    | `UPDATE t SET c = expr`                      |
/// | `row` (sql: [...])             | the provided statements, verbatim            |
///
/// The migration's [SchemaMigration.sqlWhere] scopes every generated `UPDATE`.
/// Operations that only exist as Dart closures (`compute`/`transform`/`row`
/// without their SQL counterpart) cannot be translated and raise a
/// [MigrationException] — as does a Dart-only [SchemaMigration.where] combined
/// with an `UPDATE`-producing operation, which would otherwise silently apply
/// to every row. [SchemaMigration.entityType] is ignored: SQL adapters store
/// one entity per table, so the table name is already the scope.
///
/// `RENAME COLUMN` and `DROP COLUMN` require SQLite 3.25+/3.35+; all current
/// Flutter/Dart sqlite bundles ship newer versions.
class SqlMigrationGenerator {
  const SqlMigrationGenerator({this.dialect = SqlDialect.sqlite});

  final SqlDialect dialect;

  /// Emits the ordered SQL statements for [migration] against [table].
  List<String> statementsFor(SchemaMigration migration, {required String table}) {
    if (dialect == SqlDialect.custom) {
      throw MigrationException(
        message: 'SqlMigrationGenerator supports sqlite and postgresql; for a custom '
            'dialect, implement SqlConvertibleOperation on your operations instead.',
        code: DatumExceptionCode.migrationError,
      );
    }
    final statements = <String>[];
    for (final operation in migration.operations) {
      statements.addAll(_statementsForOperation(operation, migration, table));
    }
    return statements;
  }

  List<String> _statementsForOperation(
    ColumnOperation operation,
    SchemaMigration migration,
    String table,
  ) {
    if (operation is SqlConvertibleOperation) {
      // No promotion here: SqlConvertibleOperation is not a ColumnOperation subtype.
      return (operation as SqlConvertibleOperation).toSqlStatements(table, dialect);
    }
    return switch (operation) {
      AddColumn() => _addColumn(operation, migration, table),
      RenameColumn() => [
          'ALTER TABLE ${_ident(table)} RENAME COLUMN ${_ident(operation.from)} TO ${_ident(operation.to)}',
        ],
      RemoveColumn() => [
          'ALTER TABLE ${_ident(table)} DROP COLUMN ${_ident(operation.name)}',
        ],
      TransformColumn() => [
          _update(
            operation.name,
            operation.sqlExpression ?? _unsupported('transform', operation.name, hint: 'a Dart transform closure needs its SQL counterpart via sqlExpression'),
            migration,
            table,
          ),
        ],
      RowTransform() => operation.sql ?? _unsupported('row', '(whole-row rewrite)', hint: 'pass its SQL form via ColumnOperation.row(..., sql: [...])'),
      _ => _unsupported(operation.runtimeType.toString(), '', hint: 'implement SqlConvertibleOperation on it to define its SQL form'),
    };
  }

  List<String> _addColumn(AddColumn operation, SchemaMigration migration, String table) {
    if (operation.compute != null && operation.sqlExpression == null) {
      _unsupported('add', operation.name, hint: 'a Dart compute closure needs its SQL counterpart via sqlExpression');
    }
    final type = operation.sqlType ?? _inferType(operation);
    final defaultClause = operation.defaultValue != null ? ' DEFAULT ${_literal(operation.defaultValue)}' : '';
    return [
      'ALTER TABLE ${_ident(table)} ADD COLUMN ${_ident(operation.name)} $type$defaultClause',
      if (operation.sqlExpression != null) _update(operation.name, operation.sqlExpression!, migration, table),
    ];
  }

  String _update(String column, String expression, SchemaMigration migration, String table) {
    if (migration.where != null && migration.sqlWhere == null) {
      throw MigrationException(
        message: 'Migration v${migration.fromVersion} -> v${migration.toVersion} has a Dart-only '
            '`where` predicate; provide the equivalent `sqlWhere` so generated UPDATEs '
            'are scoped the same way.',
        code: DatumExceptionCode.migrationError,
      );
    }
    final whereClause = migration.sqlWhere != null ? ' WHERE ${migration.sqlWhere}' : '';
    return 'UPDATE ${_ident(table)} SET ${_ident(column)} = $expression$whereClause';
  }

  String _inferType(AddColumn operation) => switch (operation.defaultValue) {
        int() => 'INTEGER',
        bool() => dialect == SqlDialect.postgresql ? 'BOOLEAN' : 'INTEGER',
        double() => dialect == SqlDialect.postgresql ? 'DOUBLE PRECISION' : 'REAL',
        String() => 'TEXT',
        DateTime() => dialect == SqlDialect.postgresql ? 'TIMESTAMP' : 'TEXT',
        _ => throw MigrationException(
            message: 'Cannot infer a SQL type for column "${operation.name}" '
                '(defaultValue: ${operation.defaultValue}); pass sqlType explicitly.',
            code: DatumExceptionCode.migrationError,
          ),
      };

  String _literal(Object? value) => switch (value) {
        null => 'NULL',
        bool() => dialect == SqlDialect.postgresql ? (value ? 'TRUE' : 'FALSE') : (value ? '1' : '0'),
        num() => value.toString(),
        DateTime() => "'${value.toIso8601String()}'",
        _ => "'${value.toString().replaceAll("'", "''")}'",
      };

  String _ident(String name) => '"${name.replaceAll('"', '""')}"';

  Never _unsupported(String operation, String detail, {required String hint}) {
    throw MigrationException(
      message: 'Operation `$operation` $detail cannot be expressed as SQL; $hint.',
      code: DatumExceptionCode.migrationError,
    );
  }
}

/// Runs [SchemaMigration]s natively on a SQL store through the adapter's
/// [RawQueryCapable.rawQuery] — the SQL twin of the map-based
/// [MigrationExecutor].
///
/// Where the map-based executor rewrites every row through the entity's
/// serialization round-trip (right for schemaless stores like Hive or
/// in-memory), this executor emits `ALTER TABLE`/`UPDATE` statements so the
/// database changes its own schema — the only way columns can actually be
/// added or dropped on a SQL table.
///
/// Every statement for the whole chain is generated (and therefore validated)
/// up front, and the plan is checked with [MigrationPlan.resolve], so nothing
/// touches the database unless the entire migration is expressible. Execution
/// runs inside [LocalAdapter.transaction]; atomicity is the adapter's —
/// SQLite and PostgreSQL both roll back DDL+DML together.
class SqlMigrationExecutor<T extends DatumEntityInterface> {
  SqlMigrationExecutor({
    required this.localAdapter,
    required this.table,
    required this.migrations,
    required this.targetVersion,
    required this.logger,
    SqlDialect dialect = SqlDialect.sqlite,
  })  : generator = SqlMigrationGenerator(dialect: dialect),
        assert(
          localAdapter is RawQueryCapable,
          'SqlMigrationExecutor requires a LocalAdapter that mixes in RawQueryCapable.',
        );

  final LocalAdapter<T> localAdapter;
  final String table;
  final List<SchemaMigration> migrations;
  final int targetVersion;
  final DatumLogger logger;
  final SqlMigrationGenerator generator;

  /// Whether the stored schema version is behind [targetVersion].
  Future<bool> needsMigration() async {
    return await localAdapter.getStoredSchemaVersion() < targetVersion;
  }

  /// Resolves, translates, and executes the migration chain.
  ///
  /// Returns a failed [MigrationResult] without touching the database when
  /// the chain is invalid or any operation has no SQL form. Statement
  /// execution errors surface in the result after the adapter's transaction
  /// rolls back.
  Future<MigrationResult> execute() async {
    final List<(SchemaMigration, List<String>)> plannedSteps;
    try {
      final plan = MigrationPlan.resolve(
        migrations,
        fromVersion: await localAdapter.getStoredSchemaVersion(),
        toVersion: targetVersion,
      );
      plannedSteps = [
        for (final step in plan.steps.cast<SchemaMigration>()) (step, generator.statementsFor(step, table: table)),
      ];
    } catch (planError, planStack) {
      logger.error('SQL migration plan invalid, nothing was modified: $planError');
      return (success: false, migrationError: planError, migrationStack: planStack);
    }

    try {
      return await localAdapter.transaction(() async {
        final rawCapable = localAdapter as RawQueryCapable;
        for (final (migration, statements) in plannedSteps) {
          logger.info('Running SQL migration from v${migration.fromVersion} to v${migration.toVersion} '
              '(${statements.length} statements)...');
          for (final statement in statements) {
            await rawCapable.rawQuery(DatumRawQuery(sql: statement));
          }
          await localAdapter.setStoredSchemaVersion(migration.toVersion);
        }
        logger.info('SQL schema migration completed. Current version: $targetVersion');
        return (success: true, migrationError: null, migrationStack: null);
      });
    } catch (migrationError, migrationStack) {
      logger.error('SQL migration failed (adapter transaction rolled back): $migrationError', migrationStack);
      return (success: false, migrationError: migrationError, migrationStack: migrationStack);
    }
  }
}
