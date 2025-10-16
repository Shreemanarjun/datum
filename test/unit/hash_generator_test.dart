// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter_test/flutter_test.dart';
import 'package:datum/datum.dart';

/// A simple, self-contained entity for testing purposes.
class TestHashEntity implements DatumEntity {
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

  TestHashEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'modifiedAt': modifiedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
    };
  }

  @override
  TestHashEntity copyWith({
    String? name,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return TestHashEntity(
      id: id,
      userId: userId,
      name: name ?? this.name,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;

  @override
  bool operator ==(covariant TestHashEntity other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.userId == userId &&
        other.name == name &&
        other.modifiedAt == modifiedAt &&
        other.createdAt == createdAt &&
        other.version == version &&
        other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      userId,
      name,
      modifiedAt,
      createdAt,
      version,
      isDeleted,
    );
  }
}

void main() {
  group('DatumHashGenerator', () {
    late DatumHashGenerator hashGenerator;
    late List<TestHashEntity> entities;

    setUp(() {
      hashGenerator = const DatumHashGenerator();
      final time = DateTime(2023);
      entities = [
        TestHashEntity(
          id: 'b',
          userId: 'user1',
          name: 'Entity B',
          modifiedAt: time,
          createdAt: time,
        ),
        TestHashEntity(
          id: 'a',
          userId: 'user1',
          name: 'Entity A',
          modifiedAt: time,
          createdAt: time,
        ),
      ];
    });

    test('generates a consistent hash for the same list of entities', () {
      final hash1 = hashGenerator.hashEntities(entities);
      final hash2 = hashGenerator.hashEntities(entities);

      expect(hash1, isA<String>());
      expect(hash1.length, 64); // SHA-256 hash length
      expect(hash1, equals(hash2));
    });

    test('generates the same hash regardless of entity order', () {
      final orderedEntities = entities.toList(); // ['b', 'a']
      final reversedEntities = entities.reversed.toList(); // ['a', 'b']

      final hash1 = hashGenerator.hashEntities(orderedEntities);
      final hash2 = hashGenerator.hashEntities(reversedEntities);

      expect(hash1, equals(hash2));
    });

    test('generates a different hash if an entity property changes', () {
      final originalHash = hashGenerator.hashEntities(entities);

      final modifiedEntities = List<TestHashEntity>.from(entities);
      modifiedEntities[0] = modifiedEntities[0].copyWith(name: 'Modified Name');

      final modifiedHash = hashGenerator.hashEntities(modifiedEntities);

      expect(originalHash, isNot(equals(modifiedHash)));
    });

    test('generates a different hash if an entity is added', () {
      final originalHash = hashGenerator.hashEntities(entities);

      final addedEntities = List<TestHashEntity>.from(entities)
        ..add(
          TestHashEntity(
            id: 'c',
            userId: 'user1',
            name: 'Entity C',
            modifiedAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
        );

      final addedHash = hashGenerator.hashEntities(addedEntities);

      expect(originalHash, isNot(equals(addedHash)));
    });

    test('generates a consistent hash for an empty list', () {
      final hash = hashGenerator.hashEntities<TestHashEntity>([]);

      expect(hash, isA<String>());
      expect(hash.length, 64);
      // This specific hash corresponds to an empty JSON array '[]'
      expect(
        hash,
        '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
      );
    });
  });
}
