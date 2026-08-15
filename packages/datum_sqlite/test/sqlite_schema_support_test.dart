import 'package:datum/datum.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The runtime-schema support added to SqliteLocalAdapter: schema-derived
/// columns, strictColumns, fingerprint storage, and end-to-end
/// auto-migration against a real table.
void main() {
  late Database db;
  final logger = DatumLogger(enabled: false);

  DatumSchema<ConformanceEntity> schema() => DatumSchema<ConformanceEntity>(
    name: 'entities',
    fields: [
      ...datumCoreFieldSpecs<ConformanceEntity>().all,
      DatumFieldSpec<ConformanceEntity, String>('name', defaultValue: ''),
      DatumFieldSpec<ConformanceEntity, int>('value', defaultValue: 0),
    ],
  );

  setUp(() => db = sqlite3.openInMemory());
  tearDown(() => db.dispose());

  List<String> columnsOf(String table) => db
      .select('PRAGMA table_info("$table")')
      .map((r) => r['name'] as String)
      .toList();

  test(
    'schema-derived columns produce the same table as hand-written ones',
    () async {
      final byHand = SqliteLocalAdapter<ConformanceEntity>(
        database: db,
        table: 'by_hand',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT', 'value': 'INTEGER'},
      );
      final bySchema = SqliteLocalAdapter<ConformanceEntity>(
        database: db,
        table: 'by_schema',
        fromMap: ConformanceEntity.fromMap,
        schema: schema(),
      );
      await byHand.initialize();
      await bySchema.initialize();
      expect(columnsOf('by_schema'), columnsOf('by_hand'));

      await bySchema.create(ConformanceEntity.make('a', name: 'Ada', value: 3));
      final back = await bySchema.read('a', userId: 'conformance-user');
      expect(back?.name, 'Ada');
      expect(back?.value, 3);
    },
  );

  test('explicit columns win over a schema', () async {
    final adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'explicit_wins',
      fromMap: ConformanceEntity.fromMap,
      columns: const {'name': 'TEXT'},
      schema: schema(),
    );
    await adapter.initialize();
    expect(columnsOf('explicit_wins'), isNot(contains('value')));
  });

  group('strictColumns', () {
    test('true throws on undeclared write and patch keys', () async {
      final strict = SqliteLocalAdapter<ConformanceEntity>(
        database: db,
        table: 'strict',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT'}, // 'value' deliberately undeclared
        strictColumns: true,
      );
      await strict.initialize();
      await expectLater(
        strict.create(ConformanceEntity.make('a', name: 'Ada', value: 1)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('value'),
          ),
        ),
      );
      await expectLater(
        strict.patch(
          id: 'a',
          delta: const {'ghost': 1},
          userId: 'conformance-user',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('ghost'),
          ),
        ),
      );
    });

    test('false keeps the historical silent-drop behavior', () async {
      final lenient = SqliteLocalAdapter<ConformanceEntity>(
        database: db,
        table: 'lenient',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT'},
      );
      await lenient.initialize();
      await lenient.create(ConformanceEntity.make('a', name: 'Ada', value: 9));
      final back = await lenient.read('a', userId: 'conformance-user');
      expect(back?.name, 'Ada');
      expect(
        back?.value,
        isNot(9),
        reason: 'undeclared column was dropped, as before',
      );
    });
  });

  test('fingerprint round-trips through the meta table', () async {
    final adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'fp',
      fromMap: ConformanceEntity.fromMap,
      schema: schema(),
    );
    await adapter.initialize();
    expect(await adapter.getStoredSchemaFingerprint(), isNull);
    await adapter.setStoredSchemaFingerprint('abc123');
    expect(await adapter.getStoredSchemaFingerprint(), 'abc123');
  });

  test('auto-migration reconciles a legacy table with real DDL', () async {
    final legacy = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'entities',
      fromMap: ConformanceEntity.fromMap,
      columns: const {'name': 'TEXT', 'legacy': 'INTEGER'},
    );
    await legacy.initialize();
    await legacy.create(ConformanceEntity.make('a', name: 'Ada', value: 1));

    final declared = DatumSchema<ConformanceEntity>(
      name: 'entities',
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
    final adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'entities',
      fromMap: ConformanceEntity.fromMap,
      schema: declared,
    );
    await adapter.initialize();

    final executor = AutoMigrationExecutor<ConformanceEntity>(
      localAdapter: adapter,
      schema: declared,
      dropRemovedColumns: true,
      logger: logger,
    );
    expect(await executor.needsMigration(), isTrue);
    final outcome = await executor.execute();
    expect(outcome.success, isTrue, reason: '${outcome.error}');

    final cols = columnsOf('entities');
    expect(cols, containsAll(['title', 'score']));
    expect(cols, isNot(contains('name')));
    expect(cols, isNot(contains('legacy')));
    final row = db.select('SELECT title, score FROM entities').single;
    expect(row['title'], 'Ada', reason: 'the rename preserved the value');
    expect(row['score'], 5, reason: 'the add backfilled its default');

    expect(await adapter.getStoredSchemaFingerprint(), declared.fingerprint);
    expect(
      await executor.needsMigration(),
      isFalse,
      reason: 'fingerprint fast path',
    );
  });
}
