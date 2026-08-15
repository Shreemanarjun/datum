/// Sync-engine correctness (2026-08 audit fixes):
///
/// 1. The delta watermark derives from the DATA — the max remote
///    `modifiedAt` seen in a pull is persisted as `serverTimestamp` — never
///    from this device's wall clock stamped at end-of-cycle (clock skew or a
///    long push phase silently skipped rows forever).
/// 2. A retryably-failed operation blocks LATER queued operations for the
///    same entity within the cycle, so replay order is preserved (no remote
///    regression / delete resurrection).
/// 3. A failed batch falls back to per-operation processing: one
///    already-deleted id must not cancel sibling deletions.
/// 4. A cursor staged by an aborted pull is never persisted by a later
///    push-only cycle.
/// 5. The manager's change-echo dedupe keys on CONTENT (id+version+
///    modifiedAt): its own write echoes are dropped (no double-run of
///    pre-save middleware, no duplicate queue ops) while a genuine external
///    change arriving within the cache window is still applied.
library;

import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart' as functional;
import '../mocks/mock_connectivity_checker.dart';
import '../test_utils/test_datum_entity.dart';

class MockLocalAdapter extends Mock implements LocalAdapter<TestDatumEntity> {}

class MockRemoteAdapter extends Mock implements RemoteAdapter<TestDatumEntity> {}

class MockDeltaRemoteAdapter extends Mock implements RemoteAdapter<TestDatumEntity>, DeltaSyncCapable<TestDatumEntity> {}

class MockCursorRemoteAdapter extends Mock implements RemoteAdapter<TestDatumEntity>, CursorSyncCapable<TestDatumEntity> {}

class MockQueueManager extends Mock implements QueueManager<TestDatumEntity> {}

TestDatumEntity entity(String id, {String value = 'v', DateTime? modifiedAt, int version = 1}) => TestDatumEntity(
      id: id,
      userId: 'u1',
      value: value,
      createdAt: DateTime.utc(2026, 1, 1),
      modifiedAt: modifiedAt ?? DateTime.utc(2026, 1, 1),
      version: version,
    );

