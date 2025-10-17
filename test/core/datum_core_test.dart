import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import '../integration/observer_integration_test.dart'
    show MockedLocalAdapter, MockedRemoteAdapter;
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// A second entity type for testing multi-manager scenarios.
class AnotherTestEntity extends DatumEntity {
  const AnotherTestEntity({
    required this.id,
    required this.userId,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final DateTime createdAt;
  @override
  final String id;
  @override
  final bool isDeleted;
  @override
  final DateTime modifiedAt;
  @override
  final String userId;
  @override
  final int version;

  @override
  DatumEntity copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    return this;
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) {
    return null;
  }

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) {
    return {'id': id, 'userId': userId};
  }
}

class MockGlobalObserver extends Mock implements GlobalDatumObserver {}

class MockLogger extends Mock implements DatumLogger {}

void main() {
  group('Datum Core', () {
    late Datum datum;
    late MockedLocalAdapter<TestEntity> localAdapter1;
    late MockedRemoteAdapter<TestEntity> remoteAdapter1;
    late MockedLocalAdapter<AnotherTestEntity> localAdapter2;
    late MockedRemoteAdapter<AnotherTestEntity> remoteAdapter2;
    late MockConnectivityChecker connectivityChecker;
    late MockGlobalObserver globalObserver;

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(
        const DatumSyncResult(
          userId: 'fb',
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: <DatumSyncOperation<DatumEntity>>[],
          duration: Duration.zero,
        ),
      );
      registerFallbackValue(
        AnotherTestEntity(
          id: 'fb',
          userId: 'fb',
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
          version: 0,
        ),
      );
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb-op',
          userId: 'fb',
          entityId: 'fb-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
          data: TestEntity.create('fb', 'fb', 'fb'),
        ),
      );
      registerFallbackValue(
        DatumSyncOperation<AnotherTestEntity>(
          id: 'fb-op-another',
          userId: 'fb',
          entityId: 'fb-another-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
          data: AnotherTestEntity(
            id: 'fb',
            userId: 'fb',
            modifiedAt: DateTime(0),
            createdAt: DateTime(0),
            version: 0,
          ),
        ),
      );
      registerFallbackValue(
        const DatumSyncMetadata(
          userId: 'fallback-user',
          dataHash: 'fallback-hash',
        ),
      );
    });

    setUp(() async {
      localAdapter1 = MockedLocalAdapter<TestEntity>();
      remoteAdapter1 = MockedRemoteAdapter<TestEntity>();
      localAdapter2 = MockedLocalAdapter<AnotherTestEntity>();
      remoteAdapter2 = MockedRemoteAdapter<AnotherTestEntity>();
      connectivityChecker = MockConnectivityChecker();
      globalObserver = MockGlobalObserver();

      // Stub default behaviors for all adapters
      _stubAdapterBehaviors<TestEntity>(localAdapter1, remoteAdapter1);
      _stubAdapterBehaviors<AnotherTestEntity>(localAdapter2, remoteAdapter2);
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      // Initialize Datum without any registrations in the main setUp.
      // Tests will be responsible for initializing their own instances.
    });

    tearDown(() async {
      // Dispose the static instance to ensure test isolation.
      Datum.resetForTesting();
    });

    test('register stores adapter pairs correctly', () async {
      // Arrange & Act: Initialize Datum with registrations.
      datum = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker, // Now required
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
          DatumRegistration<AnotherTestEntity>(
            localAdapter: localAdapter2,
            remoteAdapter: remoteAdapter2,
          ),
        ],
      );

      // Assert
      expect(Datum.manager<TestEntity>(), isA<DatumManager<TestEntity>>());
      expect(
        Datum.manager<AnotherTestEntity>(),
        isA<DatumManager<AnotherTestEntity>>(),
      );
    });

    test(
      'initialize creates and initializes managers for registered types',
      () async {
        // Arrange
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker, // Now required
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
          ],
        );

        // Assert
        verify(localAdapter1.initialize).called(1);
        verify(() => remoteAdapter1.initialize()).called(1);
        expect(
          Datum.manager<TestEntity>(),
          isA<DatumManager>().having(
            (manager) => manager,
            'manager',
            isA<DatumManager<TestEntity>>(),
          ),
        );
      },
    );

    test(
      'Datum.manager<T> returns the correct manager for a registered type',
      () async {
        // Arrange
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker, // Now required
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
          ],
        );

        // Act
        final retrievedManager = Datum.manager<TestEntity>();

        // Assert
        expect(retrievedManager, isA<DatumManager<TestEntity>>());
      },
    );

    test('manager<T> throws StateError for unregistered type', () {
      expect(() => Datum.manager<TestEntity>(), throwsA(isA<StateError>()));
    });

    test('uses default DatumLogger if none is provided', () async {
      datum = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker, // Now required
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
        ],
      );

      // To verify that the *internal* logger is being used (and is disabled),
      // we can't inspect it directly. Instead, we can create a separate mock
      // logger and confirm it's never used.
      final separateMockLogger = MockLogger();
      when(() => separateMockLogger.info(any())).thenAnswer((_) {});

      // Act: Perform an action that would normally log an info message.
      // We make the first sync slow to ensure the second one is skipped.
      final completer = Completer<List<TestEntity>>();
      when(
        () => remoteAdapter1.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) => completer.future);

      unawaited(datum.synchronize('user1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await datum.synchronize('user1');

      // Assert: The separate mock logger should never have been called,
      // proving the internal (disabled) logger was used.
      verifyNever(() => separateMockLogger.info(any()));
      completer.complete([]); // Clean up
    });

    test('CRUD methods delegate to the correct manager', () async {
      // Arrange
      datum = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker, // Now required
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
        ],
      );

      final entity = TestEntity.create('e1', 'u1', 'Test');

      // Act & Assert for create
      await Datum.instance.create<TestEntity>(entity);
      verify(() => localAdapter1.create(entity)).called(1);

      clearInteractions(localAdapter1);
      // Act & Assert for read
      when(
        () => localAdapter1.read('e1', userId: 'u1'),
      ).thenAnswer((_) async => entity);
      final result = await Datum.instance.read<TestEntity>('e1', userId: 'u1');
      expect(result, entity);
      verify(() => localAdapter1.read('e1', userId: 'u1')).called(1);

      // Act & Assert for delete
      when(
        () => localAdapter1.read('e1', userId: 'u1'),
      ).thenAnswer((_) async => entity);
      await Datum.instance.delete<TestEntity>(id: 'e1', userId: 'u1');
      verify(() => localAdapter1.delete('e1', userId: 'u1')).called(1);
    });
    test(
      'readAll and update methods delegate to the correct manager',
      () async {
        // Arrange
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker, // Now required
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
          ],
        );
        final entity = TestEntity.create('e1', 'u1', 'Test');
        when(
          () => localAdapter1.readAll(userId: 'u1'),
        ).thenAnswer((_) async => [entity]);
        await Datum.instance.readAll<TestEntity>(userId: 'u1');
        verify(() => localAdapter1.readAll(userId: 'u1')).called(1);

        // Arrange for update
        final updatedEntity = entity.copyWith(name: 'Updated');
        when(
          () => localAdapter1.read(entity.id, userId: 'u1'),
        ).thenAnswer((_) async => entity);
        when(
          () => localAdapter1.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async => updatedEntity);
        await Datum.instance.update<TestEntity>(updatedEntity);
        verify(
          () => localAdapter1.patch(
            id: 'e1',
            delta: any(named: 'delta'),
            userId: 'u1',
          ),
        ).called(1);
      },
    );

    test('global observer is passed to managers and receives events', () async {
      // Arrange
      datum = await Datum.initialize(
        config: const DatumConfig(enableLogging: false), // Now required
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
        ],
      )
        ..addObserver(globalObserver);

      // Act
      await Datum.instance.synchronize('user1');
      // Add a small delay to allow the asynchronous sync process to start
      // and call the observer before verification.
      await Future<void>.delayed(Duration.zero);

      // Assert
      verify(() => globalObserver.onSyncStart()).called(1);
      verify(() => globalObserver.onSyncEnd(any())).called(1);
    });

    test('global synchronize orchestrates push and pull phases', () async {
      // Arrange
      datum = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker, // Now required
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
          DatumRegistration<AnotherTestEntity>(
            localAdapter: localAdapter2,
            remoteAdapter: remoteAdapter2,
          ),
        ],
      );

      // Stub pending ops for TestEntity
      when(() => localAdapter1.getPendingOperations('user1')).thenAnswer(
        (_) async => [
          DatumSyncOperation<TestEntity>(
            id: 'op1',
            userId: 'user1',
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e1', 'user1', 'Test'),
          ),
        ],
      );
      // Stub remote data for AnotherTestEntity
      when(
        () => remoteAdapter2.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).thenAnswer(
        (_) async => [
          AnotherTestEntity(
            id: 'ae1',
            userId: 'user1',
            modifiedAt: DateTime.now(),
            createdAt: DateTime.now(),
            version: 1,
          ),
        ],
      );

      // Act
      await Datum.instance.synchronize('user1');

      // Assert
      // Push phase for TestEntity manager
      await Future.delayed(Duration.zero); // allow microtasks to run
      verify(() => remoteAdapter1.create(any())).called(1);

      // Pull phase for AnotherTestEntity manager
      verify(
        () => remoteAdapter2.readAll(
          userId: 'user1',
          scope: any(named: 'scope'),
        ),
      ).called(1);
      verify(() => localAdapter2.create(any())).called(1);
    });

    test('events stream emits events from synchronization', () async {
      // Arrange
      datum = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker, // Now required
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
        ],
      );

      // Stub a pending operation to ensure progress events are generated
      when(() => localAdapter1.getPendingOperations('user1')).thenAnswer(
        (_) async => [
          DatumSyncOperation<TestEntity>(
            id: 'op1',
            userId: 'user1',
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
            data: TestEntity.create('e1', 'user1', 'Test'),
          ),
        ],
      );

      // Act & Assert
      final eventFuture = expectLater(
        Datum.instance.events,
        emitsInOrder([
          isA<DatumSyncStartedEvent>(),
          isA<DatumSyncProgressEvent>(), // Event from the manager's engine
          isA<DatumSyncCompletedEvent>(),
        ]),
      );

      await Datum.instance.synchronize('user1');
      await eventFuture;
    });

    test(
      'synchronize skips if another sync is already in progress for the same user',
      () async {
        // Arrange
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker, // Now required
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
          ],
        );

        final syncCompleter = Completer<List<TestEntity>>();
        // Make the underlying manager's sync call slow
        when(
          () => remoteAdapter1.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        ).thenAnswer((_) => syncCompleter.future);

        // Act
        // Start the first sync, but don't await it
        final firstSyncFuture = Datum.instance.synchronize('user1');
        // Give it a moment to start and set the status to 'syncing'
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // Start the second sync while the first is blocked
        final secondSyncResult = await Datum.instance.synchronize('user1');

        // Assert
        expect(secondSyncResult.wasSkipped, isTrue);

        // Clean up by completing the first sync
        syncCompleter.complete([]);
        await firstSyncFuture;
      },
    );

    group('global synchronize with different directions', () {
      setUp(() async {
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false), // Now required
          connectivityChecker: connectivityChecker,
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
            DatumRegistration<AnotherTestEntity>(
              localAdapter: localAdapter2,
              remoteAdapter: remoteAdapter2,
            ),
          ],
        );

        // Stub pending ops for TestEntity (for push phase)
        when(() => localAdapter1.getPendingOperations('user1')).thenAnswer(
          (_) async => [
            DatumSyncOperation<TestEntity>(
              id: 'op1',
              userId: 'user1',
              entityId: 'e1',
              type: DatumOperationType.create,
              timestamp: DateTime.now(),
              data: TestEntity.create('e1', 'user1', 'Test'),
            ),
          ],
        );

        // Stub remote data for AnotherTestEntity (for pull phase)
        when(
          () => remoteAdapter2.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        ).thenAnswer(
          (_) async => [
            AnotherTestEntity(
              id: 'ae1',
              userId: 'user1',
              modifiedAt: DateTime.now(),
              createdAt: DateTime.now(),
              version: 1,
            ),
          ],
        );
      });

      test('pushThenPull executes push then pull', () async {
        // Act
        await Datum.instance.synchronize(
          'user1',
          options: const DatumSyncOptions(
            direction: SyncDirection.pushThenPull,
          ),
        );

        // Assert
        verifyInOrder([
          () => remoteAdapter1.create(any()), // Push
          () => remoteAdapter2.readAll(
                userId: 'user1',
                scope: any(named: 'scope'),
              ), // Pull
        ]);
      });

      test('pullThenPush executes pull then push', () async {
        // Act
        await Datum.instance.synchronize(
          'user1',
          options: const DatumSyncOptions(
            direction: SyncDirection.pullThenPush,
          ),
        );

        // Assert
        verifyInOrder([
          () => remoteAdapter2.readAll(
                userId: 'user1',
                scope: any(named: 'scope'),
              ), // Pull
          () => remoteAdapter1.create(any()), // Push
        ]);
      });

      test('pushOnly executes only push', () async {
        // Act
        await Datum.instance.synchronize(
          'user1',
          options: const DatumSyncOptions(direction: SyncDirection.pushOnly),
        );

        // Assert
        verify(() => remoteAdapter1.create(any())).called(1);
        verifyNever(
          () => remoteAdapter2.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        );
      });

      test('pullOnly executes only pull', () async {
        // Act
        await Datum.instance.synchronize(
          'user1',
          options: const DatumSyncOptions(direction: SyncDirection.pullOnly),
        );

        // Assert
        verifyNever(() => remoteAdapter1.create(any()));
        verify(
          () => remoteAdapter2.readAll(
            userId: 'user1',
            scope: any(named: 'scope'),
          ),
        ).called(1);
      });
    });

    group('Error and Edge Cases', () {
      test('synchronize skips remote calls when offline', () async {
        // Arrange
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker, // Now required
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
          ],
        );
        when(
          () => connectivityChecker.isConnected,
        ).thenAnswer((_) async => false);

        // Act
        final result = await Datum.instance.synchronize('user1');

        // Assert
        // The manager's internal check should skip, so no remote calls are made.
        verifyNever(() => remoteAdapter1.readAll(userId: any(named: 'userId')));
        verifyNever(() => remoteAdapter1.create(any()));

        // The global result should reflect that the underlying syncs were skipped.
        expect(result.syncedCount, 0);
      });

      test('synchronize propagates error from a failing manager', () async {
        // Arrange
        final exception = Exception('Remote is down!');
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker, // Now required
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
          ],
        );

        // Stub a pending operation to trigger a push
        when(() => localAdapter1.getPendingOperations('user1')).thenAnswer(
          (_) async => [
            DatumSyncOperation<TestEntity>(
              id: 'op1',
              userId: 'user1',
              entityId: 'e1',
              type: DatumOperationType.create,
              timestamp: DateTime.now(),
              data: TestEntity.create('e1', 'user1', 'Test'),
            ),
          ],
        );
        // Make the remote adapter throw an error
        when(() => remoteAdapter1.create(any())).thenThrow(exception);

        // Act & Assert: Await both the thrown exception and the emitted event
        // concurrently to avoid a race condition.
        final syncThrowsFuture = expectLater(
          () => Datum.instance.synchronize('user1'),
          throwsA(exception),
        );
        final errorEventFuture = expectLater(
          datum.events,
          // Use `emitsThrough` to find the error event in the stream, ignoring others.
          emitsThrough(
            isA<DatumSyncErrorEvent>().having(
              (e) => e.error,
              'error',
              exception,
            ),
          ),
        );
        await Future.wait([syncThrowsFuture, errorEventFuture]);
      });

      test('dispose correctly cleans up managers and subscriptions', () async {
        // Arrange
        datum = await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: connectivityChecker, // Now required
          registrations: [
            DatumRegistration<TestEntity>(
              localAdapter: localAdapter1,
              remoteAdapter: remoteAdapter1,
            ),
          ],
        );

        // Act
        await Datum.instance.dispose();

        // Assert
        // Verify that dispose was called on the underlying manager
        verify(() => localAdapter1.dispose()).called(1);
        // A closed stream will complete immediately.
        await expectLater(Datum.instance.events, emitsDone);
      });
    });

    test('statusForUser stream emits status updates', () async {
      // Arrange
      datum = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker, // Now required
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
        ],
      );

      // Act & Assert
      final statusFuture = expectLater(
        Datum.instance.statusForUser('user1').where((event) => event != null),
        emitsInOrder([
          isA<DatumSyncStatusSnapshot>().having(
            (s) => s.status,
            'status',
            DatumSyncStatus.syncing,
          ),
          isA<DatumSyncStatusSnapshot>().having(
            (s) => s.status,
            'status',
            DatumSyncStatus.completed,
          ),
        ]),
      );

      await Datum.instance.synchronize('user1');
      await statusFuture;
    });
  });
}

void _stubAdapterBehaviors<T extends DatumEntity>(
  MockedLocalAdapter<T> localAdapter,
  MockedRemoteAdapter<T> remoteAdapter,
) {
  when(() => localAdapter.initialize()).thenAnswer((_) async {});
  when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
  when(() => localAdapter.dispose()).thenAnswer((_) async {});
  when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
  when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
  when(
    () => localAdapter.getPendingOperations(any()),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.removePendingOperation(any()),
  ).thenAnswer((_) async {});
  when(
    () => localAdapter.addPendingOperation(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => localAdapter.read(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => null);
  when(
    () => localAdapter.delete(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => true);
  when(() => localAdapter.create(any())).thenAnswer((_) async {});
  when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
  when(() => remoteAdapter.update(any())).thenAnswer((_) async {});
  when(
    () => remoteAdapter.readAll(
      userId: any(named: 'userId'),
      scope: any(named: 'scope'),
    ),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => {});
  when(
    () => localAdapter.readAll(userId: any(named: 'userId')),
  ).thenAnswer((_) async => []);
  when(
    () => localAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => remoteAdapter.updateSyncMetadata(any(), any()),
  ).thenAnswer((_) async {});
}
