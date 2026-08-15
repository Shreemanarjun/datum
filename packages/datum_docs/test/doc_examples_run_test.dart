// Executes the documented examples for real and asserts every output the
// docs claim (the `// prints 3`-style comments), against real stores.
//
// tool/snippet_check.dart proves every fence COMPILES; this suite proves the
// critical ones BEHAVE as documented:
//   - guides/collaborative_editing.md — CRDT convergence claims
//   - guides/typed_schema.md          — typed queries, reader, derived
//     columns, the auto-migration journey, and the conformance example as-is
//   - guides/migrations.md            — the declarative chain as real DDL
//
// Run: dart test test/doc_examples_run_test.dart
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../tool/snippet_scaffold.dart';

// --- guides/typed_schema.md: the one declaration -----------------------------

abstract final class TaskFields {
  static final title = DatumFieldSpec<Task, String>('title', getter: (t) => t.title, defaultValue: '');
  static final priority = DatumFieldSpec<Task, int>('priority',
      getter: (t) => t.priority, defaultValue: 0, renamedFrom: 'prio');
  static final description = DatumFieldSpec<Task, String?>('description', getter: (t) => t.description);
}

final core = datumCoreFieldSpecs<Task>();

final taskSchema = DatumSchema<Task>(
  name: 'tasks',
  fields: [...core.all, TaskFields.title, TaskFields.priority, TaskFields.description],
);

/// The docs' cast-free `fromMap`, verbatim in structure.
Task taskFromMap(Map<String, dynamic> map) {
  final r = taskSchema.reader(map);
  return Task(
    id: r(core.id),
    userId: r(core.userId),
    title: r(TaskFields.title),
    priority: r.getOr(TaskFields.priority, 0),
    description: r(TaskFields.description),
    createdAt: r(core.createdAt),
    modifiedAt: r(core.modifiedAt),
    version: r(core.version),
    isDeleted: r.getOr(core.isDeleted, false),
  );
}

Map<String, dynamic> goodTaskMap() => {
      'id': 't1',
      'userId': 'u1',
      'title': 'documented',
      'priority': 3,
      'description': null,
      'isCompleted': false,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-01T00:00:00.000Z',
      'version': 1,
      'isDeleted': false,
    };

