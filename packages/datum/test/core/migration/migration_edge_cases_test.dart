import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../../mocks/test_entity.dart';

/// Adapter whose overwriteAllRawData can be armed to fail on a specific call,
/// letting tests reach the executor's restore-failure branch.
class _RestoreFailingAdapter extends InMemoryLocalAdapter<TestEntity> {
  _RestoreFailingAdapter() : super(fromMap: TestEntity.fromJson);

  int overwriteCalls = 0;
  int? failOnCall;

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) {
    overwriteCalls++;
    if (overwriteCalls == failOnCall) {
      throw StateError('storage wedged on write #$overwriteCalls');
    }
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
  group('ColumnOperation edge cases', () {
    test('rename onto an existing key overwrites the target value', () {
      final row = ColumnOperation.rename('old', to: 'new').apply({'old': 1, 'new': 2});
      expect(row, {'new': 1});
    });

    test('transform sees an explicit null value (present key)', () {
      final row = ColumnOperation.transform('c', (v, _) => v ?? 'filled').apply({'c': null});
      expect(row, {'c': 'filled'});
    });

    test('add with neither defaultValue nor compute adds an explicit null', () {
      final row = ColumnOperation.add('c').apply({'id': '1'});
      expect(row.containsKey('c'), isTrue);
      expect(row['c'], isNull);
    });

    test('remove of an absent column is a no-op', () {
      expect(ColumnOperation.remove('ghost').apply({'keep': 1}), {'keep': 1});
    });
  });

  group('SchemaMigration edge cases', () {
    test('empty operations list is an identity migration (still a copy)', () {
      final input = {'id': '1'};
      final migration = SchemaMigration(fromVersion: 0, toVersion: 1, operations: const []);
      final output = migration.migrate(input);
      expect(output, input);
      expect(identical(output, input), isFalse);
    });

    test('entityType and where must both match', () {
      final migration = SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        entityType: 'Task',
        where: (r) => r['value'] == 1,
        operations: [ColumnOperation.add('flag', defaultValue: true)],
      );
      expect(migration.migrate({'__typename': 'Task', 'value': 1}), contains('flag'));
      expect(migration.migrate({'__typename': 'Task', 'value': 2}), isNot(contains('flag')));
      expect(migration.migrate({'__typename': 'Note', 'value': 1}), isNot(contains('flag')));
    });

    test('operations list is unmodifiable', () {
      final migration = SchemaMigration(fromVersion: 0, toVersion: 1, operations: [ColumnOperation.remove('x')]);
      expect(() => migration.operations.add(ColumnOperation.remove('y')), throwsUnsupportedError);
    });
  });

  group('MigrationPlan edge cases', () {
    SchemaMigration step(int from, int to) => SchemaMigration(fromVersion: from, toVersion: to, operations: const []);

    test('aggregates multiple configuration problems into one exception message', () {
      expect(
        () => MigrationPlan.resolve(
          [
            _BackwardsMigration(),
            SchemaMigration(fromVersion: 5, toVersion: 6, operations: const []),
            SchemaMigration(fromVersion: 5, toVersion: 7, operations: const []),
          ],
          fromVersion: 0,
          toVersion: 2,
        ),
        throwsA(
          isA<MigrationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('does not move forward'), contains('ambiguous')),
          ),
        ),
      );
    });

    test('config problems are flagged even on steps outside the active path', () {
      // The 9->8 backwards step is never needed for 0->1, but it is still a
      // misconfiguration worth failing loudly on.
      final backwards = _BackwardsMigration();
      expect(
        () => MigrationPlan.resolve([step(0, 1), backwards], fromVersion: 0, toVersion: 1),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('does not move forward'))),
      );
    });

    test('empty migrations list with work to do reports the gap', () {
      expect(
        () => MigrationPlan.resolve(const [], fromVersion: 0, toVersion: 1),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('no migration starts at v0'))),
      );
    });
  });

  group('MigrationExecutor edge cases', () {
    final logger = DatumLogger(enabled: false);

    MigrationExecutor<TestEntity> executor(
      _RestoreFailingAdapter adapter, {
      List<Migration>? migrations,
      int target = 1,
    }) =>
        MigrationExecutor<TestEntity>(
          localAdapter: adapter,
          migrations: migrations ??
              [
                SchemaMigration(
                  fromVersion: 0,
                  toVersion: 1,
                  operations: [ColumnOperation.transform('value', (v, _) => (v as int) + 1)],
                ),
              ],
          targetVersion: target,
          logger: logger,
        );

    test('an empty store still advances the stored version', () async {
      final adapter = _RestoreFailingAdapter();
      await adapter.initialize();

      final result = await executor(adapter).execute();

      expect(result.success, isTrue);
      expect(await adapter.getStoredSchemaVersion(), 1);
    });

    test('a store already past the target is a successful no-op (downgrade safety)', () async {
      final adapter = _RestoreFailingAdapter();
      await adapter.initialize();
      await adapter.setStoredSchemaVersion(5);
      await adapter.create(_entity('a', value: 1));

      final needs = await executor(adapter).needsMigration();
      final result = await executor(adapter).execute();

      expect(needs, isFalse);
      expect(result.success, isTrue);
      expect(await adapter.getStoredSchemaVersion(), 5);
      expect((await adapter.getAllRawData()).single['value'], 1, reason: 'no rewrite happened');
    });

    test('restore failure still reports the original migration error', () async {
      final adapter = _RestoreFailingAdapter();
      await adapter.initialize();
      await adapter.create(_entity('a', value: 1));

      final migrations = [
        SchemaMigration(
          fromVersion: 0,
          toVersion: 1,
          operations: [ColumnOperation.transform('value', (v, _) => (v as int) + 1)],
        ),
        SchemaMigration(
          fromVersion: 1,
          toVersion: 2,
          operations: [ColumnOperation.row((r) => throw ArgumentError('bad row'))],
        ),
      ];
      // Call #1 = step-1 write, call #2 = the restore write.
      adapter.failOnCall = 2;

      final result = await executor(adapter, migrations: migrations, target: 2).execute();

      expect(result.success, isFalse);
      expect(result.migrationError, isA<ArgumentError>(), reason: 'original error wins over the restore error');
    });
  });
}

/// A migration whose version pair goes backwards — inexpressible via
/// SchemaMigration (its assert forbids it), so modelled directly.
class _BackwardsMigration extends Migration {
  @override
  int get fromVersion => 9;
  @override
  int get toVersion => 8;
  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) => oldData;
}
