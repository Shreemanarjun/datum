import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

/// Remote adapter whose single-entity create always fails with [error].
class _FailingCreateRemoteAdapter extends MockRemoteAdapter<TestEntity> {
  _FailingCreateRemoteAdapter(this.error) : super(fromJson: TestEntity.fromJson);

  final Object error;

  @override
  Future<void> create(TestEntity entity) async => throw error;
}

/// A detector that never reports conflicts, so a pull falls through to the
/// engine's own "is remote strictly newer" version comparison.
class _NeverConflictDetector extends DatumConflictDetector<TestEntity> {
  @override
  DatumConflictContext? detect({
    required TestEntity? localItem,
    required TestEntity? remoteItem,
    required String userId,
    DatumSyncMetadata? localMetadata,
    DatumSyncMetadata? remoteMetadata,
  }) =>
      null;
}

/// Leaves every conflict unresolved.
class _AbortResolver implements DatumConflictResolver<TestEntity> {
  @override
  String get name => 'AbortAll';

  @override
  FutureOr<DatumConflictResolution<TestEntity>> resolve({
    TestEntity? local,
    TestEntity? remote,
    required DatumConflictContext context,
  }) =>
      const DatumConflictResolution.abort('left unresolved');
}

/// Defers every conflict to the user.
class _AskUserResolver implements DatumConflictResolver<TestEntity> {
  @override
  String get name => 'AskUser';

  @override
  FutureOr<DatumConflictResolution<TestEntity>> resolve({
    TestEntity? local,
    TestEntity? remote,
    required DatumConflictContext context,
  }) =>
      const DatumConflictResolution.requireUserInput('you decide');
}

/// Accepts remote deletions: a FULL pull with this resolver deletes local
/// orphans, which lets tests prove a filtered pull does NOT.
class _DeleteLocalOnMissingRemoteResolver implements DatumConflictResolver<TestEntity> {
  @override
  String get name => 'DeleteLocalOnMissingRemote';

  @override
  FutureOr<DatumConflictResolution<TestEntity>> resolve({
    TestEntity? local,
    TestEntity? remote,
    required DatumConflictContext context,
  }) {
    if (local != null && remote == null) {
      return const DatumConflictResolution.deleteLocal('remote gone');
    }
    if (remote != null) {
      return DatumConflictResolution.useRemote(remote);
    }
    return const DatumConflictResolution.abort('no data');
  }
}

/// Builds a [DatumSyncEngine] wired to the in-memory mock adapters, exposing
/// every collaborator so tests can drive and inspect the engine directly.
class _EngineHarness {
  _EngineHarness({
    MockRemoteAdapter<TestEntity>? remote,
    DatumConflictDetector<TestEntity>? detector,
    DatumConflictResolver<TestEntity>? resolver,
    DatumConfig? config,
  })  : local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        remoteAdapter = remote ?? MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson) {
    final connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());

    queueManager = QueueManager<TestEntity>(
      localAdapter: local,
      logger: DatumLogger(enabled: false),
    );
    engine = DatumSyncEngine<TestEntity>(
      localAdapter: local,
      remoteAdapter: remoteAdapter,
      conflictResolver: resolver ?? LastWriteWinsResolver<TestEntity>(),
      queueManager: queueManager,
      conflictDetector: detector ?? DatumConflictDetector<TestEntity>(),
      logger: DatumLogger(enabled: false),
      config: config ?? const DatumConfig(),
      connectivityChecker: connectivity,
      eventController: eventController,
      statusSubject: statusSubject,
      metadataSubject: metadataSubject,
      isolateHelper: const IsolateHelper(),
    );
  }

  final MockLocalAdapter<TestEntity> local;
  final MockRemoteAdapter<TestEntity> remoteAdapter;
  late final QueueManager<TestEntity> queueManager;
  final StreamController<DatumSyncEvent<TestEntity>> eventController = StreamController<DatumSyncEvent<TestEntity>>.broadcast();
  final BehaviorSubject<DatumSyncStatusSnapshot> statusSubject = BehaviorSubject<DatumSyncStatusSnapshot>.seeded(DatumSyncStatusSnapshot.initial('u1'));
  final BehaviorSubject<DatumSyncMetadata> metadataSubject = BehaviorSubject<DatumSyncMetadata>();
  late final DatumSyncEngine<TestEntity> engine;

  Future<void> dispose() async {
    if (!eventController.isClosed) await eventController.close();
    if (!statusSubject.isClosed) await statusSubject.close();
    if (!metadataSubject.isClosed) await metadataSubject.close();
    await local.dispose();
    await remoteAdapter.dispose();
  }
}

