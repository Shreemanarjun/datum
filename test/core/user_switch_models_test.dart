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
  });
}
