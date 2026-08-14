import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../../mocks/test_entity.dart';

/// A fake SQL-backed adapter: records every statement passed to [rawQuery]
/// and simulates transactional rollback of the schema version.
class _FakeSqlAdapter extends InMemoryLocalAdapter<TestEntity> with RawQueryCapable {
  _FakeSqlAdapter() : super(fromMap: TestEntity.fromJson);

  final List<String> executed = [];

  /// When set, [rawQuery] throws once it sees a statement containing this.
  String? failOn;

  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId}) async {
    final sql = query.sql!;
    if (failOn != null && sql.contains(failOn!)) {
      throw StateError('SQL failure on: $sql');
    }
    executed.add(sql);
    return const [];
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    final versionBackup = await getStoredSchemaVersion();
    try {
      return await action();
    } catch (_) {
      await setStoredSchemaVersion(versionBackup);
      rethrow;
    }
  }
}

class _CustomSqlOp extends ColumnOperation implements SqlConvertibleOperation {
  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) => row;

  @override
  List<String> toSqlStatements(String table, SqlDialect dialect) => ['CREATE INDEX idx_custom ON $table (id) -- ${dialect.name}'];
}

class _OpaqueOp extends ColumnOperation {
  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) => row;
}

void main() {
  SchemaMigration wrap(List<ColumnOperation> ops, {bool Function(Map<String, dynamic>)? where, String? sqlWhere}) => SchemaMigration(fromVersion: 0, toVersion: 1, operations: ops, where: where, sqlWhere: sqlWhere);

  group('SqlMigrationGenerator (sqlite)', () {
    const gen = SqlMigrationGenerator();

    test('add with defaultValue emits ALTER with inferred type and DEFAULT', () {
      expect(
        gen.statementsFor(wrap([ColumnOperation.add('priority', defaultValue: 3)]), table: 'tasks'),
        ['ALTER TABLE "tasks" ADD COLUMN "priority" INTEGER DEFAULT 3'],
      );
    });

    test('type inference covers bool, double, String, DateTime', () {
      String typeOf(Object v) => gen.statementsFor(wrap([ColumnOperation.add('c', defaultValue: v)]), table: 't').single;
      expect(typeOf(true), contains('"c" INTEGER DEFAULT 1'));
      expect(typeOf(1.5), contains('"c" REAL DEFAULT 1.5'));
      expect(typeOf('x'), contains('"c" TEXT DEFAULT \'x\''));
      expect(typeOf(DateTime.utc(2026)), contains('"c" TEXT DEFAULT \'2026-01-01T00:00:00.000Z\''));
    });

    test('string literals escape embedded quotes', () {
      expect(
        gen.statementsFor(wrap([ColumnOperation.add('c', defaultValue: "it's")]), table: 't').single,
        contains("DEFAULT 'it''s'"),
      );
    });

    test('identifiers escape embedded double quotes', () {
      expect(
        gen.statementsFor(wrap([ColumnOperation.remove('we"ird')]), table: 't"bl').single,
        'ALTER TABLE "t""bl" DROP COLUMN "we""ird"',
      );
    });

    test('sqlType overrides inference and nullable add omits DEFAULT', () {
      expect(
        gen.statementsFor(wrap([ColumnOperation.add('note', sqlType: 'VARCHAR(40)')]), table: 't'),
        ['ALTER TABLE "t" ADD COLUMN "note" VARCHAR(40)'],
      );
    });

    test('uninferrable default without sqlType is rejected', () {
      expect(
        () => gen.statementsFor(
            wrap([
              ColumnOperation.add('tags', defaultValue: const ['a'])
            ]),
            table: 't'),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('pass sqlType'))),
      );
    });

    test('add with compute but no sqlExpression is rejected', () {
      expect(
        () => gen.statementsFor(wrap([ColumnOperation.add('slug', compute: (r) => r['id'])]), table: 't'),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('sqlExpression'))),
      );
    });

    test('add with sqlExpression backfills via UPDATE', () {
      expect(
        gen.statementsFor(
          wrap([ColumnOperation.add('slug', sqlType: 'TEXT', sqlExpression: 'LOWER(title)')]),
          table: 't',
        ),
        [
          'ALTER TABLE "t" ADD COLUMN "slug" TEXT',
          'UPDATE "t" SET "slug" = LOWER(title)',
        ],
      );
    });

    test('rename and remove emit ALTER statements', () {
      expect(
        gen.statementsFor(
          wrap([ColumnOperation.rename('title', to: 'name'), ColumnOperation.remove('legacy')]),
          table: 't',
        ),
        [
          'ALTER TABLE "t" RENAME COLUMN "title" TO "name"',
          'ALTER TABLE "t" DROP COLUMN "legacy"',
        ],
      );
    });

    test('transform with sqlExpression emits UPDATE scoped by sqlWhere', () {
      expect(
        gen.statementsFor(
          wrap(
            [ColumnOperation.transform('priority', (v, _) => v, sqlExpression: 'priority + 1')],
            sqlWhere: 'priority < 5',
          ),
          table: 't',
        ),
        ['UPDATE "t" SET "priority" = priority + 1 WHERE priority < 5'],
      );
    });

    test('transform without sqlExpression is rejected', () {
      expect(
        () => gen.statementsFor(wrap([ColumnOperation.transform('c', (v, _) => v)]), table: 't'),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('sqlExpression'))),
      );
    });

    test('Dart-only where combined with an UPDATE is rejected', () {
      expect(
        () => gen.statementsFor(
          wrap(
            [ColumnOperation.transform('c', (v, _) => v, sqlExpression: 'c + 1')],
            where: (r) => true,
          ),
          table: 't',
        ),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('sqlWhere'))),
      );
    });

    test('row with sql runs the provided statements verbatim', () {
      expect(
        gen.statementsFor(
          wrap([
            ColumnOperation.row((r) => r, sql: ['UPDATE "t" SET "a" = "b" || \'!\'']),
          ]),
          table: 't',
        ),
        ['UPDATE "t" SET "a" = "b" || \'!\''],
      );
    });

    test('row without sql is rejected', () {
      expect(
        () => gen.statementsFor(wrap([ColumnOperation.row((r) => r)]), table: 't'),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('sql:'))),
      );
    });

    test('SqlConvertibleOperation takes precedence over built-in mapping', () {
      expect(
        gen.statementsFor(wrap([_CustomSqlOp()]), table: 't'),
        ['CREATE INDEX idx_custom ON t (id) -- sqlite'],
      );
    });

    test('an unknown operation type without SqlConvertibleOperation is rejected', () {
      expect(
        () => gen.statementsFor(wrap([_OpaqueOp()]), table: 't'),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('SqlConvertibleOperation'))),
      );
    });

    test('custom dialect is rejected with guidance', () {
      const customGen = SqlMigrationGenerator(dialect: SqlDialect.custom);
      expect(
        () => customGen.statementsFor(wrap([ColumnOperation.remove('c')]), table: 't'),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('sqlite and postgresql'))),
      );
    });
  });

  group('SqlMigrationGenerator (postgresql)', () {
    const gen = SqlMigrationGenerator(dialect: SqlDialect.postgresql);

    test('bool, double, DateTime map to native postgres types and literals', () {
      String stmt(Object v) => gen.statementsFor(wrap([ColumnOperation.add('c', defaultValue: v)]), table: 't').single;
      expect(stmt(false), contains('"c" BOOLEAN DEFAULT FALSE'));
      expect(stmt(true), contains('"c" BOOLEAN DEFAULT TRUE'));
      expect(stmt(2.5), contains('"c" DOUBLE PRECISION DEFAULT 2.5'));
      expect(stmt(DateTime.utc(2026)), contains('"c" TIMESTAMP DEFAULT'));
    });
  });

  group('SqlMigrationExecutor', () {
    late _FakeSqlAdapter adapter;
    final logger = DatumLogger(enabled: false);

    List<SchemaMigration> chain() => [
          SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
            ColumnOperation.add('priority', defaultValue: 0),
          ]),
          SchemaMigration(fromVersion: 1, toVersion: 2, operations: [
            ColumnOperation.transform('priority', (v, _) => v, sqlExpression: 'priority + 1'),
          ]),
        ];

    SqlMigrationExecutor<TestEntity> executor({List<SchemaMigration>? migrations, int target = 2}) => SqlMigrationExecutor<TestEntity>(
          localAdapter: adapter,
          table: 'tasks',
          migrations: migrations ?? chain(),
          targetVersion: target,
          logger: logger,
        );

    setUp(() async {
      adapter = _FakeSqlAdapter();
      await adapter.initialize();
    });

    test('runs the chain in order and stamps the version', () async {
      expect(await executor().needsMigration(), isTrue);
      final result = await executor().execute();

      expect(result.success, isTrue);
      expect(await adapter.getStoredSchemaVersion(), 2);
      expect(adapter.executed, [
        'ALTER TABLE "tasks" ADD COLUMN "priority" INTEGER DEFAULT 0',
        'UPDATE "tasks" SET "priority" = priority + 1',
      ]);
      expect(await executor().needsMigration(), isFalse);
    });

    test('resumes mid-chain from the stored version', () async {
      await adapter.setStoredSchemaVersion(1);
      final result = await executor().execute();

      expect(result.success, isTrue);
      expect(adapter.executed, ['UPDATE "tasks" SET "priority" = priority + 1']);
    });

    test('an invalid plan fails before any SQL runs', () async {
      final result = await executor(
        migrations: [chain().first], // gap: nothing starts at v1
        target: 3,
      ).execute();

      expect(result.success, isFalse);
      expect(result.migrationError, isA<MigrationException>());
      expect(adapter.executed, isEmpty);
    });

    test('an untranslatable operation fails before any SQL runs', () async {
      final migrations = [
        SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
          ColumnOperation.add('ok', defaultValue: 1),
        ]),
        SchemaMigration(fromVersion: 1, toVersion: 2, operations: [
          ColumnOperation.row((r) => r), // no SQL form
        ]),
      ];
      final result = await executor(migrations: migrations).execute();

      expect(result.success, isFalse);
      expect(result.migrationError, isA<MigrationException>());
      expect(adapter.executed, isEmpty, reason: 'step 1 must not run when step 2 cannot be translated');
      expect(await adapter.getStoredSchemaVersion(), 0);
    });

    test('a failing statement surfaces the error and the transaction restores the version', () async {
      adapter.failOn = 'UPDATE';
      final result = await executor().execute();

      expect(result.success, isFalse);
      expect(result.migrationError, isA<StateError>());
      expect(await adapter.getStoredSchemaVersion(), 0, reason: 'transaction rollback restores the version');
    });
  });
}
