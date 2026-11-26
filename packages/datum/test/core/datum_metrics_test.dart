import 'dart:async';

import 'package:datum/datum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';
import '../mocks/forward_bulk_writes.dart';

// Use mocktail mocks instead of hand-written ones for `when()` to work.
class MockLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

// Helper to wait for a specific metric condition with timeout.
Future<void> waitForMetric(
  Datum datum,
  bool Function(DatumMetrics) condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final completer = Completer<void>();
  StreamSubscription<DatumMetrics>? subscription;
  Timer? timer;

  timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      subscription?.cancel();
      completer.completeError(TimeoutException(message: 'Metric condition not met within $timeout'));
    }
  });

  subscription = datum.metrics.listen(
    (metrics) {
      if (condition(metrics) && !completer.isCompleted) {
        timer?.cancel();
        subscription?.cancel();
        completer.complete();
      }
    },
    onError: (error) {
      if (!completer.isCompleted) {
        timer?.cancel();
        completer.completeError(error);
      }
    },
    cancelOnError: true,
  );

  try {
    await completer.future;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}

@isTest
void runMetricsTest(
  String description,
  Future<void> Function(
    Datum datum, {
    required MockLocalAdapter<TestEntity> localAdapter,
    required MockRemoteAdapter<TestEntity> remoteAdapter,
    required MockConnectivityChecker connectivityChecker,
    required FakeAsync async,
  }) testBody,
) {
  test(description, () async {
    fakeAsync((async) async {
      // ARRANGE
      final localAdapter = MockLocalAdapter<TestEntity>();
      final remoteAdapter = MockRemoteAdapter<TestEntity>();
      final mockConnectivityChecker = MockConnectivityChecker();

      // Common stubs
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {});
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localAdapter.changeStream()).thenAnswer((_) => const Stream.empty());
      when(() => remoteAdapter.changeStream).thenAnswer((_) => const Stream.empty());
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getAllUserIds()).thenAnswer((_) => Future.value([]));
      when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) => Future.value(null as DatumSyncMetadata?));
      when(() => mockConnectivityChecker.isConnected).thenAnswer((_) async => Future.value(true));

      const config = DatumConfig(schemaVersion: 0, autoStartSync: false); // Disable auto-sync for predictable tests
      final datumEither = await Datum.initialize(
        config: config,
        connectivityChecker: mockConnectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      final datum = datumEither.successOrNull;
      if (datum == null) fail('Datum initialization failed');

      try {
        await testBody(
          datum,
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
          connectivityChecker: mockConnectivityChecker,
          async: async,
        );
        // Advance time to ensure all async operations complete
        async.elapse(const Duration(milliseconds: 100));
      } finally {
        await datum.dispose();
        Datum.resetForTesting();
      }
    });
  });
}

