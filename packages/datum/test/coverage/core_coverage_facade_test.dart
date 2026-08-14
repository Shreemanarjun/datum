import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../core/non_relational_test_entity.dart';
import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class _RecordingGlobalObserver extends GlobalDatumObserver {
  int syncStartCount = 0;
  final List<DatumSyncResult> syncEndResults = [];

  @override
  void onSyncStart() {
    syncStartCount++;
  }

  @override
  void onSyncEnd(DatumSyncResult result) {
    syncEndResults.add(result);
  }
}

/// A local adapter whose sync-metadata lookup can be made to fail on demand.
class _FlakyMetadataAdapter extends MockLocalAdapter<NonRelationalTestEntity> {
  bool throwOnGetMetadata = false;

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    if (throwOnGetMetadata) {
      throw StateError('metadata unavailable');
    }
    return super.getSyncMetadata(userId);
  }
}

MockConnectivityChecker _connectivity() {
  final checker = MockConnectivityChecker();
  when(() => checker.isConnected).thenAnswer((_) async => true);
  when(() => checker.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return checker;
}

Future<bool> _retryRetryableNetwork(DatumException error) async => error is NetworkException && error.isRetryable;

void main() {
  tearDown(() async {
    if (Datum.instanceOrNull != null) {
      await Datum.instance.dispose();
    }
    Datum.resetForTesting();
  });

  group('Datum facade with no registered managers', () {
    test('getLastSyncTime and getUnifiedSyncMetadata return null', () async {
      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: _connectivity(),
      );
      final datum = result.getSuccess();

      expect(await datum.getLastSyncTime('u1'), isNull);
      expect(await datum.getUnifiedSyncMetadata('u1'), isNull);
    });
  });

  group('Datum facade with registered managers', () {
    late MockLocalAdapter<TestEntity> localA;
    late MockRemoteAdapter<TestEntity> remoteA;
    late _FlakyMetadataAdapter localB;
    late MockRemoteAdapter<NonRelationalTestEntity> remoteB;
    late _RecordingGlobalObserver observer;
    late Datum datum;

    setUp(() async {
      localA = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      remoteA = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      localB = _FlakyMetadataAdapter();
      remoteB = MockRemoteAdapter<NonRelationalTestEntity>();
      observer = _RecordingGlobalObserver();

      final result = await Datum.initialize(
        config: const DatumConfig(
          enableLogging: false,
          errorRecoveryStrategy: DatumErrorRecoveryStrategy(
            shouldRetry: _retryRetryableNetwork,
            maxRetries: 1,
          ),
        ),
        connectivityChecker: _connectivity(),
        observers: [observer],
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localA,
            remoteAdapter: remoteA,
          ),
          DatumRegistration<NonRelationalTestEntity>(
            localAdapter: localB,
            remoteAdapter: remoteB,
          ),
        ],
      );
      datum = result.getSuccess();
    });

    test('addObserver registers an additional global observer', () {
      final extra = _RecordingGlobalObserver();
      datum.addObserver(extra);
      expect(datum.globalObservers, contains(extra));
      expect(datum.globalObservers, contains(observer));
    });

    test('refreshStreams completes across all managers', () async {
      await expectLater(datum.refreshStreams(), completes);
    });

    test('getColdStartActiveUsers reflects tracked cold-start users', () {
      expect(datum.getColdStartActiveUsers<TestEntity>(), isEmpty);
      datum.resetColdStartForUser<TestEntity>('cold-user');
      expect(datum.getColdStartActiveUsers<TestEntity>(), {'cold-user'});
    });

    test('cascadeDelete delegates to the manager and reports missing entities', () async {
      final result = await datum.cascadeDelete<TestEntity>(
        id: 'missing-id',
        userId: 'u1',
      );

      expect(result.success, isFalse);
      expect(result.entity, isNull);
      expect(result.errors, contains(contains('does not exist')));
    });

    test('deleteCascade returns a fluent builder bound to the entity manager', () {
      final builder = datum.deleteCascade<TestEntity>('some-id');
      expect(builder, isA<CascadeDeleteBuilder<TestEntity>>());
    });

    test('concurrent global synchronize is skipped and observers are notified', () async {
      final first = datum.synchronize('u-sync');
      final second = datum.synchronize('u-sync');

      final skipped = await second;
      expect(skipped.wasSkipped, isTrue);

      final completed = await first;
      expect(completed.wasSkipped, isFalse);

      // Global observers are notified for the sync that actually ran.
      expect(observer.syncStartCount, greaterThanOrEqualTo(1));
      expect(observer.syncEndResults, isNotEmpty);
    });

    test('a completed sync with permanent failures increments failedSyncs metrics', () async {
      final manager = Datum.manager<TestEntity>();
      const pushOnly = DatumSyncOptions(direction: SyncDirection.pushOnly);

      remoteA.isConnectedValue = false;

      // First operation: fails retryable, gets re-queued (sync itself succeeds).
      await manager.push(item: TestEntity.create('a1', 'u1', 'A'), userId: 'u1');
      final firstSync = await manager.synchronize('u1', options: pushOnly);
      expect(firstSync.failedCount, 0);

      // Second operation joins the first in a batch. The batch failure is
      // retryable, but 'a1' has exhausted its retries, so it fails permanently
      // while 'b1' is re-queued — the sync completes with failedCount > 0.
      await manager.push(item: TestEntity.create('b1', 'u1', 'B'), userId: 'u1');
      expect(await manager.getPendingCount('u1'), 2);

      final completedWithFailure = datum.events
          .firstWhere(
            (event) => event is DatumSyncCompletedEvent && event.result.failedCount > 0,
          )
          .timeout(const Duration(seconds: 5));

      final secondSync = await manager.synchronize('u1', options: pushOnly);
      expect(secondSync.failedCount, 1);

      await completedWithFailure;
      await Future<void>.delayed(Duration.zero);

      expect(datum.currentMetrics.failedSyncs, 1);
      expect(datum.currentMetrics.activeUsers, contains('u1'));
    });

    test('getLastSyncTime returns the most recent time across managers and survives failures', () async {
      final older = DateTime(2024, 1, 1);
      final newer = DateTime(2024, 6, 1);

      await localA.updateSyncMetadata(
        DatumSyncMetadata(userId: 'u1', lastSyncTime: older),
        'u1',
      );
      await localB.updateSyncMetadata(
        DatumSyncMetadata(userId: 'u1', lastSyncTime: newer),
        'u1',
      );

      expect(await datum.getLastSyncTime('u1'), newer);

      // When one manager's metadata lookup fails, the others still contribute.
      localB.throwOnGetMetadata = true;
      expect(await datum.getLastSyncTime('u1'), older);
    });

    test('getUnifiedSyncMetadata returns null when no manager has metadata', () async {
      expect(await datum.getUnifiedSyncMetadata('unknown-user'), isNull);
    });

    test('getUnifiedSyncMetadata merges counts, devices and conflicts across managers', () async {
      final older = DateTime(2024, 1, 1);
      final newer = DateTime(2024, 6, 1);
      final deviceSeenA = DateTime(2024, 2, 2);
      final deviceSeenB = DateTime(2024, 5, 5);

      await localA.updateSyncMetadata(
        DatumSyncMetadata(
          userId: 'u1',
          lastSyncTime: older,
          syncStatus: SyncStatus.synced,
          conflictCount: 1,
          entityCounts: const {
            'TestEntity': DatumEntitySyncDetails(count: 2),
          },
          devices: {'device-a': deviceSeenA},
        ),
        'u1',
      );
      await localB.updateSyncMetadata(
        DatumSyncMetadata(
          userId: 'u1',
          lastSyncTime: newer,
          syncStatus: SyncStatus.failed,
          conflictCount: 2,
          entityCounts: const {
            'NonRelationalTestEntity': DatumEntitySyncDetails(count: 5),
          },
          devices: {'device-b': deviceSeenB},
        ),
        'u1',
      );

      final unified = await datum.getUnifiedSyncMetadata('u1');

      expect(unified, isNotNull);
      // The most recent metadata is the base.
      expect(unified!.lastSyncTime, newer);
      // Any failed manager makes the overall status failed.
      expect(unified.syncStatus, SyncStatus.failed);
      // Entity counts and devices are merged from all managers.
      expect(unified.entityCounts!.keys, containsAll(['TestEntity', 'NonRelationalTestEntity']));
      expect(unified.devices!.keys, containsAll(['device-a', 'device-b']));
      // Conflict counts are summed.
      expect(unified.conflictCount, 3);
    });

    test('getUnifiedSyncMetadata derives syncing, conflict, pending, neverSynced and synced statuses', () async {
      Future<void> setStatuses(DatumSyncMetadata a, DatumSyncMetadata b) async {
        await localA.updateSyncMetadata(a, 'u1');
        await localB.updateSyncMetadata(b, 'u1');
      }

      final t = DateTime(2024, 3, 3);

      // syncing wins over everything except failed.
      await setStatuses(
        DatumSyncMetadata(userId: 'u1', lastSyncTime: t, syncStatus: SyncStatus.synced),
        const DatumSyncMetadata(userId: 'u1', syncStatus: SyncStatus.syncing),
      );
      expect((await datum.getUnifiedSyncMetadata('u1'))!.syncStatus, SyncStatus.syncing);

      // conflicts win when nothing is failed or syncing.
      await setStatuses(
        DatumSyncMetadata(userId: 'u1', lastSyncTime: t, syncStatus: SyncStatus.synced, conflictCount: 4),
        const DatumSyncMetadata(userId: 'u1', syncStatus: SyncStatus.synced),
      );
      final conflicted = await datum.getUnifiedSyncMetadata('u1');
      expect(conflicted!.syncStatus, SyncStatus.conflict);
      expect(conflicted.conflictCount, 4);

      // pending changes surface as pending.
      await setStatuses(
        DatumSyncMetadata(
          userId: 'u1',
          lastSyncTime: t,
          syncStatus: SyncStatus.synced,
          entityCounts: const {
            'TestEntity': DatumEntitySyncDetails(count: 1, pendingChanges: 3),
          },
        ),
        const DatumSyncMetadata(userId: 'u1', syncStatus: SyncStatus.synced),
      );
      expect((await datum.getUnifiedSyncMetadata('u1'))!.syncStatus, SyncStatus.pending);

      // all neverSynced -> neverSynced.
      await setStatuses(
        const DatumSyncMetadata(userId: 'u1'),
        const DatumSyncMetadata(userId: 'u1'),
      );
      expect((await datum.getUnifiedSyncMetadata('u1'))!.syncStatus, SyncStatus.neverSynced);

      // everything clean and synced -> synced.
      await setStatuses(
        DatumSyncMetadata(userId: 'u1', lastSyncTime: t, syncStatus: SyncStatus.synced),
        const DatumSyncMetadata(userId: 'u1', syncStatus: SyncStatus.synced),
      );
      expect((await datum.getUnifiedSyncMetadata('u1'))!.syncStatus, SyncStatus.synced);
    });

    test('getUnifiedSyncMetadata skips managers whose metadata lookup fails', () async {
      final t = DateTime(2024, 4, 4);
      await localA.updateSyncMetadata(
        DatumSyncMetadata(userId: 'u1', lastSyncTime: t, syncStatus: SyncStatus.synced),
        'u1',
      );
      localB.throwOnGetMetadata = true;

      final unified = await datum.getUnifiedSyncMetadata('u1');
      expect(unified, isNotNull);
      expect(unified!.lastSyncTime, t);
      expect(unified.syncStatus, SyncStatus.synced);
    });
  });

  group('connectivity monitoring', () {
    test('logs an error when the connectivity stream fails', () async {
      final sink = CollectingLogSink();
      final logger = DatumLogger(colors: false, sink: sink);

      final checker = MockConnectivityChecker();
      when(() => checker.isConnected).thenAnswer((_) async => true);
      when(() => checker.onStatusChange).thenAnswer(
        (_) => Stream<bool>.error(StateError('connectivity backend crashed')),
      );

      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: checker,
        logger: logger,
      );
      expect(result.isSuccess(), isTrue);

      // Let the stream error propagate to the subscription's error handler.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        sink.messages.join('\n'),
        contains('Error monitoring connectivity changes'),
      );
    });
  });
}
