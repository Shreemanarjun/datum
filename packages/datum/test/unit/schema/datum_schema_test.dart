import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'schema_test_entity.dart';

Map<String, dynamic> rawTask({int? priority = 2, Object? due}) => {
      'id': 't1',
      'userId': 'u1',
      'title': 'hello',
      if (priority != null) 'priority': priority,
      if (due != null) 'due': due,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-01T00:00:00.000Z',
      'version': 1,
      'isDeleted': false,
    };

void main() {
  group('declaration validation (fail-fast, all problems listed)', () {
    test('duplicate field names are rejected', () {
      expect(
        () => DatumSchema<SchemaTask>(name: 's', fields: [
          DatumFieldSpec<SchemaTask, String>('title'),
          DatumFieldSpec<SchemaTask, String>('title'),
        ]),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('more than once'))),
      );
    });

    test('renamedFrom self-reference and collisions are rejected together', () {
      expect(
        () => DatumSchema<SchemaTask>(name: 's', fields: [
          DatumFieldSpec<SchemaTask, String>('a', renamedFrom: 'a'),
          DatumFieldSpec<SchemaTask, String>('b', renamedFrom: 'c'),
          DatumFieldSpec<SchemaTask, String>('c'),
        ]),
        throwsA(isA<MigrationException>().having((e) => e.message, 'message', contains('pointing at itself')).having((e) => e.message, 'message', contains('still a declared field'))),
      );
    });
  });

  group('reader / decode', () {
    test('decode builds the entity through construct', () {
      final task = SchemaTask.schema.decode(rawTask(due: '2026-02-01T00:00:00.000Z'));
      expect(task.id, 't1');
      expect(task.title, 'hello');
      expect(task.priority, 2);
      expect(task.due, DateTime.utc(2026, 2));
      expect(task.version, 1);
    });

    test('getOr falls back when key absent; maybe returns null', () {
      final task = SchemaTask.schema.decode(rawTask(priority: null));
      expect(task.priority, 0);
      expect(task.due, isNull);
    });

    test('missing non-nullable key names entity, field, and reason', () {
      final map = rawTask()..remove('title');
      expect(
        () => SchemaTask.schema.decode(map),
        throwsA(isA<SchemaReadException>().having((e) => e.entity, 'entity', 'schema_tasks').having((e) => e.fieldName, 'fieldName', 'title').having((e) => e.message, 'message', contains('key missing'))),
      );
    });

    test('null for a non-nullable field is distinguished from a missing key', () {
      final map = rawTask()..['title'] = null;
      expect(
        () => SchemaTask.schema.reader(map).get(SchemaTask.titleField),
        throwsA(isA<SchemaReadException>().having((e) => e.message, 'message', contains('value is null'))),
      );
    });

    test('decode failures carry the entity name', () {
      final map = rawTask()..['priority'] = 'high';
      expect(
        () => SchemaTask.schema.decode(map),
        throwsA(isA<SchemaReadException>().having((e) => e.entity, 'entity', 'schema_tasks').having((e) => e.fieldName, 'fieldName', 'priority')),
      );
    });

    test('decode without construct gives guidance', () {
      final schema = DatumSchema<SchemaTask>(name: 'no_ctor', fields: [SchemaTask.core.id]);
      expect(
        () => schema.decode(rawTask()),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('construct'))),
      );
    });

    test('reader exposes the raw map and call shorthand', () {
      final reader = SchemaTask.schema.reader(rawTask());
      expect(reader.raw['title'], 'hello');
      expect(reader(SchemaTask.titleField), 'hello');
      expect(reader.maybe(SchemaTask.priorityField), 2);
      expect(SchemaTask.schema.reader(rawTask(priority: null)).maybe(SchemaTask.priorityField), isNull);
    });
  });

  group('toMap', () {
    test('round-trips through decode', () {
      final task = makeSchemaTask(title: 'round', priority: 5, due: DateTime.utc(2026, 6));
      final map = SchemaTask.schema.toMap(task);
      expect(map['title'], 'round');
      expect(map['due'], '2026-06-01T00:00:00.000Z');
      final back = SchemaTask.schema.decode(map);
      expect(back, task);
    });

    test('requires a getter on every field', () {
      final schema = DatumSchema<SchemaTask>(name: 'no_getter', fields: [
        DatumFieldSpec<SchemaTask, String>('title'),
      ]);
      expect(
        () => schema.toMap(makeSchemaTask()),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('"title" has none'))),
      );
    });
  });

  group('diffOf / propsOf', () {
    test('diffOf returns null when nothing changed', () {
      final task = makeSchemaTask(title: 'same', priority: 1);
      expect(SchemaTask.schema.diffOf(task, task), isNull);
    });

    test('diffOf emits only changed payload fields plus modifiedAt/version', () {
      final before = makeSchemaTask(title: 'old', priority: 1);
      final after = SchemaTask(
        id: before.id,
        userId: before.userId,
        title: 'new',
        priority: 1,
        createdAt: before.createdAt,
        modifiedAt: DateTime.utc(2026, 5),
        version: 2,
      );
      final delta = SchemaTask.schema.diffOf(before, after)!;
      expect(delta['title'], 'new');
      expect(delta.containsKey('priority'), isFalse, reason: 'unchanged fields stay out');
      expect(delta.containsKey('id'), isFalse, reason: 'core fields are never payload');
      expect(delta['modifiedAt'], '2026-05-01T00:00:00.000Z');
      expect(delta['version'], 2);
    });

    test('diffOf compares through codecs (DateTime payload)', () {
      final before = makeSchemaTask(due: DateTime.utc(2026, 1));
      final after = SchemaTask(
        id: before.id,
        userId: before.userId,
        title: before.title,
        due: DateTime.utc(2026, 2),
        createdAt: before.createdAt,
        modifiedAt: before.modifiedAt,
        version: before.version,
      );
      expect(SchemaTask.schema.diffOf(before, after)!['due'], '2026-02-01T00:00:00.000Z');
    });

    test('propsOf returns payload values only, in declaration order', () {
      final task = makeSchemaTask(title: 'p', priority: 9);
      expect(SchemaTask.schema.propsOf(task), ['p', 9, null]);
    });
  });

  group('validate', () {
    test('reports missing keys, nulls, and undecodable values; passes clean maps', () {
      expect(SchemaTask.schema.validate(rawTask()), isEmpty);
      final broken = rawTask()
        ..remove('title')
        ..['version'] = null
        ..['priority'] = 'high';
      final violations = SchemaTask.schema.validate(broken);
      expect(violations.map((v) => v.field), containsAll(['title', 'version', 'priority']));
      expect(violations.firstWhere((v) => v.field == 'title').message, contains('missing key'));
      expect(violations.firstWhere((v) => v.field == 'version').message, contains('null for non-nullable'));
    });
  });

  group('sqlColumns / fieldByName', () {
    test('derives a column per field', () {
      final columns = SchemaTask.schema.sqlColumns();
      expect(columns['title'], 'TEXT');
      expect(columns['priority'], 'INTEGER');
      expect(columns['isDeleted'], 'BOOLEAN');
      expect(columns['due'], 'TEXT');
      expect(columns.length, SchemaTask.schema.fields.length);
    });

    test('fieldByName finds declared fields only', () {
      expect(SchemaTask.schema.fieldByName('title'), same(SchemaTask.titleField));
      expect(SchemaTask.schema.fieldByName('ghost'), isNull);
    });
  });

  group('fingerprint', () {
    List<DatumFieldSpec<SchemaTask, dynamic>> baseFields() => [
          DatumFieldSpec<SchemaTask, String>('title'),
          DatumFieldSpec<SchemaTask, int>('priority'),
        ];

    test('is stable and field-order independent', () {
      final a = DatumSchema<SchemaTask>(name: 's', fields: baseFields());
      final b = DatumSchema<SchemaTask>(name: 's', fields: baseFields().reversed.toList());
      expect(a.fingerprint, b.fingerprint);
      expect(a.fingerprint, DatumSchema<SchemaTask>(name: 's', fields: baseFields()).fingerprint);
    });

    test('changes when a field is added, retyped, renamed-from, or given a default', () {
      final base = DatumSchema<SchemaTask>(name: 's', fields: baseFields()).fingerprint;
      expect(
        DatumSchema<SchemaTask>(name: 's', fields: [...baseFields(), DatumFieldSpec<SchemaTask, bool>('done')]).fingerprint,
        isNot(base),
      );
      expect(
        DatumSchema<SchemaTask>(name: 's', fields: [
          DatumFieldSpec<SchemaTask, String?>('title'),
          DatumFieldSpec<SchemaTask, int>('priority'),
        ]).fingerprint,
        isNot(base),
      );
      expect(
        DatumSchema<SchemaTask>(name: 's', fields: [
          DatumFieldSpec<SchemaTask, String>('title', renamedFrom: 'name'),
          DatumFieldSpec<SchemaTask, int>('priority'),
        ]).fingerprint,
        isNot(base),
      );
      expect(
        DatumSchema<SchemaTask>(name: 's', fields: [
          DatumFieldSpec<SchemaTask, String>('title'),
          DatumFieldSpec<SchemaTask, int>('priority', defaultValue: 0),
        ]).fingerprint,
        isNot(base),
      );
    });
  });
}
