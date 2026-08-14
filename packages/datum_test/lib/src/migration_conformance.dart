import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// Runs the Datum **migration conformance suite** against a local adapter.
///
/// Certifies that datum's migration machinery ([SchemaMigration] chains run
/// through [MigrationExecutor], or [SqlMigrationExecutor] on SQL stores)
/// behaves correctly on the adapter under test:
///
/// - a valid chain transforms data, stamps the target version, and flips
///   `needsMigration` to false;
/// - an invalid chain (gap) fails fast without touching data or version;
/// - a mid-chain failure restores the original data and version (snapshot
///   restore on the map path, transaction rollback on the SQL path);
/// - a partially-migrated store resumes from its stored version without
///   re-running earlier steps;
/// - with [reopenLocal], a successful migration is run-once across a
///   simulated app relaunch.
///
/// Every test receives a fresh adapter from [createLocal] (already
/// initialized) seeded with two [ConformanceEntity] rows, and disposes it
/// afterwards ([destroyLocal] runs after dispose for extra teardown).
///
/// The suite's standard chain is v0 -> v1 (transform `value` by +100, SQL
/// counterpart `value + 100`) then v1 -> v2 (add `archived`, default false).
/// On the map path over typed adapters the added column may not survive the
/// entity round-trip, so the suite asserts on version + transformed values
/// and only asserts the added column where `getAllRawData` shows it.
///
/// Map path (schemaless stores — Hive, in-memory):
///
/// ```dart
/// runMigrationConformanceTests(
///   name: 'HiveLocalAdapter',
///   createLocal: () async { ... },
///   reopenLocal: () async { /* same box name */ },
/// );
/// ```
///
/// SQL path (adapters mixing in [RawQueryCapable]) — pass [sqlPath] and the
/// adapter's [table] so the chain runs as real `ALTER TABLE`/`UPDATE`
/// statements:
///
/// ```dart
/// runMigrationConformanceTests(
///   name: 'SqliteLocalAdapter',
///   createLocal: () async { ... },
///   sqlPath: true,
///   table: 'conformance_migration',
/// );
/// ```
void runMigrationConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroyLocal,
  Future<LocalAdapter<ConformanceEntity>> Function()? reopenLocal,
  bool sqlPath = false,
  String? table,
}) {
  if (sqlPath && table == null) {
    throw ArgumentError.notNull(
      'table (required when sqlPath is true: SqlMigrationExecutor needs the '
      'table its ALTER TABLE/UPDATE statements target)',
    );
  }

  group('$name migration conformance', () {
    final logger = DatumLogger(enabled: false);
    late LocalAdapter<ConformanceEntity> adapter;

    setUp(() async {
      adapter = await createLocal();
      await adapter.create(
        ConformanceEntity.make('m1', name: 'first', value: 1),
      );
      await adapter.create(
        ConformanceEntity.make('m2', name: 'second', value: 9),
      );
    });

    tearDown(() async {
      await adapter.dispose();
      await destroyLocal?.call(adapter);
    });

    /// The standard conformance chain: transform then add.
    List<SchemaMigration> standardChain() => [
      SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        operations: [
          ColumnOperation.transform(
            'value',
            (value, _) => (value as num).toInt() + 100,
            sqlExpression: 'value + 100',
          ),
        ],
      ),
      SchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        operations: [ColumnOperation.add('archived', defaultValue: false)],
      ),
    ];

    /// Step 1 succeeds, step 2 fails — per-path failure mechanics.
    List<SchemaMigration> failingChain() => [
      standardChain().first,
      SchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        operations: [
          if (sqlPath)
            // Statement generation succeeds; execution hits a missing
            // column, so the adapter's transaction must roll back.
            ColumnOperation.row(
              (row) => row,
              sql: ['UPDATE $table SET nonexistent_col = 1'],
            )
          else
            ColumnOperation.row(
              (row) =>
                  throw StateError('simulated mid-chain migration failure'),
            ),
        ],
      ),
    ];

    /// Builds the executor matching the adapter's migration path.
    ({
      Future<bool> Function() needsMigration,
      Future<MigrationResult> Function() execute,
    })
    executorFor(List<SchemaMigration> migrations, {int targetVersion = 2}) {
      if (sqlPath) {
        final executor = SqlMigrationExecutor<ConformanceEntity>(
          localAdapter: adapter,
          table: table!,
          migrations: migrations,
          targetVersion: targetVersion,
          logger: logger,
        );
        return (
          needsMigration: executor.needsMigration,
          execute: executor.execute,
        );
      }
      final executor = MigrationExecutor<ConformanceEntity>(
        localAdapter: adapter,
        migrations: migrations,
        targetVersion: targetVersion,
        logger: logger,
      );
      return (
        needsMigration: executor.needsMigration,
        execute: executor.execute,
      );
    }

    /// The seeded entities' `value`s, ordered by id (`m1` then `m2`).
    Future<List<int>> storedValues() async {
      final all = await adapter.readAll(userId: 'conformance-user');
      final sorted = [...all]..sort((a, b) => a.id.compareTo(b.id));
      return sorted.map((e) => e.value).toList();
    }

    /// Asserts the added `archived` column on every row — but only where the
    /// adapter's raw representation actually shows it (typed map-path
    /// adapters may drop columns the entity does not model).
    Future<void> expectArchivedWhereVisible() async {
      final raw = await adapter.getAllRawData();
      if (raw.isEmpty || !raw.first.containsKey('archived')) return;
      for (final row in raw) {
        expect(
          row['archived'],
          anyOf(false, 0),
          reason: 'added column must carry its default on every row',
        );
      }
    }

    test(
      'valid chain transforms values, stamps the target version, and flips needsMigration',
      () async {
        final executor = executorFor(standardChain());
        expect(await executor.needsMigration(), isTrue);

        final result = await executor.execute();

        expect(result.success, isTrue, reason: '${result.migrationError}');
        expect(
          await storedValues(),
          [101, 109],
          reason: 'v0 -> v1 transform applied once to every row',
        );
        expect(
          await adapter.getStoredSchemaVersion(),
          2,
          reason: 'version stamped at target',
        );
        expect(await executor.needsMigration(), isFalse);
        await expectArchivedWhereVisible();
      },
    );

    test(
      'invalid chain (gap) fails fast with no data or version change',
      () async {
        // v1 -> v2 is missing: the plan cannot reach the target.
        final executor = executorFor([
          standardChain().first,
          SchemaMigration(
            fromVersion: 2,
            toVersion: 3,
            operations: [ColumnOperation.add('never', defaultValue: 0)],
          ),
        ], targetVersion: 3);

        final result = await executor.execute();

        expect(result.success, isFalse);
        expect(result.migrationError, isA<MigrationException>());
        expect(
          await storedValues(),
          [1, 9],
          reason: 'an unresolvable plan must not touch the store',
        );
        expect(
          await adapter.getStoredSchemaVersion(),
          0,
          reason: 'version untouched by an invalid plan',
        );
      },
    );

    test('mid-chain failure restores original data and version', () async {
      final executor = executorFor(failingChain());

      final result = await executor.execute();

      expect(result.success, isFalse);
      expect(result.migrationError, isNotNull);
      expect(
        await storedValues(),
        [1, 9],
        reason: 'step 1\'s transform must not survive step 2\'s failure',
      );
      expect(
        await adapter.getStoredSchemaVersion(),
        0,
        reason: 'version must roll back with the data',
      );
    });

    test('resume from stored version runs only the remaining steps', () async {
      // Simulate a store that already completed v0 -> v1 (values NOT yet
      // transformed by this run's chain — only steps >= 1 may execute).
      await adapter.setStoredSchemaVersion(1);

      final executor = executorFor(standardChain());
      expect(await executor.needsMigration(), isTrue);

      final result = await executor.execute();

      expect(result.success, isTrue, reason: '${result.migrationError}');
      expect(
        await storedValues(),
        [1, 9],
        reason: 'the v0 -> v1 transform must not run again on a v1 store',
      );
      expect(await adapter.getStoredSchemaVersion(), 2);
      expect(await executor.needsMigration(), isFalse);
      await expectArchivedWhereVisible();
    });

    if (reopenLocal != null) {
      test('a successful migration runs once across an app relaunch', () async {
        final first = executorFor(standardChain());
        final result = await first.execute();
        expect(result.success, isTrue, reason: '${result.migrationError}');
        expect(await storedValues(), [101, 109]);

        // Simulated relaunch: fresh adapter over the same store.
        await adapter.dispose();
        adapter = await reopenLocal();

        final second = executorFor(standardChain());
        expect(
          await second.needsMigration(),
          isFalse,
          reason: 'the stored version must survive the relaunch',
        );

        final rerun = await second.execute();
        expect(rerun.success, isTrue);
        expect(
          await storedValues(),
          [101, 109],
          reason: 'a second launch must be a no-op, not another +100',
        );
        expect(await adapter.getStoredSchemaVersion(), 2);
      });
    }
  });
}
