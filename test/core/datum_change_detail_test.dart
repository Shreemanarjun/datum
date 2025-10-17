import 'package:datum/source/core/models/datum_change_detail.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumChangeDetail', () {
    final now = DateTime.now();
    final entity = TestEntity.create('e1', 'u1', 'Test');
    final changeDetail = DatumChangeDetail<TestEntity>(
      type: DatumOperationType.create,
      entityId: 'e1',
      userId: 'u1',
      timestamp: now,
      data: entity,
      sourceId: 'device-1',
    );

    test('copyWith creates a correct copy with new values', () {
      // Arrange
      final newTimestamp = now.add(const Duration(seconds: 10));
      final updatedEntity = entity.copyWith(name: 'Updated');

      // Act
      final copied = changeDetail.copyWith(
        type: DatumOperationType.update,
        timestamp: newTimestamp,
        data: updatedEntity,
      );

      // Assert
      expect(copied.type, DatumOperationType.update);
      expect(copied.timestamp, newTimestamp);
      expect(copied.data, updatedEntity);
      expect(copied.entityId, changeDetail.entityId); // Unchanged
      expect(copied.userId, changeDetail.userId); // Unchanged
      expect(copied.sourceId, changeDetail.sourceId); // Unchanged
    });

    test(
      'copyWith creates an identical copy when no arguments are provided',
      () {
        final copied = changeDetail.copyWith();
        expect(copied, changeDetail);
        expect(copied.hashCode, changeDetail.hashCode);
      },
    );

    test('equality operator (==) and hashCode work correctly', () {
      // Arrange
      final same = DatumChangeDetail<TestEntity>(
        type: DatumOperationType.create,
        entityId: 'e1',
        userId: 'u1',
        timestamp: now,
        data: entity,
        sourceId: 'device-1',
      );

      final differentType = changeDetail.copyWith(
        type: DatumOperationType.delete,
      );
      final differentEntityId = changeDetail.copyWith(entityId: 'e2');
      final differentUserId = changeDetail.copyWith(userId: 'u2');
      final differentTimestamp = changeDetail.copyWith(
        timestamp: now.add(const Duration(seconds: 1)),
      );
      final differentSourceId = changeDetail.copyWith(sourceId: 'device-2');
      // Note: `data` is not part of the equality check.
      final differentData = changeDetail.copyWith(data: null);

      // Assert
      expect(changeDetail, same);
      expect(changeDetail.hashCode, same.hashCode);

      expect(changeDetail == differentType, isFalse);
      expect(changeDetail == differentEntityId, isFalse);
      expect(changeDetail == differentUserId, isFalse);
      expect(changeDetail == differentTimestamp, isFalse);
      expect(changeDetail == differentSourceId, isFalse);
      expect(changeDetail == differentData, isTrue); // `data` is not compared
    });

    test('toString provides a useful representation', () {
      // Arrange
      final detail = DatumChangeDetail<TestEntity>(
        type: DatumOperationType.update,
        entityId: 'entity-123',
        userId: 'user-abc',
        timestamp: now,
        sourceId: 'device-xyz',
      );

      // Act
      final stringRepresentation = detail.toString();

      // Assert
      expect(stringRepresentation, contains('type: update'));
      expect(stringRepresentation, contains('entityId: entity-123'));
      expect(stringRepresentation, contains('userId: user-abc'));
      expect(stringRepresentation, contains('sourceId: device-xyz'));
    });
  });
}
