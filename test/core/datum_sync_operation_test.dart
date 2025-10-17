import 'dart:convert';

import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumSyncOperation', () {
    final now = DateTime.now();
    final entity = TestEntity.create('e1', 'u1', 'Test');
    final operation = DatumSyncOperation<TestEntity>(
      id: 'op1',
      userId: 'u1',
      entityId: 'e1',
      type: DatumOperationType.create,
      timestamp: now,
      data: entity,
      delta: const {'name': 'Test'},
      retryCount: 2,
    );

    test('toMap and fromMap work correctly for a full operation', () {
      // Act
      final map = operation.toMap();
      final fromMap = DatumSyncOperation.fromMap(map, TestEntity.fromJson);

      // Assert
      expect(fromMap.id, operation.id);
      expect(fromMap.userId, operation.userId);
      expect(fromMap.entityId, operation.entityId);
      expect(fromMap.type, operation.type);
      // Timestamps can have microsecond differences after serialization
      expect(
        fromMap.timestamp.millisecondsSinceEpoch,
        operation.timestamp.millisecondsSinceEpoch,
      );
      expect(fromMap.data, operation.data);
      expect(fromMap.delta, operation.delta);
      expect(fromMap.retryCount, operation.retryCount);
    });

    test('toMap and fromMap handle null data and delta', () {
      // Arrange
      final deleteOp = DatumSyncOperation<TestEntity>(
        id: 'op-delete',
        userId: 'u1',
        entityId: 'e1',
        type: DatumOperationType.delete,
        timestamp: now,
      );

      // Act
      final map = deleteOp.toMap();
      final fromMap = DatumSyncOperation.fromMap(map, TestEntity.fromJson);

      // Assert
      expect(fromMap.id, deleteOp.id);
      expect(fromMap.data, isNull);
      expect(fromMap.delta, isNull);
    });

    test('toJson produces a valid JSON string', () {
      // Act
      final jsonString = operation.toJson();
      final decoded = json.decode(jsonString) as Map<String, dynamic>;

      // Assert
      expect(decoded['id'], 'op1');
      expect(decoded['type'], 'create');
      expect(decoded['data'], isNotNull);
      expect(decoded['data']['name'], 'Test');
    });

    test('copyWith creates a correct copy with new values', () {
      // Act
      final copied = operation.copyWith(
        type: DatumOperationType.update,
        retryCount: 3,
      );

      // Assert
      expect(copied.id, operation.id); // Unchanged
      expect(copied.type, DatumOperationType.update); // Changed
      expect(copied.retryCount, 3); // Changed
      expect(copied.data, operation.data); // Unchanged
    });

    test('toString provides a useful representation', () {
      // Act
      final stringRepresentation = operation.toString();

      // Assert
      expect(stringRepresentation, contains('op1'));
      expect(stringRepresentation, contains('create'));
      expect(stringRepresentation, contains('e1'));
      // Check for the value of retryCount, not the key-value pair.
      expect(stringRepresentation, contains(', 2)'));
    });

    test('equality operator and hashCode work correctly', () {
      // Arrange
      final same = DatumSyncOperation<TestEntity>(
        id: 'op1',
        userId: 'u1',
        entityId: 'e1',
        type: DatumOperationType.create,
        timestamp: now,
        data: entity,
        delta: const {'name': 'Test'},
        retryCount: 2,
      );

      final differentId = operation.copyWith(id: 'op2');
      final differentType = operation.copyWith(type: DatumOperationType.delete);

      // Assert
      expect(operation, same);
      expect(operation.hashCode, same.hashCode);
      expect(operation == differentId, isFalse);
      expect(operation.hashCode == differentId.hashCode, isFalse);
      expect(operation == differentType, isFalse);
      expect(operation.hashCode == differentType.hashCode, isFalse);
    });
  });
}
