import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';

part 'generator_test.g.dart';

@DatumSerializable(tableName: 'test_entities')
class TestEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
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

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return datumToMap(target: target);
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    return datumDiff(oldVersion);
  }

  factory TestEntity.fromMap(Map<String, dynamic> map) {
    return _$TestEntityFromMap(map);
  }
}

// Since extensions can't add factories, we'll use top-level generated helpers or
// the user will call them. Our generator produces _$TestEntityFromMap.
void main() {}
