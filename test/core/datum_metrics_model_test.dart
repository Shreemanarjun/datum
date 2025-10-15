import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatumMetrics Model', () {
    const metrics1 = DatumMetrics(
      totalSyncOperations: 10,
      successfulSyncs: 8,
      failedSyncs: 2,
      conflictsDetected: 3,
      conflictsResolvedAutomatically: 1,
      userSwitchCount: 4,
      activeUsers: {'user-1', 'user-2'},
    );

    const metrics1Copy = DatumMetrics(
      totalSyncOperations: 10,
      successfulSyncs: 8,
      failedSyncs: 2,
      conflictsDetected: 3,
      conflictsResolvedAutomatically: 1,
      userSwitchCount: 4,
      activeUsers: {'user-1', 'user-2'},
    );

    group('toString()', () {
      test('provides a useful summary', () {
        // Act
        final string = metrics1.toString();

        // Assert
        expect(string, contains('totalSyncs: 10'));
        expect(string, contains('successful: 8'));
        expect(string, contains('failed: 2'));
        expect(string, contains('conflicts: 3'));
      });
    });

    group('Equality and HashCode', () {
      test('instances with same values are equal', () {
        // Assert
        expect(metrics1, equals(metrics1Copy));
        expect(metrics1.hashCode, equals(metrics1Copy.hashCode));
      });

      test('instances with different totalSyncOperations are not equal', () {
        final different = metrics1.copyWith(totalSyncOperations: 99);
        expect(metrics1, isNot(equals(different)));
        expect(metrics1.hashCode, isNot(equals(different.hashCode)));
      });

      test('instances with different successfulSyncs are not equal', () {
        final different = metrics1.copyWith(successfulSyncs: 99);
        expect(metrics1, isNot(equals(different)));
        expect(metrics1.hashCode, isNot(equals(different.hashCode)));
      });

      test('instances with different failedSyncs are not equal', () {
        final different = metrics1.copyWith(failedSyncs: 99);
        expect(metrics1, isNot(equals(different)));
        expect(metrics1.hashCode, isNot(equals(different.hashCode)));
      });

      test('instances with different conflictsDetected are not equal', () {
        final different = metrics1.copyWith(conflictsDetected: 99);
        expect(metrics1, isNot(equals(different)));
        expect(metrics1.hashCode, isNot(equals(different.hashCode)));
      });

      test(
        'instances with different conflictsResolvedAutomatically are not equal',
        () {
          final different = metrics1.copyWith(
            conflictsResolvedAutomatically: 99,
          );
          expect(metrics1, isNot(equals(different)));
          expect(metrics1.hashCode, isNot(equals(different.hashCode)));
        },
      );

      test('instances with different userSwitchCount are not equal', () {
        final different = metrics1.copyWith(userSwitchCount: 99);
        expect(metrics1, isNot(equals(different)));
        expect(metrics1.hashCode, isNot(equals(different.hashCode)));
      });

      test('instances with different activeUsers are not equal', () {
        final different = metrics1.copyWith(activeUsers: {'user-3'});
        expect(metrics1, isNot(equals(different)));
        expect(metrics1.hashCode, isNot(equals(different.hashCode)));
      });

      test(
        'instances with same values but different order of activeUsers are equal',
        () {
          // Sets are unordered, so equality should hold if the elements are the same.
          const metricsWithDifferentOrder = DatumMetrics(
            totalSyncOperations: 10,
            successfulSyncs: 8,
            failedSyncs: 2,
            conflictsDetected: 3,
            conflictsResolvedAutomatically: 1,
            userSwitchCount: 4,
            activeUsers: {'user-2', 'user-1'}, // Different order
          );

          expect(metrics1, equals(metricsWithDifferentOrder));
          expect(metrics1.hashCode, equals(metricsWithDifferentOrder.hashCode));
        },
      );
    });
  });
}
