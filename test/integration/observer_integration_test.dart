import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/datum.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class MockedLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

class MockDatumObserver<T extends DatumEntity> extends Mock
    implements DatumObserver<T> {}

class MockGlobalDatumObserver extends Mock implements GlobalDatumObserver {}

void main() {
  group('DatumObserver Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late MockDatumObserver<TestEntity> mockObserver;

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(DataSource.local);
      registerFallbackValue(
        const DatumSyncMetadata(
          userId: 'fb',
          lastSyncTime: null,
          dataHash: 'fb',
        ),
      );
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb',
          userId: 'fb',
          entityId: 'fb',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(StackTrace.empty);
      registerFallbackValue(
        DatumConflictContext(
          userId: 'fb',
          entityId: 'fb',
          type: DatumConflictType.bothModified,
          detectedAt: DateTime(0),
        ),
      );
      registerFallbackValue(DatumConflictResolution<TestEntity>.abort('fb'));
      registerFallbackValue(
        const DatumSyncResult(
          userId: 'fb',
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
          duration: Duration.zero,
        ),
      );
    });

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();
      mockObserver = MockDatumObserver<TestEntity>();

      // Apply default stubs for all mocks
      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      // The manager needs to be created with the event stream to notify observers.
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: LastWriteWinsResolver<TestEntity>(),
        datumConfig: const DatumConfig(maxRetries: 0),
        connectivity: connectivityChecker,
        // The key fix: pass the observer to the manager's constructor.
        localObservers: [mockObserver],
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('onSyncStart and onSyncEnd are called during synchronize', () async {
      await manager.synchronize('user1');

      verify(() => mockObserver.onSyncStart()).called(1);

      verify(
        () => mockObserver.onSyncEnd(any(that: isA<DatumSyncResult>())),
      ).called(1);
    });

    test(
      'onCreateStart and onCreateEnd are called for a successful push op',
      () async {
        final entity = TestEntity.create('op-e1', 'user1', 'Op Success');
        await manager.push(item: entity, userId: 'user1');

        // Verify that the create hooks were called in order.
        verifyInOrder([
          () => mockObserver.onCreateStart(entity),
          () => mockObserver.onCreateEnd(entity),
        ]);
      },
    );

    test(
      'onUpdateStart and onUpdateEnd are called for a successful push op',
      () async {
        final initialEntity = TestEntity.create('op-e2', 'user1', 'Initial');
        final updatedEntity = initialEntity.copyWith(name: 'Updated');

        // Stub the read to return the initial entity, so a diff is created.
        when(
          () => localAdapter.read(initialEntity.id, userId: 'user1'),
        ).thenAnswer((_) async => initialEntity);
        // Stub the patch operation which is called for updates.
        when(
          () => localAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async => updatedEntity);

        await manager.push(item: updatedEntity, userId: 'user1');

        // Verify that the update hooks were called in order.
        verifyInOrder([
          () => mockObserver.onUpdateStart(updatedEntity),
          () => mockObserver.onUpdateEnd(updatedEntity),
        ]);
      },
    );

    test(
      'onDeleteStart and onDeleteEnd are called for a successful delete op',
      () async {
        final entity = TestEntity.create('op-e3', 'user1', 'To Delete');
        when(
          () => localAdapter.read(entity.id, userId: 'user1'),
        ).thenAnswer((_) async => entity);
        when(
          () => localAdapter.delete(entity.id, userId: 'user1'),
        ).thenAnswer((_) async => true);

        await manager.delete(id: entity.id, userId: 'user1');

        verifyInOrder([
          () => mockObserver.onDeleteStart(entity.id),
          () => mockObserver.onDeleteEnd(entity.id, success: true),
        ]);
      },
    );

    test(
      'onDeleteEnd is called with success: false on failed delete op',
      () async {
        final entity = TestEntity.create('op-e4', 'user1', 'To Delete');
        when(
          () => localAdapter.read(entity.id, userId: 'user1'),
        ).thenAnswer((_) async => entity);
        // Simulate a failure in the adapter
        when(
          () => localAdapter.delete(entity.id, userId: 'user1'),
        ).thenAnswer((_) async => false);

        await manager.delete(id: entity.id, userId: 'user1');

        verify(
          () => mockObserver.onDeleteEnd(entity.id, success: false),
        ).called(1);
      },
    );

    test(
      'onOperationFailure is called for a failed sync op',
      skip: 'onOperation* methods are not part of the public observer API.',
      () async {},
    );

    test('onConflictDetected and onConflictResolved are called', () async {
      final baseTime = DateTime.now();
      final local = TestEntity(
        id: 'conflict-1',
        userId: 'user1',
        name: 'Local',
        value: 1,
        modifiedAt: baseTime,
        createdAt: baseTime,
        version: 1,
      );
      final remote = local.copyWith(
        name: 'Remote',
        modifiedAt: baseTime.add(const Duration(seconds: 1)),
        version: 2,
      );

      when(
        () => localAdapter.readByIds(['conflict-1'], userId: 'user1'),
      ).thenAnswer((_) async => {'conflict-1': local});
      when(
        () => remoteAdapter.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => [remote]);
      // This stub is crucial for the conflict resolver to save the winning entity.
      when(() => localAdapter.update(any())).thenAnswer((_) async {});

      // Stub the onConflictResolved method for the mock observer
      when(() => mockObserver.onConflictResolved(any())).thenAnswer((_) {});

      await manager.synchronize('user1');
      verify(
        () => mockObserver.onConflictDetected(
          any(that: predicate<TestEntity>((e) => e.id == local.id)),
          any(that: predicate<TestEntity>((e) => e.id == remote.id)),
          any(that: isA<DatumConflictContext>()),
        ),
      ).called(1);

      verify(
        () => mockObserver.onConflictResolved(
          any(that: isA<DatumConflictResolution<TestEntity>>()),
        ),
      ).called(1);
    });
  });

  group('GlobalDatumObserver Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late MockGlobalDatumObserver mockGlobalObserver;

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();
      mockGlobalObserver = MockGlobalDatumObserver();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        datumConfig: const DatumConfig(maxRetries: 0),
        connectivity: connectivityChecker,
        globalObservers: [mockGlobalObserver],
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('onSyncStart and onSyncEnd are called during synchronize', () async {
      await manager.synchronize('user1');

      verify(() => mockGlobalObserver.onSyncStart()).called(1);
      verify(
        () => mockGlobalObserver.onSyncEnd(any(that: isA<DatumSyncResult>())),
      ).called(1);
    });

    test('onCreateStart is called on push', () async {
      final entity = TestEntity.create('global-e1', 'user1', 'Global Test');
      await manager.push(item: entity, userId: 'user1');
      verify(() => mockGlobalObserver.onCreateStart(entity)).called(1);
    });

    test('onUpdateStart and onUpdateEnd are called on push', () async {
      final initialEntity = TestEntity.create('global-e2', 'user1', 'Initial');
      final updatedEntity = initialEntity.copyWith(name: 'Updated');

      when(
        () => localAdapter.read(initialEntity.id, userId: 'user1'),
      ).thenAnswer((_) async => initialEntity);
      when(
        () => localAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async => updatedEntity);

      await manager.push(item: updatedEntity, userId: 'user1');

      verifyInOrder([
        () => mockGlobalObserver.onUpdateStart(updatedEntity),
        () => mockGlobalObserver.onUpdateEnd(updatedEntity),
      ]);
    });

    test('onDeleteStart and onDeleteEnd are called on delete', () async {
      final entity = TestEntity.create('global-e3', 'user1', 'To Delete');
      when(
        () => localAdapter.read(entity.id, userId: 'user1'),
      ).thenAnswer((_) async => entity);
      when(
        () => localAdapter.delete(entity.id, userId: 'user1'),
      ).thenAnswer((_) async => true);

      await manager.delete(id: entity.id, userId: 'user1');

      verifyInOrder([
        () => mockGlobalObserver.onDeleteStart(entity.id),
        () => mockGlobalObserver.onDeleteEnd(entity.id, success: true),
      ]);
    });

    test('onConflictDetected and onConflictResolved are called', () async {
      final baseTime = DateTime.now();
      final local = TestEntity(
        id: 'conflict-g1',
        userId: 'user1',
        name: 'Local',
        value: 1,
        modifiedAt: baseTime,
        createdAt: baseTime,
        version: 1,
      );
      final remote = local.copyWith(
        name: 'Remote',
        modifiedAt: baseTime.add(const Duration(seconds: 1)),
        version: 2,
      );

      when(
        () => localAdapter.readByIds(['conflict-g1'], userId: 'user1'),
      ).thenAnswer((_) async => {'conflict-g1': local});
      when(
        () => remoteAdapter.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => [remote]);
      when(() => localAdapter.update(any())).thenAnswer((_) async {});

      // Stub observer methods to prevent mocktail from hanging on async calls
      when(
        () => mockGlobalObserver.onConflictDetected(any(), any(), any()),
      ).thenAnswer((_) {});
      when(
        () => mockGlobalObserver.onConflictResolved(any()),
      ).thenAnswer((_) {});

      await manager.synchronize('user1');

      verify(
        () => mockGlobalObserver.onConflictDetected(
          any(that: predicate<DatumEntity>((e) => e.id == local.id)),
          any(that: predicate<DatumEntity>((e) => e.id == remote.id)),
          any(that: isA<DatumConflictContext>()),
        ),
      ).called(1);

      verify(
        () => mockGlobalObserver.onConflictResolved(
          any(
            that: isA<DatumConflictResolution<DatumEntity>>().having(
              (r) => r.strategy,
              'strategy',
              DatumResolutionStrategy.takeRemote,
            ),
          ),
        ),
      ).called(1);
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

  // Core Operations
  when(() => localAdapter.create(any())).thenAnswer((_) async {});
  when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
  when(() => localAdapter.update(any())).thenAnswer((_) async {});
  when(
    () => localAdapter.addPendingOperation(any(), any()),
  ).thenAnswer((_) async {});
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
    () => remoteAdapter.readAll(
      userId: any(named: 'userId'),
      scope: any(named: 'scope'),
    ),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.patch(
      id: any(named: 'id'),
      delta: any(named: 'delta'),
      userId: any(named: 'userId'),
    ),
  ).thenAnswer(
    (inv) async =>
        TestEntity.fromJson(inv.namedArguments[#delta] as Map<String, dynamic>),
  );
  when(
    () => remoteAdapter.patch(
      id: any(named: 'id'),
      delta: any(named: 'delta'),
      userId: any(named: 'userId'),
    ),
  ).thenAnswer(
    (inv) async => TestEntity.create('patched', 'user1', 'Patched remotely'),
  );
  when(() => remoteAdapter.update(any())).thenAnswer((_) async {});

  // Sync-related Operations
  when(
    () => localAdapter.getPendingOperations(any()),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.removePendingOperation(any()),
  ).thenAnswer((_) async {});

  // Metadata
  when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
  when(
    () => remoteAdapter.getSyncMetadata(any()),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => remoteAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});

  // Delete
  when(
    () => localAdapter.delete(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => true);
  when(
    () => remoteAdapter.delete(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async {});
}
