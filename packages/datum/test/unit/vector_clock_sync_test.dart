import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import '../test_utils/test_datum_entity.dart';
import 'dart:async';
import 'package:rxdart/rxdart.dart';

class MockLocalAdapter<T extends DatumEntityInterface> extends Mock implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements DatumConnectivityChecker {}

class MockQueueManager<T extends DatumEntityInterface> extends Mock implements QueueManager<T> {}

void main() {
  group('VectorClock Sync Integration', () {
    late DatumSyncEngine<TestDatumEntity> engine;
    late MockLocalAdapter<TestDatumEntity> localAdapter;
    late MockRemoteAdapter<TestDatumEntity> remoteAdapter;
    late MockConnectivityChecker connectivity;
    late MockQueueManager<TestDatumEntity> queueManager;

    setUp(() async {
      registerFallbackValue(const DatumQuery());
      registerFallbackValue(TestDatumEntity(id: '', userId: '', value: ''));
      registerFallbackValue(const DatumSyncMetadata(userId: ''));
      registerFallbackValue(DatumSyncResult<TestDatumEntity>.skipped('user-1', 0));
      registerFallbackValue(DatumSyncOperation<TestDatumEntity>(
        id: '1',
        userId: 'user-1',
        type: DatumOperationType.create,
        entityId: '1',
        data: TestDatumEntity(id: '1', userId: 'user-1', value: '1'),
        timestamp: DateTime.now(),
      ));

      localAdapter = MockLocalAdapter<TestDatumEntity>();
      remoteAdapter = MockRemoteAdapter<TestDatumEntity>();
      connectivity = MockConnectivityChecker();
      queueManager = MockQueueManager<TestDatumEntity>();

      when(() => connectivity.isConnected).thenAnswer((_) async => true);

      engine = DatumSyncEngine<TestDatumEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: LastWriteWinsResolver<TestDatumEntity>(),
        queueManager: queueManager,
        conflictDetector: DatumConflictDetector<TestDatumEntity>(),
        logger: DatumLogger(),
        config: const DatumConfig<TestDatumEntity>(),
        connectivityChecker: connectivity,
        eventController: StreamController<DatumSyncEvent<TestDatumEntity>>.broadcast(),
        statusSubject: BehaviorSubject.seeded(DatumSyncStatusSnapshot.initial('user-1')),
        metadataSubject: BehaviorSubject.seeded(const DatumSyncMetadata(userId: 'user-1')),
        isolateHelper: const IsolateHelper(),
        localObservers: [],
        globalObservers: [],
        deviceId: 'device-1',
      );

      when(() => queueManager.getPending(any())).thenAnswer((_) async => []);
      when(() => queueManager.getPendingCount(any())).thenAnswer((_) async => 0);
      when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async => {});
      when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async => {});
      when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async => {});
      when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
    });

    test('should NOT overwrite local item if remote item has an older vector clock', () async {
      const localVC = VectorClock({'device-1': 5, 'device-2': 3});
      const remoteVC = VectorClock({'device-1': 4, 'device-2': 3});

      final localItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'local', vectorClock: localVC);
      final remoteItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'remote', vectorClock: remoteVC);

      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {'1': localItem});

      var readCount = 0;
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async {
        if (readCount++ == 0) return [remoteItem];
        return [];
      });

      when(() => localAdapter.update(any())).thenAnswer((_) async => remoteItem);

      await engine.synchronize('user-1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      verifyNever(() => localAdapter.update(any()));
    });

    test('should overwrite local item if remote item has a newer vector clock', () async {
      const localVC = VectorClock({'device-1': 5, 'device-2': 3});
      const remoteVC = VectorClock({'device-1': 5, 'device-2': 4});

      final localItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'local', vectorClock: localVC);
      final remoteItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'remote', vectorClock: remoteVC);

      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {'1': localItem});

      var readCount = 0;
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async {
        if (readCount++ == 0) return [remoteItem];
        return [];
      });

      when(() => localAdapter.update(any())).thenAnswer((_) async => remoteItem);

      await engine.synchronize('user-1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      verify(() => localAdapter.update(any())).called(1);
    });

    test('should trigger conflict resolution if vector clocks are concurrent', () async {
      const localVC = VectorClock({'device-1': 6, 'device-2': 3});
      const remoteVC = VectorClock({'device-1': 5, 'device-2': 4});

      final localItem = TestDatumEntity(
        id: '1',
        userId: 'user-1',
        value: 'local',
        vectorClock: localVC,
        modifiedAt: DateTime(2023, 1, 1, 10, 0, 0),
      );
      final remoteItem = TestDatumEntity(
        id: '1',
        userId: 'user-1',
        value: 'remote',
        vectorClock: remoteVC,
        modifiedAt: DateTime(2023, 1, 1, 10, 0, 1),
      );

      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {'1': localItem});

      var readCount = 0;
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async {
        if (readCount++ == 0) return [remoteItem];
        return [];
      });

      when(() => localAdapter.update(any())).thenAnswer((_) async => remoteItem);

      await engine.synchronize('user-1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      // With LWW, remote should win because it is newer
      verify(() => localAdapter.update(any())).called(1);
    });

    // --- Bug fix: no vector clock present ------------------------------------
    // Previously, when either vector clock was null the newer-check was skipped
    // and local was ALWAYS overwritten, producing redundant updates / sync noise.

    test('does NOT overwrite when clocks are null and item is identical', () async {
      final at = DateTime(2024, 1, 1);
      final localItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'same', version: 1, modifiedAt: at, createdAt: at);
      final remoteItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'same', version: 1, modifiedAt: at, createdAt: at);

      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {'1': localItem});
      var readCount = 0;
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async {
        if (readCount++ == 0) return [remoteItem];
        return [];
      });
      when(() => localAdapter.update(any())).thenAnswer((_) async => remoteItem);

      await engine.synchronize('user-1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      verifyNever(() => localAdapter.update(any()));
    });

    test('keeps the newer local on equal versions AND queues a push-back so the remote converges', () async {
      // Same version + divergent content = concurrent edits (the most common
      // concurrency signature without vector clocks). The old behavior
      // silently skipped the row, stranding the winner on this device
      // forever (split-brain, found by the convergence fuzz suite): now it
      // is a detected conflict — LWW keeps the newer local AND enqueues a
      // resolution push.
      final localItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'local', version: 1, modifiedAt: DateTime(2024, 1, 2));
      final remoteItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'remote', version: 1, modifiedAt: DateTime(2024, 1, 1));

      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {'1': localItem});
      var readCount = 0;
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async {
        if (readCount++ == 0) return [remoteItem];
        return [];
      });
      when(() => localAdapter.update(any())).thenAnswer((_) async => remoteItem);
      when(() => queueManager.enqueue(any())).thenAnswer((_) async {});

      await engine.synchronize('user-1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      verifyNever(() => localAdapter.update(any()));
      verify(() => queueManager.enqueue(any())).called(1);
    });

    test('DOES overwrite when clocks are null and remote modifiedAt is newer', () async {
      final localItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'local', version: 1, modifiedAt: DateTime(2024, 1, 1));
      final remoteItem = TestDatumEntity(id: '1', userId: 'user-1', value: 'remote', version: 1, modifiedAt: DateTime(2024, 1, 2));

      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {'1': localItem});
      var readCount = 0;
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async {
        if (readCount++ == 0) return [remoteItem];
        return [];
      });
      when(() => localAdapter.update(any())).thenAnswer((_) async => remoteItem);

      await engine.synchronize('user-1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));

      verify(() => localAdapter.update(any())).called(1);
    });
  });

  group('VectorClock Manager Integration', () {
    late DatumManager<TestDatumEntity> manager;
    late MockLocalAdapter<TestDatumEntity> localAdapter;
    late MockRemoteAdapter<TestDatumEntity> remoteAdapter;
    late MockConnectivityChecker connectivity;

    setUp(() async {
      localAdapter = MockLocalAdapter<TestDatumEntity>();
      remoteAdapter = MockRemoteAdapter<TestDatumEntity>();
      connectivity = MockConnectivityChecker();

      manager = DatumManager<TestDatumEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivity,
        datumConfig: const DatumConfig<TestDatumEntity>(),
        deviceId: 'device-1',
      );

      // Setup some defaults
      when(() => localAdapter.initialize()).thenAnswer((_) async => {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async => {});
      when(() => localAdapter.addPendingOperation(any(), any())).thenAnswer((_) async => {});
      when(() => localAdapter.getAllUserIds()).thenAnswer((_) async => []);
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);

      await manager.initialize();
    });

    test('push should increment vector clock', () async {
      final item = TestDatumEntity(id: '1', userId: 'user-1', value: 'test', vectorClock: const VectorClock({'device-1': 1}));

      when(() => localAdapter.read(any(), userId: any(named: 'userId'))).thenAnswer((_) async => null);
      when(() => localAdapter.create(any())).thenAnswer((_) async => {});

      await manager.push(item: item, userId: 'user-1');

      final captured = verify(() => localAdapter.create(captureAny())).captured.first as TestDatumEntity;
      expect(captured.vectorClock?.getValue('device-1'), 2);
    });

    test('soft delete should increment vector clock', () async {
      final existing = TestDatumEntity(id: '1', userId: 'user-1', value: 'test', vectorClock: const VectorClock({'device-1': 1}));

      when(() => localAdapter.read(any(), userId: any(named: 'userId'))).thenAnswer((_) async => existing);
      when(() => localAdapter.patch(id: any(named: 'id'), delta: any(named: 'delta'), userId: any(named: 'userId'))).thenAnswer((Invocation invocation) async {
        final delta = invocation.namedArguments[#delta] as Map<String, dynamic>;
        return existing.copyWith(
          isDeleted: delta['isDeleted'] as bool?,
          vectorClock: VectorClock.fromMap(delta['vectorClock'] as Map<String, dynamic>),
        );
      });

      await manager.delete(id: '1', userId: 'user-1', behavior: DeleteBehavior.softDelete);

      final capturedDelta = verify(() => localAdapter.patch(
            id: '1',
            delta: captureAny(named: 'delta'),
            userId: 'user-1',
          )).captured.first as Map<String, dynamic>;

      expect(capturedDelta['isDeleted'], true);
      final vcMap = capturedDelta['vectorClock'] as Map<String, dynamic>;
      expect(vcMap['device-1'], 2);
    });
  });
}
