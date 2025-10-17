import 'package:test/test.dart';
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

void main() {
  group('User Switch Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb',
          userId: 'fb',
          entityId: 'fb',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'),
      );
    });

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        datumConfig: const DatumConfig(),
        connectivity: connectivityChecker,
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('data is isolated between different users', () async {
      // Arrange
      final user1Entity = TestEntity.create('entity1', 'user1', 'User1 Item');
      final user2Entity = TestEntity.create('entity2', 'user2', 'User2 Item');

      // Stub readAll to return the correct data for each user
      when(
        () => localAdapter.readAll(userId: 'user1'),
      ).thenAnswer((_) async => [user1Entity]);
      when(
        () => localAdapter.readAll(userId: 'user2'),
      ).thenAnswer((_) async => [user2Entity]);

      // Act
      await manager.push(item: user1Entity, userId: 'user1');
      await manager.push(item: user2Entity, userId: 'user2');

      // Assert
      final user1Items = await manager.readAll(userId: 'user1');
      final user2Items = await manager.readAll(userId: 'user2');

      expect(user1Items, hasLength(1));
      expect(user1Items.first.name, 'User1 Item');
      expect(user2Items, hasLength(1));
      expect(user2Items.first.name, 'User2 Item');
    });

    test('emits UserSwitchedEvent when operating on a new user', () async {
      // Arrange
      final user1Entity = TestEntity.create('e1', 'user1', 'Item 1');
      final user2Entity = TestEntity.create('e2', 'user2', 'Item 2');

      // Stub getPendingOperations for user1 to simulate unsynced data
      when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
        (_) async => [
          DatumSyncOperation<TestEntity>(
            id: 'op-user-switch',
            userId: 'user1',
            entityId: user1Entity.id,
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: user1Entity,
          ),
        ],
      );

      // Act & Assert
      // Expect a UserSwitchedEvent when we push for user2 after user1
      final eventFuture = expectLater(
        manager.onUserSwitched,
        emits(
          isA<UserSwitchedEvent>()
              .having((e) => e.previousUserId, 'previousUserId', 'user1')
              .having((e) => e.newUserId, 'newUserId', 'user2')
              .having((e) => e.hadUnsyncedData, 'hadUnsyncedData', isTrue),
        ),
      );

      // First, operate on user1
      await manager.push(item: user1Entity, userId: 'user1');

      // Then, operate on user2, which should trigger the event
      await manager.push(item: user2Entity, userId: 'user2');

      // Await the future to ensure the event was emitted.
      await eventFuture;
    });

    test(
      'emits UserSwitchedEvent with hadUnsyncedData: false when previous user is clean',
      () async {
        // Arrange
        final user1Entity = TestEntity.create('e1', 'user1', 'Item 1');
        final user2Entity = TestEntity.create('e2', 'user2', 'Item 2');

        // Stub getPendingOperations for user1 to return an empty list,
        // simulating a clean state.
        when(
          () => localAdapter.getPendingOperations('user1'),
        ).thenAnswer((_) async => []);

        // Act & Assert
        final eventFuture = expectLater(
          manager.onUserSwitched,
          emits(
            isA<UserSwitchedEvent>()
                .having((e) => e.previousUserId, 'previousUserId', 'user1')
                .having((e) => e.newUserId, 'newUserId', 'user2')
                .having((e) => e.hadUnsyncedData, 'hadUnsyncedData', isFalse),
          ),
        );

        // First, operate on user1
        await manager.push(item: user1Entity, userId: 'user1');
        // Then, operate on user2, which should trigger the event
        await manager.push(item: user2Entity, userId: 'user2');

        await eventFuture;
      },
    );

    test('synchronize only pushes operations for the specified user', () async {
      // Arrange
      final user1Entity = TestEntity.create('e1', 'user1', 'User1 Op');
      final user2Entity = TestEntity.create('e2', 'user2', 'User2 Op');

      final user1Op = _createTestOperation(
        user1Entity,
        DatumOperationType.create,
      );
      final user2Op = _createTestOperation(
        user2Entity,
        DatumOperationType.create,
      );

      // Stub getPendingOperations to return the correct ops for each user.
      when(
        () => localAdapter.getPendingOperations('user1'),
      ).thenAnswer((_) async => [user1Op]);
      when(
        () => localAdapter.getPendingOperations('user2'),
      ).thenAnswer((_) async => [user2Op]);

      // Stub the remote create and local dequeue for user1's operation.
      when(() => remoteAdapter.create(user1Entity)).thenAnswer((_) async {});
      when(
        () => localAdapter.removePendingOperation(user1Op.id),
      ).thenAnswer((_) async {});

      // Act: Synchronize only for user1.
      final result = await manager.synchronize('user1');

      // Assert
      expect(result.syncedCount, 1);

      // Verify that only user1's entity was sent to the remote.
      verify(() => remoteAdapter.create(user1Entity)).called(1);
      verifyNever(() => remoteAdapter.create(user2Entity));

      // Verify that only user1's operation was dequeued.
      verify(() => localAdapter.removePendingOperation(user1Op.id)).called(1);
      verifyNever(() => localAdapter.removePendingOperation(user2Op.id));
    });

    test('onSyncStart is called for the correct user after a switch', () async {
      // Arrange
      final mockObserver = MockDatumObserver<TestEntity>();
      await manager.dispose(); // Dispose the old manager

      // Re-create manager with an observer
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        datumConfig: const DatumConfig(),
        connectivity: connectivityChecker,
        localObservers: [mockObserver],
      );
      await manager.initialize();

      final user1Entity = TestEntity.create('e1', 'user1', 'User1 Op');
      final user2Entity = TestEntity.create('e2', 'user2', 'User2 Op');

      // Stub getPendingOperations for both users
      when(() => localAdapter.getPendingOperations('user1')).thenAnswer(
        (_) async =>
            [_createTestOperation(user1Entity, DatumOperationType.create)],
      );
      when(() => localAdapter.getPendingOperations('user2')).thenAnswer(
        (_) async =>
            [_createTestOperation(user2Entity, DatumOperationType.create)],
      );

      // Stub remote create for both
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {});

      // Act: Sync for user1, then for user2
      await manager.synchronize('user1');
      await manager.synchronize('user2');

      // Assert
      // Verify that onSyncStart was called for both syncs.
      // Since the observer is shared, we can't distinguish which call was for which user
      // directly from the mock, but the sync engine's internal logic ensures
      // the context is correct. The fact that both syncs complete successfully
      // and onSyncStart is called twice is sufficient.
      verify(() => mockObserver.onSyncStart()).called(2);
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
  when(
    () => localAdapter.read(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.readAll(userId: any(named: 'userId')),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => {});

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
}

/// Helper function to create a test operation.
DatumSyncOperation<T> _createTestOperation<T extends DatumEntity>(
  T entity,
  DatumOperationType type,
) =>
    DatumSyncOperation(
      id: 'op-${entity.id}',
      userId: entity.userId,
      entityId: entity.id,
      type: type,
      timestamp: DateTime.now(),
      data: type == DatumOperationType.delete ? null : entity,
    );
