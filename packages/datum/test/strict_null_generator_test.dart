import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';
import 'package:test/test.dart';

part 'strict_null_generator_test.g.dart';

@DatumSerializable(tableName: 'strict_entities', generateMixin: false, strictNullChecks: true)
class StrictEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final int count;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const StrictEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.count,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => datumToMap(target: target);
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => datumDiff(oldVersion);
  factory StrictEntity.fromMap(Map<String, dynamic> map) => _$StrictEntityFromMap(map);
}

@DatumSerializable(tableName: 'lenient_entities', generateMixin: false)
class LenientEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const LenientEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => datumToMap(target: target);
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => datumDiff(oldVersion);
  factory LenientEntity.fromMap(Map<String, dynamic> map) => _$LenientEntityFromMap(map);
}

Map<String, dynamic> _base() => {
      'id': 'e1',
      'user_id': 'u1',
      'name': 'hello',
      'count': 5,
      'created_at': DateTime(2024).millisecondsSinceEpoch,
      'modified_at': DateTime(2024).millisecondsSinceEpoch,
      'version': 1,
      'is_deleted': false,
    };

void main() {
  test('#29 strictNullChecks: valid map round-trips', () {
    final e = StrictEntity.fromMap(_base());
    expect(e.name, 'hello');
    expect(e.count, 5);
  });

  test('#29 strictNullChecks: null for a non-nullable field throws (not silently defaulted)', () {
    final bad = _base()..['name'] = null;
    expect(() => StrictEntity.fromMap(bad), throwsA(anything));

    final badInt = _base()..['count'] = null;
    expect(() => StrictEntity.fromMap(badInt), throwsA(anything));
  });

  test('#29 default (lenient) still substitutes primitive defaults', () {
    final missingName = _base()..remove('name');
    final e = LenientEntity.fromMap(missingName);
    expect(e.name, '', reason: 'lenient mode keeps the silent default');
  });
}
