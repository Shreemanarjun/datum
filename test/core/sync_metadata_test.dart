import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatumEntitySyncDetails', () {
    const details = DatumEntitySyncDetails(count: 10, hash: 'hash123');

    test('toMap and fromJson work correctly', () {
      final map = details.toMap();
      final fromMap = DatumEntitySyncDetails.fromJson(map);
      expect(fromMap, details);
    });

    test('toMap and fromJson work correctly with null hash', () {
      const detailsWithNullHash = DatumEntitySyncDetails(count: 5);
      final map = detailsWithNullHash.toMap();
      final fromMap = DatumEntitySyncDetails.fromJson(map);

      expect(map.containsKey('hash'), isFalse);
      expect(fromMap, detailsWithNullHash);
      expect(fromMap.hash, isNull);
    });

    test('equality works correctly', () {
      const same = DatumEntitySyncDetails(count: 10, hash: 'hash123');
      const differentCount = DatumEntitySyncDetails(count: 11, hash: 'hash123');
      const differentHash = DatumEntitySyncDetails(count: 10, hash: 'hash456');
      expect(details, same);
      expect(details.hashCode, same.hashCode);
      expect(details == differentCount, isFalse);
      expect(details == differentHash, isFalse);
    });

    test('toString provides a useful representation', () {
      expect(
        details.toString(),
        'DatumEntitySyncDetails(count: 10, hash: hash123)',
      );
    });
  });

  group('DatumSyncMetadata', () {
    final now = DateTime.now().toUtc();
    final metadata = DatumSyncMetadata(
      userId: 'user-123',
      lastSyncTime: now, // Use UTC time for consistent testing
      dataHash: 'hash123',
      deviceId: 'device-abc',
      entityCounts: const {
        'tasks': DatumEntitySyncDetails(count: 10, hash: 'task_hash'),
        'projects': DatumEntitySyncDetails(count: 2, hash: 'project_hash'),
        'notes': DatumEntitySyncDetails(count: 5, hash: 'notes_hash'),
      },
      customMetadata: const {'isPremium': true},
    );

    test('toMap and fromJson work correctly', () {
      // Arrange
      final map = metadata.toMap();

      // Act
      final fromMap = DatumSyncMetadata.fromJson(map);

      // Assert
      expect(fromMap, metadata);
    });

    test('toMap and fromJson handle null values', () {
      // Arrange
      final minimalMetadata = DatumSyncMetadata(
        userId: 'user-456',
        lastSyncTime: now, // Use UTC time for consistent testing
      );
      final map = minimalMetadata.toMap();

      // Act
      final fromMap = DatumSyncMetadata.fromJson(map);

      // Assert
      expect(fromMap.userId, 'user-456');
      expect(fromMap.lastSyncTime?.toIso8601String(), now.toIso8601String());
      expect(fromMap.dataHash, isNull);
      expect(fromMap.deviceId, isNull);
      expect(fromMap.entityCounts, isNull);
      expect(fromMap.customMetadata, isNull);
    });

    test('copyWith creates a correct copy with new values', () {
      // Arrange
      final newTime = now.add(const Duration(minutes: 5));
      const newEntityCounts = {'notes': DatumEntitySyncDetails(count: 20)};

      // Act
      final copied = metadata.copyWith(
        lastSyncTime: newTime,
        entityCounts: newEntityCounts,
      );

      // Assert
      expect(copied.userId, metadata.userId);
      expect(copied.lastSyncTime, newTime);
      expect(copied.entityCounts, newEntityCounts);
      expect(copied.dataHash, metadata.dataHash); // Should remain unchanged
    });

    test('copyWith correctly updates a single entity in entityCounts', () {
      // Arrange
      final updatedCounts = Map<String, DatumEntitySyncDetails>.from(
        metadata.entityCounts!,
      );
      updatedCounts['tasks'] = const DatumEntitySyncDetails(
        count: 15,
        hash: 'new_task_hash',
      );

      // Act
      final copied = metadata.copyWith(entityCounts: updatedCounts);

      // Assert
      expect(copied.entityCounts, isNotNull);
      expect(copied.entityCounts!.length, 3);
      // Check that 'tasks' was updated
      expect(
        copied.entityCounts!['tasks'],
        const DatumEntitySyncDetails(count: 15, hash: 'new_task_hash'),
      );
      // Check that 'projects' remains unchanged
      expect(
        copied.entityCounts!['projects'],
        metadata.entityCounts!['projects'],
      );
      expect(copied.entityCounts!['notes'], metadata.entityCounts!['notes']);
    });

    test('equality operator (==) works correctly', () {
      // Arrange
      final same = DatumSyncMetadata(
        userId: 'user-123',
        lastSyncTime: now,
        dataHash: 'hash123',
        deviceId: 'device-abc',
        entityCounts: const {
          'tasks': DatumEntitySyncDetails(count: 10, hash: 'task_hash'),
          'projects': DatumEntitySyncDetails(count: 2, hash: 'project_hash'),
          'notes': DatumEntitySyncDetails(count: 5, hash: 'notes_hash'),
        },
        customMetadata: const {'isPremium': true},
      );
      final different = metadata.copyWith(dataHash: 'different-hash');

      // Assert
      expect(metadata == same, isTrue);
      expect(metadata == different, isFalse);
    });

    test('equality is false if entityCounts have different details', () {
      // Arrange
      final differentCounts = metadata.copyWith(
        entityCounts: {
          'tasks': const DatumEntitySyncDetails(count: 10, hash: 'task_hash'),
          'projects': const DatumEntitySyncDetails(
            count: 3,
            hash: 'different_project_hash',
          ),
        },
      );

      // Assert
      expect(metadata == differentCounts, isFalse);
    });

    test('hashCode is consistent with equality', () {
      // Arrange
      final same = metadata.copyWith();
      final different = metadata.copyWith(dataHash: 'different-hash');

      // Assert
      expect(metadata.hashCode, same.hashCode);
      expect(metadata.hashCode, isNot(different.hashCode));
    });
  });
}
