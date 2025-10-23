import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/datum.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class MockedLocalAdapter<T extends DatumEntityBase> extends Mock implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntityBase> extends Mock implements RemoteAdapter<T> {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      TestEntity(
        id: 'fb',
        userId: 'fb',
        name: 'fb',
        value: 0,
        modifiedAt: DateTime(0),
        createdAt: DateTime(0),
        version: 0,
      ),
    );
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(
      DatumSyncOperation<TestEntity>(
        id: 'fb',
        userId: 'fb',
        entityId: 'fb',
        type: DatumOperationType.create,
        timestamp: DateTime(0),
      ),
    );
    registerFallbackValue(const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'));
    registerFallbackValue(DatumQueryBuilder<TestEntity>().build());
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
  });
  group('DatumManager Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: LastWriteWinsResolver<TestEntity>(),
        datumConfig: const DatumConfig(), // Use default config
        // connectivity is required
        connectivity: connectivityChecker,
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('saves entity locally and enqueues sync operation', () async {
      // Arrange
      final entity = TestEntity.create('entity1', 'user1', 'Test Item');

      // Assert: Verify event was emitted. This must be set up before the action.
      expect(
        manager.onDataChange,
        emits(
          isA<DataChangeEvent<TestEntity>>().having((e) => e.changeType, 'changeType', ChangeType.created).having((e) => e.source, 'source', DataSource.local).having((e) => e.data!.id, 'data.id', 'entity1'),
        ),
      );

      // Stub the getPendingOperations to reflect the state after the push.
      // Act
      await manager.push(item: entity, userId: 'user1');

      when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
        (_) async => [
          DatumSyncOperation<TestEntity>(
            id: 'op-create',
            userId: 'user1',
            entityId: entity.id,
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: entity,
          ),
        ],
      );

      // Assert
      verify(() => localAdapter.create(entity)).called(1);
      verify(
        () => localAdapter.addPendingOperation(
          'user1',
          any(
            that: isA<DatumSyncOperation<TestEntity>>().having((op) => op.entityId, 'entityId', 'entity1').having((op) => op.type, 'type', DatumOperationType.create),
          ),
        ),
      ).called(1);

      // Verify operation count
      final pendingCount = await manager.getPendingCount('user1');
      expect(pendingCount, 1);
    });

    test('syncs pending operations to remote', () async {
      // Arrange
      final entity = TestEntity.create('entity1', 'user1', 'Test Item');
      final op = DatumSyncOperation<TestEntity>(
        id: 'op-sync',
        userId: 'user1',
        entityId: entity.id,
        type: DatumOperationType.create,
        timestamp: DateTime.now(),
        data: entity,
      );
      final pendingOps = [op]; // A stateful list for this test

      // Stub getPendingOperations to return our stateful list
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => pendingOps);
      // Stub removePendingOperation to modify our stateful list
      when(
        () => localAdapter.removePendingOperation('op-sync'),
      ).thenAnswer((_) async => pendingOps.remove(op));
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {});

      // Act
      final result = await manager.synchronize('user1');

      // Assert
      expect(result.isSuccess, isTrue);
      expect(result.syncedCount, 1);
      expect(result.failedCount, 0);

      // Verify remote state
      verify(() => remoteAdapter.create(entity)).called(1);
      verify(() => localAdapter.removePendingOperation('op-sync')).called(1);
      verify(() => remoteAdapter.updateSyncMetadata(any(), 'user1')).called(1);

      // Verify local queue is empty
      final pendingCount = await manager.getPendingCount('user1');
      expect(pendingCount, 0);
    });

    test('pulls remote items during sync', () async {
      // Arrange
      final remoteEntity = TestEntity.create('entity2', 'user1', 'Remote Item');
      when(
        () => remoteAdapter.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => [remoteEntity]);
      when(
        () => localAdapter.readByIds(any(), userId: 'user1'),
      ).thenAnswer((_) async => {});
      when(() => localAdapter.create(any())).thenAnswer((_) async {});

      // Act
      final result = await manager.synchronize('user1');

      // Assert
      expect(result.isSuccess, isTrue);
      verify(() => localAdapter.create(remoteEntity)).called(1);

      // To verify the result, we need to stub the final readAll
      when(
        () => localAdapter.readAll(userId: 'user1'),
      ).thenAnswer((_) async => [remoteEntity]);
      final localItems = await manager.readAll(userId: 'user1');
      expect(localItems, hasLength(1));
      expect(localItems.first.name, 'Remote Item');
    });

    test('resolves conflicts using last-write-wins', () async {
      // Arrange
      final baseTime = DateTime.now();
      final localEntity = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local Version',
        value: 1,
        modifiedAt: baseTime,
        createdAt: baseTime,
        version: 1,
      );
      final remoteEntity = localEntity.copyWith(
        name: 'Remote Version',
        modifiedAt: baseTime.add(const Duration(seconds: 10)),
        version: 2,
      );

      // Setup conflict scenario
      when(
        () => remoteAdapter.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => [remoteEntity]);
      when(
        () => localAdapter.readByIds(['entity1'], userId: 'user1'),
      ).thenAnswer((_) async => {'entity1': localEntity});
      when(() => localAdapter.update(any())).thenAnswer((_) async {});

      // Act
      final result = await manager.synchronize('user1');

      // Assert
      expect(result.isSuccess, isTrue, reason: result.error?.toString());
      expect(result.conflictsResolved, 1);

      // Verify remote version was saved locally
      verify(() => localAdapter.update(remoteEntity)).called(1);
      // To verify the result, we need to stub the final readAll
      when(
        () => localAdapter.readAll(userId: 'user1'),
      ).thenAnswer((_) async => [remoteEntity]);
      final localItems = await manager.readAll(userId: 'user1');
      expect(localItems.first.name, 'Remote Version');
    });

    test('deletes entity locally and remotely', () async {
      // Arrange
      final entity = TestEntity.create('entity1', 'user1', 'Test Item');
      // Simulate that the entity already exists locally before the delete action.
      when(
        () => localAdapter.read('entity1', userId: 'user1'),
      ).thenAnswer((_) async => entity);

      // Act
      await manager.delete(id: 'entity1', userId: 'user1');
      when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
        (_) async => [
          DatumSyncOperation<TestEntity>(
            id: 'op-delete',
            userId: 'user1',
            entityId: entity.id,
            type: DatumOperationType.delete,
            timestamp: DateTime.now(),
          ),
        ],
      );
      when(
        () => remoteAdapter.delete(any(), userId: 'user1'),
      ).thenAnswer((_) async {});
      await manager.synchronize('user1');

      // Assert
      when(
        () => localAdapter.readAll(userId: 'user1'),
      ).thenAnswer((_) async => []);
      expect(await manager.readAll(userId: 'user1'), isEmpty);
      verify(() => remoteAdapter.delete('entity1', userId: 'user1')).called(1);
    });

    test('handles network errors gracefully', () async {
      // Arrange
      final entity = TestEntity.create('entity1', 'user1', 'Test Item');
      await manager.push(item: entity, userId: 'user1');
      when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
        (_) async => [
          DatumSyncOperation<TestEntity>(
            id: 'op-network-error',
            userId: 'user1',
            entityId: entity.id,
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: entity,
          ),
        ],
      );

      // Go offline
      when(
        () => connectivityChecker.isConnected,
      ).thenAnswer((_) async => false);

      // Act
      final result = await manager.synchronize('user1');

      // Assert
      expect(result.wasSkipped, isTrue);
      final pendingCount = await manager.getPendingCount('user1');
      expect(pendingCount, 1);
      verifyNever(() => remoteAdapter.create(any()));
    });

    test('retrieves entity by id', () async {
      // Arrange
      final entity = TestEntity.create('entity1', 'user1', 'Test Item');
      await manager.push(item: entity, userId: 'user1');
      when(
        () => localAdapter.read('entity1', userId: 'user1'),
      ).thenAnswer((_) async => entity);

      // Act
      final retrieved = await manager.read('entity1', userId: 'user1');

      // Assert
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Test Item');
    });

    test('returns null when entity does not exist', () async {
      when(
        () => localAdapter.read('nonexistent', userId: 'user1'),
      ).thenAnswer((_) async => null);
      // Act
      final retrieved = await manager.read('nonexistent', userId: 'user1');

      // Assert
      expect(retrieved, isNull);
    });

    group('query', () {
      final user1Entities = [
        TestEntity.create('e1', 'user1', 'Apple').copyWith(value: 10),
        TestEntity.create('e2', 'user1', 'Banana').copyWith(value: 20),
        TestEntity.create('e3', 'user1', 'Avocado').copyWith(value: 30),
      ];

      test('can query local adapter with a where clause', () async {
        // Arrange
        when(() => localAdapter.query(any(), userId: 'user1')).thenAnswer((
          inv,
        ) async {
          // Simulate the adapter's query logic
          return user1Entities.where((e) => e.name.startsWith('A')).toList();
        });

        final query = DatumQueryBuilder<TestEntity>().where('name', startsWith: 'A').build();

        // Act
        final results = await manager.query(
          query,
          source: DataSource.local,
          userId: 'user1',
        );

        // Assert
        expect(results, hasLength(2));
        expect(results.map((e) => e.name), containsAll(['Apple', 'Avocado']));
        verify(() => localAdapter.query(query, userId: 'user1')).called(1);
      });

      test('can query remote adapter with sorting and limit', () async {
        // Arrange
        when(() => remoteAdapter.query(any(), userId: 'user1')).thenAnswer((
          inv,
        ) async {
          // Simulate the adapter's query logic
          final sorted = List<TestEntity>.from(user1Entities)..sort((a, b) => b.value.compareTo(a.value)); // Descending
          return sorted.take(2).toList();
        });

        final query = DatumQueryBuilder<TestEntity>().orderBy('value', descending: true).limit(2).build();

        // Act
        final results = await manager.query(
          query,
          source: DataSource.remote,
          userId: 'user1',
        );

        // Assert
        expect(results, hasLength(2));
        // The results should be the two items with the highest values.
        expect(results[0].name, 'Avocado'); // value: 30
        expect(results[1].name, 'Banana'); // value: 20
        verify(() => remoteAdapter.query(query, userId: 'user1')).called(1);
      });
    });

    test(
      'forceFullSync option triggers a pull even with matching metadata',
      () async {
        // Arrange
        final metadata = DatumSyncMetadata(
          userId: 'user1',
          lastSyncTime: DateTime.now(),
          dataHash: 'identical-hash',
        );

        // Stub both adapters to return identical metadata.
        // Normally, this would cause the sync engine to skip the pull phase.
        when(
          () => localAdapter.getSyncMetadata('user1'),
        ).thenAnswer((_) async => metadata);
        when(
          () => remoteAdapter.getSyncMetadata('user1'),
        ).thenAnswer((_) async => metadata);

        final remoteEntity = TestEntity.create(
          'remote-e1',
          'user1',
          'Fresh Data',
        );
        when(
          () => remoteAdapter.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) async => [remoteEntity]);

        // Act
        await manager.synchronize(
          'user1',
          options: const DatumSyncOptions(forceFullSync: true),
        );

        // Assert
        // Verify that a pull was performed (by checking that the remote data was
        // saved locally), despite the matching metadata, because forceFullSync was true.
        verify(() => localAdapter.create(remoteEntity)).called(1);
      },
    );

    test('health stream reflects adapter health', () async {
      // Arrange: Stub the adapter's health check
      when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.unhealthy);
      when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);

      // Act & Assert
      // The health stream should emit a DatumHealth object reflecting the adapters' statuses.
      // Since the local adapter is unhealthy, the overall status should become degraded.
      expect(
        manager.health,
        emitsInOrder([
          // The stream first emits its initial 'healthy' state.
          isA<DatumHealth>().having((h) => h.status, 'status', DatumSyncHealth.healthy),
          // Then, after the health check runs, it emits the 'degraded' state.
          isA<DatumHealth>()
              .having((h) => h.status, 'status', DatumSyncHealth.degraded)
              .having((h) => h.localAdapterStatus, 'localAdapterStatus', AdapterHealthStatus.unhealthy)
              .having((h) => h.remoteAdapterStatus, 'remoteAdapterStatus', AdapterHealthStatus.healthy),
        ]),
      );

      // Act: Trigger the health check, which will cause the stream to emit.
      await manager.checkHealth();
    });

    test('watchStorageSize stream emits size updates', () async {
      // Arrange
      // Stub the watchStorageSize to return a stream of values.
      when(() => localAdapter.watchStorageSize(userId: 'user1')).thenAnswer(
        (_) => Stream.fromIterable([1024, 2048]),
      );

      // Act
      final stream = manager.watchStorageSize(userId: 'user1');

      // Assert
      // The manager's stream should emit the values from the adapter's stream.
      await expectLater(stream, emitsInOrder([1024, 2048]));

      verify(() => localAdapter.watchStorageSize(userId: 'user1')).called(1);
    });
  });

  group('DatumManager Pause and Resume', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('pauseSync prevents synchronization and updates status', () async {
      // Arrange
      manager.pauseSync();

      // Assert: Check that the status is updated to paused.
      expect(manager.currentStatus.status, DatumSyncStatus.paused);

      // Act: Attempt to synchronize while paused.
      final result = await manager.synchronize('user1');

      // Assert: The sync should be skipped.
      expect(result.wasSkipped, isTrue);
      expect(result.skipReason, 'Sync is paused');

      // Verify that no remote operations were attempted.
      verifyNever(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope')));
      verifyNever(() => remoteAdapter.create(any()));
    });

    test('resumeSync allows synchronization to proceed', () async {
      // Arrange
      manager.pauseSync();
      manager.resumeSync();

      // Act & Assert: Synchronization should now proceed normally.
      await expectLater(manager.synchronize('user1'), completes);
      verify(() => remoteAdapter.readAll(userId: 'user1', scope: any(named: 'scope'))).called(1);
    });
  });

  group('DatumManager Health and Storage', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig(enableLogging: false),
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('checkHealth calls checkHealth on both adapters', () async {
      // Arrange
      when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
      when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);

      // Act
      await manager.checkHealth();

      // Assert
      verify(() => localAdapter.checkHealth()).called(1);
      verify(() => remoteAdapter.checkHealth()).called(1);
    });

    test('getStorageSize calls getStorageSize on the local adapter', () async {
      // Arrange
      when(() => localAdapter.getStorageSize(userId: 'user1')).thenAnswer((_) async => 4096);

      // Act
      final size = await manager.getStorageSize(userId: 'user1');

      // Assert
      expect(size, 4096);
      verify(() => localAdapter.getStorageSize(userId: 'user1')).called(1);
    });

    test('getLastSyncResult calls getLastSyncResult on the local adapter', () async {
      // Arrange
      const mockResult = DatumSyncResult<TestEntity>(
        userId: 'user1',
        duration: Duration(seconds: 5),
        syncedCount: 10,
        failedCount: 0,
        conflictsResolved: 1,
        pendingOperations: [],
      );
      when(() => localAdapter.getLastSyncResult('user1')).thenAnswer((_) async => mockResult);

      // Act
      final result = await manager.getLastSyncResult('user1');

      // Assert
      expect(result, mockResult);
      verify(() => localAdapter.getLastSyncResult('user1')).called(1);
    });

    test('getPendingOperations calls getPending on the queue manager', () async {
      // Arrange
      final mockOps = [
        DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user1',
          entityId: 'e1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
        )
      ];
      when(() => localAdapter.getPendingOperations('user1')).thenAnswer((_) async => mockOps);

      // Act
      final ops = await manager.getPendingOperations('user1');

      // Assert
      expect(ops, mockOps);
      verify(() => localAdapter.getPendingOperations('user1')).called(1);
    });

    test('updateAndSync performs a push and then a synchronize', () async {
      // Arrange
      final initialEntity = TestEntity.create('e1', 'user1', 'Initial State');
      final updatedEntity = initialEntity.copyWith(name: 'Updated State');

      // Stub the internal read that push() performs to check for existence
      when(() => localAdapter.read(initialEntity.id, userId: 'user1')).thenAnswer((_) async => initialEntity);

      // Stub the patch call that push() will make for an update
      when(() => localAdapter.patch(id: 'e1', delta: any(named: 'delta'), userId: 'user1')).thenAnswer((_) async => updatedEntity);

      // Act
      final (savedItem, syncResult) = await manager.updateAndSync(
        item: updatedEntity,
        userId: 'user1',
      );

      // Assert
      expect(savedItem, updatedEntity);
      expect(syncResult.isSuccess, isTrue);
      verify(() => localAdapter.addPendingOperation('user1', any())).called(1);
      verify(() => remoteAdapter.readAll(userId: 'user1', scope: any(named: 'scope'))).called(1);
    });
  });
}

