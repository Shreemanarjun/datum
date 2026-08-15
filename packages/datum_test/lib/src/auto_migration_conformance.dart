/// Conformance suite for **auto-migration** (`DatumSchema` +
/// `AutoMigrationExecutor`) against a real adapter.
///
/// Certifies the observable contract:
/// 1. a legacy store is reconciled — renames keep values, adds backfill
///    defaults, undeclared columns are kept by default;
/// 2. `dropRemovedColumns` removes undeclared leftovers when opted in;
/// 3. the schema fingerprint stamps run-once behavior, surviving a
///    simulated relaunch when the adapter is [SchemaFingerprintCapable].
///
/// The suite seeds the store through `overwriteAllRawData` with a **legacy
/// shape** (`name` + `legacy` payload keys). SQL adapters must therefore be
/// created with those legacy columns declared, e.g.:
///
/// ```dart
/// runAutoMigrationConformanceTests(
///   name: 'SqliteLocalAdapter',
///   createLocal: () async {
///     final adapter = SqliteLocalAdapter<ConformanceEntity>(
///       database: sqlite3.openInMemory(),
///       table: 'entities',
///       fromMap: ConformanceEntity.fromMap,
///       columns: const {'name': 'TEXT', 'legacy': 'INTEGER'},
///     );
///     await adapter.initialize();
///     return adapter;
///   },
/// );
/// ```
library;

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// The declared target shape every suite run reconciles toward:
/// `name` → `title` (rename hint), plus a new `score` with default 5.
DatumSchema<ConformanceEntity> autoMigrationConformanceSchema() =>
    DatumSchema<ConformanceEntity>(
      name: 'auto_migration_conformance',
      fields: [
        ...datumCoreFieldSpecs<ConformanceEntity>().all,
        DatumFieldSpec<ConformanceEntity, String>(
          'title',
          renamedFrom: 'name',
          defaultValue: '',
        ),
        DatumFieldSpec<ConformanceEntity, int>('score', defaultValue: 5),
      ],
    );

/// Registers the auto-migration conformance tests for one local adapter.
void runAutoMigrationConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroyLocal,
  Future<LocalAdapter<ConformanceEntity>> Function()? reopenLocal,
}) {
  group('$name auto-migration conformance', () {
    final logger = DatumLogger(enabled: false);
    LocalAdapter<ConformanceEntity>? current;

    tearDown(() async {
      final adapter = current;
      current = null;
      if (adapter != null) await destroyLocal?.call(adapter);
    });

    Future<LocalAdapter<ConformanceEntity>> seeded() async {
      final adapter = await createLocal();
      current = adapter;
      await adapter.overwriteAllRawData([
        for (final (id, entityName) in [('a', 'Ada'), ('b', 'Grace')])
          {
            'id': id,
            'userId': 'conformance-user',
            'name': entityName,
            'legacy': 1,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'modifiedAt': '2026-01-01T00:00:00.000Z',
            'version': 1,
            'isDeleted': false,
          },
      ]);
      return adapter;
    }

    AutoMigrationExecutor<ConformanceEntity> executor(
      LocalAdapter<ConformanceEntity> adapter, {
      bool drop = false,
    }) => AutoMigrationExecutor<ConformanceEntity>(
      localAdapter: adapter,
      schema: autoMigrationConformanceSchema(),
      dropRemovedColumns: drop,
      logger: logger,
    );

    test(
      'reconciles a legacy store: rename keeps values, add backfills, undeclared kept',
      () async {
        final adapter = await seeded();
        final outcome = await executor(adapter).execute();
        expect(outcome.success, isTrue, reason: '${outcome.error}');

        final rows = await adapter.getAllRawData();
        expect(rows.map((r) => r['title']).toSet(), {'Ada', 'Grace'});
        expect(rows.every((r) => r['score'] == 5), isTrue);
        expect(rows.any((r) => r.containsKey('name')), isFalse);
        expect(
          rows.every((r) => r.containsKey('legacy')),
          isTrue,
          reason: 'undeclared columns are kept by default',
        );
        expect(outcome.warnings.join(), contains('legacy'));
      },
    );

    test(
      'dropRemovedColumns removes undeclared leftovers when opted in',
      () async {
        final adapter = await seeded();
        final outcome = await executor(adapter, drop: true).execute();
        expect(outcome.success, isTrue, reason: '${outcome.error}');
        final rows = await adapter.getAllRawData();
        expect(rows.any((r) => r.containsKey('legacy')), isFalse);
      },
    );

    test(
      'a second pass is a no-op, run-once across a relaunch when fingerprinted',
      () async {
        final adapter = await seeded();
        final schema = autoMigrationConformanceSchema();
        expect((await executor(adapter).execute()).success, isTrue);

        final second = await executor(adapter).execute();
        expect(second.success, isTrue);
        expect(second.applied, isEmpty, reason: 'nothing left to reconcile');

        if (adapter case final SchemaFingerprintCapable capable) {
          expect(
            await capable.getStoredSchemaFingerprint(),
            schema.fingerprint,
          );
          if (reopenLocal != null) {
            await destroyLocal?.call(adapter);
            final reopened = await reopenLocal();
            current = reopened;
            expect(
              await (reopened as SchemaFingerprintCapable)
                  .getStoredSchemaFingerprint(),
              schema.fingerprint,
              reason: 'the stamp must survive a relaunch',
            );
            expect(await executor(reopened).needsMigration(), isFalse);
          }
        }
      },
    );
  });
}
