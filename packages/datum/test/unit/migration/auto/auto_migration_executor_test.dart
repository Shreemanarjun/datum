import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../../schema/schema_test_entity.dart';

Map<String, dynamic> legacyRow(String id, {String name = 'n', bool withLegacy = true}) => {
      'id': id,
      'userId': 'u1',
      'name': name,
      if (withLegacy) 'legacy': 1,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-01T00:00:00.000Z',
      'version': 1,
      'isDeleted': false,
    };

DatumSchema<SchemaTask> reconciliationSchema() => DatumSchema<SchemaTask>(
      name: 'tasks',
      fields: [
        ...SchemaTask.core.all,
        DatumFieldSpec<SchemaTask, String>('title', renamedFrom: 'name', defaultValue: ''),
        DatumFieldSpec<SchemaTask, int>('priority', defaultValue: 5),
      ],
    );

class _MapAdapter implements LocalAdapter<SchemaTask> {
  _MapAdapter([List<Map<String, dynamic>>? seed]) : rows = [...?seed];

  List<Map<String, dynamic>> rows;
  int getAllCalls = 0;
  bool failNextOverwrite = false;

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    getAllCalls++;
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) async {
    if (failNextOverwrite) {
      failNextOverwrite = false;
      throw StateError('disk full');
    }
    rows = [for (final row in data) Map<String, dynamic>.from(row)];
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) => action();

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FingerprintMapAdapter extends _MapAdapter implements SchemaFingerprintCapable {
  _FingerprintMapAdapter([super.seed]);

  String? fingerprint;

  @override
  Future<String?> getStoredSchemaFingerprint() async => fingerprint;

  @override
  Future<void> setStoredSchemaFingerprint(String value) async => fingerprint = value;
}

class _SqlAdapter with RawQueryCapable, SqlSchemaCapable implements LocalAdapter<SchemaTask> {
  _SqlAdapter({required this.columns});

  List<String> columns;
  int rowCount = 2;
  final ddl = <String>[];
  var inTransaction = false;
  var ddlRanInTransaction = true;