void main() {
  group('collaborative_editing.md claims, executed', () {
    test('counters merge to 3 in any order', () {
      var likesOnPhone = const PNCounter();
      var likesOnLaptop = const PNCounter();

      likesOnPhone = likesOnPhone.increment('phone');
      likesOnPhone = likesOnPhone.increment('phone');
      likesOnLaptop = likesOnLaptop.increment('laptop');

      expect(likesOnPhone.merge(likesOnLaptop).value, 3);
      expect(likesOnLaptop.merge(likesOnPhone).value, 3);
    });

    test('ORSet: a concurrent add survives a remove (add-wins)', () {
      var tagsA = const ORSet<String>();
      var tagsB = ORSet<String>.fromMap(tagsA.toMap(), (raw) => raw as String);

      tagsA = tagsA.add('urgent', 'a-1');
      tagsB = tagsB.add('urgent', 'b-1');
      tagsB = tagsB.remove('urgent');
      tagsA = tagsA.add('home', 'a-2');

      final merged = tagsA.merge(tagsB);
      expect(merged.value.contains('urgent'), isTrue);
      expect(merged.value.contains('home'), isTrue);
    });

    test('RgaText: "the big cat slept" from any merge order', () {
      var noteOnA = RgaText(replicaId: 'device-a');
      noteOnA = noteOnA.insert(0, 'the cat sat');

      var noteOnB = RgaText.fromMap(noteOnA.toMap(), replicaId: 'device-b');

      noteOnA = noteOnA.insert(4, 'big ');
      noteOnB = noteOnB.delete(8, 3);
      noteOnB = noteOnB.insert(8, 'slept');

      expect(noteOnA.merge(noteOnB).value, 'the big cat slept');
      expect(noteOnB.merge(noteOnA).value, 'the big cat slept');
    });

    test('character ids anchor cursors across edits (index 7)', () {
      var doc = RgaText(replicaId: 'editor');
      doc = doc.insert(0, 'hello');
      final anchor = doc.characterIdAt(4);
      doc = doc.insert(0, '>> ');
      expect(doc.indexOfCharacter(anchor), 7);
    });
  });

  group('typed_schema.md claims, executed', () {
    test('typed whereField queries equal the string path', () {
      final viaSpec = DatumQueryBuilder<Task>()
          .whereField(TaskFields.priority, isGreaterThan: 2)
          .orderByField(TaskFields.title, descending: true)
          .build();
      final viaStrings =
          DatumQueryBuilder<Task>().where('priority', isGreaterThan: 2).orderBy('title', descending: true).build();

      final specFilter = viaSpec.filters.single as Filter;
      final stringFilter = viaStrings.filters.single as Filter;
      expect(specFilter.field, stringFilter.field);
      expect(specFilter.operator, stringFilter.operator);
      expect(specFilter.value, stringFilter.value);
      expect(viaSpec.sorting.single.field, 'title');

      final open = TaskFields.priority.greaterThanOrEqual(3);
      expect(open.field, 'priority');
      expect(open.operator, FilterOperator.greaterThanOrEqual);
    });

    test('the reader decodes without casts and names failing fields', () {
      final task = taskFromMap(goodTaskMap());
      expect(task.title, 'documented');
      expect(task.priority, 3);
      expect(task.description, isNull);

      expect(
        () => taskFromMap(goodTaskMap()..['priority'] = 'high'),
        throwsA(isA<SchemaReadException>()
            .having((e) => e.entity, 'entity', 'tasks')
            .having((e) => e.fieldName, 'fieldName', 'priority')),
      );
      expect(
        () => taskFromMap(goodTaskMap()..remove('title')),
        throwsA(isA<SchemaReadException>().having((e) => e.message, 'message', contains('key missing'))),
      );
    });

    test('the documented auto-migration journey on a real SQLite table', () async {
      final db = sqlite.sqlite3.openInMemory();
      addTearDown(db.dispose);
      final logger = DatumLogger(enabled: false);

      // A legacy app version: `prio` (pre-rename) plus an orphaned column.
      final legacy = SqliteLocalAdapter<Task>(
        database: db,
        table: 'tasks',
        fromMap: Task.fromMap,
        columns: const {'title': 'TEXT', 'prio': 'INTEGER', 'stale': 'TEXT'},
      );
      await legacy.initialize();
      await legacy.overwriteAllRawData([
        {
          'id': 'a',
          'userId': 'u1',
          'title': 'keep me',
          'prio': 4,
          'stale': 'old',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'modifiedAt': '2026-01-01T00:00:00.000Z',
          'version': 1,
          'isDeleted': false,
        },
      ]);

      List<String> columns() => db.select('PRAGMA table_info("tasks")').map((r) => r['name'] as String).toList();

      // Claim: renames follow the hint, missing fields are added, undeclared
      // columns are kept and warned about by default.
      final kept = await AutoMigrationExecutor<Task>(
        localAdapter: legacy,
        schema: taskSchema,
        logger: logger,
      ).execute();
      expect(kept.success, isTrue, reason: '${kept.error}');
      expect(columns(), containsAll(['priority', 'description', 'stale']));
      expect(columns(), isNot(contains('prio')));
      expect(kept.warnings.single, contains('"stale"'));
      final row = db.select('SELECT title, priority FROM tasks').single;
      expect(row['title'], 'keep me');
      expect(row['priority'], 4, reason: 'the rename preserved the value');

      // Claim: destructive changes are opt-in.
      final dropped = await AutoMigrationExecutor<Task>(
        localAdapter: legacy,
        schema: taskSchema,
        dropRemovedColumns: true,
        logger: logger,
      ).execute();
      expect(dropped.success, isTrue);
      expect(columns(), isNot(contains('stale')));

      // Claim: the fingerprint makes unchanged launches skip the pass.
      expect(await legacy.getStoredSchemaFingerprint(), '${taskSchema.fingerprint}+drop');
      expect(
        await AutoMigrationExecutor<Task>(localAdapter: legacy, schema: taskSchema, dropRemovedColumns: true, logger: logger)
            .needsMigration(),
        isFalse,
      );

      // Claim: a non-nullable field without a default fails fast, touching nothing.
      final bad = DatumSchema<Task>(name: 'tasks', fields: [
        ...core.all,
        TaskFields.title,
        DatumFieldSpec<Task, String>('label'),
      ]);
      final failed = await AutoMigrationExecutor<Task>(localAdapter: legacy, schema: bad, logger: logger).execute();
      expect(failed.success, isFalse);
      expect(failed.error, isA<MigrationException>());
      expect('${failed.error}', contains('"label"'));
      expect(columns(), isNot(contains('label')));
    });

    test('strictColumns turns the silent drop into an error (docs §3)', () async {
      final db = sqlite.sqlite3.openInMemory();
      addTearDown(db.dispose);
      final strict = SqliteLocalAdapter<Task>(
        database: db,
        table: 'strict_tasks',
        fromMap: Task.fromMap,
        columns: const {'title': 'TEXT'},
        strictColumns: true,
      );
      await strict.initialize();
      await expectLater(
        strict.create(Task.fromMap(goodTaskMap())),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('priority'))),
      );
    });
  });

  group('migrations.md claims, executed', () {
    test('the declarative chain runs as real ALTER TABLE / UPDATE DDL (§4)', () async {
      final db = sqlite.sqlite3.openInMemory();
      addTearDown(db.dispose);
      final adapter = SqliteLocalAdapter<Task>(
        database: db,
        table: 'chain_tasks',
        fromMap: Task.fromMap,
        columns: const {'name': 'TEXT'},
      );
      await adapter.initialize();
      await adapter.overwriteAllRawData([
        {
          'id': 'a',
          'userId': 'u1',
          'name': 'renamed by DDL',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'modifiedAt': '2026-01-01T00:00:00.000Z',
          'version': 1,
          'isDeleted': false,
        },
      ]);

      final result = await SqlMigrationExecutor<Task>(
        localAdapter: adapter,
        table: 'chain_tasks',
        migrations: [
          SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
            ColumnOperation.rename('name', to: 'title'),
            ColumnOperation.add('priority', defaultValue: 0),
          ]),
        ],
        targetVersion: 1,
        logger: DatumLogger(enabled: false),
      ).execute();
      expect(result.success, isTrue, reason: '${result.migrationError}');
      final row = db.select('SELECT title, priority FROM chain_tasks').single;
      expect(row['title'], 'renamed by DDL');
      expect(row['priority'], 0);
      expect(await adapter.getStoredSchemaVersion(), 1);
    });
  });

  // guides/typed_schema.md "Certify your adapter" — the doc snippet, as-is.
  runAutoMigrationConformanceTests(
    name: 'SqliteLocalAdapter (docs example)',
    createLocal: () async {
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: sqlite.sqlite3.openInMemory(),
        table: 'entities',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT', 'legacy': 'INTEGER'},
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
