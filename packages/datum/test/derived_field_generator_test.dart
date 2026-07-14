import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';
import 'package:test/test.dart';

part 'derived_field_generator_test.g.dart';

/// Entity where `userId` is NOT a constructor parameter — it is derived from
/// `id` in the initializer list. Regression fixture for issue #26: generated
/// `copyWithAll` / `fromMap` must not pass `userId` to the constructor.
@DatumSerializable(tableName: 'derived_users', generateMixin: false)
class DerivedUser extends DatumEntity {
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

  const DerivedUser({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id; // derived — not a constructor parameter

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => datumToMap(target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => datumDiff(oldVersion);

  factory DerivedUser.fromMap(Map<String, dynamic> map) => _$DerivedUserFromMap(map);
}

void main() {
  test('#26 copyWithAll/fromMap ignore non-constructor fields (userId derived)', () {
    final u = DerivedUser(id: 'u1', name: 'Alice', modifiedAt: DateTime(2024), createdAt: DateTime(2024));
    expect(u.userId, 'u1');

    // copyWithAll compiles (does not expose/pass `userId`); changing `id`
    // re-derives userId via the constructor.
    final copied = u.copyWithAll(id: 'u2', name: 'Bob');
    expect(copied.id, 'u2');
    expect(copied.userId, 'u2');
    expect(copied.name, 'Bob');

    // fromMap round-trips through the constructor without passing userId.
    final back = DerivedUser.fromMap(u.toDatumMap());
    expect(back.id, 'u1');
    expect(back.userId, 'u1');
    expect(back.name, 'Alice');
  });
}
