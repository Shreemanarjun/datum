import 'package:datum/source/core/models/user_switch_models.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumUserSwitchResult', () {
    test('success factory creates a correct successful result', () {
      // Arrange
      final conflicts = [TestEntity.create('e1', 'u1', 'Conflict')];

      // Act
      final result = DatumUserSwitchResult.success(
        newUserId: 'user-new',
        previousUserId: 'user-old',
        unsyncedOperationsHandled: 5,
        conflicts: conflicts,
      );

      // Assert
      expect(result.success, isTrue);
      expect(result.newUserId, 'user-new');
      expect(result.previousUserId, 'user-old');
      expect(result.unsyncedOperationsHandled, 5);
      expect(result.conflicts, conflicts);
      expect(result.errorMessage, isNull);
    });

    test('failure factory creates a correct failed result', () {
      // Act
      final result = DatumUserSwitchResult.failure(
        newUserId: 'user-new',
        previousUserId: 'user-old',
        errorMessage: 'Could not sync old user data.',
      );

      // Assert
      expect(result.success, isFalse);
      expect(result.newUserId, 'user-new');
      expect(result.previousUserId, 'user-old');
      expect(result.errorMessage, 'Could not sync old user data.');
      // Check default values
      expect(result.unsyncedOperationsHandled, 0);
      expect(result.conflicts, isNull);
    });

    test('primary constructor sets all fields correctly', () {
      const result = DatumUserSwitchResult(
        success: true,
        newUserId: 'user-new',
      );

      expect(result.success, isTrue);
      expect(result.newUserId, 'user-new');
    });

    group('aggregate', () {
      test('returns a successful result for an empty list', () {
        // Arrange
        final results = <DatumUserSwitchResult>[];

        // Act
        final aggregated = DatumUserSwitchResult.aggregate(
          results,
          previousUserId: 'user-old',
          newUserId: 'user-new',
        );

        // Assert
        expect(aggregated.success, isTrue);
        expect(aggregated.previousUserId, 'user-old');
        expect(aggregated.newUserId, 'user-new');
        expect(aggregated.unsyncedOperationsHandled, 0);
        expect(aggregated.errorMessage, isNull);
      });

      test('returns a successful result when all inputs are successful', () {
        // Arrange
        final results = [
          DatumUserSwitchResult.success(
            newUserId: 'user-new',
            previousUserId: 'user-old',
            unsyncedOperationsHandled: 2,
          ),
          DatumUserSwitchResult.success(
            newUserId: 'user-new',
            previousUserId: 'user-old',
            unsyncedOperationsHandled: 3,
          ),
        ];

        // Act
        final aggregated = DatumUserSwitchResult.aggregate(
          results,
          previousUserId: 'user-old',
          newUserId: 'user-new',
        );

        // Assert
        expect(aggregated.success, isTrue);
        expect(aggregated.unsyncedOperationsHandled, 5);
        expect(aggregated.errorMessage, isNull);
      });

      test('returns a failed result if any input is a failure', () {
        // Arrange
        final results = [
          DatumUserSwitchResult.success(
            newUserId: 'user-new',
            previousUserId: 'user-old',
            unsyncedOperationsHandled: 2,
          ),
          DatumUserSwitchResult.failure(
            newUserId: 'user-new',
            previousUserId: 'user-old',
            errorMessage: 'Sync failed for manager 2',
          ),
        ];

        // Act
        final aggregated = DatumUserSwitchResult.aggregate(
          results,
          previousUserId: 'user-old',
          newUserId: 'user-new',
        );

        // Assert
        expect(aggregated.success, isFalse);
        expect(aggregated.unsyncedOperationsHandled, 2);
        expect(aggregated.errorMessage, 'Sync failed for manager 2');
      });
    });
  });
}
