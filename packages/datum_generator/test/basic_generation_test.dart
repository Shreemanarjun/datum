import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _basicEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(tableName: 'test_entities', generateMixin: false)
class TestEntity extends DatumEntity {
  final String id;
  final String userId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int version;
  final bool isDeleted;

  final String name;
  final int age;

  @DatumField(name: 'custom_field')
  final String customField;

  final DateTime customDate;

  @DatumIgnore()
  final String ignoredField;

  const TestEntity({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    required this.isDeleted,
    required this.name,
    required this.age,
    required this.customField,
    required this.customDate,
    this.ignoredField = '',
  });
}
''';

void main() {
  group('basic generation', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_basicEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(result.output, isNotNull);
      output = result.output!;
    });

    test('generates extension with explicit table name', () {
      expect(output, contains(r'extension $TestEntityDatum on TestEntity'));
      expect(
        output,
        contains("static const String tableName = 'test_entities';"),
      );
    });

    test('generates datumToMap with snake_case keys and metadata handling', () {
      expect(
        output,
        contains(
          'Map<String, dynamic> datumToMap({MapTarget target = MapTarget.local})',
        ),
      );
      expect(output, contains("'id': id,"));
      expect(output, contains("'user_id': userId,"));
      expect(output, contains("'name': name,"));
      expect(output, contains("'age': age,"));
      // createdAt / modifiedAt handled specially (not inline in initial map).
      expect(output, isNot(contains("'created_at': createdAt,")));
      expect(
        output,
        contains("map['created_at'] = createdAt.toIso8601String();"),
      );
      expect(
        output,
        contains("map['modified_at'] = modifiedAt.millisecondsSinceEpoch;"),
      );
    });

    test('respects @DatumField custom name', () {
      expect(output, contains("'custom_field': customField,"));
    });

    test('DateTime fields serialize per target', () {
      expect(
        output,
        containsCode(
          "'custom_date': target == MapTarget.remote ? customDate.toIso8601String() : customDate.millisecondsSinceEpoch,",
        ),
      );
    });

    test('ignored field is excluded from serialization and fromMap', () {
      // DatumIgnore defaults: fromMap: true, toMap: true (but stays in
      // copyWith and equality).
      expect(output, isNot(contains("'ignored_field'"))); // not serialized
      expect(output, isNot(contains("map['ignoredField']"))); // not read back
      expect(
        output,
        contains('ignoredField: ignoredField ?? this.ignoredField'),
      );
      expect(output, contains('other.ignoredField == ignoredField'));
    });

    test('generates datumDiff excluding metadata fields', () {
      expect(
        output,
        containsCode(
          'Map<String, dynamic>? datumDiff(DatumEntityInterface oldVersion',
        ),
      );
      expect(output, contains('final old = oldVersion as TestEntity;'));
      expect(output, contains('if (name != old.name)'));
      expect(output, isNot(contains('if (id != old.id)')));
      expect(
        output,
        contains("changes['modified_at'] = modifiedAt.toIso8601String();"),
      );
      expect(output, contains("changes['version'] = version;"));
      expect(output, contains('return changes.isEmpty ? null : changes;'));
    });

    test('generates copyWith delegating to copyWithAll', () {
      expect(output, contains('TestEntity copyWith({'));
      expect(output, contains('return copyWithAll('));
    });

    test('generates copyWithAll with automatic version increment', () {
      expect(output, contains('TestEntity copyWithAll({'));
      expect(
        output,
        contains(
          'version: version ?? (hasChanges ? this.version + 1 : this.version),',
        ),
      );
      expect(output, contains('name: name ?? this.name,'));
    });

    test('generates equality helpers', () {
      expect(output, contains('bool datumEquals(TestEntity other)'));
      expect(output, contains('if (identical(this, other)) return true;'));
      expect(output, contains('other.name == name'));
      expect(output, contains('int get datumHashCode'));
      expect(output, contains('name.hashCode'));
    });

    test('generates fromMap with default value coercion (non-strict)', () {
      expect(
        output,
        contains(r'TestEntity _$TestEntityFromMap(Map<String, dynamic> map)'),
      );
      expect(
        output,
        contains("name: (map['name'] ?? map['name'] ?? '') as String,"),
      );
      expect(output, contains("age: (map['age'] ?? map['age'] ?? 0) as int,"));
      expect(
        output,
        contains(
          "isDeleted: (map['is_deleted'] ?? map['isDeleted'] ?? false) as bool,",
        ),
      );
      expect(
        output,
        contains(
          "customField: (map['custom_field'] ?? map['customField'] ?? '') as String,",
        ),
      );
      expect(output, contains('_testEntityParseDate('));
      expect(output, contains('DateTime _testEntityParseDate(dynamic value)'));
    });

    test('does not generate mixin when generateMixin is false', () {
      expect(output, isNot(contains(r'mixin _$TestEntityMixin')));
      expect(output, isNot(contains('extension TestEntityFactory')));
    });

    test('generates type-safe query builder', () {
      expect(
        output,
        contains('extension TestEntityQuery on DatumQueryBuilder<TestEntity>'),
      );
      expect(output, contains('DatumQueryBuilder<TestEntity> whereName({'));
      expect(output, contains('DatumQueryBuilder<TestEntity> whereAge({'));
      expect(
        output,
        contains(
          'DatumQueryBuilder<TestEntity> orderByName({bool descending = false})',
        ),
      );
      // String-only operators:
      expect(output, contains('String? containsIgnoreCase,'));
      // Numeric-only operators:
      expect(output, contains('int? isGreaterThan,'));
      expect(output, contains('List<int>? between,'));
    });

    test('bool query has no orderBy or between', () {
      expect(
        output,
        contains('DatumQueryBuilder<TestEntity> whereIsDeleted({'),
      );
      expect(output, isNot(contains('orderByIsDeleted')));
      expect(output, isNot(contains('List<bool>? between,')));
      expect(output, isNot(contains('List<bool>? isIn,')));
    });
  });

  group('default table name', () {
    test(
      'falls back to snake_case class name when tableName omitted',
      () async {
        final result = await generate('''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class MyHttpEntityV2 extends DatumEntity {
  final String name;
  const MyHttpEntityV2({required this.name});
}
''');
        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        expect(
          result.output,
          contains("static const String tableName = 'my_http_entity_v2';"),
        );
      },
    );

    test('generateMixin false produces no mixin for minimal entity', () async {
      final result = await generate('''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Simple extends DatumEntity {
  final String name;
  const Simple({required this.name});
}
''');
      expect(result.succeeded, isTrue);
      expect(result.output, isNot(contains(r'mixin _$SimpleMixin')));
    });
  });
}