TestEntity _entity(String id, {int version = 1, String name = 'n'}) => TestEntity(
      id: id,
      userId: 'u1',
      name: name,
      value: 0,
      modifiedAt: DateTime(2024),
      createdAt: DateTime(2024),
      version: version,
    );

DatumSyncOperation<TestEntity> _op(
  String id,
  String entityId,
  DatumOperationType type, {
  TestEntity? data,
}) =>
    DatumSyncOperation<TestEntity>(
      id: id,
      userId: 'u1',
      entityId: entityId,
      type: type,
      timestamp: DateTime(2024),
      data: data,
    );

void main() {
  group('DatumSyncEngine tail paths', () {
    test('closed event controller: the ORIGINAL error is rethrown, not the event wrapper', () async {
      final h = _EngineHarness(remote: _FailingCreateRemoteAdapter(StateError('permanent failure')));
      addTearDown(h.dispose);

      await h.queueManager.enqueue(_op('op1', 'e1', DatumOperationType.create, data: _entity('e1')));

      // Simulates a manager disposed mid-cycle: events can no longer be
      // delivered, so wrapping the error in SyncExceptionWithEvents is useless.
      await h.eventController.close();

      await expectLater(
        Future.sync(() => h.engine.synchronize('u1')),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'permanent failure')),
      );
    });

    test('EntityNotFoundException on a create push fails the cycle and keeps the op queued', () async {
      final h = _EngineHarness(remote: _FailingCreateRemoteAdapter(const EntityNotFoundException(message: 'missing upstream')));
      addTearDown(h.dispose);

      await h.queueManager.enqueue(_op('op1', 'e1', DatumOperationType.create, data: _entity('e1')));

      await expectLater(
        Future.sync(() => h.engine.synchronize('u1')),
        throwsA(
          isA<SyncExceptionWithEvents<TestEntity>>().having((e) => e.originalError, 'originalError', isA<EntityNotFoundException>()),
        ),
      );

      // Unlike the update->create fallback, a CREATE rejected with "not found"
      // cannot be converted; it is not dequeued and stays pending.
      expect(await h.queueManager.getPending('u1'), hasLength(1));
      expect(h.statusSubject.value.status, DatumSyncStatus.failed);
    });

    test('pull applies remote only when its version is strictly higher (no vector clocks, no conflict)', () async {
      final h = _EngineHarness(detector: _NeverConflictDetector());
      addTearDown(h.dispose);

      h.local.addLocalItem('u1', _entity('newer-remote', version: 1, name: 'local-old'));
      h.remoteAdapter.addRemoteItem('u1', _entity('newer-remote', version: 2, name: 'remote-new'));

      h.local.addLocalItem('u1', _entity('older-remote', version: 3, name: 'local-new'));
      h.remoteAdapter.addRemoteItem('u1', _entity('older-remote', version: 1, name: 'remote-old'));

      await h.engine.synchronize(
        'u1',
        options: const DatumSyncOptions(direction: SyncDirection.pullOnly),
      );

      expect(
        (await h.local.read('newer-remote', userId: 'u1'))?.name,
        'remote-new',
        reason: 'a strictly higher remote version must be applied',
      );
      expect(
        (await h.local.read('older-remote', userId: 'u1'))?.name,
        'local-new',
        reason: 'a lower remote version must not overwrite local',
      );
    });

    test('consecutive full updates are pushed as ONE batch through updateAll', () async {
      final h = _EngineHarness();
      addTearDown(h.dispose);

      // Entities already exist on the remote with stale content.
      h.remoteAdapter.addRemoteItem('u1', _entity('e1', name: 'stale'));
      h.remoteAdapter.addRemoteItem('u1', _entity('e2', name: 'stale'));

      // Two consecutive full updates (data, no delta) are grouped into a batch.
      await h.queueManager.enqueue(_op('op1', 'e1', DatumOperationType.update, data: _entity('e1', version: 2, name: 'fresh-1')));
      await h.queueManager.enqueue(_op('op2', 'e2', DatumOperationType.update, data: _entity('e2', version: 2, name: 'fresh-2')));

      final (result, _) = await h.engine.synchronize(
        'u1',
        options: const DatumSyncOptions(direction: SyncDirection.pushOnly),
      );

      expect(result.syncedCount, 2);
      expect((await h.remoteAdapter.read('e1', userId: 'u1'))?.name, 'fresh-1');
      expect((await h.remoteAdapter.read('e2', userId: 'u1'))?.name, 'fresh-2');
      expect(await h.queueManager.getPending('u1'), isEmpty);
    });

    test('filtered sync (options.query) pulls data but never treats missing remotes as deletions', () async {
      final h = _EngineHarness(
        resolver: _DeleteLocalOnMissingRemoteResolver(),
        config: const DatumConfig(detectRemoteDeletions: true),
      );
      addTearDown(h.dispose);

      // A local-only entity that a FULL pull with this resolver WOULD delete.
      h.local.addLocalItem('u1', _entity('local-only', name: 'survivor'));
      h.remoteAdapter.addRemoteItem('u1', _entity('from-remote', version: 2, name: 'pulled'));

      final (result, events) = await h.engine.synchronize(
        'u1',
        options: const DatumSyncOptions(
          direction: SyncDirection.pullOnly,
          query: DatumQuery(filters: [Filter('name', FilterOperator.equals, 'pulled')]),
        ),
      );

      expect((await h.local.read('from-remote', userId: 'u1'))?.name, 'pulled');
      expect(
        await h.local.read('local-only', userId: 'u1'),
        isNotNull,
        reason: 'a filtered pull must not run remote-deletion detection',
      );
      expect(events.whereType<ConflictDetectedEvent<TestEntity>>(), isEmpty);
      expect(result.conflictsResolved, 0);
    });

    test('unresolved deletion conflict (abort) keeps local and resolves nothing', () async {
      final h = _EngineHarness(
        resolver: _AbortResolver(),
        config: const DatumConfig(detectRemoteDeletions: true),
      );
      addTearDown(h.dispose);

      h.local.addLocalItem('u1', _entity('e1', name: 'keep-me'));
      // Remote is empty: a full pull sees e1 as deleted remotely.

      final (result, events) = await h.engine.synchronize('u1');

      expect(await h.local.read('e1', userId: 'u1'), isNotNull, reason: 'abort must not delete the local copy');
      expect(result.conflictsResolved, 0);
      expect(events.whereType<ConflictDetectedEvent<TestEntity>>(), hasLength(1));
      expect(
        events.whereType<ConflictResolvedEvent<TestEntity>>(),
        isEmpty,
        reason: 'an unresolved conflict must not emit a resolved event',
      );
    });

    test('unresolved deletion conflict (askUser) keeps local and resolves nothing', () async {
      final h = _EngineHarness(
        resolver: _AskUserResolver(),
        config: const DatumConfig(detectRemoteDeletions: true),
      );
      addTearDown(h.dispose);

      h.local.addLocalItem('u1', _entity('e1', name: 'keep-me'));

      final (result, events) = await h.engine.synchronize('u1');

      expect(await h.local.read('e1', userId: 'u1'), isNotNull);
      expect(result.conflictsResolved, 0);
      expect(events.whereType<ConflictDetectedEvent<TestEntity>>(), hasLength(1));
      expect(events.whereType<ConflictResolvedEvent<TestEntity>>(), isEmpty);
    });
  });
}
