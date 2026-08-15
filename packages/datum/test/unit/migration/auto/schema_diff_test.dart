import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../../schema/schema_test_entity.dart';

SchemaShape shape({required Set<String> all, Set<String>? universal, int rows = 3}) => (allKeys: all, universalKeys: universal ?? all, rowCount: rows);

DatumSchema<SchemaTask> schemaOf(List<DatumFieldSpec<SchemaTask, dynamic>> payload) => DatumSchema<SchemaTask>(name: 'tasks', fields: [...SchemaTask.core.all, ...payload]);

const coreKeys = {'id', 'userId', 'modifiedAt', 'createdAt', 'version', 'isDeleted'};

void main() {
  group('additions', () {
    test('a clean store produces no changes, operations, or warnings', () {
      final schema = schemaOf([DatumFieldSpec<SchemaTask, String>('title', defaultValue: '')]);
      final result = diffSchema(
        schema: schema,
        actual: shape(all: {...coreKeys, 'title'}),
        dropRemovedColumns: false,
        sqlPath: true,
      );
      expect(result.changes, isEmpty);
      expect(result.operations, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('missing fields become AddColumn with encoded default / null for nullable', () {
      final due = DatumFieldSpec<SchemaTask, DateTime?>('due', codec: DatumFieldCodec.dateTimeIso.nullable);
      final priority = DatumFieldSpec<SchemaTask, int>('priority', defaultValue: 2);
      final result = diffSchema(
        schema: schemaOf([priority, due]),
        actual: shape(all: coreKeys),
        dropRemovedColumns: false,
        sqlPath: true,
      );
      expect(result.changes.whereType<SchemaColumnAdded>().map((c) => c.field.name), ['priority', 'due']);
      final addPriority = result.operations.whereType<AddColumn>().firstWhere((op) => op.name == 'priority');
      expect(addPriority.defaultValue, 2);
      expect(addPriority.sqlType, 'INTEGER');
      final addDue = result.operations.whereType<AddColumn>().firstWhere((op) => op.name == 'due');
      expect(addDue.defaultValue, isNull);
      expect(addDue.sqlType, 'TEXT');
    });

    test('a key present on only some rows is backfilled on the map path', () {
      final priority = DatumFieldSpec<SchemaTask, int>('priority', defaultValue: 0);
      final result = diffSchema(
        schema: schemaOf([priority]),
        actual: shape(all: {...coreKeys, 'priority'}, universal: coreKeys),
        dropRemovedColumns: false,
        sqlPath: false,
      );
      expect(result.changes.single, isA<SchemaColumnAdded>());
      expect(result.operations.single, isA<AddColumn>());
    });

    test('non-nullable fields without defaults fail fast, listing every offender', () {
      expect(
        () => diffSchema(
          schema: schemaOf([
            DatumFieldSpec<SchemaTask, String>('title'),
            DatumFieldSpec<SchemaTask, int>('priority'),
          ]),
          actual: shape(all: coreKeys),
          dropRemovedColumns: false,
          sqlPath: true,
        ),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('"title"')).having((e) => e.message, 'message', contains('"priority"'))),
      );
    });
  });

  group('renames', () {
    final titled = DatumFieldSpec<SchemaTask, String>('title', renamedFrom: 'name', defaultValue: '');

    test('renamedFrom hint produces a SchemaRenameOperation instead of drop + add', () {
      final result = diffSchema(
        schema: schemaOf([titled]),
        actual: shape(all: {...coreKeys, 'name'}),
        dropRemovedColumns: true,
        sqlPath: true,
      );
      final change = result.changes.single as SchemaColumnRenamed;
      expect(change.from, 'name');
      expect(change.field.name, 'title');
      expect(result.operations.single, isA<SchemaRenameOperation>());
      expect(result.changes.whereType<SchemaColumnRemoved>(), isEmpty, reason: 'the old column is renamed away, not removed');
    });

    test('SQL path with both columns present leaves the old one as an undeclared leftover', () {
      final result = diffSchema(
        schema: schemaOf([titled]),
        actual: shape(all: {...coreKeys, 'name', 'title'}),
        dropRemovedColumns: false,
        sqlPath: true,
      );
      expect(result.operations, isEmpty, reason: 'the declared column already exists; no rename possible');
      expect(result.warnings.single, contains('"name" is not in the "tasks" schema'));
    });

    test('map path with a partially-renamed store still emits the row-safe rename', () {
      final result = diffSchema(
        schema: schemaOf([titled]),
        actual: shape(all: {...coreKeys, 'name', 'title'}, universal: coreKeys),
        dropRemovedColumns: false,
        sqlPath: false,
      );
      expect(result.operations.single, isA<SchemaRenameOperation>());
    });

    test('renames come before adds and removes in operation order', () {
      final result = diffSchema(
        schema: schemaOf([titled, DatumFieldSpec<SchemaTask, int>('priority', defaultValue: 0)]),
        actual: shape(all: {...coreKeys, 'name', 'legacy'}),
        dropRemovedColumns: true,
        sqlPath: true,
      );
      expect(result.operations.map((op) => op.runtimeType), [SchemaRenameOperation, AddColumn, RemoveColumn]);
    });
  });

  group('removals', () {
    test('undeclared columns are kept with a warning by default', () {
      final result = diffSchema(
        schema: schemaOf([]),
        actual: shape(all: {...coreKeys, 'legacy'}),
        dropRemovedColumns: false,
        sqlPath: true,
      );
      expect(result.operations, isEmpty);
      expect(result.warnings.single, contains('"legacy"'));
    });

    test('opt-in drop removes undeclared columns but never core or __-prefixed ones', () {
      final result = diffSchema(
        schema: schemaOf([]),
        actual: shape(all: {...coreKeys, 'legacy', '__typename'}),
        dropRemovedColumns: true,
        sqlPath: true,
      );
      expect(result.changes.single, isA<SchemaColumnRemoved>());
      expect((result.operations.single as RemoveColumn).name, 'legacy');
    });
  });

  group('SchemaRenameOperation', () {
    final op = SchemaRenameOperation('name', to: 'title');

    test('moves the value when only the old key exists', () {
      expect(op.apply({'name': 'x'}), {'title': 'x'});
    });

    test('is a no-op when the old key is absent', () {
      expect(op.apply({'title': 'kept'}), {'title': 'kept'});
    });

    test('prefers the newer value when both keys exist', () {
      expect(op.apply({'name': 'old', 'title': 'new'}), {'title': 'new'});
    });

    test('emits quoted RENAME COLUMN DDL', () {
      expect(
        SchemaRenameOperation('na"me', to: 'title').toSqlStatements('ta"ble', SqlDialect.sqlite),
        ['ALTER TABLE "ta""ble" RENAME COLUMN "na""me" TO "title"'],
      );
    });
  });
}
