import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/test_entity.dart';

class MockConflictResolver<T extends DatumEntityInterface> extends Mock implements DatumConflictResolver<T> {}

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
      expect(config.defaultSyncDirection, SyncDirection.pullThenPush);
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
      expect(config.syncDirectionResolver, isNull);
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

    group('syncDirectionResolver', () {
      test('defaults to null', () {
        const config = DatumConfig<TestEntity>();
        expect(config.syncDirectionResolver, isNull);
      });

      test('can be set via constructor', () {
        SyncDirection? resolver(int pendingCount, SyncDirection defaultDirection) {
          return SyncDirection.pullOnly;
        }

        final config = DatumConfig<TestEntity>(
          syncDirectionResolver: resolver,
        );

        expect(config.syncDirectionResolver, isNotNull);
        final result = config.syncDirectionResolver!(5, SyncDirection.pushThenPull);
        expect(result, SyncDirection.pullOnly);
      });

      test('can return null to use default direction', () {
        SyncDirection? resolver(int pendingCount, SyncDirection defaultDirection) {
          return null; // Use default
        }

        final config = DatumConfig<TestEntity>(
          syncDirectionResolver: resolver,
        );

        final result = config.syncDirectionResolver!(5, SyncDirection.pushThenPull);
        expect(result, isNull);
      });

      test('receives correct parameters', () {
        int capturedPendingCount = -1;
        SyncDirection capturedDefaultDirection = SyncDirection.pushOnly;

        SyncDirection? resolver(int pendingCount, SyncDirection defaultDirection) {
          capturedPendingCount = pendingCount;
          capturedDefaultDirection = defaultDirection;
          return SyncDirection.pullOnly;
        }

        final config = DatumConfig<TestEntity>(
          syncDirectionResolver: resolver,
        );

        config.syncDirectionResolver!(42, SyncDirection.pullThenPush);

        expect(capturedPendingCount, 42);
        expect(capturedDefaultDirection, SyncDirection.pullThenPush);
      });

      test('can implement fast sync logic for no pending changes', () {
        // This mimics the example app logic
        SyncDirection? resolver(int pendingCount, SyncDirection defaultDirection) {
          if (pendingCount == 0) {
            return SyncDirection.pullThenPush; // Prioritize remote changes
          }
          return null; // Use default
        }

        final config = DatumConfig<TestEntity>(
          syncDirectionResolver: resolver,
        );

        // Test with no pending changes
        final resultNoPending = config.syncDirectionResolver!(0, SyncDirection.pushThenPull);
        expect(resultNoPending, SyncDirection.pullThenPush);

        // Test with pending changes
        final resultWithPending = config.syncDirectionResolver!(5, SyncDirection.pushThenPull);
        expect(resultWithPending, isNull);
      });

      test('can implement different strategies based on pending count', () {
        SyncDirection? resolver(int pendingCount, SyncDirection defaultDirection) {
          if (pendingCount == 0) {
            return SyncDirection.pullOnly; // Only pull when no local changes
          } else if (pendingCount < 10) {
            return SyncDirection.pushThenPull; // Normal sync for few changes
          } else {
            return SyncDirection.pullThenPush; // Pull first for many changes
          }
        }

        final config = DatumConfig<TestEntity>(
          syncDirectionResolver: resolver,
        );

        expect(config.syncDirectionResolver!(0, SyncDirection.pushThenPull), SyncDirection.pullOnly);
        expect(config.syncDirectionResolver!(5, SyncDirection.pushThenPull), SyncDirection.pushThenPull);
        expect(config.syncDirectionResolver!(15, SyncDirection.pushThenPull), SyncDirection.pullThenPush);
      });

      test('copyWith preserves syncDirectionResolver when not specified', () {
        SyncDirection? originalResolver(int pendingCount, SyncDirection defaultDirection) {
          return SyncDirection.pullOnly;
        }

        final originalConfig = DatumConfig<TestEntity>(
          syncDirectionResolver: originalResolver,
        );

        final copiedConfig = originalConfig.copyWith();

        expect(copiedConfig.syncDirectionResolver, isNotNull);
        final result = copiedConfig.syncDirectionResolver!(1, SyncDirection.pushThenPull);
        expect(result, SyncDirection.pullOnly);
      });

      test('copyWith can update syncDirectionResolver', () {
        final originalConfig = DatumConfig<TestEntity>(
          syncDirectionResolver: (pendingCount, defaultDirection) => SyncDirection.pullOnly,
        );

        SyncDirection? newResolver(int pendingCount, SyncDirection defaultDirection) {
          return SyncDirection.pushOnly;
        }

        final updatedConfig = originalConfig.copyWith(
          syncDirectionResolver: newResolver,
        );

        expect(updatedConfig.syncDirectionResolver, isNotNull);
        final result = updatedConfig.syncDirectionResolver!(1, SyncDirection.pushThenPull);
        expect(result, SyncDirection.pushOnly);
      });

      test('copyWith preserves syncDirectionResolver when null is passed (standard copyWith behavior)', () {
        SyncDirection originalResolver(int pendingCount, SyncDirection defaultDirection) => SyncDirection.pullOnly;
        final originalConfig = DatumConfig<TestEntity>(
          syncDirectionResolver: originalResolver,
        );

        // When null is passed to copyWith for a nullable field, it typically preserves the original value
        // This is standard copyWith behavior - to explicitly set to null, you'd need a different API
        final updatedConfig = originalConfig.copyWith(
          syncDirectionResolver: null,
        );

        // The original resolver should be preserved since null ?? originalResolver returns originalResolver
        expect(updatedConfig.syncDirectionResolver, isNotNull);
        final result = updatedConfig.syncDirectionResolver!(1, SyncDirection.pushThenPull);
        expect(result, SyncDirection.pullOnly);
      });

      test('equality considers syncDirectionResolver', () {
        SyncDirection resolver1(int pendingCount, SyncDirection defaultDirection) => SyncDirection.pullOnly;
        SyncDirection resolver2(int pendingCount, SyncDirection defaultDirection) => SyncDirection.pullOnly;
        SyncDirection resolver3(int pendingCount, SyncDirection defaultDirection) => SyncDirection.pushOnly;

        final config1 = DatumConfig<TestEntity>(syncDirectionResolver: resolver1);
        final config2 = DatumConfig<TestEntity>(syncDirectionResolver: resolver2);
        final config3 = DatumConfig<TestEntity>(syncDirectionResolver: resolver3);
        const config4 = DatumConfig<TestEntity>(syncDirectionResolver: null);
        const config5 = DatumConfig<TestEntity>(syncDirectionResolver: null);

        // Note: Function equality in Dart compares by reference, not by behavior
        // So configs with different function instances are not equal
        expect(config1, isNot(equals(config2))); // Different function instances
        expect(config1, isNot(equals(config3))); // Different functions
        expect(config4, equals(config5)); // Both null
        expect(config1, isNot(equals(config4))); // One null, one not
      });
    });

    group('default shouldRetry logic', () {
      // Access the default shouldRetry function via the default config.
      const config = DatumConfig();
      final shouldRetry = config.errorRecoveryStrategy.shouldRetry;

      test('returns true for a retryable NetworkException', () async {
        const exception = NetworkException(message: 'Connection timeout', isRetryable: true);
        final result = await shouldRetry(exception);
        expect(result, isTrue);
      });

      test('returns false for a non-retryable NetworkException', () async {
        const exception = NetworkException(message: 'Bad request', isRetryable: false);
        final result = await shouldRetry(exception);
        expect(result, isFalse);
      });

      test('returns false for other DatumException types', () async {
        const exception = AdapterException(
          message: 'TestAdapter',
          error: 'Read failed',
        );
        final result = await shouldRetry(exception);
        expect(result, isFalse);
      });
    });
  });
}

Future<bool> _alwaysRetry(DatumException error) async => true;
