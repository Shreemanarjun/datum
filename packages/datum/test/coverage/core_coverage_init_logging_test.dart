import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../core/non_relational_test_entity.dart';
import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class _NoopMiddleware extends DatumMiddleware<TestEntity> {}

class _EntityObserver extends DatumObserver<TestEntity> {}

class _GlobalObserver extends GlobalDatumObserver {}

/// A request strategy that is neither Sequential nor SkipConcurrent, to hit
/// the "custom request strategy" logging branch.
class _CustomRequestStrategy implements DatumSyncRequestStrategy {
  const _CustomRequestStrategy();

  @override
  Future<T> execute<T>(
    Future<T> Function() action, {
    required bool Function() isSyncInProgress,
    required T Function() onSkipped,
  }) =>
      action();

  @override
  void dispose() {}
}

/// A local adapter whose user discovery fails, to exercise the warning path
/// in the pending-operations summary.
class _ThrowingUserIdsAdapter extends MockLocalAdapter<TestEntity> {
  _ThrowingUserIdsAdapter() : super(fromJson: TestEntity.fromJson);

  @override
  Future<List<String>> getAllUserIds() async => throw StateError('cannot list users');
}

MockConnectivityChecker _connectivity() {
  final checker = MockConnectivityChecker();
  when(() => checker.isConnected).thenAnswer((_) async => true);
  when(() => checker.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return checker;
}

void main() {
  tearDown(() async {
    if (Datum.instanceOrNull != null) {
      await Datum.instance.dispose();
    }
    Datum.resetForTesting();
  });

  group('TypeSafeManagerRegistry guards', () {
    test('get<DatumEntityInterface>() rejects the base interface', () {
      final registry = TypeSafeManagerRegistry();
      expect(
        () => registry.get<DatumEntityInterface>(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('Cannot use DatumEntityInterface directly'))),
      );
    });

    test('getByType(DatumEntityInterface) rejects the base interface', () {
      final registry = TypeSafeManagerRegistry();
      expect(
        () => registry.getByType(DatumEntityInterface),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('Cannot use DatumEntityInterface directly'))),
      );
    });
  });

  group('type utilities', () {
    test('sameTypes matches identical types and rejects different ones', () {
      expect(sameTypes<String, String>(), isTrue);
      expect(sameTypes<TestEntity, TestEntity>(), isTrue);
      expect(sameTypes<String, int>(), isFalse);
      // Sub-typing alone is not "the same type".
      expect(sameTypes<DatumEntityInterface, TestEntity>(), isFalse);
    });
  });

  group('Datum.initialize logging variants', () {
    test('logs targeted initial user, pullThenPush, parallel/skip strategies, clearAndFetch, observers and middlewares', () async {
      final sink = CollectingLogSink();
      final logger = DatumLogger(colors: false, sink: sink);

      final result = await Datum.initialize(
        config: DatumConfig(
          autoStartSync: true,
          initialUserId: () async => 'auto-user',
          coldStartConfig: const ColdStartConfig(strategy: ColdStartStrategy.disabled),
          defaultSyncDirection: SyncDirection.pullThenPush,
          syncExecutionStrategy: const ParallelStrategy(),
          syncRequestStrategy: const SkipConcurrentStrategy(),
          defaultUserSwitchStrategy: UserSwitchStrategy.clearAndFetch,
        ),
        connectivityChecker: _connectivity(),
        logger: logger,
        observers: [_GlobalObserver()],
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson),
            remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
            middlewares: [_NoopMiddleware()],
            observers: [_EntityObserver()],
          ),
        ],
      );

      expect(result.isSuccess(), isTrue);
      final logOutput = sink.messages.join('\n');
      // initialUserId is a callback, so the log prints the closure itself.
      expect(logOutput, contains('Targeting initial user:'));
      expect(logOutput, contains('Remote changes will be pulled before pushing local changes'));
      expect(logOutput, contains('processed in parallel batches'));
      expect(logOutput, contains('skipped if a sync is already in progress'));
      expect(logOutput, contains('Clears new user\'s local data'));
      expect(logOutput, contains('Global Observers Registered (1)'));
      expect(logOutput, contains('Middlewares (1)'));
      expect(logOutput, contains('Observers (1)'));
    });

    test('logs user discovery, pushOnly, custom request strategy, promptIfUnsyncedData and non-relational entity', () async {
      final sink = CollectingLogSink();
      final logger = DatumLogger(colors: false, sink: sink);

      final result = await Datum.initialize(
        config: const DatumConfig(
          autoStartSync: true,
          coldStartConfig: ColdStartConfig(strategy: ColdStartStrategy.disabled),
          defaultSyncDirection: SyncDirection.pushOnly,
          syncRequestStrategy: _CustomRequestStrategy(),
          defaultUserSwitchStrategy: UserSwitchStrategy.promptIfUnsyncedData,
        ),
        connectivityChecker: _connectivity(),
        logger: logger,
        registrations: [
          DatumRegistration<NonRelationalTestEntity>(
            localAdapter: MockLocalAdapter<NonRelationalTestEntity>(),
            remoteAdapter: MockRemoteAdapter<NonRelationalTestEntity>(),
          ),
        ],
      );

      expect(result.isSuccess(), isTrue);
      final logOutput = sink.messages.join('\n');
      expect(logOutput, contains('Discovering all local users to sync'));
      expect(logOutput, contains('Only local changes will be pushed to the remote'));
      expect(logOutput, contains('Using custom request strategy'));
      expect(logOutput, contains('Fails switch if previous user has unsynced data'));
      expect(logOutput, contains('Relational: false'));
    });

    test('logs pullOnly, keepLocal, last sync time and transferred data for known users', () async {
      final sink = CollectingLogSink();
      final logger = DatumLogger(colors: false, sink: sink);

      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      localAdapter.addLocalItem('u1', TestEntity.create('e1', 'u1', 'One'));
      await localAdapter.updateSyncMetadata(
        DatumSyncMetadata(
          userId: 'u1',
          lastSyncTime: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        'u1',
      );
      await localAdapter.saveLastSyncResult(
        'u1',
        const DatumSyncResult<TestEntity>(
          userId: 'u1',
          duration: Duration(seconds: 1),
          syncedCount: 1,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
          totalBytesPushed: 2048,
          totalBytesPulled: 1024,
          bytesPushedInCycle: 512,
          bytesPulledInCycle: 256,
        ),
      );

      final result = await Datum.initialize(
        config: const DatumConfig(
          defaultSyncDirection: SyncDirection.pullOnly,
          defaultUserSwitchStrategy: UserSwitchStrategy.keepLocal,
        ),
        connectivityChecker: _connectivity(),
        logger: logger,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
          ),
        ],
      );

      expect(result.isSuccess(), isTrue);
      final logOutput = sink.messages.join('\n');
      expect(logOutput, contains('Only remote changes will be pulled to local'));
      expect(logOutput, contains('Switches user without any data modifications'));
      // Last sync time was present, so the "ago" branch is used.
      expect(logOutput, contains('ago'));
      expect(logOutput, isNot(contains('Never synced')));
      // Byte counters from the persisted last sync result.
      expect(logOutput, contains('Total Data: ↑2.00 KB / ↓1.00 KB'));
      expect(logOutput, contains('Last Sync: ↑0.50 KB / ↓0.25 KB'));
    });

    test('warns when a local adapter cannot enumerate user ids', () async {
      final sink = CollectingLogSink();
      final logger = DatumLogger(colors: false, sink: sink);

      final result = await Datum.initialize(
        config: const DatumConfig(),
        connectivityChecker: _connectivity(),
        logger: logger,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: _ThrowingUserIdsAdapter(),
            remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
          ),
        ],
      );

      expect(result.isSuccess(), isTrue);
      final logOutput = sink.messages.join('\n');
      expect(logOutput, contains('Could not get user IDs from _ThrowingUserIdsAdapter'));
      expect(logOutput, contains('No local users found yet'));
    });

    test('initialize is idempotent: a second call returns the existing instance', () async {
      final first = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: _connectivity(),
      );
      expect(first.isSuccess(), isTrue);

      final second = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: _connectivity(),
      );

      expect(second.isSuccess(), isTrue);
      expect(identical(first.getSuccess(), second.getSuccess()), isTrue);
      expect(identical(second.getSuccess(), Datum.instance), isTrue);
    });
  });
}
