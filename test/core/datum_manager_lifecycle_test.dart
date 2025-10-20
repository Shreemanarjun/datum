import 'package:datum/datum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// Create mocktail-based mocks for this test file to allow `when()` stubs.
class MockedLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

void main() {
  group('DatumManager Lifecycle & Memory Leak Verification', () {
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    late DatumManager<TestEntity> manager;

    setUpAll(() {
      // Register a fallback value for any custom types used with `any()`
      registerFallbackValue(
        const DatumSyncMetadata(
            userId: 'fallback-user', dataHash: 'fallback-hash'),
      );
      registerFallbackValue(const DatumQuery());
    });

    setUp(() {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      // Stub basic behaviors needed for initialization and sync
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.getStoredSchemaVersion())
          .thenAnswer((_) async => 0);
      when(() => localAdapter.getPendingOperations(any()))
          .thenAnswer((_) async => []);
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(() => localAdapter.readByIds(any(), userId: any(named: 'userId')))
          .thenAnswer((_) async => {});
      when(() => localAdapter.updateSyncMetadata(any(), any()))
          .thenAnswer((_) async {});
      when(() => localAdapter.changeStream())
          .thenAnswer((_) => const Stream.empty());
      when(() => remoteAdapter.changeStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => remoteAdapter.updateSyncMetadata(any(), any()))
          .thenAnswer((_) async {});

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig(
          autoSyncInterval: Duration(seconds: 30),
          enableLogging: false,
        ),
      );
    });

    tearDown(() async {
      // Ensure manager is disposed if it hasn't been already in a test
      if (manager.isInitialized && !manager.isDisposed) {
        await manager.dispose();
      }
    });

    test(
      'calling dispose() closes internal BehaviorSubjects',
      () async {
        // Arrange
        await manager.initialize();

        // Assert: Check that the streams complete when dispose is called.
        // A "done" event signifies the underlying StreamController was closed.
        // For a BehaviorSubject-backed stream like `health`, we must account for
        // the initial value it emits upon listening before it closes.
        expect(manager.health, emitsInOrder([isA<DatumHealth>(), emitsDone]));

        // For a regular broadcast stream, we just expect it to close.
        expect(manager.eventStream, emitsDone);

        // Act
        await manager.dispose();
      },
    );

    test(
      'switchUser stops auto-sync timer for the old user to prevent leaks',
      () {
        // Use fakeAsync to control the passage of time for Timers.
        fakeAsync((async) async {
          // Arrange
          await manager.initialize();

          // Start auto-sync for the first user.
          manager.startAutoSync('user-A');

          // Act 1: Advance the clock. A sync should be triggered for user-A.
          async.elapse(const Duration(seconds: 31));

          // Assert 1: Verify the sync was called for user-A.
          verify(
            () => remoteAdapter.readAll(
              userId: 'user-A',
              scope: any(named: 'scope'),
            ),
          ).called(1);

          // Act 2: Switch to a new user. This should cancel the timer for user-A.
          await manager.switchUser(oldUserId: 'user-A', newUserId: 'user-B');

          // Act 3: Advance the clock again.
          async.elapse(const Duration(seconds: 31));

          // Assert 3: The sync for user-A should NOT have been called again.
          // The verification count should still be 1 from the first time.
          verify(
            () => remoteAdapter.readAll(
              userId: 'user-A',
              scope: any(named: 'scope'),
            ),
          ).called(1);

          // Clean up
          await manager.dispose();
        });
      },
    );

    test('dispose() stops all auto-sync timers', () {
      fakeAsync((async) async {
        // Arrange
        await manager.initialize();
        manager.startAutoSync('user-A');
        manager.startAutoSync('user-B');

        // Act: Dispose the manager
        await manager.dispose();

        // Advance the clock past the sync interval
        async.elapse(const Duration(seconds: 31));

        // Assert: No sync operations should have been triggered for any user
        // after the manager was disposed.
        verifyNever(
          () => remoteAdapter.readAll(
            userId: any(named: 'userId'),
            scope: any(named: 'scope'),
          ),
        );
      });
    });

    group('Auto-Sync Time Streams and Futures', () {
      test('emits DateTime when startAutoSync is called', () {
        fakeAsync((async) async {
          // Arrange
          await manager.initialize();

          // Assert: Expect the stream to emit a non-null DateTime.
          // The time should be approximately now + the sync interval.
          final expectation = expectLater(
            manager.onNextSyncTimeChanged,
            emits(
              isA<DateTime>().having(
                (dt) => dt.isAfter(DateTime.now()),
                'is in the future',
                isTrue,
              ),
            ),
          );

          // Act
          manager.startAutoSync('user-A');

          // Await the expectation to ensure the event was received.
          await expectation;
        });
      });

      test('emits null when stopAutoSync is called for a specific user', () {
        fakeAsync((async) async {
          // Arrange
          await manager.initialize();
          manager.startAutoSync('user-A');
          // Let the first (non-null) event pass through the stream.
          await manager.watchNextSyncTime.first;

          // Assert: Expect the next event to be null.
          final expectation =
              expectLater(manager.watchNextSyncTime, emits(isNull));

          // Act
          manager.stopAutoSync(userId: 'user-A');

          await expectation;
        });
      });

      test('emits null when stopAutoSync is called for all users', () {
        fakeAsync((async) async {
          await manager.initialize();
          manager.startAutoSync('user-A');
          await manager.watchNextSyncTime.first;
          expectLater(manager.watchNextSyncTime, emits(isNull));
          manager.stopAutoSync();
        });
      });

      test('getNextSyncTime returns future DateTime or null', () async {
        await manager.initialize();

        // Initially, should be null
        expect(await manager.getNextSyncTime(), isNull);

        // After starting, should return a future time
        manager.startAutoSync('user-A');
        final nextTime = await manager.getNextSyncTime();
        expect(nextTime, isNotNull);
        expect(nextTime!.isAfter(DateTime.now()), isTrue);

        // After stopping, should be null again
        manager.stopAutoSync();
        expect(await manager.getNextSyncTime(), isNull);
      });

      test('getNextSyncDuration returns future Duration or null', () async {
        await manager.initialize();

        // Initially, should be null
        expect(await manager.getNextSyncDuration(), isNull);

        // After starting, should return a positive duration
        manager.startAutoSync('user-A');
        final nextDuration = await manager.getNextSyncDuration();
        expect(nextDuration, isNotNull);
        expect(nextDuration!.isNegative, isFalse);
        expect(
          nextDuration.inSeconds,
          lessThanOrEqualTo(manager.config.autoSyncInterval.inSeconds),
        );

        // After stopping, should be null again
        manager.stopAutoSync();
        expect(await manager.getNextSyncDuration(), isNull);
      });
    });
  });
}