  @override
  String get sqlTable => 'tasks';

  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId}) async {
    final sql = query.sql!;
    if (sql.startsWith('PRAGMA')) {
      return [
        for (final c in columns) {'name': c}
      ];
    }
    if (sql.contains('COUNT(*)')) {
      return [
        {'c': rowCount}
      ];
    }
    ddl.add(sql);
    if (!inTransaction) ddlRanInTransaction = false;
    return const [];
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    inTransaction = true;
    try {
      return await action();
    } finally {
      inTransaction = false;
    }
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AutoMigrationExecutor<SchemaTask> executorFor(LocalAdapter<SchemaTask> adapter, {DatumSchema<SchemaTask>? schema, bool drop = true}) => AutoMigrationExecutor<SchemaTask>(
      localAdapter: adapter,
      schema: schema ?? reconciliationSchema(),
      dropRemovedColumns: drop,
      logger: DatumLogger(enabled: false),
    );

void main() {
  group('fingerprint fast path', () {
    test('a matching stamp skips introspection entirely', () async {
      final adapter = _FingerprintMapAdapter([legacyRow('a')]);
      final executor = executorFor(adapter);
      adapter.fingerprint = executor.appliedStamp;
      expect(await executor.needsMigration(), isFalse);
      final outcome = await executor.execute();
      expect(outcome.success, isTrue);
      expect(outcome.applied, isEmpty);
      expect(adapter.getAllCalls, 0, reason: 'no introspection on a fingerprint hit');
    });

    test('a fresh install stamps without touching rows', () async {
      final adapter = _FingerprintMapAdapter();
      final executor = executorFor(adapter);
      final outcome = await executor.execute();
      expect(outcome.success, isTrue);
      expect(adapter.fingerprint, executor.appliedStamp);
      expect(await executorFor(adapter).needsMigration(), isFalse);
    });
  });

  group('map-path reconciliation', () {
    test('renames, adds with defaults, and drops undeclared columns', () async {
      final adapter = _FingerprintMapAdapter([legacyRow('a', name: 'alpha'), legacyRow('b', name: 'beta')]);
      final outcome = await executorFor(adapter).execute();
      expect(outcome.success, isTrue);
      expect(outcome.applied, hasLength(3));
      for (final row in adapter.rows) {
        expect(row.containsKey('name'), isFalse);
        expect(row.containsKey('legacy'), isFalse);
        expect(row['priority'], 5);
      }
      expect(adapter.rows.map((r) => r['title']), ['alpha', 'beta']);
      expect(adapter.fingerprint, executorFor(adapter).appliedStamp);
    });

    test('keeps undeclared columns by default, surfacing warnings', () async {
      final adapter = _MapAdapter([legacyRow('a')]);
      final outcome = await executorFor(adapter, drop: false).execute();
      expect(outcome.success, isTrue);
      expect(adapter.rows.single.containsKey('legacy'), isTrue);
      expect(outcome.warnings.single, contains('"legacy"'));
    });

    test('enabling dropRemovedColumns later re-runs the pass; disabling later fast-paths', () async {
      final adapter = _FingerprintMapAdapter([legacyRow('a')]);
      expect((await executorFor(adapter, drop: false).execute()).success, isTrue);
      expect(adapter.rows.single.containsKey('legacy'), isTrue, reason: 'kept in keep-mode');

      // The policy is part of the stamp: flipping it invalidates the fast path once.
      final dropRun = await executorFor(adapter).execute();
      expect(dropRun.success, isTrue);
      expect(adapter.rows.single.containsKey('legacy'), isFalse);

      // Back to keep-mode: the drop stamp reconciled a superset — fast path holds.
      expect(await executorFor(adapter, drop: false).needsMigration(), isFalse);
    });

    test('a mid-write failure restores the snapshot and leaves no stamp', () async {
      final adapter = _FingerprintMapAdapter([legacyRow('a', name: 'alpha')])..failNextOverwrite = true;
      final outcome = await executorFor(adapter).execute();
      expect(outcome.success, isFalse);
      expect(outcome.error, isA<StateError>());
      expect(adapter.rows.single['name'], 'alpha', reason: 'rolled back');
      expect(adapter.fingerprint, isNull, reason: 'failure must not stamp');

      final retry = await executorFor(adapter).execute();
      expect(retry.success, isTrue);
      expect(adapter.rows.single['title'], 'alpha');
    });

    test('needsMigration reflects pending operations without a fingerprint store', () async {
      final dirty = _MapAdapter([legacyRow('a')]);
      expect(await executorFor(dirty).needsMigration(), isTrue);

      final clean = _MapAdapter([
        legacyRow('a')
          ..remove('name')
          ..remove('legacy')
          ..['title'] = 't'
          ..['priority'] = 1,
      ]);
      expect(await executorFor(clean).needsMigration(), isFalse);
    });
  });

  group('SQL-path reconciliation', () {
    test('emits rename, add, and drop DDL inside one transaction', () async {
      final adapter = _SqlAdapter(columns: [
        'id',
        'userId',
        'modifiedAt',
        'createdAt',
        'version',
        'isDeleted',
        'name',
        'legacy',
      ]);
      final outcome = await executorFor(adapter).execute();
      expect(outcome.success, isTrue);
      expect(adapter.ddl, [
        'ALTER TABLE "tasks" RENAME COLUMN "name" TO "title"',
        'ALTER TABLE "tasks" ADD COLUMN "priority" INTEGER DEFAULT 5',
        'ALTER TABLE "tasks" DROP COLUMN "legacy"',
      ]);
      expect(adapter.ddlRanInTransaction, isTrue);
    });

    test('a table already matching the declaration is a no-op', () async {
      final adapter = _SqlAdapter(columns: [
        'id',
        'userId',
        'modifiedAt',
        'createdAt',
        'version',
        'isDeleted',
        'title',
        'priority',
      ]);
      final outcome = await executorFor(adapter).execute();
      expect(outcome.success, isTrue);
      expect(adapter.ddl, isEmpty);
      expect(await executorFor(adapter).needsMigration(), isFalse);
    });
  });
}