/// Helper function to apply all default stubs to a set of mocks.
void _stubDefaultBehaviors(
  MockedLocalAdapter<TestEntity> localAdapter,
  MockedRemoteAdapter<TestEntity> remoteAdapter,
  MockConnectivityChecker connectivityChecker,
) {
  // Connectivity
  when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

  // Initialization
  when(() => localAdapter.initialize()).thenAnswer((_) async {});
  when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
  when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
  when(
    () => localAdapter.changeStream(),
  ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
  when(
    () => remoteAdapter.changeStream,
  ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());

  // Disposal
  when(() => localAdapter.dispose()).thenAnswer((_) async {});
  when(() => remoteAdapter.dispose()).thenAnswer((_) async {});

  // Core Local Operations
  when(() => localAdapter.create(any())).thenAnswer((_) async {});
  when(() => localAdapter.update(any())).thenAnswer((_) async {});
  when(
    () => localAdapter.read(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => {});
  when(
    () => localAdapter.readAll(userId: any(named: 'userId')),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.delete(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => true);

  // Querying
  when(
    () => localAdapter.query(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => []);
  when(
    () => remoteAdapter.query(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => []);

  // Core Remote Operations
  when(
    () => remoteAdapter.readAll(
      userId: any(named: 'userId'),
      scope: any(named: 'scope'),
    ),
  ).thenAnswer((_) async => []);

  // Sync-related Operations
  when(
    () => localAdapter.getPendingOperations(any()),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.addPendingOperation(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => localAdapter.removePendingOperation(any()),
  ).thenAnswer((_) async {});

  // Metadata
  when(
    () => localAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => remoteAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});
  when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
  when(
    () => remoteAdapter.getSyncMetadata(any()),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.saveLastSyncResult(any(), any()),
  ).thenAnswer((_) async {});
  // Add missing stub for getLastSyncResult
  when(
    () => localAdapter.getLastSyncResult(any()),
  ).thenAnswer((_) async => null);

  // Health & Storage
  when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
  when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
  when(() => localAdapter.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
}
