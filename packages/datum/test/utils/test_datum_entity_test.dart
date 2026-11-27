import 'package:datum/datum.dart';
import '../test_utils/test_datum_entity.dart';
import 'package:test/test.dart';

void main() {
  group('TestDatumEntity', () {
    const testId = 'test_id';
    const testUserId = 'test_user';
    const testValue = 'test_value';
    final testCreatedAt = DateTime(2023, 1, 1, 12, 0, 0);
    final testModifiedAt = DateTime(2023, 1, 1, 12, 30, 0);

    test('constructor sets required fields correctly', () {
      final entity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
      );

      expect(entity.id, testId);
      expect(entity.userId, testUserId);
      expect(entity.value, testValue);
      expect(entity.version, 1);
      expect(entity.isDeleted, false);
      expect(entity.createdAt, isNotNull);
      expect(entity.modifiedAt, isNotNull);
    });

    test('constructor sets optional fields correctly', () {
      final entity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 5,
        isDeleted: true,
      );

      expect(entity.id, testId);
      expect(entity.userId, testUserId);
      expect(entity.value, testValue);
      expect(entity.createdAt, testCreatedAt);
      expect(entity.modifiedAt, testModifiedAt);
      expect(entity.version, 5);
      expect(entity.isDeleted, true);
    });

    test('toDatumMap returns correct map for local target', () {
      final entity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 5,
        isDeleted: true,
      );

      final map = entity.toDatumMap();

      expect(map['id'], testId);
      expect(map['userId'], testUserId);
      expect(map['value'], testValue);
      expect(map['createdAt'], testCreatedAt.toIso8601String());
      expect(map['modifiedAt'], testModifiedAt.toIso8601String());
      expect(map['version'], 5);
      expect(map['isDeleted'], true);
      expect(map.length, 8);
    });

    test('toDatumMap returns correct map for remote target', () {
      final entity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 5,
        isDeleted: true,
      );

      final map = entity.toDatumMap(target: MapTarget.remote);

      expect(map['id'], testId);
      expect(map['userId'], testUserId);
      expect(map['value'], testValue);
      expect(map['createdAt'], testCreatedAt.toIso8601String());
      expect(map['modifiedAt'], testModifiedAt.toIso8601String());
      expect(map['version'], 5);
      expect(map['isDeleted'], true);
      expect(map.length, 8);
    });

    test('fromMap creates entity correctly', () {
      final map = {
        'id': testId,
        'userId': testUserId,
        'value': testValue,
        'createdAt': testCreatedAt.toIso8601String(),
        'modifiedAt': testModifiedAt.toIso8601String(),
        'version': 5,
        'isDeleted': true,
      };

      final entity = TestDatumEntity.fromMap(map);

      expect(entity.id, testId);
      expect(entity.userId, testUserId);
      expect(entity.value, testValue);
      expect(entity.createdAt, testCreatedAt);
      expect(entity.modifiedAt, testModifiedAt);
      expect(entity.version, 5);
      expect(entity.isDeleted, true);
    });

    test('copyWith creates new instance with updated fields', () {
      final original = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      final copied = original.copyWith(
        value: 'new_value',
        version: 2,
        isDeleted: true,
      );

      expect(copied.id, testId); // Unchanged
      expect(copied.userId, testUserId); // Unchanged
      expect(copied.value, 'new_value'); // Changed
      expect(copied.createdAt, testCreatedAt); // Unchanged
      expect(copied.modifiedAt, testModifiedAt); // Unchanged
      expect(copied.version, 2); // Changed
      expect(copied.isDeleted, true); // Changed
    });

    test('copyWith with null values keeps original values', () {
      final original = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      final copied = original.copyWith(
        value: null,
        version: null,
        isDeleted: null,
      );

      expect(copied.value, testValue); // Unchanged
      expect(copied.version, 1); // Unchanged
      expect(copied.isDeleted, false); // Unchanged
    });

    test('copyWith creates different instance', () {
      final original = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
      );

      final copied = original.copyWith(value: 'new_value');

      expect(copied, isNot(same(original)));
      expect(copied.value, 'new_value');
      expect(original.value, testValue);
    });

    test('diff returns null when no changes', () {
      final entity1 = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        isDeleted: false,
      );

      final entity2 = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        isDeleted: false,
      );

      final diff = entity1.diff(entity2);
      expect(diff, isNull);
    });

    test('diff returns changes for value field', () {
      final oldEntity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: 'old_value',
        isDeleted: false,
      );

      final newEntity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: 'new_value',
        isDeleted: false,
      );

      final diff = newEntity.diff(oldEntity);
      expect(diff, {'value': 'new_value'});
    });

    test('diff returns changes for isDeleted field', () {
      final oldEntity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        isDeleted: false,
      );

      final newEntity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        isDeleted: true,
      );

      final diff = newEntity.diff(oldEntity);
      expect(diff, {'isDeleted': true});
    });

    test('diff returns changes for both value and isDeleted fields', () {
      final oldEntity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: 'old_value',
        isDeleted: false,
      );

      final newEntity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: 'new_value',
        isDeleted: true,
      );

      final diff = newEntity.diff(oldEntity);
      expect(diff, {'value': 'new_value', 'isDeleted': true});
    });

    test('diff returns null for non-TestDatumEntity', () {
      final entity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
      );

      // Create a mock entity that's not TestDatumEntity
      final otherEntity = _MockDatumEntity();

      final diff = entity.diff(otherEntity);
      expect(diff, isNull);
    });

    test('props returns correct equality properties', () {
      final entity1 = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      final entity2 = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      final entity3 = TestDatumEntity(
        id: 'different_id',
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      expect(entity1.props, equals(entity2.props));
      expect(entity1.props, isNot(equals(entity3.props)));
      expect(entity1.props.length, 8); // All fields should be included (now including vectorClock)
    });

    test('supports value equality', () {
      final entity1 = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      final entity2 = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      final entity3 = TestDatumEntity(
        id: 'different_id',
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 1,
        isDeleted: false,
      );

      expect(entity1, equals(entity2));
      expect(entity1.hashCode, equals(entity2.hashCode));
      expect(entity1, isNot(equals(entity3)));
    });

    test('round trip serialization works', () {
      final original = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
        createdAt: testCreatedAt,
        modifiedAt: testModifiedAt,
        version: 5,
        isDeleted: true,
      );

      final map = original.toDatumMap();
      final deserialized = TestDatumEntity.fromMap(map);

      expect(deserialized, equals(original));
    });

    test('toString includes key information', () {
      final entity = TestDatumEntity(
        id: testId,
        userId: testUserId,
        value: testValue,
      );

      final string = entity.toString();
      expect(string, contains('TestDatumEntity'));
      expect(string, contains(testId));
      expect(string, contains(testUserId));
      expect(string, contains(testValue));
    });
  });
}

// Mock class for testing diff with non-TestDatumEntity
class _MockDatumEntity implements DatumEntityInterface {
  @override
  String get id => 'mock_id';

  @override
  String get userId => 'mock_user';

  @override
  DateTime get createdAt => DateTime.now();

  @override
  DateTime get modifiedAt => DateTime.now();

  @override
  int get version => 1;

  @override
  bool get isDeleted => false;

  @override
  bool get isRelational => false;

  @override
  Set<String> get deviceOnlyFields => const {};

  @override
  VectorClock? get vectorClock => null;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {};

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => null;

  @override
  DatumEntityInterface merge(covariant DatumEntityInterface other) => other;

  @override
  DatumEntityInterface incrementClock(String replicaId) => this;
}
