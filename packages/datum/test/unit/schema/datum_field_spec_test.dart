import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'schema_test_entity.dart';

void main() {
  group('DatumFieldSpec basics', () {
    test('exposes valueType and nullability derived from V', () {
      expect(SchemaTask.titleField.valueType, String);
      expect(SchemaTask.titleField.isNullable, isFalse);
      expect(SchemaTask.dueField.isNullable, isTrue);
    });

    test('encode/decode delegate to the codec', () {
      expect(SchemaTask.priorityField.encode(3), 3);
      expect(SchemaTask.priorityField.decode(3.0), 3);
    });

    test('decode wraps codec failures in SchemaReadException naming the field', () {
      expect(
        () => SchemaTask.priorityField.decode('oops'),
        throwsA(isA<SchemaReadException>().having((e) => e.fieldName, 'fieldName', 'priority').having((e) => e.expectedType, 'expectedType', int).having((e) => e.message, 'message', contains('String (oops)'))),
      );
    });

    test('decode rethrows SchemaReadException from nested specs unchanged', () {
      final inner = DatumFieldSpec<SchemaTask, int>('inner');
      final outer = DatumFieldSpec<SchemaTask, int>('outer', codec: DatumFieldCodec.jsonObject<int>((json) => inner.decode(json['v']), (v) => {'v': v}));
      expect(
        () => outer.decode({'v': 'bad'}),
        throwsA(isA<SchemaReadException>().having((e) => e.fieldName, 'fieldName', 'inner')),
      );
    });
  });

  group('resolveSqlType', () {
    test('derives from V for supported types', () {
      expect(DatumFieldSpec<SchemaTask, int>('a').resolveSqlType(), 'INTEGER');
      expect(DatumFieldSpec<SchemaTask, int?>('a').resolveSqlType(), 'INTEGER');
      expect(DatumFieldSpec<SchemaTask, double>('a').resolveSqlType(), 'REAL');
      expect(
        DatumFieldSpec<SchemaTask, double>('a').resolveSqlType(dialect: SqlDialect.postgresql),
        'DOUBLE PRECISION',
      );
      expect(DatumFieldSpec<SchemaTask, num>('a').resolveSqlType(), 'NUMERIC');
      expect(DatumFieldSpec<SchemaTask, bool>('a').resolveSqlType(), 'BOOLEAN');
      expect(DatumFieldSpec<SchemaTask, String>('a').resolveSqlType(), 'TEXT');
      expect(DatumFieldSpec<SchemaTask, DateTime?>('a', codec: DatumFieldCodec.dateTimeIso.nullable).resolveSqlType(), 'TEXT');
      expect(DatumFieldSpec<SchemaTask, Duration>('a', codec: DatumFieldCodec.durationMicros).resolveSqlType(), 'INTEGER');
      expect(DatumFieldSpec<SchemaTask, Uri>('a', codec: DatumFieldCodec.uri).resolveSqlType(), 'TEXT');
      expect(DatumFieldSpec<SchemaTask, BigInt>('a', codec: DatumFieldCodec.bigInt).resolveSqlType(), 'TEXT');
    });

    test('explicit sqlType wins', () {
      expect(DatumFieldSpec<SchemaTask, int>('a', sqlType: 'BIGINT').resolveSqlType(), 'BIGINT');
    });

    test('unsupported types demand an explicit sqlType', () {
      final spec = DatumFieldSpec<SchemaTask, SchemaPriority>('p', codec: DatumFieldCodec.enumByName(SchemaPriority.values));
      expect(
        () => spec.resolveSqlType(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('sqlType'))),
      );
      expect(
        DatumFieldSpec<SchemaTask, SchemaPriority>('p', codec: DatumFieldCodec.enumByName(SchemaPriority.values), sqlType: 'TEXT').resolveSqlType(),
        'TEXT',
      );
    });
  });

  group('query interop (spec IS-A DatumQueryField)', () {
    test('whereField/orderByField with a spec produce the identical query to the string path', () {
      final viaSpec = DatumQueryBuilder<SchemaTask>().whereField(SchemaTask.priorityField, isGreaterThan: 2).orderByField(SchemaTask.titleField, descending: true).build();
      final viaStrings = DatumQueryBuilder<SchemaTask>().where('priority', isGreaterThan: 2).orderBy('title', descending: true).build();
      final specFilter = viaSpec.filters.single as Filter;
      final stringFilter = viaStrings.filters.single as Filter;
      expect(specFilter.field, stringFilter.field);
      expect(specFilter.operator, stringFilter.operator);
      expect(specFilter.value, stringFilter.value);
      expect(viaSpec.sorting.single.field, viaStrings.sorting.single.field);
      expect(viaSpec.sorting.single.descending, viaStrings.sorting.single.descending);
    });

    test('inherited Filter helpers work on specs', () {
      final gte = SchemaTask.priorityField.greaterThanOrEqual(3);
      expect(gte.field, 'priority');
      expect(gte.operator, FilterOperator.greaterThanOrEqual);
      expect(gte.value, 3);
      final isNull = SchemaTask.dueField.isNull;
      expect(isNull.field, 'due');
      expect(isNull.operator, FilterOperator.isNull);
    });
  });

  group('datumCoreFieldSpecs', () {
    test('defaults to camelCase keys with getters and lenient dates', () {
      final core = datumCoreFieldSpecs<SchemaTask>();
      expect(core.all.map((f) => f.name), ['id', 'userId', 'modifiedAt', 'createdAt', 'version', 'isDeleted']);
      final task = makeSchemaTask();
      expect(core.id.getter!(task), 't1');
      expect(core.version.getter!(task), 1);
      expect(core.isDeleted.getter!(task), isFalse);
      expect(core.userId.getter!(task), 'u1');
      expect(core.modifiedAt.decode(task.modifiedAt.millisecondsSinceEpoch), task.modifiedAt.toLocal());
      expect(core.createdAt.getter!(task), task.createdAt);
    });

    test('keys and date codec are overridable', () {
      final core = datumCoreFieldSpecs<SchemaTask>(
        userId: 'user_id',
        modifiedAt: 'modified_at',
        createdAt: 'created_at',
        isDeleted: 'is_deleted',
        dateCodec: DatumFieldCodec.dateTimeEpochMillis,
      );
      expect(core.userId.name, 'user_id');
      expect(core.isDeleted.name, 'is_deleted');
      final task = makeSchemaTask();
      expect(core.modifiedAt.encode(task.modifiedAt), task.modifiedAt.millisecondsSinceEpoch);
    });
  });
}
