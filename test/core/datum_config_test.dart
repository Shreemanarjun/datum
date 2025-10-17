import 'package:datum/datum.dart';
import 'package:test/test.dart';
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
      // Verify the new error recovery strategy defaults
      expect(config.errorRecoveryStrategy, isA<DatumErrorRecoveryStrategy>());
      expect(config.errorRecoveryStrategy.maxRetries, 3);
      expect(
        config.errorRecoveryStrategy.backoffStrategy,
        isA<ExponentialBackoff>(),
      );
    });

    test('defaultConfig factory returns a config with default values', () {
      final config = DatumConfig.defaultConfig();

      // Just check a few key properties to ensure it's the default.
      expect(config.autoSyncInterval, const Duration(minutes: 15));
      expect(config.errorRecoveryStrategy.maxRetries, 3);
      expect(config.schemaVersion, 0);
    });

    test('copyWith creates a new instance with updated values', () {
      const originalConfig = DatumConfig<TestEntity>();
      final newInterval = const Duration(minutes: 5);
      const newStrategy = ParallelStrategy();
      final newResolver = MockConflictResolver<TestEntity>();
      const newErrorStrategy = DatumErrorRecoveryStrategy(
        maxRetries: 5,
        backoffStrategy: FixedBackoff(),
        shouldRetry: _alwaysRetry,
      );

      final newConfig = originalConfig.copyWith(
        autoSyncInterval: newInterval,
        autoStartSync: true,
        enableLogging: false,
        syncExecutionStrategy: newStrategy,
        defaultConflictResolver: newResolver,
        schemaVersion: 2,
        errorRecoveryStrategy: newErrorStrategy,
      );

      // Check updated values
      expect(newConfig.autoSyncInterval, newInterval);
      expect(newConfig.autoStartSync, isTrue);
      expect(newConfig.enableLogging, isFalse);
      expect(newConfig.syncExecutionStrategy, newStrategy);
      expect(newConfig.defaultConflictResolver, newResolver);
      expect(newConfig.schemaVersion, 2);
      expect(newConfig.errorRecoveryStrategy, newErrorStrategy);

      // Check that other values are unchanged from the original
      expect(newConfig.migrations, originalConfig.migrations);
    });

    test(
      'copyWith creates an identical copy when no arguments are provided',
      () {
        final resolver = MockConflictResolver<TestEntity>();
        final originalConfig = DatumConfig<TestEntity>(
          autoStartSync: true,
          schemaVersion: 2,
          defaultConflictResolver: resolver,
          syncExecutionStrategy: const ParallelStrategy(),
        );

        final copiedConfig = originalConfig.copyWith();

        // Verify that all properties are identical
        expect(copiedConfig.autoSyncInterval, originalConfig.autoSyncInterval);
        expect(copiedConfig.autoStartSync, originalConfig.autoStartSync);
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

Future<bool> _alwaysRetry(DatumException error) async => true;
