import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class MockLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

class MockDatumObserver<T extends DatumEntity> extends Mock
    implements DatumObserver<T> {}

void main() {
  group('DatumManager User Switching', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late MockDatumObserver<TestEntity> mockObserver;

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb-op',
          userId: 'fb',
          entityId: 'fb-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        const DatumSyncMetadata(
          userId: 'fallback-user',
          dataHash: 'fallback-hash',
        ),
      );
      registerFallbackValue(
        const DatumUserSwitchResult(success: false, newUserId: 'fb'),
      );
      registerFallbackValue(
        UserSwitchStrategy.keepLocal,
      ); // Add fallback for the enum
    });

    setUp(() {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();
      mockObserver = MockDatumObserver<TestEntity>();

      // Stub observer methods to prevent tests from hanging on async calls
      when(
        () => mockObserver.onUserSwitchStart(any(), any(), any()),
      ).thenAnswer((_) {});
      when(() => mockObserver.onUserSwitchEnd(any())).thenAnswer((_) {});

      // Default stubs
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(() => remoteAdapter.create(any())).thenAnswer((_) async {});
      when(() => localAdapter.create(any())).thenAnswer((_) async {});
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.addPendingOperation(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.removePendingOperation(any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.clearUserData(any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
    });

    Future<DatumManager<TestEntity>> createManager({
      DatumConfig<TestEntity>? config,
    }) async {
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: config ?? const DatumConfig(),
        // The key fix: pass the observer to the manager's constructor.
        localObservers: [mockObserver],
      );
      await manager.initialize();
      return manager;
    }

    group('with promptIfUnsyncedData strategy', () {
      test('returns a failed result if pending ops exist', () async {
        // Arrange
        final manager = await createManager();
        when(() => localAdapter.getPendingOperations('oldUser')).thenAnswer(
          (_) async => [
            DatumSyncOperation<TestEntity>(
              id: 'op1',
              userId: 'oldUser',
              entityId: 'e1',
              type: DatumOperationType.create,
              timestamp: DateTime.now(),
              data: TestEntity.create('e1', 'oldUser', 'Test'),
            ),
          ],
        );

        // Act
        final result = await manager.switchUser(
          oldUserId: 'oldUser',
          newUserId: 'newUser',
          strategy: UserSwitchStrategy.promptIfUnsyncedData,
        );

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Unsynced data exists'));

        // Verify observer calls
        verify(
          () => mockObserver.onUserSwitchStart(
            'oldUser',
            'newUser',
            UserSwitchStrategy.promptIfUnsyncedData,
          ),
        ).called(1);
        verify(() => mockObserver.onUserSwitchEnd(result)).called(1);
      });

      test('returns a successful result if no pending ops exist', () async {
        // Arrange
        final manager = await createManager();
        when(
          () => localAdapter.getPendingOperations('oldUser'),
        ).thenAnswer((_) async => []);

        // Act
        final result = await manager.switchUser(
          oldUserId: 'oldUser',
          newUserId: 'newUser',
          strategy: UserSwitchStrategy.promptIfUnsyncedData,
        );

        // Assert
        expect(result.success, isTrue);
        verify(
          () => mockObserver.onUserSwitchStart(
            'oldUser',
            'newUser',
            UserSwitchStrategy.promptIfUnsyncedData,
          ),
        ).called(1);
        verify(() => mockObserver.onUserSwitchEnd(result)).called(1);
      });
    });

    group('with syncThenSwitch strategy', () {
      test('triggers synchronize for old user if pending ops exist', () async {
        // Arrange
        final manager = await createManager();
        when(() => localAdapter.getPendingOperations('oldUser')).thenAnswer(
          (_) async => [
            DatumSyncOperation<TestEntity>(
              id: 'op1',
              userId: 'oldUser',
              entityId: 'e1',
              type: DatumOperationType.create,
              timestamp: DateTime.now(),
              data: TestEntity.create('e1', 'oldUser', 'Test'),
            ),
          ],
        );
        when(
          () => remoteAdapter.create(any()),
        ).thenAnswer((_) async {});
        when(
          () => localAdapter.removePendingOperation(any()),
        ).thenAnswer((_) async {});

        // Act
        final result = await manager
            .switchUser(
          oldUserId: 'oldUser',
          newUserId: 'newUser',
          strategy: UserSwitchStrategy.syncThenSwitch,
        )
            .catchError((e) {
          // This catch block is to understand why the test might fail.
          // In a real scenario, the sync might throw, and that should be handled.
          // For this test, we just want to verify the switch result.
          // If sync fails, switchUser will also fail.
          return DatumUserSwitchResult.failure(
            newUserId: 'newUser',
            errorMessage: e.toString(),
          );
        });

        // Assert
        expect(result.success, isTrue);
        // Verify that synchronize was called for the old user.
        verify(() => remoteAdapter.create(any())).called(1);
        verify(
          () => mockObserver.onUserSwitchStart(
            'oldUser',
            'newUser',
            UserSwitchStrategy.syncThenSwitch,
          ),
        ).called(1);
        verify(() => mockObserver.onUserSwitchEnd(result)).called(1);
      });

      test('does not trigger synchronize if no pending ops exist', () async {
        // Arrange
        final manager = await createManager();
        when(
          () => localAdapter.getPendingOperations('oldUser'),
        ).thenAnswer((_) async => []);

        // Act
        final result = await manager.switchUser(
          oldUserId: 'oldUser',
          newUserId: 'newUser',
          strategy: UserSwitchStrategy.syncThenSwitch,
        );

        // Assert
        expect(result.success, isTrue);
        // Verify that synchronize was NOT called.
        verifyNever(() => remoteAdapter.create(any()));
        verify(
          () => mockObserver.onUserSwitchStart(
            'oldUser',
            'newUser',
            UserSwitchStrategy.syncThenSwitch,
          ),
        ).called(1);
        verify(() => mockObserver.onUserSwitchEnd(result)).called(1);
      });
    });

    group('with clearAndFetch strategy', () {
      test("clears new user's local data and triggers a sync", () async {
        // Arrange
        // Stub getPendingOperations for both users to prevent null errors.
        when(
          () => localAdapter.getPendingOperations('oldUser'),
        ).thenAnswer((_) async => []);
        when(
          () => localAdapter.getPendingOperations('newUser'),
        ).thenAnswer((_) async => []);
        final manager = await createManager();

        // Act
        final result = await manager.switchUser(
          oldUserId: 'oldUser',
          newUserId: 'newUser',
          strategy: UserSwitchStrategy.clearAndFetch,
        );

        // Assert
        expect(result.success, isTrue);
        // Verify that the local data for the NEW user was cleared.
        verify(() => localAdapter.clearUserData('newUser')).called(1);
        // Verify that a sync (pull phase) was triggered for the NEW user.
        verify(
          () => remoteAdapter.readAll(
            userId: 'newUser',
            scope: any(named: 'scope'),
          ),
        ).called(1);
      });
    });

    group('with keepLocal strategy', () {
      test('switches user without performing any data operations', () async {
        // Arrange
        when(
          () => localAdapter.getPendingOperations('oldUser'),
        ).thenAnswer((_) async => []);
        final manager = await createManager();

        // Act
        final result = await manager.switchUser(
          oldUserId: 'oldUser',
          newUserId: 'newUser',
          strategy: UserSwitchStrategy.keepLocal,
        );

        // Assert
        expect(result.success, isTrue);
        verifyNever(() => localAdapter.clearUserData(any()));
        verifyNever(() => remoteAdapter.create(any()));
        verifyNever(() => remoteAdapter.readAll(userId: any(named: 'userId')));
      });
    });

    group('Event and Observer Notifications', () {
      test('emits UserSwitchedEvent on successful switch', () async {
        // Arrange
        final manager = await createManager();
        when(
          () => localAdapter.getPendingOperations('oldUser'),
        ).thenAnswer((_) async => []);

        // Act & Assert
        final eventFuture = expectLater(
          manager.onUserSwitched,
          emits(
            isA<UserSwitchedEvent>()
                .having((e) => e.previousUserId, 'previousUserId', 'oldUser')
                .having((e) => e.newUserId, 'newUserId', 'newUser'),
          ),
        );

        await manager.switchUser(oldUserId: 'oldUser', newUserId: 'newUser');

        await eventFuture;
      });
    });

    group('Edge Cases', () {
      test('handles switch from null (initial login)', () async {
        // Arrange
        final manager = await createManager();

        // Act
        final result = await manager.switchUser(
          oldUserId: null,
          newUserId: 'newUser',
          strategy: UserSwitchStrategy.keepLocal,
        );

        // Assert
        expect(result.success, isTrue);
        verify(
          () => mockObserver.onUserSwitchStart(
            null,
            'newUser',
            UserSwitchStrategy.keepLocal,
          ),
        ).called(1);
        verify(() => mockObserver.onUserSwitchEnd(result)).called(1);
        // No sync or clear operations should be called for a null old user
        verifyNever(() => localAdapter.getPendingOperations(any()));
      });

      test('handles switch to the same user gracefully', () async {
        // Arrange
        when(
          () => localAdapter.getPendingOperations('userA'),
        ).thenAnswer((_) async => []);
        final manager = await createManager();

        // Act
        final result = await manager.switchUser(
          oldUserId: 'userA',
          newUserId: 'userA',
          strategy: UserSwitchStrategy.promptIfUnsyncedData,
        );

        // Assert
        expect(result.success, isTrue);
        // No significant operations should occur
        // It's okay for it to check for pending ops, but it shouldn't do anything else.
        verify(() => localAdapter.getPendingOperations('userA')).called(1);
        verifyNever(() => localAdapter.clearUserData(any()));
        verifyNever(() => remoteAdapter.create(any()));
        verifyNever(() => remoteAdapter.readAll(userId: any(named: 'userId')));
      });
    });
  });
}
