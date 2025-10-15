import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class MockLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

void main() {
  group('DatumManager User Switching', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

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
    });

    setUp(() {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

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
      );
      await manager.initialize();
      return manager;
    }

    test(
      'throws UserSwitchException with promptIfUnsyncedData strategy if pending ops exist',
      () async {
        // Arrange
        final manager = await createManager(
          config: DatumConfig(
            defaultUserSwitchStrategy: UserSwitchStrategy.promptIfUnsyncedData,
          ),
        );

        // First, establish 'oldUser' as the last active user by performing
        // a sync. We stub getPendingOperations to be empty for this initial
        // sync so it completes quickly.
        when(
          () => localAdapter.getPendingOperations('oldUser'),
        ).thenAnswer((_) async => []);
        await manager.synchronize('oldUser');

        // Now, set up the stub for the actual check: when the manager checks
        // for pending ops for 'oldUser', it should find one.
        when(() => localAdapter.getPendingOperations('oldUser')).thenAnswer(
          (_) async => [
            DatumSyncOperation<TestEntity>(
              id: 'op1',
              userId: 'oldUser',
              entityId: 'e1',
              type: DatumOperationType.create,
              timestamp: DateTime.now(),
            ),
          ],
        );

        // Act: Attempt to sync with a new user, which triggers the user switch check.
        final syncFuture = manager.synchronize('newUser');

        // Assert
        await expectLater(syncFuture, throwsA(isA<UserSwitchException>()));
      },
    );
  });
}
