import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/relational_test_entity.dart';
import '../mocks/test_entity.dart';
import '../mocks/forward_bulk_writes.dart';

class MockLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements DatumConnectivityChecker {}

void main() {
  setUpAll(() {
    registerFallbackValue(TestEntity.create('fallback', 'fallback-user', 'Fallback Entity'));
    registerFallbackValue(DatumSyncOperation<TestEntity>(
      id: 'fallback-operation',
      userId: 'fallback-user',
      type: DatumOperationType.create,
      entityId: 'fallback-entity',
      timestamp: DateTime.now(),
    ));
  });

  group('Remote Change Subscription Management', () {
    late MockConnectivityChecker connectivityChecker;

    setUp(() {
      connectivityChecker = MockConnectivityChecker();
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => Stream.value(true));
    });

    tearDown(() {
      Datum.resetForTesting();
    });

    group('DatumManager remote change subscription', () {
      late DatumManager<TestEntity> manager;
      late MockLocalAdapter<TestEntity> localAdapter;
      late MockRemoteAdapter<TestEntity> remoteAdapter;

      setUp(() async {
        localAdapter = MockLocalAdapter<TestEntity>();
        remoteAdapter = MockRemoteAdapter<TestEntity>();

        // Set up basic adapter stubs BEFORE Datum.initialize
        when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
        when(() => localAdapter.initialize()).thenAnswer((_) async {});
        when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
        when(() => localAdapter.dispose()).thenAnswer((_) async {});
        when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
        when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
        when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
        when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
        when(() => localAdapter.getAllUserIds()).thenAnswer((_) async => []);
        when(() => localAdapter.read(any(), userId: any(named: 'userId'))).thenAnswer((_) async => null);
        when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
        when(() => localAdapter.create(any())).thenAnswer((_) async {});
        when(() => localAdapter.addPendingOperation(any(), any())).thenAnswer((_) async {});
        when(() => localAdapter.patch(id: any(named: 'id'), delta: any(named: 'delta'), userId: any(named: 'userId'))).thenAnswer((_) async => TestEntity.create('test', 'user1', 'Test Item'));
        when(() => localAdapter.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
        when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter.changeStream).thenReturn(null);
        when(() => remoteAdapter.unsubscribeFromChanges()).thenAnswer((_) async {});
        when(() => remoteAdapter.resubscribeToChanges()).thenAnswer((_) async {});

        final registration = DatumRegistration<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
        );

        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker,
          registrations: [registration],
        );

        manager = Datum.manager<TestEntity>();
      });

      test('unsubscribeFromRemoteChanges stops listening to remote changes', () async {
        // Ensure we start from a subscribed state
        await manager.resubscribeToRemoteChanges();
        expect(manager.isSubscribedToRemoteChanges, isTrue);

        // Unsubscribe from remote changes
        await manager.unsubscribeFromRemoteChanges();

        // Now it should not be subscribed
        expect(manager.isSubscribedToRemoteChanges, isFalse);
      });

      test('resubscribeToRemoteChanges resumes listening to remote changes', () async {
        // Start by unsubscribing
        await manager.unsubscribeFromRemoteChanges();
        expect(manager.isSubscribedToRemoteChanges, isFalse);

        // Resubscribe to remote changes
        await manager.resubscribeToRemoteChanges();

        // Now it should be subscribed again
        expect(manager.isSubscribedToRemoteChanges, isTrue);
      });

      test('multiple unsubscribe calls are idempotent', () async {
        // Ensure we start from a subscribed state
        await manager.resubscribeToRemoteChanges();
        expect(manager.isSubscribedToRemoteChanges, isTrue);

        // Multiple unsubscribes should be safe
        await manager.unsubscribeFromRemoteChanges();
        await manager.unsubscribeFromRemoteChanges();
        await manager.unsubscribeFromRemoteChanges();

        expect(manager.isSubscribedToRemoteChanges, isFalse);
      });

      test('multiple resubscribe calls are idempotent', () async {
        // Start unsubscribed
        await manager.unsubscribeFromRemoteChanges();
        expect(manager.isSubscribedToRemoteChanges, isFalse);

        // Multiple resubscribes should be safe
        await manager.resubscribeToRemoteChanges();
        await manager.resubscribeToRemoteChanges();
        await manager.resubscribeToRemoteChanges();

        expect(manager.isSubscribedToRemoteChanges, isTrue);
      });
    });

    group('Datum global remote change subscription', () {
      late DatumManager<TestEntity> manager1;
      late DatumManager<RelationalTestEntity> manager2;

      setUp(() async {
        final localAdapter1 = MockLocalAdapter<TestEntity>();
        final remoteAdapter1 = MockRemoteAdapter<TestEntity>();
        final localAdapter2 = MockLocalAdapter<RelationalTestEntity>();
        final remoteAdapter2 = MockRemoteAdapter<RelationalTestEntity>();

        // Set up basic adapter stubs
        when(() => localAdapter1.getStoredSchemaVersion()).thenAnswer((_) async => 0);
        when(() => localAdapter1.initialize()).thenAnswer((_) async {});
        when(() => remoteAdapter1.initialize()).thenAnswer((_) async {});
        when(() => localAdapter1.dispose()).thenAnswer((_) async {});
        when(() => remoteAdapter1.dispose()).thenAnswer((_) async {});
        when(() => localAdapter1.getPendingOperations(any())).thenAnswer((_) async => []);
        when(() => localAdapter1.getSyncMetadata(any())).thenAnswer((_) async => null);
        when(() => localAdapter1.getLastSyncResult(any())).thenAnswer((_) async => null);
        when(() => localAdapter1.getAllUserIds()).thenAnswer((_) async => []);
        when(() => localAdapter1.read(any(), userId: any(named: 'userId'))).thenAnswer((_) async => null);
        when(() => localAdapter1.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
        when(() => localAdapter1.create(any())).thenAnswer((_) async {});
        when(() => localAdapter1.patch(id: any(named: 'id'), delta: any(named: 'delta'), userId: any(named: 'userId'))).thenAnswer((_) async => TestEntity.create('test', 'user1', 'Test Item'));
        when(() => localAdapter1.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
        when(() => localAdapter1.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter1.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter1.changeStream).thenReturn(null);
        when(() => remoteAdapter1.unsubscribeFromChanges()).thenAnswer((_) async {});
        when(() => remoteAdapter1.resubscribeToChanges()).thenAnswer((_) async {});

        when(() => localAdapter2.getStoredSchemaVersion()).thenAnswer((_) async => 0);
        when(() => localAdapter2.initialize()).thenAnswer((_) async {});
        when(() => remoteAdapter2.initialize()).thenAnswer((_) async {});
        when(() => localAdapter2.dispose()).thenAnswer((_) async {});
        when(() => remoteAdapter2.dispose()).thenAnswer((_) async {});
        when(() => localAdapter2.getPendingOperations(any())).thenAnswer((_) async => []);
        when(() => localAdapter2.getSyncMetadata(any())).thenAnswer((_) async => null);
        when(() => localAdapter2.getLastSyncResult(any())).thenAnswer((_) async => null);
        when(() => localAdapter2.getAllUserIds()).thenAnswer((_) async => []);
        when(() => localAdapter2.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
        when(() => localAdapter2.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
        when(() => localAdapter2.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter2.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter2.changeStream).thenReturn(null);
        when(() => remoteAdapter2.unsubscribeFromChanges()).thenAnswer((_) async {});
        when(() => remoteAdapter2.resubscribeToChanges()).thenAnswer((_) async {});

        final registration1 = DatumRegistration<TestEntity>(
          localAdapter: localAdapter1,
          remoteAdapter: remoteAdapter1,
        );

        final registration2 = DatumRegistration<RelationalTestEntity>(
          localAdapter: localAdapter2,
          remoteAdapter: remoteAdapter2,
        );

        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker,
          registrations: [registration1, registration2],
        );

        manager1 = Datum.manager<TestEntity>();
        manager2 = Datum.manager<RelationalTestEntity>();
      });

      test('unsubscribeAllFromRemoteChanges unsubscribes all managers', () async {
        // Initially all managers should be subscribed
        expect(manager1.isSubscribedToRemoteChanges, isTrue);
        expect(manager2.isSubscribedToRemoteChanges, isTrue);

        // Unsubscribe all from remote changes
        await Datum.instance.unsubscribeAllFromRemoteChanges();

        // All managers should now be unsubscribed
        expect(manager1.isSubscribedToRemoteChanges, isFalse);
        expect(manager2.isSubscribedToRemoteChanges, isFalse);
      });

      test('resubscribeAllToRemoteChanges resubscribes all managers', () async {
        // Start by unsubscribing all
        await Datum.instance.unsubscribeAllFromRemoteChanges();
        expect(manager1.isSubscribedToRemoteChanges, isFalse);
        expect(manager2.isSubscribedToRemoteChanges, isFalse);

        // Resubscribe all to remote changes
        await Datum.instance.resubscribeAllToRemoteChanges();

        // All managers should now be subscribed again
        expect(manager1.isSubscribedToRemoteChanges, isTrue);
        expect(manager2.isSubscribedToRemoteChanges, isTrue);
      });

      test('unsubscribeAllFromRemoteChanges works with empty manager registry', () async {
        // Reset Datum to have no managers
        Datum.resetForTesting();

        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker,
          registrations: [], // No registrations
        );

        // Should not throw an error
        expect(() => Datum.instance.unsubscribeAllFromRemoteChanges(), returnsNormally);
      });

      test('resubscribeAllToRemoteChanges works with empty manager registry', () async {
        // Reset Datum to have no managers
        Datum.resetForTesting();

        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker,
          registrations: [], // No registrations
        );

        // Should not throw an error
        expect(() => Datum.instance.resubscribeAllToRemoteChanges(), returnsNormally);
      });
    });

    group('Subscription state persistence', () {
      late DatumManager<TestEntity> manager;

      setUp(() async {
        final localAdapter = MockLocalAdapter<TestEntity>();
        final remoteAdapter = MockRemoteAdapter<TestEntity>();

        // Set up basic adapter stubs
        when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
        when(() => localAdapter.initialize()).thenAnswer((_) async {});
        when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
        when(() => localAdapter.dispose()).thenAnswer((_) async {});
        when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
        when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
        when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
        when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
        when(() => localAdapter.getAllUserIds()).thenAnswer((_) async => []);
        when(() => localAdapter.read(any(), userId: any(named: 'userId'))).thenAnswer((_) async => null);
        when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
        when(() => localAdapter.create(any())).thenAnswer((_) async {});
        when(() => localAdapter.addPendingOperation(any(), any())).thenAnswer((_) async {});
        when(() => localAdapter.patch(id: any(named: 'id'), delta: any(named: 'delta'), userId: any(named: 'userId'))).thenAnswer((_) async => TestEntity.create('test', 'user1', 'Test Item'));
        when(() => localAdapter.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
        when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
        when(() => remoteAdapter.changeStream).thenReturn(null);
        when(() => remoteAdapter.unsubscribeFromChanges()).thenAnswer((_) async {});
        when(() => remoteAdapter.resubscribeToChanges()).thenAnswer((_) async {});

        final registration = DatumRegistration<TestEntity>(
          localAdapter: localAdapter,
          remoteAdapter: remoteAdapter,
        );

        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker,
          registrations: [registration],
        );

        manager = Datum.manager<TestEntity>();
      });

      test('subscription state is maintained across operations', () async {
        // Ensure we start from a subscribed state
        await manager.resubscribeToRemoteChanges();
        expect(manager.isSubscribedToRemoteChanges, isTrue);

        // Unsubscribe
        await manager.unsubscribeFromRemoteChanges();
        expect(manager.isSubscribedToRemoteChanges, isFalse);

        // Perform some operations - subscription state should persist
        await manager.push(item: TestEntity.create('test', 'user1', 'Test Item'), userId: 'user1');
        expect(manager.isSubscribedToRemoteChanges, isFalse);

        // Read operations shouldn't change subscription state
        await manager.readAll(userId: 'user1');
        expect(manager.isSubscribedToRemoteChanges, isFalse);

        // Resubscribe
        await manager.resubscribeToRemoteChanges();
        expect(manager.isSubscribedToRemoteChanges, isTrue);

        // More operations shouldn't change state
        await manager.push(item: TestEntity.create('test2', 'user1', 'Test Item 2'), userId: 'user1');
        expect(manager.isSubscribedToRemoteChanges, isTrue);
      });
    });
  });
}
