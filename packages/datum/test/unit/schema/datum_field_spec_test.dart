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

  group('query interop — full builder surface', () {
    // Normalizes list values: the typed path reifies List<V> where the
    // string path holds List<dynamic> — identical contents, different
    // runtime types, and record equality would see them as different.
    List<(String, FilterOperator, Object?)> shape(DatumQuery q) => [
          for (final f in q.filters.whereType<Filter>()) (f.field, f.operator, f.value is List ? List<Object?>.of(f.value as List).toString() : f.value),
        ];

    test('every whereField parameter delegates identically to the string path', () {
      final typed = DatumQueryBuilder<SchemaTask>()
          .whereField(SchemaTask.priorityField, isEqualTo: 1, isNotEqualTo: 2, isGreaterThan: 3, isGreaterThanOrEqualTo: 4, isLessThan: 5, isLessThanOrEqualTo: 6, isIn: [7, 8], isNotIn: [9], between: [10, 11])
          .whereField(SchemaTask.titleField, contains: 'a', containsIgnoreCase: 'B', startsWith: 'c', endsWith: 'd', matches: r'^e$')
          .build();
      final stringly = DatumQueryBuilder<SchemaTask>()
          .where('priority', isEqualTo: 1, isNotEqualTo: 2, isGreaterThan: 3, isGreaterThanOrEqualTo: 4, isLessThan: 5, isLessThanOrEqualTo: 6, isIn: [7, 8], isNotIn: [9], between: [10, 11])
          .where('title', contains: 'a', containsIgnoreCase: 'B', startsWith: 'c', endsWith: 'd', matches: r'^e$')
          .build();
      expect(shape(typed), shape(stringly));
      expect(shape(typed), hasLength(14));
    });

    test('whereFieldNull / whereFieldNotNull and orderByField nullSortOrder delegate', () {
      final typed = DatumQueryBuilder<SchemaTask>().whereFieldNull(SchemaTask.dueField).whereFieldNotNull(SchemaTask.titleField).orderByField(SchemaTask.dueField, descending: true, nullSortOrder: NullSortOrder.first).build();
      expect(shape(typed), [
        ('due', FilterOperator.isNull, null),
        ('title', FilterOperator.isNotNull, null),
      ]);
      final sort = typed.sorting.single;
      expect(sort.field, 'due');
      expect(sort.descending, isTrue);
      expect(sort.nullSortOrder, NullSortOrder.first);
    });

    test('remaining Filter helpers on specs cover the operator set', () {
      expect(SchemaTask.priorityField.equalTo(1).operator, FilterOperator.equals);
      expect(SchemaTask.priorityField.notEqualTo(1).operator, FilterOperator.notEquals);
      expect(SchemaTask.priorityField.greaterThan(1).operator, FilterOperator.greaterThan);
      expect(SchemaTask.priorityField.lessThan(1).operator, FilterOperator.lessThan);
      expect(SchemaTask.priorityField.lessThanOrEqual(1).operator, FilterOperator.lessThanOrEqual);
      expect(SchemaTask.priorityField.isIn([1, 2]).operator, FilterOperator.isIn);
      expect(SchemaTask.priorityField.isNotIn([1]).operator, FilterOperator.isNotIn);
      expect(SchemaTask.dueField.isNotNull.operator, FilterOperator.isNotNull);
    });
  });

  group('coreRole', () {
    test('core specs carry their role; payload specs carry none', () {
      final core = datumCoreFieldSpecs<SchemaTask>();
      expect(core.id.coreRole, DatumCoreRole.id);
      expect(core.userId.coreRole, DatumCoreRole.userId);
      expect(core.modifiedAt.coreRole, DatumCoreRole.modifiedAt);
      expect(core.createdAt.coreRole, DatumCoreRole.createdAt);
      expect(core.version.coreRole, DatumCoreRole.version);
      expect(core.isDeleted.coreRole, DatumCoreRole.isDeleted);
      expect(SchemaTask.titleField.coreRole, isNull);
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