void main() {
  // This needs to be defined at the top level for the fallback registration
  final now = DateTime.now();

  final baseEntity = TestEntity(
    id: 'conflict-entity',
    userId: 'user-metrics',
    name: 'Base',
    value: 1,
    modifiedAt: now,
    createdAt: now,
    version: 1,
  );

  setUpAll(() {
    // Register fallback values for any custom types used in `when()`
    registerFallbackValue(
      DatumSyncOperation<TestEntity>(
        id: 'fallback-op',
        userId: 'fallback-user',
        entityId: 'fallback-entity',
        type: DatumOperationType.create,
        timestamp: DateTime(0),
      ),
    );
    registerFallbackValue(const DatumConfig());
    registerFallbackValue(
      DatumConflictContext(
        userId: 'fb',
        entityId: 'fb',
        type: DatumConflictType.bothModified,
        detectedAt: DateTime(0),
      ),
    );
    registerFallbackValue(
      TestEntity(
        id: 'fb',
        userId: 'fb',
        name: 'fb',
        value: 0,
        modifiedAt: now,
        createdAt: now,
        version: 1,
      ),
    );
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
    registerFallbackValue(
      const DatumSyncMetadata(userId: 'fallback-user', dataHash: 'fallback-hash'),
    );
  });

  runMetricsTest(
    'totalSyncOperations increments on sync start',
    (datum, {required localAdapter, required remoteAdapter, required connectivityChecker, required async}) async {
      expect(datum.currentMetrics.totalSyncOperations, 0);

      await datum.synchronize('user-metrics');
      await waitForMetric(datum, (m) => m.totalSyncOperations == 1);
      expect(datum.currentMetrics.totalSyncOperations, 1);

      await datum.synchronize('user-metrics');
      await waitForMetric(datum, (m) => m.totalSyncOperations == 2);
      expect(datum.currentMetrics.totalSyncOperations, 2);
    },
  );

  runMetricsTest(
    'successfulSyncs increments on successful completion',
    (datum, {required localAdapter, required remoteAdapter, required connectivityChecker, required async}) async {
      expect(datum.currentMetrics.successfulSyncs, 0);
      await datum.synchronize('user-metrics');
      await waitForMetric(datum, (m) => m.successfulSyncs == 1);
      expect(datum.currentMetrics.successfulSyncs, 1);
    },
  );

  runMetricsTest(
    'failedSyncs increments on sync error',
    (datum, {required localAdapter, required remoteAdapter, required connectivityChecker, required async}) async {
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'))).thenThrow(Exception('Remote fetch failed'));
      expect(datum.currentMetrics.failedSyncs, 0);

      await expectLater(datum.synchronize('user-metrics'), throwsException);

      await waitForMetric(datum, (m) => m.failedSyncs == 1);
      expect(datum.currentMetrics.failedSyncs, 1);
    },
  );

  runMetricsTest(
    'activeUsers tracks unique user IDs',
    (datum, {required localAdapter, required remoteAdapter, required connectivityChecker, required async}) async {
      expect(datum.currentMetrics.activeUsers, isEmpty);

      await datum.synchronize('user-1');
      await waitForMetric(datum, (m) => m.activeUsers.contains('user-1'));
      expect(datum.currentMetrics.activeUsers, {'user-1'});

      await datum.synchronize('user-2');
      await waitForMetric(datum, (m) => m.activeUsers.contains('user-2'));
      expect(datum.currentMetrics.activeUsers, {'user-1', 'user-2'});

      await datum.synchronize('user-1');
      // Advance time for any potential metric updates to propagate
      async.elapse(const Duration(milliseconds: 50));
      // No new user, so set should remain the same
      expect(datum.currentMetrics.activeUsers, {'user-1', 'user-2'});
    },
  );

  runMetricsTest(
    'userSwitchCount increments on user switch event',
    (datum, {required localAdapter, required remoteAdapter, required connectivityChecker, required async}) async {
      expect(datum.currentMetrics.userSwitchCount, 0);

      // First, synchronize with one user to establish the "last active user".
      await datum.synchronize('user-A');
      await waitForMetric(datum, (m) => m.activeUsers.contains('user-A'));
      expect(datum.currentMetrics.userSwitchCount, 0);

      // Now, synchronize with a different user. This will trigger the UserSwitchedEvent.
      await datum.synchronize('user-B');
      await waitForMetric(datum, (m) => m.userSwitchCount == 1);

      expect(datum.currentMetrics.userSwitchCount, 1);
    },
  );

  runMetricsTest(
    'conflictsDetected and conflictsResolvedAutomatically are updated on conflict',
    (datum, {required localAdapter, required remoteAdapter, required connectivityChecker, required async}) async {
      final localEntity = baseEntity.copyWith(name: 'Local Change', version: 2);
      final remoteEntity = baseEntity.copyWith(name: 'Remote Change', version: 3);

      when(() => remoteAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => [remoteEntity]);
      when(() => localAdapter.readByIds(any(that: contains(remoteEntity.id)), userId: any(named: 'userId'))).thenAnswer((_) async => {remoteEntity.id: localEntity});
      when(() => localAdapter.update(any())).thenAnswer((_) async {});

      expect(datum.currentMetrics.conflictsDetected, 0);
      expect(datum.currentMetrics.conflictsResolvedAutomatically, 0);

      await datum.synchronize('user-metrics');
      await waitForMetric(datum, (m) => m.conflictsDetected == 1);

      expect(datum.currentMetrics.conflictsDetected, 1);
      expect(datum.currentMetrics.conflictsResolvedAutomatically, 1);
    },
  );

  runMetricsTest(
    'metrics stream emits new snapshots on change',
    (datum, {required localAdapter, required remoteAdapter, required connectivityChecker, required async}) async {
      final metricsReceived = <DatumMetrics>[];
      final subscription = datum.metrics.listen(metricsReceived.add);

      await datum.synchronize('user-metrics');

      // Wait for sync to complete and metrics to update
      await waitForMetric(datum, (m) => m.successfulSyncs == 1);

      // Give a moment for all metrics to be emitted
      async.elapse(const Duration(milliseconds: 100));
      await subscription.cancel();

      // Verify we received the expected sequence
      expect(metricsReceived.length, greaterThanOrEqualTo(3));
      expect(metricsReceived.first.totalSyncOperations, 0);
      expect(metricsReceived.last.totalSyncOperations, 1);
      expect(metricsReceived.last.successfulSyncs, 1);
    },
  );

  test('toString includes basic sync information', () {
    const metrics = DatumMetrics(
      totalSyncOperations: 5,
      successfulSyncs: 3,
      failedSyncs: 2,
      conflictsDetected: 1,
      conflictsResolvedAutomatically: 1,
      activeUsers: {'user1', 'user2'},
      totalBytesPushed: 1024,
      totalBytesPulled: 2048,
    );

    final result = metrics.toString();
    expect(result, contains('Syncs: 5'));
    expect(result, contains('✅: 3'));
    expect(result, contains('❌: 2'));
    expect(result, contains('Conflicts: 1'));
    expect(result, contains('Resolved: 1'));
    expect(result, contains('Users: 2'));
    expect(result, contains('Pushed: 1.00 KB'));
    expect(result, contains('Pulled: 2.00 KB'));
  });

  test('toString excludes performance info when not available', () {
    const metrics = DatumMetrics(
      totalSyncOperations: 3,
      successfulSyncs: 3,
      failedSyncs: 0,
    );

    final result = metrics.toString();
    expect(result, contains('Syncs: 3'));
    expect(result, contains('✅: 3'));
    expect(result, contains('❌: 0'));
  });
}
