import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';
import '../mocks/forward_bulk_writes.dart';

// This test focuses specifically on sync request strategy behavior
// and should not require 100% coverage of the entire DatumManager

class MockedLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

void main() {
  group('Sync Request Strategy Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    const userId = 'sequential-user';

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(
        const DatumSyncResult<TestEntity>(
          userId: 'fallback-user',
          duration: Duration.zero,
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        ),
      );
      registerFallbackValue(const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'));
    });

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Stub default behaviors
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => Stream.value(true));
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {});
      when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) => Future.value(null));
      when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) => Future.value(null));
      when(() => localAdapter.changeStream()).thenAnswer((_) => const Stream.empty());
      when(() => remoteAdapter.changeStream).thenAnswer((_) => const Stream.empty());

      // Adapters are mocked here, Datum and Manager are initialized in each test.
    });

    tearDown(() async {
      if (Datum.isInitialized) {
        await Datum.instance.dispose();
        Datum.resetForTesting();
      }
    });

    test('concurrent synchronize calls are executed sequentially', () async {
      // Arrange
      final syncCompleters = [Completer<void>(), Completer<void>()];
      final syncExecutionOrder = <int>[];
      final firstSyncStarted = Completer<void>();

      // Initialize Datum with the SequentialRequestStrategy
      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false, syncRequestStrategy: SequentialRequestStrategy()),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );
      if (result.isFailure()) {
        fail('Datum initialization failed: ${result.errorOrNull}');
      }
      manager = Datum.manager<TestEntity>();

      // Stub the remote adapter to be slow and record execution order.
      when(() => remoteAdapter.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async {
        if (syncExecutionOrder.isEmpty) {
          // First sync call
          syncExecutionOrder.add(1);
          firstSyncStarted.complete(); // Signal that first sync has started
          await syncCompleters[0].future; // Block until told to continue
        } else {
          // Second sync call
          syncExecutionOrder.add(2);
        }
        return [];
      });

      // Act
      // Start the first sync call
      final future1 = manager.synchronize(userId);

      // Wait for the first sync to actually start executing
      await firstSyncStarted.future;

      // Now start the second sync call
      final future2 = manager.synchronize(userId);

      // Give a small delay to ensure the second sync is queued
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Unblock the first sync. The second one should start immediately after.
      syncCompleters[0].complete();

      // Await both futures to ensure they both complete.
      final results = await Future.wait([future1, future2]);

      // Assert
      expect(syncExecutionOrder, [1, 2], reason: 'Syncs should execute in the order they were called.');
      expect(results.every((r) => !r.wasSkipped), isTrue, reason: 'No sync should be skipped.');
    });

    test('concurrent synchronize calls are skipped with SkipConcurrentStrategy', () async {
      // Arrange
      final syncCompleter = Completer<void>();

      // Initialize Datum with the SkipConcurrentStrategy
      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false, syncRequestStrategy: SkipConcurrentStrategy()),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );
      if (result.isFailure()) {
        fail('Datum initialization failed: ${result.errorOrNull}');
      }
      manager = Datum.manager<TestEntity>();

      // Stub the remote adapter to be slow.
      when(() => remoteAdapter.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async {
        // Block until told to continue to simulate a long-running sync.
        await syncCompleter.future;
        return [];
      });

      // Act
      // Fire two sync calls concurrently.
      final future1 = manager.synchronize(userId);
      // Give the first call a moment to start and set the `isSyncing` flag.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final future2 = manager.synchronize(userId);

      // Unblock the first sync.
      syncCompleter.complete();

      // Await both futures to ensure they both complete.
      final results = await Future.wait([future1, future2]);

      // Assert
      // The remote method should only be called once because the second sync is skipped.
      verify(() => remoteAdapter.readAll(userId: userId, scope: any(named: 'scope'))).called(1);

      expect(results[0].wasSkipped, isFalse, reason: 'The first sync should execute.');
      expect(results[1].wasSkipped, isTrue, reason: 'The second sync should be skipped.');
    });
  });
}
