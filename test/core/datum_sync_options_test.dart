import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/test_entity.dart';

class MockConflictResolver<T extends DatumEntity> extends Mock
    implements DatumConflictResolver<T> {}

class AnotherTestEntity extends TestEntity {
  AnotherTestEntity({required super.id, required super.userId})
      : super(
          name: 'Another',
          value: 0,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        );
}

void main() {
  group('DatumSyncOptions', () {
    test('constructor provides correct default values', () {
      const options = DatumSyncOptions();

      expect(options.includeDeletes, isTrue);
      expect(options.resolveConflicts, isTrue);
      expect(options.forceFullSync, isFalse);
      expect(options.overrideBatchSize, isNull);
      expect(options.timeout, isNull);
      expect(options.direction, isNull);
      expect(options.conflictResolver, isNull);
    });

    test('copyWith creates a new instance with updated values', () {
      // Arrange
      final resolver = MockConflictResolver<TestEntity>();
      const originalOptions = DatumSyncOptions<TestEntity>(
        includeDeletes: true,
        forceFullSync: false,
        direction: SyncDirection.pushThenPull,
      );

      // Act
      final newOptions = originalOptions.copyWith(
        forceFullSync: true,
        direction: SyncDirection.pullOnly,
        conflictResolver: resolver,
      );

      // Assert
      expect(newOptions.forceFullSync, isTrue);
      expect(newOptions.direction, SyncDirection.pullOnly);
      expect(newOptions.conflictResolver, resolver);
      // Check that other values are unchanged
      expect(newOptions.includeDeletes, originalOptions.includeDeletes);
    });

    test(
      'copyWith creates an identical copy when no arguments are provided',
      () {
        // Arrange
        final resolver = MockConflictResolver<TestEntity>();
        final originalOptions = DatumSyncOptions<TestEntity>(
          includeDeletes: false,
          direction: SyncDirection.pullThenPush,
          conflictResolver: resolver,
        );

        // Act
        final copiedOptions = originalOptions.copyWith();

        // Assert
        expect(copiedOptions, originalOptions);
        expect(copiedOptions.hashCode, originalOptions.hashCode);
      },
    );
  });
}
