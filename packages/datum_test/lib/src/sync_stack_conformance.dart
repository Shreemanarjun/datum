import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// A [DatumConnectivityChecker] the conformance suites can flip at will.
class TestConnectivityChecker implements DatumConnectivityChecker {
  bool _online = true;
  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isConnected async => _online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  /// Flips connectivity and notifies listeners.
  void setOnline(bool online) {
    _online = online;
    if (!_controller.isClosed) _controller.add(online);
  }

  /// Closes the status stream.
  Future<void> dispose() => _controller.close();
}

/// Runs the Datum **sync-stack conformance suite**: the full engine behavior
/// matrix — push/pull round-trips, multi-device convergence, offline queue
/// replay, conflict resolution, soft-delete propagation, user isolation —
/// over ANY local/remote adapter pair. Passing it certifies the pair as a
/// compatible sync stack.
///
/// Contract:
/// - [createLocal]/[createRemote] return fresh, initialized adapters. Within
///   one test, calling them again must connect to the SAME stores (the
///   two-device tests create a second manager over a second adapter pair
///   whose REMOTE hits the same backend but whose LOCAL is a fresh device).
///   In practice: locals are naturally per-call instances; remotes must
///   share backend state across calls.
/// - [resetBackend] wipes the shared remote backend; it runs before every
///   test so tests are independent.
///
/// ```dart
/// final server = LocalSyncServer();
/// runSyncStackConformanceTests(
///   name: 'InMemory + HTTP',
///   createLocal: () async => InMemoryLocalAdapter(fromMap: ConformanceEntity.fromMap)..initialize(),
///   createRemote: () async => HttpRemoteAdapter(baseUri: server.baseUri, fromMap: ConformanceEntity.fromMap),
///   resetBackend: () async { server.storage.clear(); server.metadata.clear(); },
/// );
/// ```
void runSyncStackConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  required Future<RemoteAdapter<ConformanceEntity>> Function() createRemote,
  Future<void> Function()? resetBackend,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroyLocal,
  Future<void> Function(RemoteAdapter<ConformanceEntity> adapter)?
  destroyRemote,
}) {
  group('$name sync-stack conformance', () {
    final managers = <DatumManager<ConformanceEntity>>[];
    final locals = <LocalAdapter<ConformanceEntity>>[];
    final remotes = <RemoteAdapter<ConformanceEntity>>[];
    final connectivities = <TestConnectivityChecker>[];

    /// Boots a device: fresh local + remote + manager.
    Future<
      (
        DatumManager<ConformanceEntity>,
        LocalAdapter<ConformanceEntity>,
        TestConnectivityChecker,
      )
    >
    device({
      DatumConflictResolver<ConformanceEntity>? resolver,
      DeleteBehavior deleteBehavior = DeleteBehavior.softDelete,
    }) async {
      final local = await createLocal();
      final remote = await createRemote();
      final connectivity = TestConnectivityChecker();
      final manager = DatumManager<ConformanceEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: connectivity,
        datumConfig: DatumConfig<ConformanceEntity>(
          enableLogging: false,
          deleteBehavior: deleteBehavior,
          defaultConflictResolver:
              resolver ?? LastWriteWinsResolver<ConformanceEntity>(),
        ),
      );
      await manager.initialize();
      managers.add(manager);
      locals.add(local);
      remotes.add(remote);
      connectivities.add(connectivity);
      return (manager, local, connectivity);
    }

    ConformanceEntity make(
      String id, {
      String name = 'entity',
      int value = 0,
      int version = 1,
      DateTime? modifiedAt,
    }) => ConformanceEntity.make(
      id,
      userId: 'u1',
      name: name,
      value: value,
      version: version,
      modifiedAt: modifiedAt,
    );

    setUp(() async {
      await resetBackend?.call();
    });

    tearDown(() async {
      for (final manager in managers) {
        await manager.dispose();
      }
      for (final local in locals) {
        await destroyLocal?.call(local);
      }
      for (final remote in remotes) {
        await destroyRemote?.call(remote);
      }
      for (final connectivity in connectivities) {
        await connectivity.dispose();
      }
      managers.clear();
      locals.clear();
      remotes.clear();
      connectivities.clear();
    });

    test('push: a local save reaches the remote after sync', () async {
      final (manager, _, _) = await device();
      await manager.push(
        item: make('a', name: 'pushed'),
        userId: 'u1',
      );

      final result = await manager.synchronize('u1');

      expect(result.failedCount, 0);
      final probe = await createRemote();
      remotes.add(probe);
      expect((await probe.read('a', userId: 'u1'))?.name, 'pushed');
    });

    test('pull: a remote row reaches the local store after sync', () async {
      final (manager, local, _) = await device();
      final seeder = await createRemote();
      remotes.add(seeder);
      await seeder.create(make('r1', name: 'remote-born'));

      await manager.synchronize('u1');

      expect((await local.read('r1', userId: 'u1'))?.name, 'remote-born');
    });

    test('two devices converge through the shared backend', () async {
      final (deviceA, _, _) = await device();
      final (deviceB, localB, _) = await device();

      await deviceA.push(
        item: make('a', name: 'from-A'),
        userId: 'u1',
      );
      await deviceA.synchronize('u1');
      await deviceB.synchronize('u1');
      expect((await localB.read('a', userId: 'u1'))?.name, 'from-A');

      // B edits, A picks it up.
      final current = (await localB.read('a', userId: 'u1'))!;
      await deviceB.push(
        item: current.copyWith(name: 'edited-by-B'),
        userId: 'u1',
      );
      await deviceB.synchronize('u1');
      await deviceA.synchronize('u1');

      final onA = await managers.first.read('a', userId: 'u1');
      expect(onA?.name, 'edited-by-B');
    });

    test('offline saves queue and replay when connectivity returns', () async {
      final (manager, _, connectivity) = await device();
      connectivity.setOnline(false);

      await manager.push(
        item: make('q1', name: 'queued'),
        userId: 'u1',
      );
      expect(await manager.getPendingOperations('u1'), isNotEmpty);

      connectivity.setOnline(true);
      final result = await manager.synchronize('u1');

      expect(result.failedCount, 0);
      expect(
        await manager.getPendingOperations('u1'),
        isEmpty,
        reason: 'queue drained',
      );
      final probe = await createRemote();
      remotes.add(probe);
      expect((await probe.read('q1', userId: 'u1'))?.name, 'queued');
    });

    test(
      'concurrent same-version edits resolve by last-write-wins and converge',
      () async {
        final (manager, local, _) = await device();
        await manager.push(
          item: make('c1', name: 'base'),
          userId: 'u1',
        );
        await manager.synchronize('u1');

        // Remote edit (older) and local edit (newer) at the same version.
        final base = (await local.read('c1', userId: 'u1'))!;
        final editor = await createRemote();
        remotes.add(editor);
        await editor.update(
          base.copyWith(
            name: 'remote-loser',
            modifiedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        );
        await manager.push(
          item: base.copyWith(name: 'local-winner'),
          userId: 'u1',
        );

        await manager.synchronize('u1');
        await manager.synchronize(
          'u1',
        ); // second cycle lets the winner push-back settle

        expect((await local.read('c1', userId: 'u1'))?.name, 'local-winner');
        final probe = await createRemote();
        remotes.add(probe);
        expect(
          (await probe.read('c1', userId: 'u1'))?.name,
          'local-winner',
          reason: 'winner propagates to the backend',
        );
      },
    );

    test('soft deletes propagate local -> remote', () async {
      final (manager, local, _) = await device();
      await manager.push(item: make('d1'), userId: 'u1');
      await manager.synchronize('u1');

      await manager.delete(id: 'd1', userId: 'u1');
      await manager.synchronize('u1');

      final probe = await createRemote();
      remotes.add(probe);
      final remoteRow = await probe.read('d1', userId: 'u1');
      final locallyGone = await local.read('d1', userId: 'u1');
      expect(
        (remoteRow == null || remoteRow.isDeleted) &&
            (locallyGone == null || locallyGone.isDeleted),
        isTrue,
        reason: 'deletion visible on both sides',
      );
    });

    test('a stale remote row does not clobber a newer local one', () async {
      final (manager, local, _) = await device();
      await manager.push(
        item: make('s1', name: 'newer', version: 3),
        userId: 'u1',
      );
      await manager.synchronize('u1');

      final staler = await createRemote();
      remotes.add(staler);
      await staler.update(
        make(
          's1',
          name: 'stale',
          version: 1,
          modifiedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      await manager.synchronize('u1');

      expect((await local.read('s1', userId: 'u1'))?.name, 'newer');
    });

    test('users are isolated end to end', () async {
      final (manager, local, _) = await device();
      await manager.push(item: make('mine'), userId: 'u1');
      await manager.push(
        item: ConformanceEntity.make('theirs', userId: 'u2'),
        userId: 'u2',
      );
      await manager.synchronize('u1');
      await manager.synchronize('u2');

      expect((await local.readAll(userId: 'u1')).map((e) => e.id), ['mine']);
      expect((await local.readAll(userId: 'u2')).map((e) => e.id), ['theirs']);
    });

    test('a clean second cycle is a no-op', () async {
      final (manager, _, _) = await device();
      await manager.push(item: make('n1'), userId: 'u1');
      await manager.synchronize('u1');

      final second = await manager.synchronize('u1');

      expect(second.failedCount, 0);
      expect(
        second.syncedCount,
        0,
        reason: 'nothing changed since the previous cycle',
      );
    });

    test('saveMany pushes the whole batch', () async {
      final (manager, _, _) = await device();
      await manager.saveMany(
        items: [for (var i = 0; i < 5; i++) make('b$i', value: i)],
        userId: 'u1',
      );

      await manager.synchronize('u1');

      final probe = await createRemote();
      remotes.add(probe);
      expect((await probe.readAll(userId: 'u1')).length, 5);
    });

    test(
      'sync metadata is stamped on both sides with matching hashes',
      () async {
        final (manager, local, _) = await device();
        await manager.push(item: make('m1'), userId: 'u1');
        await manager.synchronize('u1');

        final localMeta = await local.getSyncMetadata('u1');
        final probe = await createRemote();
        remotes.add(probe);
        final remoteMeta = await probe.getSyncMetadata('u1');

        expect(localMeta?.dataHash, isNotNull);
        expect(
          remoteMeta?.dataHash,
          localMeta?.dataHash,
          reason: 'beacon carries the reconciled hash',
        );
      },
    );

    test(
      'incremental pulls (when capable) still deliver later remote changes',
      () async {
        final (manager, local, _) = await device();
        await manager.push(
          item: make('i1', name: 'first'),
          userId: 'u1',
        );
        await manager.synchronize('u1');

        final editor = await createRemote();
        remotes.add(editor);
        final current = (await local.read('i1', userId: 'u1'))!;
        await editor.update(current.copyWith(name: 'second-wave'));
        await editor.updateSyncMetadata(
          const DatumSyncMetadata(userId: 'u1', dataHash: 'differs'),
          'u1',
        );

        await manager.synchronize('u1');

        expect((await local.read('i1', userId: 'u1'))?.name, 'second-wave');
      },
    );
  });
}
