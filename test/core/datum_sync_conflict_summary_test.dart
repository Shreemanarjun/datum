import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumSyncConflictSummary', () {
    final entity1 = TestEntity.create('e1', 'u1', 'Entity 1');
    final resolution1 = DatumConflictResolution<TestEntity>.useLocal(entity1);
    final summary1 = DatumSyncConflictSummary<TestEntity>(
      resolution: resolution1,
      entityId: 'e1',
    );

    test('supports value equality', () {
      // Create another instance with the same values
      final summary1Copy = DatumSyncConflictSummary<TestEntity>(
        resolution: DatumConflictResolution<TestEntity>.useLocal(entity1),
        entityId: 'e1',
      );

      expect(summary1, equals(summary1Copy));
      expect(summary1.hashCode, equals(summary1Copy.hashCode));
    });

    test('props are correct for equality check', () {
      expect(summary1.props, [resolution1, 'e1']);
    });

    test('is not equal for different entityId', () {
      final summary2 = DatumSyncConflictSummary<TestEntity>(
        resolution: resolution1,
        entityId: 'e2', // Different entityId
      );

      expect(summary1, isNot(equals(summary2)));
    });

    test('is not equal for different resolution', () {
      final entity2 = TestEntity.create('e2', 'u1', 'Entity 2');
      final resolution2 = DatumConflictResolution<TestEntity>.useRemote(
        entity2,
      );
      final summary2 = DatumSyncConflictSummary<TestEntity>(
        resolution: resolution2, // Different resolution
        entityId: 'e1',
      );

      expect(summary1, isNot(equals(summary2)));
    });

    test('toString() provides a useful summary', () {
      final string = summary1.toString();

      expect(
        string,
        contains(
          'DatumSyncConflictSummary(resolution: ${resolution1.toString()}, entityId: e1)',
        ),
      );
    });
  });
}
