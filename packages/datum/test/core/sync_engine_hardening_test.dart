import 'dart:async';

import 'package:datum/datum.dart';
import 'package:datum/source/core/manager/cold_start_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

/// Merges divergent copies into a deterministic 'merged' entity.
class MergingResolver implements DatumConflictResolver<TestEntity> {
  @override
  String get name => 'TestMerge';

  @override
  FutureOr<DatumConflictResolution<TestEntity>> resolve({TestEntity? local, TestEntity? remote, required DatumConflictContext context}) {
    if (local == null || remote == null) {
      return local != null ? DatumConflictResolution.useLocal(local) : DatumConflictResolution.useRemote(remote!);
    }
    final merged = TestEntity(
      id: local.id,
      userId: local.userId,
      name: 'merged',
      value: local.value + remote.value,
      modifiedAt: DateTime(2031),
      createdAt: local.createdAt,
      version: (local.version > remote.version ? local.version : remote.version) + 1,
    );
    return DatumConflictResolution.merge(merged);
  }
}

MockConnectivityChecker _connected() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}

void main() {
  group('DatumConfig.sanitizedForIsolate (isolate-sync sanitization bug)', () {
    test('actually clears unsendable callbacks (copyWith could not)', () {
      final config = DatumConfig<DatumEntityInterface>(
        initialUserId: () async => 'u1',
        onMigrationError: (e, s) async {},
        syncDirectionResolver: (pending, dir) => dir,
        defaultConflictResolver: LastWriteWinsResolver<DatumEntityInterface>(),
        schemaVersion: 3,
        remoteSyncBatchSize: 42,
      );

      // The old code used copyWith(x: null), which keeps the old value — prove
      // that copyWith alone cannot clear the callbacks…
      final viaCopyWith = config.copyWith<TestEntity>(
        onMigrationError: null,
        syncDirectionResolver: null,
      );
      expect(viaCopyWith.onMigrationError, isNotNull, reason: 'copyWith(null) keeps the value');
      expect(viaCopyWith.syncDirectionResolver, isNotNull);

      // …and that the dedicated sanitizer does clear them.
      final sanitized = config.sanitizedForIsolate<TestEntity>();
      expect(sanitized.initialUserId, isNull);
      expect(sanitized.onMigrationError, isNull);
      expect(sanitized.syncDirectionResolver, isNull);

      // Non-callback settings survive, and the resolver crosses the generic
      // boundary instead of being dropped.
      expect(sanitized.schemaVersion, 3);
      expect(sanitized.remoteSyncBatchSize, 42);
      expect(sanitized.defaultConflictResolver, isA<DatumConflictResolver<TestEntity>>());
    });
  });

  group('SequentialRequestStrategy shared-queue dispose (hang bug)', () {
    test('const instances are canonicalized to one shared instance', () {
      const a = SequentialRequestStrategy();
      const b = SequentialRequestStrategy();
      expect(identical(a, b), isTrue, reason: 'default-config managers share one strategy/queue');
    });

    test('disposing one user of the shared strategy does not drop queued jobs', () async {
      // Two "managers" sharing the canonical const instance (the default).
      const strategyA = SequentialRequestStrategy();
      const strategyB = SequentialRequestStrategy();

      // B starts a slow job, then queues a second one behind it.
      final slow = strategyB.execute<int>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return 1;
        },
        isSyncInProgress: () => false,
        onSkipped: () => -1,
      );
      final queued = strategyB.execute<int>(
        () async => 2,
        isSyncInProgress: () => false,
        onSkipped: () => -1,
      );

      // A is disposed while B's second job is still waiting in the queue.
      // Previously this stopped the SHARED queue: `queued` never completed.
      strategyA.dispose();

      expect(await slow, 1);
      expect(await queued, 2); // hung forever before the fix
    });

    test('strategy still works after its own dispose (new jobs run)', () async {
      const strategy = SequentialRequestStrategy();
      strategy.dispose();
      final result = await strategy.execute<int>(
        () async => 7,
        isSyncInProgress: () => false,
        onSkipped: () => -1,
      );
      expect(result, 7);
    });

    test('remote content change with SAME count is pulled, not skipped (testhash bug)', () async {
      final local = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
      final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: _connected(),
        datumConfig: const DatumConfig<TestEntity>(),
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      // 1. Device A creates and syncs one entity. Metadata (with a real content
      //    hash) is written to both sides.
      await manager.push(item: TestEntity.create('e1', 'u1', 'original'), userId: 'u1');
      await manager.synchronize('u1');

      // 2. Device B edits the SAME entity remotely (count unchanged!) and
      //    updates the remote metadata the way its own engine would — with a
      //    hash of the new content.
      final edited = TestEntity(
        id: 'e1',
        userId: 'u1',
        name: 'edited-by-device-b',
        value: 0,
        modifiedAt: DateTime(2030),
        createdAt: DateTime(2024),
        version: 99,
      );
      remote.addRemoteItem('u1', edited);
      final newHash = const DatumHashGenerator().hashEntitiesUnordered([edited]);
      remote.setRemoteMetadata(
        'u1',
        DatumSyncMetadata(
          userId: 'u1',
          dataHash: newHash,
          entityCounts: {'TestEntity': DatumEntitySyncDetails(count: 1, hash: newHash)},
        ),
      );

      // 3. Device A syncs again with no pending ops. With the old hardcoded
      //    'testhash' metadata this compared equal (hash placeholder + same
      //    count) and the sync was SKIPPED — the edit was never pulled and the
      //    devices diverged permanently.
      final result = await manager.synchronize('u1');
      expect(result.wasSkipped, isFalse, reason: 'content hash differs, so sync must run');
      expect((await manager.read('e1', userId: 'u1'))?.name, 'edited-by-device-b');

      // 4. And with both sides genuinely identical, the skip fast-path still
      //    works (real hashes now match).
      final third = await manager.synchronize('u1');
      expect(third.wasSkipped, isTrue, reason: 'no changes anywhere -> metadata matches');
    });

    test('merge resolution converges: winner is pushed to remote, conflict does not re-fire', () async {
      final local = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
      final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: _connected(),
        datumConfig: DatumConfig<TestEntity>(defaultConflictResolver: MergingResolver()),
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      // Divergent copies with NO pending ops (both edited independently).
      await local.create(TestEntity(id: 'e1', userId: 'u1', name: 'local-edit', value: 1, modifiedAt: DateTime(2030), createdAt: DateTime(2024), version: 2));
      remote.addRemoteItem('u1', TestEntity(id: 'e1', userId: 'u1', name: 'remote-edit', value: 10, modifiedAt: DateTime(2030, 2), createdAt: DateTime(2024), version: 3));

      final first = await manager.synchronize('u1');
      expect(first.conflictsResolved, 1);
      expect((await manager.read('e1', userId: 'u1'))?.name, 'merged');
      // The merged winner was queued for push (previously nothing was queued,
      // so the remote never converged and the merge re-fired every sync).
      expect(first.pendingOperations, isNotEmpty);

      final second = await manager.synchronize('u1'); // delivers the merged winner
      expect(second.failedCount, 0);
      expect((await remote.read('e1', userId: 'u1'))?.name, 'merged', reason: 'remote must converge on the merged value');

      final third = await manager.synchronize('u1');
      expect(third.conflictsResolved, 0, reason: 'the same conflict must not re-fire forever');
    });

    test('pause mid-sync yields a cancelled result, keeps paused status, no metadata stamp', () async {
      final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson)..setProcessingDelay(const Duration(milliseconds: 120));
      final manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: _connected(),
        datumConfig: const DatumConfig<TestEntity>(),
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      // Two pending pushes, each taking ~120ms on the remote.
      await manager.push(item: TestEntity.create('e1', 'u1', 'A'), userId: 'u1');
      await manager.push(item: TestEntity.create('e2', 'u1', 'B'), userId: 'u1');

      final syncFuture = manager.synchronize('u1');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      manager.pauseSync(); // interrupts the running cycle

      final result = await syncFuture;
      // Previously this reported a successful completion: status was forced
      // back to idle, metadata was stamped as fully synced, and a completed
      // event was emitted for the truncated cycle.
      expect(result.wasCancelled, isTrue);
      expect(manager.currentStatus.status, DatumSyncStatus.paused, reason: 'paused status must not be overwritten with idle');
      expect(await local.getSyncMetadata('u1'), isNull, reason: 'partial cycle must not be stamped as synced');
    });

    test('config.syncTimeout is enforced: hung remote surfaces a typed timeout', () async {
      final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson)..setProcessingDelay(const Duration(seconds: 30));
      final manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: _connected(),
        datumConfig: const DatumConfig<TestEntity>(syncTimeout: Duration(milliseconds: 200)),
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      await manager.push(item: TestEntity.create('e1', 'u1', 'A'), userId: 'u1');

      // Previously syncTimeout was configured everywhere but never applied —
      // this await would block for the full 30s remote delay.
      await expectLater(
        manager.synchronize('u1'),
        throwsA(isA<DatumException>().having((e) => e.code, 'code', DatumExceptionCode.timeout)),
      );
      expect(manager.currentStatus.status, DatumSyncStatus.failed);
    });

    test('errors are surfaced after retries are exhausted', () async {
      const strategy = SequentialRequestStrategy(retryCount: 1);
      var attempts = 0;
      final future = strategy.execute<int>(
        () async {
          attempts++;
          throw StateError('always fails');
        },
        isSyncInProgress: () => false,
        onSkipped: () => -1,
      );
      await expectLater(future, throwsStateError);
      expect(attempts, greaterThanOrEqualTo(1));
    });
  });

  group('Batch retry parity (transient batch failure must not drop operations)', () {
    test('retryable batch failure re-queues ops with retryCount+1 and succeeds next sync', () async {
      final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: _connected(),
        datumConfig: const DatumConfig<TestEntity>(remoteSyncBatchSize: 2),
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      // Two consecutive creates -> grouped into ONE batch of 2.
      await manager.push(item: TestEntity.create('e1', 'u1', 'A'), userId: 'u1');
      await manager.push(item: TestEntity.create('e2', 'u1', 'B'), userId: 'u1');

      // The remote itself fails with a retryable NetworkException (connectivity
      // checker still reports online, so the push is attempted). pushOnly keeps
      // the offline mock's pull path out of the picture.
      remote.isConnectedValue = false;
      await manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));

      // Previously the WHOLE batch was dequeued permanently on any failure —
      // a single offline blip lost both operations forever.
      final pending = await manager.getPendingOperations('u1');
      expect(pending, hasLength(2), reason: 'retryable batch failure must keep the ops queued');
      expect(pending.map((op) => op.retryCount).toSet(), {1});

      // Connectivity returns: the batch pushes cleanly on the next sync.
      remote.isConnectedValue = true;
      final second = await manager.synchronize('u1');
      expect(second.failedCount, 0);
      expect(await manager.getPendingOperations('u1'), isEmpty);
      expect(await remote.read('e1', userId: 'u1'), isNotNull);
      expect(await remote.read('e2', userId: 'u1'), isNotNull);
    });
  });

  group('Backoff and strategy guards', () {
    test('ExponentialBackoff clamps to maxDelay instead of overflowing negative/throwing', () {
      const backoff = ExponentialBackoff(maxDelay: Duration(minutes: 5));
      // Previously ~attempt 45+ wrapped the int64 microsecond field negative
      // (a negative delay defeats the cap → tight retry loop), and very large
      // attempts made pow() infinite and round() throw.
      for (final attempt in [1, 10, 45, 60, 500, 2000]) {
        final delay = backoff.getDelay(attempt);
        expect(delay.isNegative, isFalse, reason: 'attempt $attempt must not go negative');
        expect(delay <= const Duration(minutes: 5), isTrue, reason: 'attempt $attempt must respect maxDelay');
      }
      expect(backoff.getDelay(2000), const Duration(minutes: 5));
    });

    test('ParallelStrategy(batchSize: 0) terminates and processes every operation', () async {
      const strategy = ParallelStrategy(batchSize: 0, failFast: false);
      final ops = List.generate(
        3,
        (i) => DatumSyncOperation<TestEntity>(
          id: 'op$i',
          userId: 'u1',
          entityId: 'e$i',
          type: DatumOperationType.create,
          timestamp: DateTime(2024),
          data: TestEntity.create('e$i', 'u1', 'N$i'),
        ),
      );
      final processed = <String>[];
      // Previously batchSize <= 0 never advanced the loop index -> infinite loop.
      await strategy.execute<TestEntity>(
        ops,
        (op) async => processed.add(op.id),
        () => false,
        (done, total) {},
      );
      expect(processed, hasLength(3));
    });
  });

  group('ColdStartManager concurrency (TOCTOU)', () {
    test('two racing cold-start calls launch exactly one sync', () async {
      final coldStart = ColdStartManager(const ColdStartConfig(strategy: ColdStartStrategy.fullSync), logger: DatumLogger(enabled: false));
      var syncRuns = 0;
      Future<DatumSyncResult<TestEntity>> syncFn(DatumSyncOptions options) async {
        syncRuns++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const DatumSyncResult<TestEntity>(
          userId: 'u1',
          duration: Duration.zero,
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        );
      }

      // Fire both BEFORE awaiting: previously both passed the in-progress
      // guard during the awaited strategy evaluation and started two
      // concurrent cold-start syncs for the same user.
      final first = coldStart.handleColdStartIfNeeded('u1', syncFn, synchronous: true);
      final second = coldStart.handleColdStartIfNeeded('u1', syncFn, synchronous: true);
      await Future.wait([first, second]);

      expect(syncRuns, 1);
    });
  });
}
