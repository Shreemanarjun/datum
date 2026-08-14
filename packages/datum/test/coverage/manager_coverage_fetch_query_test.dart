import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';
import 'manager_coverage_helpers.dart';

/// Coverage for DatumManager fetch strategies, raw queries, query cache keys,
/// sync options merging, user-switch guards, delete failure observers, the
/// watchRelated argument validation, and the tryX convenience API.
void main() {
  late FlakyLocalAdapter<TestEntity> localAdapter;
  late MockRemoteAdapter<TestEntity> remoteAdapter;
  late DatumManager<TestEntity> manager;

  Future<DatumManager<TestEntity>> buildManager({
    DatumConfig<TestEntity>? config,
    List<GlobalDatumObserver>? globalObservers,
    RemoteAdapter<TestEntity>? remote,
  }) async {
    final m = DatumManager<TestEntity>(
      localAdapter: localAdapter,
      remoteAdapter: remote ?? remoteAdapter,
      connectivity: const OnlineConnectivity(),
      datumConfig: config ?? const DatumConfig<TestEntity>(enableLogging: false),
      globalObservers: globalObservers,
    );
    await m.initialize();
    return m;
  }

  setUp(() {
    localAdapter = FlakyLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    remoteAdapter = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
  });

  tearDown(() async {
    await manager.dispose();
  });

  group('fetch with DataFetchStrategy', () {
    test('remoteFirst persists non-empty remote results locally', () async {
      manager = await buildManager();
      remoteAdapter.addRemoteItem('u1', makeEntity('r1', name: 'remote-one'));

      final query = DatumQueryBuilder<TestEntity>().build();
      final results = await manager.fetch(
        query,
        strategy: DataFetchStrategy.remoteFirst,
        userId: 'u1',
        persistRemoteResults: true,
      );

      expect(results, hasLength(1));
      final persisted = await localAdapter.read('r1', userId: 'u1');
      expect(persisted, isNotNull, reason: 'remote results must be cached locally');
      expect(persisted!.name, 'remote-one');
    });

    test('remoteFirst still returns remote results when local persistence fails', () async {
      manager = await buildManager();
      remoteAdapter.addRemoteItem('u1', makeEntity('r2', name: 'remote-two'));
      localAdapter.throwOnUpdateAll = true;

      final query = DatumQueryBuilder<TestEntity>().build();
      final results = await manager.fetch(
        query,
        strategy: DataFetchStrategy.remoteFirst,
        userId: 'u1',
        persistRemoteResults: true,
      );

      expect(results.single.name, 'remote-two');
      expect(await localAdapter.read('r2', userId: 'u1'), isNull, reason: 'persistence failed silently');
    });
  });

  group('fetchById with DataFetchStrategy', () {
    test('localOnly reads only from the local adapter', () async {
      manager = await buildManager();
      localAdapter.addLocalItem('u1', makeEntity('l1', name: 'local'));
      remoteAdapter.addRemoteItem('u1', makeEntity('r1', name: 'remote'));

      final local = await manager.fetchById('l1', strategy: DataFetchStrategy.localOnly, userId: 'u1');
      expect(local!.name, 'local');
      final missingRemote = await manager.fetchById('r1', strategy: DataFetchStrategy.localOnly, userId: 'u1');
      expect(missingRemote, isNull, reason: 'localOnly must not consult the remote');
    });

    test('remoteOnly reads only from the remote adapter', () async {
      manager = await buildManager();
      localAdapter.addLocalItem('u1', makeEntity('l1', name: 'local'));
      remoteAdapter.addRemoteItem('u1', makeEntity('r1', name: 'remote'));

      final remote = await manager.fetchById('r1', strategy: DataFetchStrategy.remoteOnly, userId: 'u1');
      expect(remote!.name, 'remote');
      final missingLocal = await manager.fetchById('l1', strategy: DataFetchStrategy.remoteOnly, userId: 'u1');
      expect(missingLocal, isNull, reason: 'remoteOnly must not consult local storage');
    });

    test('localFirst falls back to remote and persists the result', () async {
      manager = await buildManager();
      remoteAdapter.addRemoteItem('u1', makeEntity('r1', name: 'remote'));

      final result = await manager.fetchById(
        'r1',
        userId: 'u1',
        persistRemoteResults: true,
      );

      expect(result!.name, 'remote');
      expect(await localAdapter.read('r1', userId: 'u1'), isNotNull);
    });

    test('remoteFirst returns and persists the remote entity when found', () async {
      manager = await buildManager();
      remoteAdapter.addRemoteItem('u1', makeEntity('r1', name: 'remote'));

      final result = await manager.fetchById(
        'r1',
        strategy: DataFetchStrategy.remoteFirst,
        userId: 'u1',
        persistRemoteResults: true,
      );

      expect(result!.name, 'remote');
      expect(await localAdapter.read('r1', userId: 'u1'), isNotNull);
    });

    test('remoteFirst falls back to local when the remote has no entity', () async {
      manager = await buildManager();
      localAdapter.addLocalItem('u1', makeEntity('l1', name: 'local'));

      final result = await manager.fetchById('l1', strategy: DataFetchStrategy.remoteFirst, userId: 'u1');
      expect(result!.name, 'local');
    });
  });

  group('rawQuery', () {
    test('remote source throws UnsupportedError when the adapter lacks RawQueryCapable', () async {
      manager = await buildManager();
      expect(
        () => manager.rawQuery(const DatumRawQuery(table: 'users'), source: DataSource.remote),
        throwsUnsupportedError,
      );
    });

    test('remote source dispatches to a RawQueryCapable remote adapter', () async {
      final rawRemote = RawCapableRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      manager = await buildManager(remote: rawRemote);

      final rows = await manager.rawQuery(
        const DatumRawQuery(table: 'users', count: true),
        source: DataSource.remote,
      );

      expect(rows.single['total'], 42);
      expect(rawRemote.lastRawQuery!.table, 'users');
    });
  });

  group('query', () {
    test('withRelated on a missing relation logs a warning and still returns entities', () async {
      manager = await buildManager();
      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));

      final results = await manager.query(
        const DatumQuery(withRelated: ['nonexistent']),
        userId: 'u1',
      );

      expect(results.single.name, 'one');
      DatumRelationSchema.clear();
    });

    test('post-fetch transform failure keeps original entity in query results', () async {
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
        middlewares: [ThrowingAfterFetchMiddleware('e1')],
      );
      await manager.initialize();
      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));
      localAdapter.addLocalItem('u1', makeEntity('e2', name: 'two'));

      final results = await manager.query(DatumQueryBuilder<TestEntity>().build(), userId: 'u1');
      final byId = {for (final e in results) e.id: e.name};
      expect(byId['e1'], 'one');
      expect(byId['e2'], 'transformed-two');
    });

    test('composite filters with offset and limit resolve correctly (cache key includes them)', () async {
      manager = await buildManager();
      localAdapter.addLocalItem('u1', makeEntity('a', name: 'alpha', value: 1));
      localAdapter.addLocalItem('u1', makeEntity('b', name: 'beta', value: 2));
      localAdapter.addLocalItem('u1', makeEntity('c', name: 'gamma', value: 3));

      const query = DatumQuery(
        filters: [
          CompositeFilter(
            [
              Filter('name', FilterOperator.equals, 'alpha'),
              Filter('name', FilterOperator.equals, 'beta'),
              Filter('name', FilterOperator.equals, 'gamma'),
            ],
            LogicalOperator.or,
          ),
        ],
        sorting: [SortDescriptor('value')],
        offset: 1,
        limit: 1,
      );

      final results = await manager.query(query, userId: 'u1');
      expect(results.single.name, 'beta');
    });
  });

  group('delete failure notifications', () {
    test('global observers hear onDeleteEnd(success: false) when the local delete fails', () async {
      final observer = RecordingGlobalObserver();
      manager = await buildManager(globalObservers: [observer]);

      await manager.push(item: makeEntity('d1'), userId: 'u1');
      localAdapter.deleteReturnsFalse = true;

      final deleted = await manager.delete(id: 'd1', userId: 'u1');

      expect(deleted, isFalse);
      expect(observer.deleteEndCalls, contains(('d1', false)));
    });
  });

  group('watchRelated argument validation', () {
    test('throws ArgumentError for an undefined relation name', () async {
      manager = await buildManager();
      final entity = makeEntity('e1');
      expect(
        () => manager.watchRelated<TestEntity>(entity, 'not-a-relation'),
        throwsArgumentError,
      );
    });
  });

  group('user switching', () {
    test('synchronize throws UserSwitchException when the previous user still has pending data', () async {
      manager = await buildManager(
        config: const DatumConfig<TestEntity>(
          enableLogging: false,
          defaultUserSwitchStrategy: UserSwitchStrategy.promptIfUnsyncedData,
        ),
      );

      // Establishes 'userA' as the active user and leaves one pending op.
      await manager.push(item: makeEntity('a1', userId: 'userA'), userId: 'userA');
      expect(await manager.getPendingCount('userA'), 1);

      expect(
        () => manager.synchronize('userB'),
        throwsA(isA<UserSwitchException>()),
      );
    });

    test('switchUser rejects an empty new user id', () async {
      manager = await buildManager();
      expect(
        () => manager.switchUser(oldUserId: 'u1', newUserId: ''),
        throwsArgumentError,
      );
    });
  });

  group('sync options merging', () {
    test('null fields in provided options fall back to configured defaults', () async {
      SyncDirection? observedDirection;
      manager = await buildManager(
        config: DatumConfig<TestEntity>(
          enableLogging: false,
          defaultSyncOptions: const DatumSyncOptions<TestEntity>(
            direction: SyncDirection.pullOnly,
            overrideBatchSize: 7,
            timeout: Duration(seconds: 45),
          ),
          syncDirectionResolver: (pendingCount, defaultDirection) {
            observedDirection = defaultDirection;
            return null;
          },
        ),
      );

      // Provided options omit direction/timeout/batch size, so the merged
      // options must carry the defaults - observable via the resolver, which
      // receives the merged direction.
      final result = await manager.synchronize(
        'u1',
        options: const DatumSyncOptions<DatumEntityInterface>(forceFullSync: true),
      );

      expect(observedDirection, SyncDirection.pullOnly);
      expect(result.wasSkipped, isFalse);
    });
  });

  group('tryX convenience API', () {
    test('tryReadAll returns Success with all entities', () async {
      manager = await buildManager();
      localAdapter.addLocalItem('u1', makeEntity('e1'));
      localAdapter.addLocalItem('u1', makeEntity('e2'));

      final result = await manager.tryReadAll(userId: 'u1');
      expect(result.isSuccess(), isTrue);
      expect(result.successOrNull, hasLength(2));
    });

    test('tryDelete returns Success(true) for an existing entity', () async {
      manager = await buildManager();
      await manager.push(item: makeEntity('e1'), userId: 'u1');

      final result = await manager.tryDelete(id: 'e1', userId: 'u1');
      expect(result.isSuccess(), isTrue);
      expect(result.successOrNull, isTrue);
      expect(await localAdapter.read('e1', userId: 'u1'), isNull);
    });

    test('trySynchronize returns Success with a sync result', () async {
      manager = await buildManager();
      final result = await manager.trySynchronize('u1');
      expect(result.isSuccess(), isTrue);
      expect(result.successOrNull!.wasSkipped, isFalse);
    });

    test('trySynchronize returns Failure when the sync throws', () async {
      manager = await buildManager();
      localAdapter.throwOnGetPendingOps = true;

      final result = await manager.trySynchronize('u1');
      expect(result.isFailure(), isTrue);
      localAdapter.throwOnGetPendingOps = false;
    });
  });
}
