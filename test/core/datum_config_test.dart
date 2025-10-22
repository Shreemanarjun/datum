import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/test_entity.dart';

class MockConflictResolver<T extends DatumEntity> extends Mock implements DatumConflictResolver<T> {}

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
      const newInterval = Duration(minutes: 5);
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

    test('toString() provides a useful summary from Equatable', () {
      const config = DatumConfig(
        autoStartSync: true,
        schemaVersion: 5,
        syncExecutionStrategy: ParallelStrategy(),
        enableLogging: false,
      );

      final string = config.toString();

      // Equatable's toString() format is ClassName(prop1, prop2, ...).
      // We'll check for the presence of the values in the string.
      expect(string, startsWith('DatumConfig('));
      expect(string, contains('true')); // autoStartSync
      expect(string, contains('5')); // schemaVersion
      expect(string, contains('ParallelStrategy')); // syncExecutionStrategy
    });

    group('Equality and HashCode', () {
      test('instances with same values are equal', () {
        const config1 = DatumConfig(schemaVersion: 1, autoStartSync: true);
        const config2 = DatumConfig(schemaVersion: 1, autoStartSync: true);
        expect(config1, equals(config2));
        expect(config1.hashCode, equals(config2.hashCode));
      });

      test('instances with different values are not equal', () {
        const config1 = DatumConfig(schemaVersion: 1);
        const config2 = DatumConfig(schemaVersion: 2);
        expect(config1, isNot(equals(config2)));
        expect(config1.hashCode, isNot(equals(config2.hashCode)));
      });

      test('instances with different strategies are not equal', () {
        const config1 = DatumConfig(syncExecutionStrategy: SequentialStrategy());
        const config2 = DatumConfig(syncExecutionStrategy: ParallelStrategy());
        expect(config1, isNot(equals(config2)));
      });
    });

    group('default shouldRetry logic', () {
      // Access the default shouldRetry function via the default config.
      const config = DatumConfig();
      final shouldRetry = config.errorRecoveryStrategy.shouldRetry;

      test('returns true for a retryable NetworkException', () async {
        final exception = NetworkException('Connection timeout', isRetryable: true);
        final result = await shouldRetry(exception);
        expect(result, isTrue);
      });

      test('returns false for a non-retryable NetworkException', () async {
        final exception = NetworkException('Bad request', isRetryable: false);
        final result = await shouldRetry(exception);
        expect(result, isFalse);
      });

      test('returns false for other DatumException types', () async {
        final exception = AdapterException('TestAdapter', 'Read failed');
        final result = await shouldRetry(exception);
        expect(result, isFalse);
      });
    });
  });
}

Future<bool> _alwaysRetry(DatumException error) async => true;
