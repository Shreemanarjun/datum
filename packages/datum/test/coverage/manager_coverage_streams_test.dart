import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';
import 'manager_coverage_helpers.dart';

/// Coverage for DatumManager stream getters, watch* fallbacks and error
/// handling, external change processing (cache cleanup, failure retry), change
/// stream error handlers, and auto-sync scheduling edge cases.
void main() {
  group('status and next-sync streams', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late DatumManager<TestEntity> manager;

    setUp(() async {
      localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      remoteAdapter = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        // The published next-sync time is derived from config.autoSyncInterval.
        datumConfig: const DatumConfig<TestEntity>(
          enableLogging: false,
          autoSyncInterval: Duration(seconds: 3),
        ),
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('statusStream emits the current status snapshot', () async {
      final snapshot = await manager.statusStream.first;
      expect(snapshot, manager.currentStatus);
      expect(snapshot.status, DatumSyncStatus.idle);
    });

    test('watchNextSyncDuration emits countdown values while auto-sync is scheduled', () async {
      manager.startAutoSync('u1', interval: const Duration(seconds: 3));

      // First emission comes from startWith, the second from Stream.periodic
      // (fires after ~1 second), exercising the periodic callback.
      final emissions = await manager.watchNextSyncDuration.where((d) => d != null).take(2).toList().timeout(const Duration(seconds: 5));

      expect(emissions, hasLength(2));
      final periodicValue = emissions[1]!;
      expect(periodicValue, greaterThanOrEqualTo(Duration.zero));
      expect(periodicValue, lessThanOrEqualTo(const Duration(seconds: 3)));

      manager.stopAutoSync();
      expect(await manager.getNextSyncTime(), isNull);
    });

    test('stopAutoSync for a user while paused forgets that user for resume', () async {
      manager.startAutoSync('u1', interval: const Duration(hours: 1));
      expect(await manager.getNextSyncTime(), isNotNull);

      manager.pauseSync();
      // While paused, explicitly stopping the user's auto-sync must remove it
      // from the set of users restored on resume.
      manager.stopAutoSync(userId: 'u1');
      manager.resumeSync();

      expect(await manager.getNextSyncTime(), isNull);
    });
  });

  group('auto-start sync with failing initialUserId', () {
    test('falls back to discovered users when the initialUserId function throws', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      // Seed a user so the getAllUserIds fallback discovers it.
      localAdapter.addLocalItem('userX', makeEntity('seed', userId: 'userX'));
      final remoteAdapter = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);

      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: DatumConfig<TestEntity>(
          enableLogging: false,
          autoStartSync: true,
          initialUserId: () async => throw StateError('cannot resolve user (test)'),
        ),
      );

      await manager.initialize();

      // Auto-sync started for the discovered fallback user despite the throw.
      expect(await manager.getNextSyncTime(), isNotNull);

      manager.stopAutoSync();
      // Let the unawaited cold-start sync settle before disposing.
      await settle(200);
      await manager.dispose();
    });
  });

  group('auto-sync failure handling', () {
    test('a failing auto-sync run is rescheduled', () async {
      final localAdapter = FlakyLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remoteAdapter = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
      );
      await manager.initialize();

      localAdapter.throwOnGetPendingOps = true;
      localAdapter.pendingOpsCallCount = 0;

      manager.startAutoSync('u1', interval: const Duration(milliseconds: 40));
      await settle(220);

      // The first run failed, yet subsequent runs kept being scheduled.
      expect(localAdapter.pendingOpsCallCount, greaterThanOrEqualTo(2));
      expect(await manager.getNextSyncTime(), isNotNull);

      manager.stopAutoSync();
      localAdapter.throwOnGetPendingOps = false;
      await manager.dispose();
    });
  });

  group('change stream error handlers', () {
    test('local and remote change stream errors are absorbed and processing continues', () async {
      final localAdapter = ControlledChangeLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remoteAdapter = ControlledChangeRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(
          enableLogging: false,
          // Process remote events individually (no debounce buffering).
          remoteEventDebounceTime: Duration.zero,
        ),
      );
      await manager.initialize();

      localAdapter.changeCtrl.addError(StateError('local stream error (test)'));
      remoteAdapter.changeCtrl.addError(StateError('remote stream error (test)'));
      await settle();

      // A remote change after the errors is still applied locally.
      final incoming = makeEntity('r1', name: 'from-remote');
      remoteAdapter.changeCtrl.add(changeFor(incoming));
      await settle(60);

      final stored = await localAdapter.read('r1', userId: 'u1');
      expect(stored, isNotNull);
      expect(stored!.name, 'from-remote');

      await manager.dispose();
    });

    test('debounced remote change stream errors are absorbed and batches still apply', () async {
      final localAdapter = ControlledChangeLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remoteAdapter = ControlledChangeRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(
          enableLogging: false,
          remoteEventDebounceTime: Duration(milliseconds: 25),
        ),
      );
      await manager.initialize();

      remoteAdapter.changeCtrl.addError(StateError('remote stream error (test)'));
      await settle();

      final incoming = makeEntity('r2', name: 'debounced');
      remoteAdapter.changeCtrl.add(changeFor(incoming));
      await settle(150);

      final stored = await localAdapter.read('r2', userId: 'u1');
      expect(stored, isNotNull);
      expect(stored!.name, 'debounced');

      await manager.dispose();
    });
  });

  group('external change processing', () {
    test('size-based cache cleanup evicts old entries so their changes are re-processed', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remoteAdapter = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(
          enableLogging: false,
          remoteEventDebounceTime: Duration.zero,
          // Entries never expire by age but the cache is aggressively size-capped.
          changeCacheDuration: Duration(minutes: 10),
          changeCacheCleanupInterval: Duration.zero,
          maxChangeCacheSize: 2,
        ),
      );
      await manager.initialize();
      // Suppress local echoes so only remote events populate the change cache.
      localAdapter.silent = true;

      for (final id in ['e1', 'e2', 'e3', 'e4']) {
        remoteAdapter.emitChange(changeFor(makeEntity(id, name: '$id-v1')));
        await settle();
      }

      // e1 must have been evicted from the recent-change cache, so an updated
      // change for it is processed instead of being ignored as a duplicate.
      remoteAdapter.emitChange(
        changeFor(
          makeEntity('e1', name: 'e1-v2', version: 2, modifiedAt: DateTime(2024, 6, 1)),
          type: DatumOperationType.update,
        ),
      );
      await settle(60);

      final stored = await localAdapter.read('e1', userId: 'u1');
      expect(stored, isNotNull);
      expect(stored!.name, 'e1-v2');

      await manager.dispose();
    });

    test('a failed external change is evicted from the cache so it can be retried', () async {
      final localAdapter = FlakyLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final remoteAdapter = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(
          enableLogging: false,
          remoteEventDebounceTime: Duration.zero,
        ),
      );
      await manager.initialize();
      localAdapter.silent = true;

      await manager.push(item: makeEntity('d1'), userId: 'u1');
      expect(await localAdapter.read('d1', userId: 'u1'), isNotNull);

      // First delete attempt fails inside the local adapter.
      localAdapter.throwOnDelete = true;
      remoteAdapter.emitChange(deleteChangeFor('d1'));
      await settle(60);
      expect(await localAdapter.read('d1', userId: 'u1'), isNotNull, reason: 'delete failed, entity must survive');

      // Because the failure evicted the change from the cache, replaying the
      // same event is NOT treated as a duplicate and now succeeds.
      localAdapter.throwOnDelete = false;
      remoteAdapter.emitChange(deleteChangeFor('d1'));
      await settle(60);
      expect(await localAdapter.read('d1', userId: 'u1'), isNull);

      await manager.dispose();
    });
  });

  group('watch* fallbacks for non-watchable adapters', () {
    late DatumManager<TestEntity> manager;

    setUp(() async {
      // MockLocalAdapter without externalChangeStream returns null from all
      // watch methods, triggering the empty-stream fallbacks.
      manager = DatumManager<TestEntity>(
        localAdapter: MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('watchAll returns an empty stream', () async {
      expect(await manager.watchAll(userId: 'u1').isEmpty, isTrue);
    });

    test('watchById returns an empty stream', () async {
      expect(await manager.watchById('missing', 'u1').isEmpty, isTrue);
    });

    test('watchQuery returns an empty stream', () async {
      final query = DatumQueryBuilder<TestEntity>().build();
      expect(await manager.watchQuery(query, userId: 'u1').isEmpty, isTrue);
    });
  });

  group('post-fetch transform failures', () {
    test('readAll keeps the original entity when its transform throws', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
        middlewares: [ThrowingAfterFetchMiddleware('e1')],
      );
      await manager.initialize();

      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));
      localAdapter.addLocalItem('u1', makeEntity('e2', name: 'two'));

      final all = await manager.readAll(userId: 'u1');
      final byId = {for (final e in all) e.id: e.name};
      expect(byId['e1'], 'one', reason: 'transform threw, original kept');
      expect(byId['e2'], 'transformed-two');

      await manager.dispose();
    });

    test('watchAll keeps the original entity when its transform throws', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
        middlewares: [ThrowingAfterFetchMiddleware('e1')],
      );
      await manager.initialize();
      localAdapter.externalChangeStream = manager.onDataChange;

      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));
      localAdapter.addLocalItem('u1', makeEntity('e2', name: 'two'));

      final list = await manager.watchAll(userId: 'u1').first;
      final byId = {for (final e in list) e.id: e.name};
      expect(byId['e1'], 'one');
      expect(byId['e2'], 'transformed-two');

      await manager.dispose();
    });

    test('watchById keeps the original entity when its transform throws', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
        middlewares: [ThrowingAfterFetchMiddleware('e1')],
      );
      await manager.initialize();
      localAdapter.externalChangeStream = manager.onDataChange;

      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));

      final item = await manager.watchById('e1', 'u1').first;
      expect(item, isNotNull);
      expect(item!.name, 'one');

      await manager.dispose();
    });

    test('watchQuery keeps the original entity when its transform throws', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
        middlewares: [ThrowingAfterFetchMiddleware('e1')],
      );
      await manager.initialize();
      localAdapter.externalChangeStream = manager.onDataChange;

      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));
      localAdapter.addLocalItem('u1', makeEntity('e2', name: 'two'));

      final query = DatumQueryBuilder<TestEntity>().build();
      // withRelated with an unknown relation exercises the stitch call, which
      // logs a warning and continues.
      final list = await manager.watchQuery(query, userId: 'u1', withRelated: ['nonexistent']).first;
      final byId = {for (final e in list) e.id: e.name};
      expect(byId['e1'], 'one');
      expect(byId['e2'], 'transformed-two');

      await manager.dispose();
    });
  });

  group('relation stitching failures inside watch streams', () {
    test('watchAll returns the untransformed list when relation stitching throws', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
      );
      await manager.initialize();
      localAdapter.externalChangeStream = manager.onDataChange;

      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));

      // TestEntity's 'posts' relation resolves its manager via
      // Datum.manager<DatumEntityInterface>() which always throws, so the
      // stitching fails and the original list is emitted unchanged.
      final list = await manager.watchAll(userId: 'u1', withRelated: ['posts']).first;
      expect(list, hasLength(1));
      expect(list.single.name, 'one');

      await manager.dispose();
      DatumRelationSchema.clear();
    });

    test('watchQuery returns the untransformed list when relation stitching throws', () async {
      final localAdapter = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
      );
      await manager.initialize();
      localAdapter.externalChangeStream = manager.onDataChange;

      localAdapter.addLocalItem('u1', makeEntity('e1', name: 'one'));

      final query = DatumQueryBuilder<TestEntity>().build();
      final list = await manager.watchQuery(query, userId: 'u1', withRelated: ['posts']).first;
      expect(list, hasLength(1));
      expect(list.single.name, 'one');

      await manager.dispose();
      DatumRelationSchema.clear();
    });
  });

  group('watch stream error resilience (handleError)', () {
    late WatchStreamLocalAdapter<TestEntity> localAdapter;
    late DatumManager<TestEntity> manager;

    setUp(() async {
      localAdapter = WatchStreamLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('watchAll swallows stream errors and continues emitting', () async {
      final events = <List<TestEntity>>[];
      final errors = <Object>[];
      final sub = manager.watchAll(userId: 'u1').listen(events.add, onError: errors.add);

      localAdapter.watchAllCtrl.addError(StateError('watchAll error (test)'));
      localAdapter.watchAllCtrl.add([makeEntity('e1')]);
      await settle();

      expect(errors, isEmpty);
      expect(events, hasLength(1));
      expect(events.single.single.id, 'e1');
      await sub.cancel();
    });

    test('watchById swallows stream errors and continues emitting', () async {
      final events = <TestEntity?>[];
      final errors = <Object>[];
      final sub = manager.watchById('e1', 'u1').listen(events.add, onError: errors.add);

      localAdapter.watchByIdCtrl.addError(StateError('watchById error (test)'));
      localAdapter.watchByIdCtrl.add(makeEntity('e1'));
      // A null emission maps straight through.
      localAdapter.watchByIdCtrl.add(null);
      await settle();

      expect(errors, isEmpty);
      expect(events, hasLength(2));
      expect(events.first!.id, 'e1');
      expect(events.last, isNull);
      await sub.cancel();
    });

    test('watchQuery swallows stream errors and continues emitting', () async {
      final query = DatumQueryBuilder<TestEntity>().build();
      final events = <List<TestEntity>>[];
      final errors = <Object>[];
      final sub = manager.watchQuery(query, userId: 'u1').listen(events.add, onError: errors.add);

      localAdapter.watchQueryCtrl.addError(StateError('watchQuery error (test)'));
      localAdapter.watchQueryCtrl.add([makeEntity('e2')]);
      await settle();

      expect(errors, isEmpty);
      expect(events, hasLength(1));
      expect(events.single.single.id, 'e2');
      await sub.cancel();
    });
  });
}
