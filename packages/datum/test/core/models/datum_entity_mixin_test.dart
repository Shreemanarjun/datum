import 'package:datum/source/core/models/datum_entity.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

class TestEntity extends Equatable with DatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TestEntity({
    required this.id,
    required this.userId,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  // No diff/props overrides: exercises the mixin defaults.
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'modifiedAt': modifiedAt,
        'createdAt': createdAt,
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  bool? get stringify => true;
}

void main() {
  group('DatumEntityMixin', () {
    final now = DateTime(2023, 1, 1, 12, 0, 0);
    final entity1 = TestEntity(
      id: '1',
      userId: 'user1',
      modifiedAt: now,
      createdAt: now,
      version: 1,
    );

    group('Equality and Props', () {
      test('props are correctly provided', () {
        expect(entity1.props, [
          {'id': '1', 'userId': 'user1', 'modifiedAt': now, 'createdAt': now, 'version': 1, 'isDeleted': false},
          null, // vectorClock
        ]);
      });

      test('entities with same props have same props list', () {
        final entity2 = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(entity1.props, equals(entity2.props));
      });

      test('entities with different id have different props', () {
        final entity2 = TestEntity(
          id: '2',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(entity1.props, isNot(equals(entity2.props)));
      });

      test('entities with different userId have different props', () {
        final entity2 = TestEntity(
          id: '1',
          userId: 'user2',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(entity1.props, isNot(equals(entity2.props)));
      });

      test('entities with different modifiedAt have different props', () {
        final entity2 = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now.add(const Duration(seconds: 1)),
          createdAt: now,
          version: 1,
        );
        expect(entity1.props, isNot(equals(entity2.props)));
      });

      test('entities with different createdAt have different props', () {
        final entity2 = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now.add(const Duration(seconds: 1)),
          version: 1,
        );
        expect(entity1.props, isNot(equals(entity2.props)));
      });

      test('entities with different version have different props', () {
        final entity2 = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 2,
        );
        expect(entity1.props, isNot(equals(entity2.props)));
      });

      test('entities with different isDeleted have different props', () {
        final entity2 = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
          isDeleted: true,
        );
        expect(entity1.props, isNot(equals(entity2.props)));
      });
    });

    group('Hash Code', () {
      test('entities with same props have same hashCode', () {
        final entityA = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        final entityB = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(entityA.hashCode, equals(entityB.hashCode));
      });

      test('entities with different props have different hashCode', () {
        final entityA = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        final entityB = TestEntity(
          id: '2',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(entityA.hashCode, isNot(equals(entityB.hashCode)));
      });

      test('hashCode is consistent across multiple calls', () {
        final hash1 = entity1.hashCode;
        final hash2 = entity1.hashCode;
        expect(hash1, equals(hash2));
      });
    });

    group('String Representation', () {
      test('toString returns instance description', () {
        final stringRep = entity1.toString();
        expect(stringRep, contains('TestEntity'));
        expect(stringRep, isNotNull);
      });
    });

    group('default diff (hand-written entities, no generator)', () {
      test('null when identical, changed keys only otherwise', () {
        final later = DateTime(2024);
        final copy = TestEntity(id: '1', userId: 'user1', modifiedAt: now, createdAt: now, version: 1);
        final edited = TestEntity(id: '1', userId: 'user1', modifiedAt: later, createdAt: now, version: 2, isDeleted: true);
        expect(entity1.diff(copy), isNull);
        expect(edited.diff(entity1), {'modifiedAt': later, 'version': 2, 'isDeleted': true});
        expect(entity1.diff(edited), {'modifiedAt': now, 'version': 1, 'isDeleted': false});
        expect(edited, isNot(equals(entity1)));
        expect(copy, equals(entity1));
        expect(copy.hashCode, entity1.hashCode);
      });
    });

    group('isRelational', () {
      test('returns false for non-relational entities', () {
        expect(entity1.isRelational, isFalse);
      });
    });

    group('Edge Cases', () {
      test('handles entities with extreme version numbers', () {
        final entityWithMaxVersion = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 2147483647, // Max int32
        );

        final entityWithMinVersion = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 0,
        );

        expect((entityWithMaxVersion.props.first! as Map)['version'], equals(2147483647));
        expect((entityWithMinVersion.props.first! as Map)['version'], equals(0));
        expect(entityWithMaxVersion.hashCode, isNot(equals(entityWithMinVersion.hashCode)));
      });

      test('handles entities with future and past dates', () {
        final pastDate = DateTime(2000, 1, 1);
        final futureDate = DateTime(2050, 12, 31);

        final entityPast = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: pastDate,
          version: 1,
        );

        final entityFuture = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: futureDate,
          version: 1,
        );

        expect((entityPast.props.first! as Map)['createdAt'], equals(pastDate));
        expect((entityFuture.props.first! as Map)['createdAt'], equals(futureDate));
        expect(entityPast.hashCode, isNot(equals(entityFuture.hashCode)));
      });

      test('vectorClock is null by default in props', () {
        expect(entity1.props.last, isNull);
      });

      test('handles entities with UTC and local timezones', () {
        final utcTime = DateTime.utc(2023, 1, 1, 12, 0, 0);
        final localTime = DateTime(2023, 1, 1, 12, 0, 0);

        final entityUtc = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: utcTime,
          createdAt: now,
          version: 1,
        );

        final entityLocal = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: localTime,
          createdAt: now,
          version: 1,
        );

        // Different timezone representations should result in different props.
        // DateTime.== distinguishes UTC from local even when they denote the
        // same instant (as they do on a UTC test runner, where the hashCodes —
        // instant-based — would collide), so assert on equality, not hashCode.
        expect((entityUtc.props.first! as Map)['modifiedAt'], equals(utcTime));
        expect((entityLocal.props.first! as Map)['modifiedAt'], equals(localTime));
        expect(entityUtc, isNot(equals(entityLocal)));
      });
    });

    group('Different Implementations', () {
      test('mixin works with different entity implementations', () {
        final simpleEntity = SimpleTestEntity(
          id: 'simple1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        expect(simpleEntity.props, hasLength(2));
        expect((simpleEntity.props.first! as Map)['id'], equals('simple1'));
        expect(simpleEntity.isRelational, isFalse);
      });

      test('incrementClock returns itself by default', () {
        final result = entity1.incrementClock('device-1');
        expect(result, same(entity1));
      });

      test('entities from different classes with same props are not equal', () {
        final testEntity = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final simpleEntity = SimpleTestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        // Even with same props, different runtime types should not be equal
        expect(testEntity, isNot(equals(simpleEntity)));
      });
    });

    group('Equatable Behavior', () {
      test('== operator works correctly', () {
        final entityA = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final entityB = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final entityC = TestEntity(
          id: '2',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        expect(entityA == entityB, isTrue);
        expect(entityA == entityC, isFalse);
        expect(entityA == Object(), isFalse);
      });

      test('!= operator works correctly', () {
        final entityA = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final entityB = TestEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final entityC = TestEntity(
          id: '2',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        expect(entityA != entityB, isFalse);
        expect(entityA != entityC, isTrue);
        expect(entityA != Object(), isTrue);
      });
    });
  });
}

class SimpleTestEntity with DatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const SimpleTestEntity({
    required this.id,
    required this.userId,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'modifiedAt': modifiedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
    };
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    return null; // Simplified implementation for testing
  }

  @override
  bool? get stringify => true;
}
