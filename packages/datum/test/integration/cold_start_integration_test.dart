import 'package:clock/clock.dart';
import 'package:datum/datum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  group('Cold Start Integration Tests', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late DatumConnectivityChecker connectivity;
    late DatumManager<TestEntity> manager;

    setUp(() {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivity = MockConnectivityChecker();
    });

    tearDown(() async {
      await manager.dispose();
    });

    group('Cold Start Strategy: Disabled', () {
      setUp(() async {
        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(strategy: ColdStartStrategy.disabled),
        );

        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        await manager.initialize();
      });

      test('should not perform cold start sync when disabled', () async {
        // Reset cold start state for testing
        manager.coldStartManager.resetForUser('user1');

        final syncCalled = <bool>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncCalled.add(true);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
        );

        expect(result, isFalse);
        expect(syncCalled, isEmpty);
      });
    });

    group('Cold Start Strategy: Full Sync', () {
      setUp(() async {
        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(strategy: ColdStartStrategy.fullSync),
        );

        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        await manager.initialize();
      });

      test('should perform full sync on cold start', () async {
        // Reset cold start state for testing
        manager.coldStartManager.resetForUser('user1');

        final syncOptions = <DatumSyncOptions>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncOptions.add(options);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
          synchronous: true, // Use synchronous mode for testing
        );

        expect(result, isTrue);
        expect(syncOptions.length, 1);
        expect(syncOptions.first.forceFullSync, isTrue);
        expect(syncOptions.first.timeout, const Duration(seconds: 15)); // default maxDuration
      });

      test('should not perform sync on subsequent calls (not cold start)', () async {
        // First, perform a cold start sync to complete it
        await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
        );

        // Now subsequent calls should not perform sync
        final syncCalled = <bool>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncCalled.add(true);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
        );

        expect(result, isFalse);
        expect(syncCalled, isEmpty);
      });
    });

    group('Cold Start Strategy: Adaptive', () {
      setUp(() async {
        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(
            strategy: ColdStartStrategy.adaptive,
            syncThreshold: Duration(hours: 1),
          ),
        );

        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        await manager.initialize();
      });

      test('should perform sync when no previous cold start exists', () async {
        // Reset cold start state for testing
        manager.coldStartManager.resetForUser('user1');

        final syncCalled = <bool>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncCalled.add(true);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
          synchronous: true, // Use synchronous mode for testing
        );

        expect(result, isTrue);
        expect(syncCalled.length, 1);
      });

      test('should skip sync when within threshold', () async {
        // Set last cold start to recent time
        manager.coldStartManager.setLastColdStartTimeForUser('user1', clock.now().subtract(const Duration(minutes: 30)));

        final syncCalled = <bool>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncCalled.add(true);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
        );

        expect(result, isFalse);
        expect(syncCalled, isEmpty);
      });

      test('should perform sync when beyond threshold', () async {
        // Reset cold start state and set last cold start to old time
        manager.coldStartManager.resetForUser('user1');
        manager.coldStartManager.setLastColdStartTimeForUser('user1', clock.now().subtract(const Duration(hours: 2)));

        final syncCalled = <bool>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncCalled.add(true);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
          synchronous: true, // Use synchronous mode for testing
        );

        expect(result, isTrue);
        expect(syncCalled.length, 1);
      });
    });

    group('Cold Start Strategy: Incremental', () {
      setUp(() async {
        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(strategy: ColdStartStrategy.incremental),
        );

        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        await manager.initialize();
      });

      test('should perform incremental sync (no force full sync)', () async {
        // Reset cold start state for testing
        manager.coldStartManager.resetForUser('user1');

        final syncOptions = <DatumSyncOptions>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncOptions.add(options);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
          synchronous: true, // Use synchronous mode for testing
        );

        expect(result, isTrue);
        expect(syncOptions.length, 1);
        expect(syncOptions.first.forceFullSync, isFalse);
      });
    });

    group('Cold Start Strategy: Priority Based', () {
      setUp(() async {
        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(strategy: ColdStartStrategy.priorityBased),
        );

        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        await manager.initialize();
      });

      test('should perform priority-based sync', () async {
        // Reset cold start state for testing
        manager.coldStartManager.resetForUser('user1');

        final syncCalled = <bool>[];
        final result = await manager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncCalled.add(true);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
          synchronous: true, // Use synchronous mode for testing
        );

        expect(result, isTrue);
        expect(syncCalled.length, 1);
      });
    });

    group('Cold Start Configuration', () {
      test('should apply initial delay before sync', () async {
        fakeAsync((async) async {
          const config = DatumConfig<TestEntity>(
            coldStartConfig: ColdStartConfig(
              strategy: ColdStartStrategy.fullSync,
              initialDelay: Duration(milliseconds: 100),
            ),
          );

          final testManager = DatumManager<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
            connectivity: connectivity,
            datumConfig: config,
            logger: DatumLogger(enabled: false), // Disable logging for tests
          );

          await testManager.initialize();
          testManager.coldStartManager.resetForUser('user1');

          final startTime = clock.now();
          await testManager.coldStartManager.handleColdStartIfNeeded(
            'user1',
            (options) async {
              return const DatumSyncResult<TestEntity>(
                userId: 'user1',
                duration: Duration.zero,
                syncedCount: 0,
                failedCount: 0,
                conflictsResolved: 0,
                pendingOperations: [],
              );
            },
          );
          final endTime = clock.now();

          final elapsed = endTime.difference(startTime);
          expect(elapsed.inMilliseconds, greaterThanOrEqualTo(100));
        });
      });

      test('should respect max duration timeout', () async {
        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(
            strategy: ColdStartStrategy.fullSync,
            maxDuration: Duration(seconds: 30),
          ),
        );

        final testManager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        await testManager.initialize();
        testManager.coldStartManager.resetForUser('user1');

        final syncOptions = <DatumSyncOptions>[];
        await testManager.coldStartManager.handleColdStartIfNeeded(
          'user1',
          (options) async {
            syncOptions.add(options);
            return const DatumSyncResult<TestEntity>(
              userId: 'user1',
              duration: Duration.zero,
              syncedCount: 0,
              failedCount: 0,
              conflictsResolved: 0,
              pendingOperations: [],
            );
          },
          synchronous: true, // Use synchronous mode for testing
        );

        expect(syncOptions.length, 1);
        expect(syncOptions.first.timeout, const Duration(seconds: 30));
      });
    });

    group('Cold Start Error Handling', () {
      setUp(() async {
        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(strategy: ColdStartStrategy.fullSync),
        );

        manager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        await manager.initialize();
      });

      test('should not mark cold start as completed on sync failure', () async {
        fakeAsync((async) async {
          // Reset cold start state for testing
          manager.coldStartManager.resetForUser('user1');

          final exception = Exception('Sync failed');
          try {
            await manager.coldStartManager.handleColdStartIfNeeded(
              'user1',
              (options) async {
                throw exception;
              },
            ).timeout(const Duration(seconds: 40)); // Allow time for retries
            fail('Expected exception to be rethrown');
          } catch (e) {
            expect(e, same(exception));
          }

          // Advance time to allow all retries to complete
          async.elapse(const Duration(seconds: 45));

          // Cold start should still be marked as true (not completed)
          expect(manager.coldStartManager.isColdStartForUser('user1'), isTrue);
        });
      });

      test('should allow retry after failed cold start', () async {
        fakeAsync((async) async {
          // First attempt fails
          final exception = Exception('Sync failed');
          try {
            await manager.coldStartManager.handleColdStartIfNeeded(
              'user1',
              (options) async {
                throw exception;
              },
            ).timeout(const Duration(seconds: 40)); // Allow time for retries
          } catch (e) {
            // Expected
          }

          // Advance time to allow retries to complete
          async.elapse(const Duration(seconds: 20));

          // Second attempt should still try to sync
          final syncCalled = <bool>[];
          final result = await manager.coldStartManager.handleColdStartIfNeeded(
            'user1',
            (options) async {
              syncCalled.add(true);
              return const DatumSyncResult<TestEntity>(
                userId: 'user1',
                duration: Duration.zero,
                syncedCount: 0,
                failedCount: 0,
                conflictsResolved: 0,
                pendingOperations: [],
              );
            },
          );

          expect(result, isTrue);
          expect(syncCalled.length, 1);
        });
      });
    });

    group('Integration with DatumManager', () {
      test('should integrate cold start into manager initialization', () async {
        // Mock the connectivity checker to return true
        when(() => connectivity.isConnected).thenAnswer((_) async => true);

        const config = DatumConfig<TestEntity>(
          coldStartConfig: ColdStartConfig(strategy: ColdStartStrategy.fullSync),
          autoStartSync: true,
        );

        final testManager = DatumManager<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivity: connectivity,
          datumConfig: config,
          logger: DatumLogger(enabled: false), // Disable logging for tests
        );

        // Add a test user to the local adapter
        localAdapter.addLocalItem('user1', TestEntity.create('test-id', 'user1', 'test'));

        await testManager.initialize();

        // Wait for cold start sync to complete (it runs asynchronously)
        await Future.delayed(const Duration(seconds: 3));

        // Should have performed cold start sync during initialization
        expect(testManager.coldStartManager.isColdStartForUser('user1'), isFalse);
      });
    });
  });
}
