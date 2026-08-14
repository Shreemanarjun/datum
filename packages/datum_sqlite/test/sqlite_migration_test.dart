import 'package:datum/datum.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// SqlMigrationExecutor running a real ALTER TABLE chain against the
/// adapter's own table — the end-to-end story datum_sqlite exists for.
void main() {
  late Database db;
  late SqliteLocalAdapter<ConformanceEntity> adapter;
  final logger = DatumLogger(enabled: false);

  setUp(() async {
    db = sqlite3.openInMemory();
    adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'entities',
      fromMap: ConformanceEntity.fromMap,
      columns: const {'name': 'TEXT', 'value': 'INTEGER'},
    );
    await adapter.initialize();
    await adapter.create(ConformanceEntity.make('a', name: 'Ada', value: 1));
    await adapter.create(ConformanceEntity.make('b', name: 'Grace', value: 9));
  });

  tearDown(() => db.dispose());

  List<String> columns() => db
      .select('PRAGMA table_info(entities)')
      .map((r) => r['name'] as String)
      .toList();

  test(
    'SchemaMigration chain runs as real DDL/DML and stamps the version',
    () async {
      final executor = SqlMigrationExecutor<ConformanceEntity>(
        localAdapter: adapter,
        table: 'entities',
        migrations: [
          SchemaMigration(
            fromVersion: 0,
            toVersion: 1,
            operations: [
              ColumnOperation.add('score', defaultValue: 0),
              ColumnOperation.transform(
                'value',
                (v, _) => v,
                sqlExpression: 'value * 10',
              ),
            ],
          ),
          SchemaMigration(
            fromVersion: 1,
            toVersion: 2,
            operations: [ColumnOperation.rename('score', to: 'rating')],
          ),
        ],
        targetVersion: 2,
        logger: logger,
      );

      expect(await executor.needsMigration(), isTrue);
      final result = await executor.execute();

      expect(result.success, isTrue, reason: '${result.migrationError}');
      expect(columns(), contains('rating'));
      expect(columns(), isNot(contains('score')));
      expect(
        db
            .select('SELECT value FROM entities ORDER BY id')
            .map((r) => r['value'])
            .toList(),
        [10, 90],
      );
      expect(await adapter.getStoredSchemaVersion(), 2);
      expect(await executor.needsMigration(), isFalse);
    },
  );

  test('a failing chain rolls back DDL and version atomically', () async {
    final executor = SqlMigrationExecutor<ConformanceEntity>(
      localAdapter: adapter,
      table: 'entities',
      migrations: [
        SchemaMigration(
          fromVersion: 0,
          toVersion: 1,
          operations: [ColumnOperation.add('score', defaultValue: 0)],
        ),
        SchemaMigration(
          fromVersion: 1,
          toVersion: 2,
          operations: [
            ColumnOperation.row(
              (r) => r,
              sql: ['UPDATE entities SET does_not_exist = 1'],
            ),
          ],
        ),
      ],
      targetVersion: 2,
      logger: logger,
    );

    final result = await executor.execute();

    expect(result.success, isFalse);
    expect(
      columns(),
      isNot(contains('score')),
      reason: 'step 1 DDL rolled back by the real transaction',
    );
    expect(await adapter.getStoredSchemaVersion(), 0);
  });

  test(
    'query pushdown compiles DatumQuery to SQL and scopes by user',
    () async {
      await adapter.create(
        ConformanceEntity.make(
          'c',
          userId: 'other-user',
          name: 'Alan',
          value: 99,
        ),
      );

      final result = await adapter.query(
        (DatumQueryBuilder<ConformanceEntity>()
              ..where('value', isGreaterThan: 0)
              ..orderBy('value', descending: true))
            .build(),
        userId: 'conformance-user',
      );

      expect(
        result.map((e) => e.name).toList(),
        ['Grace', 'Ada'],
        reason: 'other-user row excluded, sorted in SQL',
      );
    },
  );
}
