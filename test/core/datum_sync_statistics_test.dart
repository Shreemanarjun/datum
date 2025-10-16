import 'package:datum/source/core/events/datum_sync_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatumSyncStatistics', () {
    test('constructor provides correct default values', () {
      // Arrange & Act
      const stats = DatumSyncStatistics();

      // Assert
      expect(stats.totalSyncs, 0);
      expect(stats.successfulSyncs, 0);
      expect(stats.failedSyncs, 0);
      expect(stats.conflictsDetected, 0);
      expect(stats.conflictsAutoResolved, 0);
      expect(stats.conflictsUserResolved, 0);
      expect(stats.averageDuration, Duration.zero);
      expect(stats.totalSyncDuration, Duration.zero);
    });

    test('constructor sets all fields correctly', () {
      // Arrange & Act
      const stats = DatumSyncStatistics(
        totalSyncs: 10,
        successfulSyncs: 8,
        failedSyncs: 2,
        conflictsDetected: 3,
        conflictsAutoResolved: 2,
        conflictsUserResolved: 1,
        averageDuration: Duration(seconds: 5),
        totalSyncDuration: Duration(seconds: 50),
      );

      // Assert
      expect(stats.totalSyncs, 10);
      expect(stats.successfulSyncs, 8);
      expect(stats.failedSyncs, 2);
      expect(stats.conflictsDetected, 3);
      expect(stats.conflictsAutoResolved, 2);
      expect(stats.conflictsUserResolved, 1);
      expect(stats.averageDuration, const Duration(seconds: 5));
      expect(stats.totalSyncDuration, const Duration(seconds: 50));
    });

    test('copyWith creates a new instance with updated values', () {
      // Arrange
      const original = DatumSyncStatistics(totalSyncs: 10, successfulSyncs: 5);

      // Act
      final copied = original.copyWith(successfulSyncs: 6, failedSyncs: 1);

      // Assert
      expect(copied.totalSyncs, 10); // Unchanged
      expect(copied.successfulSyncs, 6); // Changed
      expect(copied.failedSyncs, 1); // Changed
    });

    test('supports value equality', () {
      // Arrange
      const stats1 = DatumSyncStatistics(
        totalSyncs: 10,
        successfulSyncs: 8,
        failedSyncs: 2,
      );
      const stats2 = DatumSyncStatistics(
        totalSyncs: 10,
        successfulSyncs: 8,
        failedSyncs: 2,
      );
      const stats3 = DatumSyncStatistics(
        totalSyncs: 11, // Different
        successfulSyncs: 8,
        failedSyncs: 2,
      );

      // Assert
      expect(stats1, equals(stats2));
      expect(stats1.hashCode, equals(stats2.hashCode));
      expect(stats1, isNot(equals(stats3)));
    });

    test('props list is correct for equality check', () {
      const stats = DatumSyncStatistics();
      expect(stats.props, [0, 0, 0, 0, 0, 0, Duration.zero, Duration.zero]);
    });
  });
}
