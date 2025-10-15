import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/test_entity.dart';

class MockConflictResolver<T extends DatumEntity> extends Mock
    implements DatumConflictResolver<T> {}

void main() {
  group('DatumConfig', () {
    test('constructor provides correct default values', () {
      const config = DatumConfig();

      expect(config.autoSyncInterval, const Duration(minutes: 15));
      expect(config.autoStartSync, isFalse);
      expect(config.maxRetries, 3);
      expect(config.retryDelay, const Duration(seconds: 30));
      expect(config.syncTimeout, const Duration(minutes: 2));
      expect(config.defaultConflictResolver, isNull);
      expect(
        config.defaultUserSwitchStrategy,
        UserSwitchStrategy.syncThenSwitch,
      );
      expect(config.initialUserId, isNull);
      expect(config.enableLogging, isTrue);
      expect(config.defaultSyncDirection, SyncDirection.pushThenPull);
      expect(config.schemaVersion, 0);
      expect(config.migrations, isEmpty);
      expect(config.syncExecutionStrategy, isA<SequentialStrategy>());
      expect(config.onMigrationError, isNull);
    });

    test('defaultConfig factory returns a config with default values', () {
      final config = DatumConfig.defaultConfig();

      // Just check a few key properties to ensure it's the default.
      expect(config.autoSyncInterval, const Duration(minutes: 15));
      expect(config.maxRetries, 3);
      expect(config.schemaVersion, 0);
    });

    test('copyWith creates a new instance with updated values', () {
      const originalConfig = DatumConfig<TestEntity>();
      final newInterval = const Duration(minutes: 5);
      const newStrategy = ParallelStrategy();
      final newResolver = MockConflictResolver<TestEntity>();

      final newConfig = originalConfig.copyWith(
        autoSyncInterval: newInterval,
        autoStartSync: true,
        maxRetries: 5,
        enableLogging: false,
        syncExecutionStrategy: newStrategy,
        defaultConflictResolver: newResolver,
        schemaVersion: 2,
      );

      // Check updated values
      expect(newConfig.autoSyncInterval, newInterval);
      expect(newConfig.autoStartSync, isTrue);
      expect(newConfig.maxRetries, 5);
      expect(newConfig.enableLogging, isFalse);
      expect(newConfig.syncExecutionStrategy, newStrategy);
      expect(newConfig.defaultConflictResolver, newResolver);
      expect(newConfig.schemaVersion, 2);

      // Check that other values are unchanged from the original
      expect(newConfig.retryDelay, originalConfig.retryDelay);
      expect(newConfig.migrations, originalConfig.migrations);
    });

    test(
      'copyWith creates an identical copy when no arguments are provided',
      () {
        final resolver = MockConflictResolver<TestEntity>();
        final originalConfig = DatumConfig<TestEntity>(
          autoStartSync: true,
          maxRetries: 10,
          schemaVersion: 2,
          defaultConflictResolver: resolver,
          syncExecutionStrategy: const ParallelStrategy(),
        );

        final copiedConfig = originalConfig.copyWith();

        // Verify that all properties are identical
        expect(copiedConfig.autoSyncInterval, originalConfig.autoSyncInterval);
        expect(copiedConfig.autoStartSync, originalConfig.autoStartSync);
        expect(copiedConfig.maxRetries, originalConfig.maxRetries);
        expect(copiedConfig.retryDelay, originalConfig.retryDelay);
        expect(copiedConfig.syncTimeout, originalConfig.syncTimeout);
        expect(
          copiedConfig.defaultConflictResolver,
          originalConfig.defaultConflictResolver,
        );
        expect(copiedConfig.schemaVersion, originalConfig.schemaVersion);
        expect(
          copiedConfig.syncExecutionStrategy,
          originalConfig.syncExecutionStrategy,
        );
      },
    );
  });
}