DatumSyncOperation<TestDatumEntity> op(
  String opId,
  String entityId,
  DatumOperationType type, {
  TestDatumEntity? data,
  int retryCount = 0,
}) =>
    DatumSyncOperation<TestDatumEntity>(
      id: opId,
      userId: 'u1',
      type: type,
      entityId: entityId,
      data: data ?? entity(entityId),
      timestamp: DateTime.utc(2026, 1, 1),
      retryCount: retryCount,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const DatumQuery());
    registerFallbackValue(entity('fallback'));
    registerFallbackValue(const DatumSyncMetadata(userId: 'u1'));
    registerFallbackValue(op('fallback-op', 'fallback', DatumOperationType.create));
    registerFallbackValue(DatumSyncResult<TestDatumEntity>.skipped('u1', 0));
  });

  group('engine', () {
    late MockLocalAdapter local;
    late MockQueueManager queue;
    late MockConnectivityChecker connectivity;
    late DatumSyncMetadata? storedMetadata;

    DatumSyncEngine<TestDatumEntity> buildEngine(RemoteAdapter<TestDatumEntity> remote) => DatumSyncEngine<TestDatumEntity>(
          localAdapter: local,
          remoteAdapter: remote,
          conflictResolver: LastWriteWinsResolver<TestDatumEntity>(),
          queueManager: queue,
          conflictDetector: DatumConflictDetector<TestDatumEntity>(),
          logger: DatumLogger(enabled: false),
          config: const DatumConfig(),
          connectivityChecker: connectivity,
          eventController: StreamController<DatumSyncEvent<TestDatumEntity>>.broadcast(),
          statusSubject: BehaviorSubject.seeded(DatumSyncStatusSnapshot.initial('u1')),
          metadataSubject: BehaviorSubject.seeded(const DatumSyncMetadata(userId: 'u1')),
          isolateHelper: const IsolateHelper(),
          localObservers: [],
          globalObservers: [],
          deviceId: 'device-1',
        );

    setUp(() {
      local = MockLocalAdapter();
      queue = MockQueueManager();
      connectivity = MockConnectivityChecker();
      storedMetadata = null;

      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => queue.getPending(any())).thenAnswer((_) async => []);
      when(() => queue.getPendingCount(any())).thenAnswer((_) async => 0);
      when(() => queue.dequeue(any())).thenAnswer((_) async {});
      when(() => queue.update(any())).thenAnswer((_) async {});
      when(() => local.getSyncMetadata(any())).thenAnswer((_) async => storedMetadata);
      when(() => local.updateSyncMetadata(any(), any())).thenAnswer((invocation) async {
        storedMetadata = invocation.positionalArguments[0] as DatumSyncMetadata;
      });
      when(() => local.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => local.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
      when(() => local.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => local.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {});
      when(() => local.create(any())).thenAnswer((_) async {});
      when(() => local.update(any())).thenAnswer((_) async {});
    });

    test('delta watermark comes from remote data, not this device\'s clock', () async {
      final remote = MockDeltaRemoteAdapter();
      final remoteStamp = DateTime.utc(2026, 8, 1, 12);
      when(() => remote.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => remote.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      // First sync: no watermark yet → full pull.
      when(() => remote.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => [entity('e1', modifiedAt: remoteStamp)]);

      final engine = buildEngine(remote);
      await engine.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      expect(storedMetadata?.serverTimestamp, remoteStamp, reason: 'the watermark must be the newest remote modifiedAt, immune to local clock skew');

      // Second sync: the delta pull must start from that data-derived
      // watermark (minus the configured overlap), not from lastSyncTime.
      final since = <DateTime>[];
      when(() => remote.readSince(any(), userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((invocation) async {
        since.add(invocation.positionalArguments[0] as DateTime);
        return [];
      });
      await engine.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      expect(since.single, remoteStamp.subtract(const DatumConfig().deltaSyncOverlap));
    });

    test('a retryable failure blocks later ops for the same entity, not others', () async {
      final remote = MockRemoteAdapter();
      when(() => remote.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => remote.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remote.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => []);
      when(() => remote.update(any())).thenThrow(const NetworkException(message: 'flaky'));
      when(() => remote.delete(any(), userId: any(named: 'userId'))).thenAnswer((_) async => true);
      when(() => remote.create(any())).thenAnswer((_) async {});

      // update e1 (fails retryably) → delete e1 (must be deferred) →
      // create e2 (must proceed). Alternating types prevent batching.
      when(() => queue.getPending(any())).thenAnswer((_) async => [
            op('op1', 'e1', DatumOperationType.update),
            op('op2', 'e1', DatumOperationType.delete),
            op('op3', 'e2', DatumOperationType.create),
          ]);

      final engine = buildEngine(remote);
      final (result, _) = await engine.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));

      verifyNever(() => remote.delete('e1', userId: any(named: 'userId')));
      verify(() => remote.create(any())).called(1);
      // op1 re-queued with a bumped retryCount; only op3 dequeued.
      verify(() => queue.update(any(that: isA<DatumSyncOperation<TestDatumEntity>>().having((o) => o.id, 'id', 'op1').having((o) => o.retryCount, 'retryCount', 1)))).called(1);
      verify(() => queue.dequeue('op3')).called(1);
      verifyNever(() => queue.dequeue('op1'));
      verifyNever(() => queue.dequeue('op2'));
      expect(result.syncedCount, 1);
    });

    test('a failed delete batch falls back per-op with EntityNotFound tolerance', () async {
      final remote = MockRemoteAdapter();
      when(() => remote.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => remote.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remote.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => []);
      when(() => remote.deleteAll(any(), userId: any(named: 'userId'))).thenThrow(const EntityNotFoundException(message: 'e2 already gone'));
      when(() => remote.delete(any(), userId: any(named: 'userId'))).thenAnswer((invocation) async {
        if (invocation.positionalArguments[0] == 'e2') {
          throw const EntityNotFoundException(message: 'e2 already gone');
        }
        return true;
      });

      when(() => queue.getPending(any())).thenAnswer((_) async => [
            op('op1', 'e1', DatumOperationType.delete),
            op('op2', 'e2', DatumOperationType.delete),
            op('op3', 'e3', DatumOperationType.delete),
          ]);

      final engine = buildEngine(remote);
      final (result, _) = await engine.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));

      // One id being gone already must not cancel the sibling deletions.
      verify(() => remote.deleteAll(any(), userId: any(named: 'userId'))).called(1);
      verify(() => remote.delete('e1', userId: any(named: 'userId'))).called(1);
      verify(() => remote.delete('e3', userId: any(named: 'userId'))).called(1);
      verify(() => queue.dequeue('op1')).called(1);
      verify(() => queue.dequeue('op2')).called(1);
      verify(() => queue.dequeue('op3')).called(1);
      expect(result.failedCount, 0);
    });

    test('a cursor staged by an aborted pull is never persisted by a push-only cycle', () async {
      final remote = MockCursorRemoteAdapter();
      when(() => remote.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => remote.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remote.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => []);

      var cursorCall = 0;
      when(() => remote.readChanges(any(), userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async {
        cursorCall++;
        return (items: [entity('e1')], nextCursor: 'cursor-$cursorCall');
      });

      final engine = buildEngine(remote);

      // Abort the first pull AFTER the cursor was staged: applying the
      // pulled items fails.
      when(() => local.readByIds(any(), userId: any(named: 'userId'))).thenThrow(StateError('storage exploded'));
      await expectLater(
        engine.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly)),
        throwsA(anything),
      );

      // A push-only cycle must NOT persist the stale staged cursor.
      when(() => local.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {});
      await engine.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));
      expect(storedMetadata?.customMetadata?[DatumSyncEngine.syncCursorKey], isNull, reason: 'rows behind an aborted cursor would never be fetched again');

      // A successful pull re-reads from the start and persists its cursor.
      await engine.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));
      expect(storedMetadata?.customMetadata?[DatumSyncEngine.syncCursorKey], 'cursor-2');
      final abortedThenFreshCursors = verify(() => remote.readChanges(captureAny(), userId: any(named: 'userId'), scope: any(named: 'scope'))).captured;
      expect(abortedThenFreshCursors, [null, null], reason: 'the aborted cycle must not have advanced the cursor');
    });
  });

  group('manager change-echo dedupe', () {
    late DatumManager<TestDatumEntity> manager;
    late functional.MockLocalAdapter<TestDatumEntity> local;
    var transformCount = 0;

    setUp(() async {
      transformCount = 0;
      final connectivity = MockConnectivityChecker();
      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
      local = functional.MockLocalAdapter<TestDatumEntity>(fromJson: TestDatumEntity.fromMap);
      manager = DatumManager<TestDatumEntity>(
        localAdapter: local,
        remoteAdapter: functional.MockRemoteAdapter<TestDatumEntity>(fromJson: TestDatumEntity.fromMap),
        connectivity: connectivity,
        datumConfig: const DatumConfig(enableLogging: false),
        middlewares: [_CountingMiddleware(() => transformCount++)],
      );
      await manager.initialize();
    });

    tearDown(() => manager.dispose());

    test('the adapter echo of our own write is not re-transformed or re-queued', () async {
      await manager.push(item: entity('e1', value: 'original'), userId: 'u1');
      // Let the adapter's change-stream echo propagate.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(transformCount, 1, reason: 'the echo must not re-run pre-save middleware');
      expect((await manager.getPendingOperations('u1')).length, 1, reason: 'exactly one queued operation for one write');
    });

    test('a genuine external change right after our write is still applied', () async {
      final pushed = await manager.push(item: entity('e1', value: 'ours'), userId: 'u1');

      // Another writer changes the same entity within the dedupe window —
      // different content, so the fingerprint differs and it must NOT be
      // dropped as a "duplicate".
      local.emitChange(DatumChangeDetail<TestDatumEntity>(
        entityId: 'e1',
        userId: 'u1',
        type: DatumOperationType.update,
        timestamp: DateTime.now(),
        data: pushed.copyWith(value: 'external-edit', modifiedAt: pushed.modifiedAt.add(const Duration(seconds: 1)), version: pushed.version + 1),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect((await manager.read('e1', userId: 'u1'))?.value, 'external-edit', reason: 'keying the dedupe cache by entity id alone dropped this change');
    });
  });
}

class _CountingMiddleware extends DatumMiddleware<TestDatumEntity> {
  _CountingMiddleware(this.onTransform);

  final void Function() onTransform;

  @override
  FutureOr<TestDatumEntity> transformBeforeSave(TestDatumEntity item) {
    onTransform();
    return item;
  }
}
