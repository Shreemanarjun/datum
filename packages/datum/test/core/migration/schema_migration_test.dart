import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../../mocks/test_entity.dart';

/// In-memory adapter that counts raw-data writes so tests can prove when the
/// executor did (or did not) touch the store.
class _CountingAdapter extends InMemoryLocalAdapter<TestEntity> {
  _CountingAdapter() : super(fromMap: TestEntity.fromJson);

  int overwriteCalls = 0;

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) {
    overwriteCalls++;
    return super.overwriteAllRawData(data, userId: userId);
  }
}

TestEntity _entity(String id, {int value = 0}) => TestEntity(
      id: id,
      userId: 'u1',
      name: 'name-$id',
      value: value,
      modifiedAt: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      version: 1,
    );

void main() {
  group('ColumnOperation', () {
    test('add sets a missing column to the default value', () {
      final row = ColumnOperation.add('priority', defaultValue: 3).apply({'id': '1'});
      expect(row, containsPair('priority', 3));
    });

    test('add leaves an existing column untouched by default', () {
      final row = ColumnOperation.add('priority', defaultValue: 3).apply({'priority': 9});
      expect(row['priority'], 9);
    });

    test('add overwrites an existing column when overwrite is true', () {
      final row = ColumnOperation.add('priority', defaultValue: 3, overwrite: true).apply({'priority': 9});
      expect(row['priority'], 3);
    });

    test('add can compute the value from the row', () {
      final row = ColumnOperation.add(
        'slug',
        compute: (r) => (r['title'] as String).toLowerCase(),
      ).apply({'title': 'Hello World'});
      expect(row['slug'], 'hello world');
    });

    test('add rejects passing both defaultValue and compute', () {
      expect(
        () => ColumnOperation.add('x', defaultValue: 1, compute: (_) => 2),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rename moves the value to the new key', () {
      final row = ColumnOperation.rename('title', to: 'name').apply({'title': 'a', 'other': 1});
      expect(row, {'name': 'a', 'other': 1});
    });

    test('rename is a no-op when the source key is absent', () {
      final row = ColumnOperation.rename('title', to: 'name').apply({'other': 1});
      expect(row, {'other': 1});
    });

    test('remove drops the column', () {
      final row = ColumnOperation.remove('legacy').apply({'legacy': 1, 'keep': 2});
      expect(row, {'keep': 2});
    });

    test('transform rewrites the value with access to the row', () {
      final row = ColumnOperation.transform(
        'total',
        (value, r) => (value as int) * (r['multiplier'] as int),
      ).apply({'total': 5, 'multiplier': 4});
      expect(row['total'], 20);
    });

    test('transform skips absent columns by default', () {
      final row = ColumnOperation.transform('total', (value, r) => 99).apply({'other': 1});
      expect(row, {'other': 1});
    });

    test('transform applies to absent columns when applyIfAbsent is true', () {
      final row = ColumnOperation.transform(
        'total',
        (value, r) => value ?? 0,
        applyIfAbsent: true,
      ).apply({'other': 1});
      expect(row, {'other': 1, 'total': 0});
    });

    test('row applies an arbitrary whole-row rewrite', () {
      final row = ColumnOperation.row(
        (r) => {...r, 'fullName': '${r['first']} ${r['last']}'},
      ).apply({'first': 'Ada', 'last': 'Lovelace'});
      expect(row['fullName'], 'Ada Lovelace');
    });
  });

  group('SchemaMigration', () {
    test('applies operations in order', () {
      final migration = SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        operations: [
          ColumnOperation.add('count', defaultValue: 1),
          ColumnOperation.transform('count', (v, _) => (v as int) + 1),
        ],
      );
      expect(migration.migrate({'id': '1'})['count'], 2);
    });

    test('never mutates the input map', () {
      final input = {'id': '1', 'legacy': true};
      SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        operations: [ColumnOperation.remove('legacy')],
      ).migrate(input);
      expect(input, {'id': '1', 'legacy': true});
    });

    test('entityType scopes the migration to matching __typename rows', () {
      final migration = SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        entityType: 'Task',
        operations: [ColumnOperation.add('done', defaultValue: false)],
      );
      expect(migration.migrate({'__typename': 'Task'}), contains('done'));
      expect(migration.migrate({'__typename': 'Note'}), isNot(contains('done')));
      expect(migration.migrate({'id': 'untyped'}), isNot(contains('done')));
    });

    test('where predicate scopes the migration to matching rows', () {
      final migration = SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        where: (row) => row['value'] == 1,
        operations: [ColumnOperation.add('flag', defaultValue: true)],
      );
      expect(migration.migrate({'value': 1}), contains('flag'));
      expect(migration.migrate({'value': 2}), isNot(contains('flag')));
    });

    test('rejects a version pair that does not move forward', () {
      expect(
        () => SchemaMigration(fromVersion: 2, toVersion: 2, operations: const []),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('MigrationPlan', () {
    SchemaMigration step(int from, int to) => SchemaMigration(fromVersion: from, toVersion: to, operations: const []);

    test('resolves an ordered chain from unordered input', () {
      final plan = MigrationPlan.resolve(
        [step(2, 3), step(0, 1), step(1, 2)],
        fromVersion: 0,
        toVersion: 3,
      );
      expect(plan.steps.map((m) => m.toVersion), [1, 2, 3]);
    });

    test('supports multi-version jumps in a single step', () {
      final plan = MigrationPlan.resolve(
        [step(0, 2), step(2, 3)],
        fromVersion: 0,
        toVersion: 3,
      );
      expect(plan.steps.map((m) => m.toVersion), [2, 3]);
    });

    test('returns an empty plan when already at or past the target', () {
      expect(MigrationPlan.resolve([step(0, 1)], fromVersion: 1, toVersion: 1).steps, isEmpty);
      expect(MigrationPlan.resolve([step(0, 1)], fromVersion: 2, toVersion: 1).steps, isEmpty);
    });

    test('reports a gap in the chain', () {
      expect(
        () => MigrationPlan.resolve([step(0, 1)], fromVersion: 0, toVersion: 3),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('no migration starts at v1'))),
      );
    });

    test('reports duplicate starting versions as ambiguous', () {
      expect(
        () => MigrationPlan.resolve([step(0, 1), step(0, 2)], fromVersion: 0, toVersion: 2),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('ambiguous'))),
      );
    });

    test('reports a step that overshoots the target version', () {
      expect(
        () => MigrationPlan.resolve([step(0, 5)], fromVersion: 0, toVersion: 3),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('overshoots'))),
      );
    });
  });

  group('MigrationExecutor with SchemaMigration', () {
    late _CountingAdapter adapter;
    final logger = DatumLogger(enabled: false);

    setUp(() async {
      adapter = _CountingAdapter();
      await adapter.initialize();
      await adapter.create(_entity('1', value: 1));
      await adapter.create(_entity('2', value: 2));
      adapter.overwriteCalls = 0;
    });

    test('runs a multi-step chain and stamps the stored version', () async {
      final executor = MigrationExecutor<TestEntity>(
        localAdapter: adapter,
        migrations: [
          SchemaMigration(
            fromVersion: 0,
            toVersion: 1,
            operations: [ColumnOperation.transform('value', (v, _) => (v as int) + 100)],
          ),
          SchemaMigration(
            fromVersion: 1,
            toVersion: 2,
            operations: [ColumnOperation.transform('value', (v, _) => (v as int) * 2)],
          ),
        ],
        targetVersion: 2,
        logger: logger,
      );

      expect(await executor.needsMigration(), isTrue);
      final result = await executor.execute();

      expect(result.success, isTrue);
      expect(await adapter.getStoredSchemaVersion(), 2);
      final values = (await adapter.getAllRawData()).map((r) => r['value']).toSet();
      expect(values, {202, 204});
    });

    test('an invalid plan fails fast without touching the store', () async {
      final executor = MigrationExecutor<TestEntity>(
        localAdapter: adapter,
        // Gap: nothing starts at v1.
        migrations: [
          SchemaMigration(fromVersion: 0, toVersion: 1, operations: const []),
        ],
        targetVersion: 3,
        logger: logger,
      );

      final result = await executor.execute();

      expect(result.success, isFalse);
      expect(result.migrationError, isA<MigrationException>());
      expect(adapter.overwriteCalls, 0);
      expect(await adapter.getStoredSchemaVersion(), 0);
    });

    test('a mid-chain failure restores data and version', () async {
      final executor = MigrationExecutor<TestEntity>(
        localAdapter: adapter,
        migrations: [
          SchemaMigration(
            fromVersion: 0,
            toVersion: 1,
            operations: [ColumnOperation.transform('value', (v, _) => (v as int) + 100)],
          ),
          SchemaMigration(
            fromVersion: 1,
            toVersion: 2,
            operations: [
              ColumnOperation.row((row) => throw StateError('boom on ${row['id']}')),
            ],
          ),
        ],
        targetVersion: 2,
        logger: logger,
      );

      final result = await executor.execute();

      expect(result.success, isFalse);
      expect(result.migrationError, isA<StateError>());
      expect(await adapter.getStoredSchemaVersion(), 0);
      final values = (await adapter.getAllRawData()).map((r) => r['value']).toSet();
      expect(values, {1, 2}, reason: 'original values restored after rollback');
    });
  });
}
