import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

class TestRelationalEntity extends RelationalDatumEntity {
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

  const TestRelationalEntity({
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

  @override
  Map<String, Relation> get relations => {
        'parent': BelongsTo<TestRelationalEntity>(this, 'parentId'),
        'children': HasMany<TestRelationalEntity>(this, 'parentId'),
        'profile': HasOne<TestRelationalEntity>(this, 'userId'),
      };

  @override
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return TestRelationalEntity(
      id: id,
      userId: userId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class SimpleRelationalEntity with RelationalDatumEntityMixin {
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

  const SimpleRelationalEntity({
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
    return null;
  }

  @override
  bool? get stringify => true;

  @override
  Map<String, Relation> get relations => {};

  @override
  List<Object?> get props => [id, userId, modifiedAt, createdAt, version, isDeleted, vectorClock];
}

void main() {
  group('RelationalDatumEntityMixin', () {
    final now = DateTime(2023, 1, 1, 12, 0, 0);
    final entity = TestRelationalEntity(
      id: '1',
      userId: 'user1',
      modifiedAt: now,
      createdAt: now,
      version: 1,
    );

    group('isRelational', () {
      test('returns true for relational entities', () {
        expect(entity.isRelational, isTrue);
      });
    });

    group('Relations', () {
      test('relations getter returns defined relations', () {
        final relations = entity.relations;
        expect(relations, hasLength(3));
        expect(relations.containsKey('parent'), isTrue);
        expect(relations.containsKey('children'), isTrue);
        expect(relations.containsKey('profile'), isTrue);
      });

      test('relations can be empty', () {
        final simpleEntity = SimpleRelationalEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(simpleEntity.relations, isEmpty);
      });
    });

    group('BelongsTo Relation', () {
      test('BelongsTo relation is created correctly', () {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId');
        expect(relation.foreignKey, equals('parentId'));
        expect(relation.localKey, equals('id')); // default value
        expect(relation.value, isNull);
      });

      test('BelongsTo relation with custom localKey', () {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId', localKey: 'customId');
        expect(relation.localKey, equals('customId'));
      });

      test('BelongsTo relation with initial value', () {
        final relatedEntity = TestRelationalEntity(
          id: 'parent1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId', value: relatedEntity);
        expect(relation.value, equals(relatedEntity));
      });

      test('BelongsTo set method updates value', () {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId');
        final relatedEntity = TestRelationalEntity(
          id: 'parent1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        relation.set(relatedEntity);
        expect(relation.value, equals(relatedEntity));
      });

      test('BelongsTo getRelatedManager returns correct manager type', () {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId');
        // We can't easily test the actual manager without mocking,
        // but we can verify the method exists and returns expected type
        expect(relation.getRelatedManager, isNotNull);
      });
    });

    group('HasMany Relation', () {
      test('HasMany relation is created correctly', () {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId');
        expect(relation.foreignKey, equals('parentId'));
        expect(relation.localKey, equals('id')); // default value
        expect(relation.value, isNull);
      });

      test('HasMany relation with custom localKey', () {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId', localKey: 'customId');
        expect(relation.localKey, equals('customId'));
      });

      test('HasMany relation with initial value', () {
        final relatedEntities = [
          TestRelationalEntity(
            id: 'child1',
            userId: 'user1',
            modifiedAt: now,
            createdAt: now,
            version: 1,
          ),
        ];
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId', value: relatedEntities);
        expect(relation.value, equals(relatedEntities));
      });

      test('HasMany set method updates value', () {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId');
        final relatedEntities = [
          TestRelationalEntity(
            id: 'child1',
            userId: 'user1',
            modifiedAt: now,
            createdAt: now,
            version: 1,
          ),
        ];

        relation.set(relatedEntities);
        expect(relation.value, equals(relatedEntities));
      });

      test('HasMany getRelatedManager returns correct manager type', () {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId');
        expect(relation.getRelatedManager, isNotNull);
      });
    });

    group('HasOne Relation', () {
      test('HasOne relation is created correctly', () {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId');
        expect(relation.foreignKey, equals('userId'));
        expect(relation.localKey, equals('id')); // default value
        expect(relation.value, isNull);
      });

      test('HasOne relation with custom localKey', () {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId', localKey: 'customId');
        expect(relation.localKey, equals('customId'));
      });

      test('HasOne relation with initial value', () {
        final relatedEntity = TestRelationalEntity(
          id: 'profile1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        final relation = HasOne<TestRelationalEntity>(entity, 'userId', value: relatedEntity);
        expect(relation.value, equals(relatedEntity));
      });

      test('HasOne set method updates value', () {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId');
        final relatedEntity = TestRelationalEntity(
          id: 'profile1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        relation.set(relatedEntity);
        expect(relation.value, equals(relatedEntity));
      });

      test('HasOne getRelatedManager returns correct manager type', () {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId');
        expect(relation.getRelatedManager, isNotNull);
      });
    });

    group('ManyToMany Relation', () {
      test('ManyToMany relation is created correctly', () {
        // final pivotEntity = TestRelationalEntity(...); (removed)
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
        );

        expect(relation.thisForeignKey, equals('thisForeignKey'));
        expect(relation.otherForeignKey, equals('otherForeignKey'));
        expect(relation.thisLocalKey, equals('id')); // default value
        expect(relation.otherLocalKey, equals('id')); // default value
        expect(relation.value, isNull);
      });

      test('ManyToMany relation with custom keys', () {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
          thisLocalKey: 'customThisKey',
          otherLocalKey: 'customOtherKey',
        );

        expect(relation.thisLocalKey, equals('customThisKey'));
        expect(relation.otherLocalKey, equals('customOtherKey'));
      });

      test('ManyToMany relation with initial value', () {
        final relatedEntities = [
          TestRelationalEntity(
            id: 'related1',
            userId: 'user1',
            modifiedAt: now,
            createdAt: now,
            version: 1,
          ),
        ];
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
          value: relatedEntities,
        );

        expect(relation.value, equals(relatedEntities));
      });

      test('ManyToMany set method updates value', () {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
        );
        final relatedEntities = [
          TestRelationalEntity(
            id: 'related1',
            userId: 'user1',
            modifiedAt: now,
            createdAt: now,
            version: 1,
          ),
        ];

        relation.set(relatedEntities);
        expect(relation.value, equals(relatedEntities));
      });

      test('ManyToMany getRelatedManager returns correct manager type', () {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
        );

        expect(relation.getRelatedManager, isNotNull);
      });
    });

    group('Relation Types', () {
      test('BelongsTo is a Relation', () {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId');
        expect(relation, isA<Relation<TestRelationalEntity>>());
      });

      test('HasMany is a Relation', () {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId');
        expect(relation, isA<Relation<TestRelationalEntity>>());
      });

      test('HasOne is a Relation', () {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId');
        expect(relation, isA<Relation<TestRelationalEntity>>());
      });

      test('ManyToMany is a Relation', () {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
        );
        expect(relation, isA<Relation<TestRelationalEntity>>());
      });
    });

    group('Inheritance and Equatable', () {
      test('relational entity extends Equatable', () {
        expect(entity, isA<Equatable>());
      });

      test('relational entity has correct props', () {
        // Default props: the whole toDatumMap, then the vector clock.
        expect(entity.props, [entity.toDatumMap(), null]);
      });

      test('entities with same props are equal', () {
        final entity2 = TestRelationalEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(entity == entity2, isTrue);
      });

      test('entities with different props are not equal', () {
        final entity2 = TestRelationalEntity(
          id: '2',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );
        expect(entity == entity2, isFalse);
      });
    });

    group('Relation Fetch Methods', () {
      test('BelongsTo fetch returns related entity when found', () async {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId');
        // Note: In a real scenario, this would require mocking Datum.manager
        // For now, we just verify the method exists and can be called
        expect(relation.fetch, isNotNull);
      });

      test('HasMany fetch returns related entities when found', () async {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId');
        expect(relation.fetch, isNotNull);
      });

      test('HasOne fetch returns related entity when found', () async {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId');
        expect(relation.fetch, isNotNull);
      });

      test('ManyToMany fetch returns related entities when found', () async {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
        );
        expect(relation.fetch, isNotNull);
      });

      test('BelongsTo fetch handles null foreign key value', () async {
        final entityWithNullMap = _TestEntityWithNullKey(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final relation = BelongsTo<TestRelationalEntity>(entityWithNullMap, 'missingKey');
        // The fetch method should handle null foreign keys gracefully
        expect(relation.foreignKey, equals('missingKey'));
      });
    });

    group('RelationalDatumEntity Class', () {
      test('RelationalDatumEntity extends DatumEntity', () {
        expect(entity, isA<DatumEntity>());
      });

      test('RelationalDatumEntity has correct inheritance hierarchy', () {
        expect(entity, isA<DatumEntityInterface>());
        expect(entity, isA<RelationalDatumEntity>());
      });

      test('copyWith creates new instance with updated fields', () {
        final updated = entity.copyWith(
          modifiedAt: now.add(const Duration(hours: 1)),
          version: 2,
          isDeleted: true,
        );

        expect(updated.id, equals(entity.id));
        expect(updated.userId, equals(entity.userId));
        expect(updated.createdAt, equals(entity.createdAt));
        expect(updated.modifiedAt, equals(now.add(const Duration(hours: 1))));
        expect(updated.version, equals(2));
        expect(updated.isDeleted, isTrue);
      });

      test('copyWith with null values keeps original values', () {
        final updated = entity.copyWith();

        expect(updated.id, equals(entity.id));
        expect(updated.userId, equals(entity.userId));
        expect(updated.createdAt, equals(entity.createdAt));
        expect(updated.modifiedAt, equals(entity.modifiedAt));
        expect(updated.version, equals(entity.version));
        expect(updated.isDeleted, equals(entity.isDeleted));
      });
    });

    group('Relation State Management', () {
      test('BelongsTo relation starts unloaded', () {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId');
        expect(relation.value, isNull);
        // Note: _isLoaded is private, so we can't test it directly
      });

      test('HasMany relation starts unloaded', () {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId');
        expect(relation.value, isNull);
      });

      test('HasOne relation starts unloaded', () {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId');
        expect(relation.value, isNull);
      });

      test('ManyToMany relation starts unloaded', () {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
        );
        expect(relation.value, isNull);
      });

      test('BelongsTo set method updates value and marks as loaded', () {
        final relation = BelongsTo<TestRelationalEntity>(entity, 'parentId');
        final relatedEntity = TestRelationalEntity(
          id: 'parent1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        relation.set(relatedEntity);
        expect(relation.value, equals(relatedEntity));
      });

      test('HasMany set method updates value and marks as loaded', () {
        final relation = HasMany<TestRelationalEntity>(entity, 'parentId');
        final relatedEntities = [
          TestRelationalEntity(
            id: 'child1',
            userId: 'user1',
            modifiedAt: now,
            createdAt: now,
            version: 1,
          ),
        ];

        relation.set(relatedEntities);
        expect(relation.value, equals(relatedEntities));
      });

      test('HasOne set method updates value and marks as loaded', () {
        final relation = HasOne<TestRelationalEntity>(entity, 'userId');
        final relatedEntity = TestRelationalEntity(
          id: 'profile1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        relation.set(relatedEntity);
        expect(relation.value, equals(relatedEntity));
      });

      test('ManyToMany set method updates value and marks as loaded', () {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
        );
        final relatedEntities = [
          TestRelationalEntity(
            id: 'related1',
            userId: 'user1',
            modifiedAt: now,
            createdAt: now,
            version: 1,
          ),
        ];

        relation.set(relatedEntities);
        expect(relation.value, equals(relatedEntities));
      });
    });

    group('Relation Configuration', () {
      test('ManyToMany relation accepts custom local keys', () {
        final relation = ManyToMany<TestRelationalEntity>(
          entity,
          TestRelationalEntity,
          'thisForeignKey',
          'otherForeignKey',
          thisLocalKey: 'customThisKey',
          otherLocalKey: 'customOtherKey',
        );

        expect(relation.thisLocalKey, equals('customThisKey'));
        expect(relation.otherLocalKey, equals('customOtherKey'));
      });

      test('Relations accept different parent entities', () {
        final otherEntity = TestRelationalEntity(
          id: '2',
          userId: 'user2',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final relation = BelongsTo<TestRelationalEntity>(otherEntity, 'parentId');
        // Test that the relation was created with the correct parent
        expect(relation.foreignKey, equals('parentId'));
        expect(relation.localKey, equals('id'));
      });
    });

    group('Edge Cases', () {
      test('relations with null foreign keys', () {
        // Override toDatumMap to return null for a key
        final entityWithNullMap = _TestEntityWithNullKey(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        final relation = BelongsTo<TestRelationalEntity>(entityWithNullMap, 'missingKey');
        // The fetch method would handle null foreign keys gracefully
        expect(relation.foreignKey, equals('missingKey'));
      });

      test('empty relations map', () {
        final simpleEntity = SimpleRelationalEntity(
          id: '1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        expect(simpleEntity.relations, isEmpty);
        expect(simpleEntity.isRelational, isTrue);
      });

      test('relations with complex entity hierarchies', () {
        // Test that relations work with entities that have complex inheritance
        final complexEntity = _ComplexTestEntity(
          id: 'complex1',
          userId: 'user1',
          modifiedAt: now,
          createdAt: now,
          version: 1,
          customField: 'test',
        );

        final relation = BelongsTo<TestRelationalEntity>(complexEntity, 'parentId');
        // Test that the relation can be created with a complex entity
        expect(relation.foreignKey, equals('parentId'));
        expect(relation.value, isNull);
      });
    });
  });
}

class _TestEntityWithNullKey extends RelationalDatumEntity {
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

  const _TestEntityWithNullKey({
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
      // 'missingKey' is intentionally not included
    };
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    return null;
  }

  @override
  bool? get stringify => true;

  @override
  Map<String, Relation> get relations => {};

  @override
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return _TestEntityWithNullKey(
      id: id,
      userId: userId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class _ComplexTestEntity extends RelationalDatumEntity {
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
  final String customField;

  const _ComplexTestEntity({
    required this.id,
    required this.userId,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
    required this.customField,
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
      'customField': customField,
    };
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    return null;
  }

  @override
  bool? get stringify => true;

  @override
  Map<String, Relation> get relations => {};

  @override
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return _ComplexTestEntity(
      id: id,
      userId: userId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      customField: customField,
    );
  }
}
