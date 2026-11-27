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

/// Makes the shared backend reject the next [times] writes (update, patch or
/// delete; creates may also be covered) touching [entityId] with an HTTP-like
/// [status]: 5xx = retryable, 401 = expired session (pauses sync), other
/// 4xx = non-retryable (parks).
typedef FailEntityWrites =
    void Function(String entityId, {required int status, int times});

/// Opens a NEW adapter instance over the same persistent storage as
/// [crashed] (whose manager — and so the adapter itself — was already
/// disposed), modelling an app restart after a crash.
typedef ReopenLocal =
    Future<LocalAdapter<ConformanceEntity>> Function(
      LocalAdapter<ConformanceEntity> crashed,
    );

typedef _Device = (
  DatumManager<ConformanceEntity>,
  LocalAdapter<ConformanceEntity>,
  TestConnectivityChecker,
);

const _u1 = 'u1';


/// Runs the Datum **sync-stack conformance suite**: the full engine behavior
/// matrix — push/pull/both directions, op ordering and collapse, retryable
/// and permanent (parked) failures, crash/ack-loss recovery, batch fallback,
/// conflict resolution across two devices (incl. clock skew), soft-delete
/// propagation, user isolation and switching, large queues, watch streams,
/// concurrent sync calls, the metadata skip fast path and incremental pulls —
/// over ANY local/remote adapter pair.
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
/// - [reopenLocal] (optional) reopens a crashed local's persistent storage;
///   crash tests are skipped without it. Tests that only need an ack-loss
///   replay still run, without the restart.
/// - [failEntityWrites] (optional) injects per-entity backend failures;
///   failure-path tests are skipped without it.
/// - [remotePullsByTimestamp]: the remote pulls incrementally by a
///   `modifiedSince` watermark (DeltaSyncCapable without a cursor feed);
///   skips the clock-skew cases that path is known to fail.
/// - [remoteGuardsWrites]: the remote is [GuardedWriteCapable]. Conflicts
///   then show at upload whatever the sync direction, and the tests that
///   describe "the last upload wins" expect the first one to.
///
/// [runSyncConformanceMatrix] wires this suite over every bundled remote.
void runSyncStackConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  required Future<RemoteAdapter<ConformanceEntity>> Function() createRemote,
  Future<void> Function()? resetBackend,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroyLocal,
  Future<void> Function(RemoteAdapter<ConformanceEntity> adapter)?
  destroyRemote,
  ReopenLocal? reopenLocal,
  FailEntityWrites? failEntityWrites,
  bool remotePullsByTimestamp = false,
  bool remoteGuardsWrites = false,
}) {
  group('$name sync-stack conformance', () {
    final s = _Stack(
      createLocal: createLocal,
      createRemote: createRemote,
      destroyLocal: destroyLocal,
      destroyRemote: destroyRemote,
      reopenLocal: reopenLocal,
      failEntityWrites: failEntityWrites,
      timestampPulls: remotePullsByTimestamp,
      guardsWrites: remoteGuardsWrites,
    );
    setUp(() async => resetBackend?.call());
    tearDown(s.dispose);

    _roundTripTests(s);
    _directionAndOrderingTests(s);
    _failureTests(s);
    _parkingTests(s);
    _authPauseTests(s);
    _syncOptionTests(s);
    _queueAndCompactionApiTests(s);
    _writeGuardTests(s);
    _crashAndReplayTests(s);
    _conflictTests(s);
    _conflictMatrixTests(s);
    _deleteAndWatchTests(s);
    _isolationAndScaleTests(s);
    _pullTests(s);
    _scopeTests(s);
    _queueHygieneTests(s);
  });
}

/// Per-test device/adapter bookkeeping shared by every test group.
class _Stack {
  _Stack({
    required this.createLocal,
    required this.createRemote,
    required this.destroyLocal,
    required this.destroyRemote,
    required this.reopenLocal,
    required this.failEntityWrites,
    required this.timestampPulls,
    required this.guardsWrites,
  });

  final Future<LocalAdapter<ConformanceEntity>> Function() createLocal;
  final Future<RemoteAdapter<ConformanceEntity>> Function() createRemote;
  final Future<void> Function(LocalAdapter<ConformanceEntity>)? destroyLocal;
  final Future<void> Function(RemoteAdapter<ConformanceEntity>)? destroyRemote;
  final ReopenLocal? reopenLocal;
  final FailEntityWrites? failEntityWrites;
  final bool timestampPulls;

  /// The remote refuses an edit of a row that changed since the edit started
  /// (see [GuardedWriteCapable]): conflicts then show at upload, whatever the
  /// sync direction, and edits are sent one by one.
  final bool guardsWrites;

  final managers = <DatumManager<ConformanceEntity>>[];
  final locals = <LocalAdapter<ConformanceEntity>>[];
  final remotes = <RemoteAdapter<ConformanceEntity>>[];
  final connectivities = <TestConnectivityChecker>[];
  var _metaBumps = 0;

  String? get noFaults =>
      failEntityWrites == null ? 'no failEntityWrites hook' : null;
  String? get noReopen =>
      reopenLocal == null ? 'local adapter cannot be reopened' : null;

  /// Boots a device: a local (fresh, or [local] when reopening) + remote +
  /// manager.
  Future<_Device> device({
    DatumConflictResolver<ConformanceEntity>? resolver,
    DeleteBehavior deleteBehavior = DeleteBehavior.softDelete,
    DatumErrorRecoveryStrategy? recovery,
    LocalAdapter<ConformanceEntity>? local,
    bool online = true,
    Stream<bool>? authState,
    AuthErrorPolicy authErrorPolicy = AuthErrorPolicy.pauseSync,
    Duration? deltaSyncOverlap,
  }) async {
    final adapter = local ?? await createLocal();
    final remote = await createRemote();
    final connectivity = TestConnectivityChecker()..setOnline(online);
    final defaults = DatumConfig<ConformanceEntity>();
    final manager = DatumManager<ConformanceEntity>(
      localAdapter: adapter,
      remoteAdapter: remote,
      connectivity: connectivity,
      datumConfig: DatumConfig<ConformanceEntity>(
        enableLogging: false,
        deleteBehavior: deleteBehavior,
        defaultConflictResolver:
            resolver ?? LastWriteWinsResolver<ConformanceEntity>(),
        errorRecoveryStrategy: recovery ?? defaults.errorRecoveryStrategy,
        authState: authState,
        authErrorPolicy: authErrorPolicy,
        deltaSyncOverlap: deltaSyncOverlap ?? defaults.deltaSyncOverlap,
      ),
    );
    await manager.initialize();
    managers.add(manager);
    locals.add(adapter);
    remotes.add(remote);
    connectivities.add(connectivity);
    return (manager, adapter, connectivity);
  }

  /// Kills [d] without syncing or flushing, then boots a new device over the
  /// SAME storage via [reopenLocal].
  Future<_Device> crash(
    _Device d, {
    DeleteBehavior deleteBehavior = DeleteBehavior.softDelete,
  }) async {
    await d.$1.dispose();
    final reopened = await reopenLocal!(d.$2);
    return device(local: reopened, deleteBehavior: deleteBehavior);
  }

  /// A fresh remote over the shared backend, released at teardown.
  Future<RemoteAdapter<ConformanceEntity>> probe() async {
    final remote = await createRemote();
    remotes.add(remote);
    return remote;
  }

  /// Reads [id] straight from the shared backend.
  Future<ConformanceEntity?> remoteRow(
    String id, {
    String userId = _u1,
  }) async => (await probe()).read(id, userId: userId);

  /// Live (non-deleted) remote ids of [userId].
  Future<Set<String>> remoteIds({String userId = _u1}) async => {
    for (final e in await (await probe()).readAll(userId: userId))
      if (!e.isDeleted) e.id,
  };

  /// Signals an out-of-band backend write (another device), the way a
  /// well-behaved backend bumps its change beacon.
  Future<void> bumpRemoteMeta({String userId = _u1}) async =>
      (await probe()).updateSyncMetadata(
        DatumSyncMetadata(userId: userId, dataHash: 'oob-${_metaBumps++}'),
        userId,
      );

  Future<void> dispose() async {
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
  }
}

ConformanceEntity _make(
  String id, {
  String name = 'entity',
  int value = 0,
  int version = 1,
  DateTime? modifiedAt,
  String userId = _u1,
}) => ConformanceEntity.make(
  id,
  userId: userId,
  name: name,
  value: value,
  version: version,
  modifiedAt: modifiedAt,
);

/// Runs [sync], swallowing the error a permanently failed op surfaces.
Future<Object?> _syncCatching(DatumManager<ConformanceEntity> m, {DatumSyncOptions<ConformanceEntity>? options}) async {
  try {
    await m.synchronize(_u1, options: options);
    return null;
  } on Object catch (e) {
    return e;
  }
}

Future<void> _edit(
  _Device d,
  String id, {
  String? name,
  int? value,
  DateTime? modifiedAt,
}) async {
  final current = (await d.$2.read(id, userId: _u1))!;
  await d.$1.push(
    item: current.copyWith(name: name, value: value, modifiedAt: modifiedAt),
    userId: _u1,
  );
}

Future<void> _seedSynced(_Device d, List<String> ids) async {
  for (final id in ids) {
    await d.$1.push(
      item: _make(id, name: '$id-v1'),
      userId: _u1,
    );
  }
  final result = await d.$1.synchronize(_u1);
  expect(result.failedCount, 0, reason: 'seed sync is clean');
  expect(await d.$1.getPendingOperations(_u1), isEmpty);
}

// Scenarios: sync.roundtrip (packages/datum/doc/SYNC_SCENARIOS.md)
void _roundTripTests(_Stack s) {
  test('push: a local save reaches the remote after sync', () async {
    final (manager, _, _) = await s.device();
    await manager.push(
      item: _make('a', name: 'pushed'),
      userId: _u1,
    );

    final result = await manager.synchronize(_u1);

    expect(result.failedCount, 0);
    expect((await s.remoteRow('a'))?.name, 'pushed');
  });

  test('pull: a remote row reaches the local store after sync', () async {
    final (manager, local, _) = await s.device();
    await (await s.probe()).create(_make('r1', name: 'remote-born'));

    await manager.synchronize(_u1);

    expect((await local.read('r1', userId: _u1))?.name, 'remote-born');
  });

  test('two devices converge through the shared backend', () async {
    final a = await s.device();
    final b = await s.device();

    await a.$1.push(
      item: _make('a', name: 'from-A'),
      userId: _u1,
    );
    await a.$1.synchronize(_u1);
    await b.$1.synchronize(_u1);
    expect((await b.$2.read('a', userId: _u1))?.name, 'from-A');

    await _edit(b, 'a', name: 'edited-by-B');
    await b.$1.synchronize(_u1);
    await a.$1.synchronize(_u1);

    expect((await a.$1.read('a', userId: _u1))?.name, 'edited-by-B');
  });

  test('offline saves queue and replay when connectivity returns', () async {
    final (manager, _, connectivity) = await s.device();
    connectivity.setOnline(false);

    await manager.push(
      item: _make('q1', name: 'queued'),
      userId: _u1,
    );
    expect(await manager.getPendingOperations(_u1), isNotEmpty);
    final offline = await manager.synchronize(_u1);
    expect(offline.wasSkipped, isTrue, reason: 'offline cycles are skipped');

    connectivity.setOnline(true);
    final result = await manager.synchronize(_u1);

    expect(result.failedCount, 0);
    expect(await manager.getPendingOperations(_u1), isEmpty);
    expect((await s.remoteRow('q1'))?.name, 'queued');
  });

  test('a clean second cycle is a no-op', () async {
    final (manager, _, _) = await s.device();
    await manager.push(item: _make('n1'), userId: _u1);
    await manager.synchronize(_u1);

    final second = await manager.synchronize(_u1);

    expect(second.failedCount, 0);
    expect(second.syncedCount, 0, reason: 'nothing changed since last cycle');
  });

  test('saveMany pushes the whole batch', () async {
    final (manager, _, _) = await s.device();
    await manager.saveMany(
      items: [for (var i = 0; i < 5; i++) _make('b$i', value: i)],
      userId: _u1,
    );

    await manager.synchronize(_u1);

    expect(await s.remoteIds(), {for (var i = 0; i < 5; i++) 'b$i'});
  });

  test('sync metadata is stamped on both sides with matching hashes', () async {
    final (manager, local, _) = await s.device();
    await manager.push(item: _make('m1'), userId: _u1);
    await manager.synchronize(_u1);

    final localMeta = await local.getSyncMetadata(_u1);
    final remoteMeta = await (await s.probe()).getSyncMetadata(_u1);

    expect(localMeta?.dataHash, isNotNull);
    expect(remoteMeta?.dataHash, localMeta?.dataHash);
  });
}

// Scenarios: sync.order (packages/datum/doc/SYNC_SCENARIOS.md)
void _directionAndOrderingTests(_Stack s) {
  test('pushOnly and pullOnly move data in one direction only', () async {
    final (manager, local, _) = await s.device();
    await (await s.probe()).create(_make('r1', name: 'remote-born'));
    await s.bumpRemoteMeta();
    await manager.push(
      item: _make('l1', name: 'local-born'),
      userId: _u1,
    );

    await manager.synchronize(
      _u1,
      options: const DatumSyncOptions(direction: SyncDirection.pushOnly),
    );
    expect((await s.remoteRow('l1'))?.name, 'local-born');
    expect(await local.read('r1', userId: _u1), isNull, reason: 'no pull');
    expect(await manager.getPendingOperations(_u1), isEmpty);

    await manager.push(
      item: _make('l2', name: 'held-back'),
      userId: _u1,
    );
    await s.bumpRemoteMeta();
    await manager.synchronize(
      _u1,
      options: const DatumSyncOptions(direction: SyncDirection.pullOnly),
    );
    expect((await local.read('r1', userId: _u1))?.name, 'remote-born');
    expect(await s.remoteRow('l2'), isNull, reason: 'pullOnly never pushes');
    expect((await manager.getPendingOperations(_u1)).length, 1);

    final both = await manager.synchronize(
      _u1,
      options: const DatumSyncOptions(direction: SyncDirection.pullThenPush),
    );
    expect(both.failedCount, 0);
    expect((await s.remoteRow('l2'))?.name, 'held-back');
    expect(await s.remoteIds(), {'r1', 'l1', 'l2'});
  });

  test('create -> update -> update of one entity lands as the final state '
      'exactly once', () async {
    final d = await s.device();
    await d.$1.push(
      item: _make('x', name: 'v1', value: 1),
      userId: _u1,
    );
    await _edit(d, 'x', name: 'v2', value: 2);
    await _edit(d, 'x', name: 'v3', value: 3);
    expect((await d.$1.getPendingOperations(_u1)).length, greaterThan(0));

    final result = await d.$1.synchronize(_u1);

    expect(result.failedCount, 0);
    final remote = (await s.remoteRow('x'))!;
    expect(remote.name, 'v3');
    expect(remote.value, 3);
    expect(remote.version, 3, reason: 'each edit applied once, in order');
    expect(await s.remoteIds(), {'x'});
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
    expect((await d.$2.read('x', userId: _u1))?.version, 3);
  });

  test('create -> update -> delete before any sync ends deleted on both '
      'sides', () async {
    final d = await s.device();
    await d.$1.push(
      item: _make('x', name: 'v1'),
      userId: _u1,
    );
    await _edit(d, 'x', name: 'v2');
    await d.$1.delete(id: 'x', userId: _u1);
    await d.$1.push(
      item: _make('keep', name: 'survivor'),
      userId: _u1,
    );

    final result = await d.$1.synchronize(_u1);

    expect(result.failedCount, 0);
    final remote = await s.remoteRow('x');
    expect(remote == null || remote.isDeleted, isTrue);
    expect(await d.$1.read('x', userId: _u1), isNull);
    expect((await s.remoteRow('keep'))?.name, 'survivor');
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
  });
}

// Scenarios: sync.failure (packages/datum/doc/SYNC_SCENARIOS.md)
void _failureTests(_Stack s) {
  test(
    'a retryable failure defers later ops for that entity only, then succeeds',
    () async {
      final d = await s.device();
      await _seedSynced(d, ['x', 'other']);
      await _edit(d, 'x', name: 'x-v2');
      await _edit(d, 'x', name: 'x-v3');
      await d.$1.push(
        item: _make('y', name: 'y-new'),
        userId: _u1,
      );
      await _edit(d, 'other', name: 'other-v2');
      s.failEntityWrites!('x', status: 503);

      final first = await d.$1.synchronize(_u1);

      expect(first.failedCount, 0, reason: 'retryable is not a failure');
      expect((await s.remoteRow('x'))?.name, 'x-v1', reason: 'x held back');
      expect((await s.remoteRow('y'))?.name, 'y-new', reason: 'others flow');
      expect((await s.remoteRow('other'))?.name, 'other-v2');
      final pending = await d.$1.getPendingOperations(_u1);
      expect(pending.map((op) => op.entityId), everyElement('x'));
      expect(pending.first.retryCount, 1);
      expect(pending[1].retryCount, 0, reason: 'deferred, not attempted');
      expect(
        (await d.$2.read('x', userId: _u1))?.name,
        'x-v3',
        reason: 'pull must not regress a locally pending entity',
      );

      final second = await d.$1.synchronize(_u1);

      expect(second.failedCount, 0);
      final remote = (await s.remoteRow('x'))!;
      expect(remote.name, 'x-v3', reason: 'older op first, newer wins');
      expect(remote.version, 3);
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
      expect(await d.$1.getParkedOperations(_u1), isEmpty);
    },
    skip: s.noFaults,
  );

  test(
    'an exhausted retry budget parks the op instead of dropping it',
    () async {
      final d = await s.device(
        recovery: DatumErrorRecoveryStrategy(
          shouldRetry: (e) async => e is NetworkException && e.isRetryable,
          maxRetries: 2,
        ),
      );
      await _seedSynced(d, ['x']);
      await _edit(d, 'x', name: 'x-v2');
      s.failEntityWrites!('x', status: 503, times: 100);

      await _syncCatching(d.$1); // retry 1
      await _syncCatching(d.$1); // retry 2
      expect(await d.$1.getParkedOperations(_u1), isEmpty);
      // Budget spent. Whether the cycle also throws depends on whether the
      // op ran on the single-op path (rethrows) or a batch fallback (not).
      await _syncCatching(d.$1);

      final parked = await d.$1.getParkedOperations(_u1);
      expect(parked, hasLength(1));
      expect(parked.single.entityId, 'x');
      expect(parked.single.isParked, isTrue);
      expect(parked.single.retryCount, 2);
      expect(
        (await d.$1.getPendingOperations(_u1)).first.id,
        parked.single.id,
        reason: 'parked ops stay queued, at the head',
      );
      expect((await s.remoteRow('x'))?.name, 'x-v1');

      s.failEntityWrites!('x', status: 503, times: 0);
      expect(await d.$1.retryParkedOperations(_u1), 1);
      final rearmed = (await d.$1.getPendingOperations(_u1)).first;
      expect(rearmed.id, parked.single.id);
      expect(rearmed.isParked, isFalse);
      expect(rearmed.retryCount, 0, reason: 'budget reset');
      final result = await d.$1.synchronize(_u1);
      expect(result.failedCount, 0);
      expect((await s.remoteRow('x'))?.name, 'x-v2');
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
    },
    skip: s.noFaults,
  );

  test(
    'a failed batch falls back per op without losing its siblings',
    () async {
      final d = await s.device(deleteBehavior: DeleteBehavior.hardDelete);
      final ids = [for (var i = 0; i < 5; i++) 'b$i'];
      await _seedSynced(d, ids);
      for (final id in ids) {
        await d.$1.delete(id: id, userId: _u1);
      }
      // b1 already vanished remotely; b3 is rejected for good.
      await (await s.probe()).delete('b1', userId: _u1);
      // Fails inside the batch call AND the per-op fallback.
      s.failEntityWrites!('b3', status: 403, times: 2);

      await _syncCatching(d.$1);

      expect(await s.remoteIds(), {'b3'}, reason: 'siblings all delivered');
      final parked = await d.$1.getParkedOperations(_u1);
      expect(parked.map((op) => op.entityId), ['b3']);
      expect(parked.single.parkedError, contains('403'));
      expect(
        (await d.$1.getPendingOperations(_u1)).map((op) => op.entityId),
        everyElement('b3'),
      );
      for (final id in ids.where((id) => id != 'b3')) {
        expect(await d.$1.read(id, userId: _u1), isNull);
      }

      s.failEntityWrites!('b3', status: 403, times: 0);
      expect(await d.$1.retryParkedOperations(_u1), 1);
      expect((await d.$1.synchronize(_u1)).failedCount, 0);
      expect(await s.remoteIds(), isEmpty);
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
    },
    skip: s.guardsWrites ? 'a remote that guards writes gets deletes one by one, never as a batch' : s.noFaults,
  );

  test(
    'an update of an entity missing remotely is converted to a create',
    () async {
      final d = await s.device();
      await _seedSynced(d, ['x']);
      await (await s.probe()).delete('x', userId: _u1);
      await _edit(d, 'x', name: 'x-v2', value: 7);

      final result = await d.$1.synchronize(_u1);

      expect(result.failedCount, 0);
      final remote = (await s.remoteRow('x'))!;
      expect(remote.name, 'x-v2');
      expect(remote.value, 7);
      expect(remote.version, 2);
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
    },
  );

  test('a delete of an entity missing remotely is tolerated', () async {
    final d = await s.device(deleteBehavior: DeleteBehavior.hardDelete);
    await _seedSynced(d, ['gone', 'here']);
    await (await s.probe()).delete('gone', userId: _u1);
    await d.$1.delete(id: 'gone', userId: _u1);

    final result = await d.$1.synchronize(_u1);

    expect(result.failedCount, 0);
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
    expect(await d.$1.getParkedOperations(_u1), isEmpty);
    expect(await s.remoteIds(), {'here'});
    expect(await d.$1.read('gone', userId: _u1), isNull);
  });
}

// Scenarios: sync.parked (packages/datum/doc/SYNC_SCENARIOS.md)
void _parkingTests(_Stack s) {
  test('non-retryable 403 parks the op: kept, skipped with its successors, '
      'others sync, retry re-arms, discard drops', () async {
    final d = await s.device();
    await _seedSynced(d, ['p', 'q', 'r']);
    await _edit(d, 'p', name: 'p-v2');
    await _edit(d, 'q', name: 'q-v2');
    s.failEntityWrites!('p', status: 403);

    expect(await _syncCatching(d.$1), isNotNull, reason: 'parking surfaces');

    var parked = await d.$1.getParkedOperations(_u1);
    expect(parked.map((op) => op.entityId), ['p']);
    expect(parked.single.parkedError, contains('403'));
    expect(
      (await d.$1.getPendingOperations(_u1)).map((op) => op.entityId),
      containsAll(['p', 'q']),
      reason: 'parked op stays queued',
    );

    // A later edit of the parked entity must wait behind it.
    await _edit(d, 'p', name: 'p-v3');
    s.failEntityWrites!('q', status: 403);
    await _syncCatching(d.$1);
    expect((await s.remoteRow('p'))?.name, 'p-v1', reason: 'p skipped');
    parked = await d.$1.getParkedOperations(_u1);
    expect(parked.map((op) => op.entityId).toSet(), {'p', 'q'});

    await _edit(d, 'r', name: 'r-v2');
    expect(await _syncCatching(d.$1), isNull, reason: 'parked ops skipped');
    expect((await s.remoteRow('r'))?.name, 'r-v2', reason: 'others sync');

    final pOps = parked.where((op) => op.entityId == 'p');
    final retried = await d.$1.retryParkedOperations(
      _u1,
      operationIds: {for (final op in pOps) op.id},
    );
    expect(retried, 1);
    expect((await d.$1.getParkedOperations(_u1)).single.entityId, 'q');
    expect((await d.$1.synchronize(_u1)).failedCount, 0);
    final p = (await s.remoteRow('p'))!;
    expect(p.name, 'p-v3', reason: 'retried op then its successor');
    expect(p.version, 3);

    final qParked = (await d.$1.getParkedOperations(_u1)).single;
    expect(await d.$1.discardParkedOperations(_u1), 1);
    expect(await d.$1.getParkedOperations(_u1), isEmpty);
    expect(
      (await d.$1.getPendingOperations(_u1)).map((op) => op.id),
      isNot(contains(qParked.id)),
    );
    expect(await _syncCatching(d.$1), isNull);
  }, skip: s.noFaults);

  test('parked state survives a crash and reopen', () async {
    var d = await s.device();
    await _seedSynced(d, ['p']);
    await _edit(d, 'p', name: 'p-v2');
    s.failEntityWrites!('p', status: 403);
    await _syncCatching(d.$1);
    final before = await d.$1.getParkedOperations(_u1);
    expect(before, hasLength(1));

    d = await s.crash(d);

    final after = await d.$1.getParkedOperations(_u1);
    expect(after.map((op) => op.id), before.map((op) => op.id));
    expect(after.single.parkedError, before.single.parkedError);
    expect(after.single.data?.name, 'p-v2', reason: 'payload persisted');
    expect(await _syncCatching(d.$1), isNull, reason: 'still skipped');
    expect((await s.remoteRow('p'))?.name, 'p-v1');

    expect(await d.$1.retryParkedOperations(_u1), 1);
    expect((await d.$1.synchronize(_u1)).failedCount, 0);
    expect((await s.remoteRow('p'))?.name, 'p-v2');
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
  }, skip: s.noFaults ?? s.noReopen);
}

// Scenarios: sync.auth (packages/datum/doc/SYNC_SCENARIOS.md)
void _authPauseTests(_Stack s) {
  test('an expired session (401) pauses sync with the queue untouched; '
      'signing back in resumes and delivers on its own', () async {
    final auth = StreamController<bool>.broadcast();
    addTearDown(auth.close);
    final d = await s.device(authState: auth.stream);
    await _seedSynced(d, ['a', 'b']);
    await _edit(d, 'a', name: 'a-v2');
    await _edit(d, 'b', name: 'b-v2');
    s.failEntityWrites!('a', status: 401);

    expect(await _syncCatching(d.$1), isA<AuthenticationException>());
    expect(d.$1.currentStatus.status, DatumSyncStatus.paused);
    expect(await d.$1.getParkedOperations(_u1), isEmpty, reason: 'not parked');
    final queued = await d.$1.getPendingOperations(_u1);
    expect(queued.map((op) => op.entityId), containsAll(['a', 'b']));
    expect(queued.every((op) => op.retryCount == 0), isTrue, reason: 'no retry budget spent');

    // While paused, syncs are skipped and nothing reaches the remote.
    await _edit(d, 'a', name: 'a-v3');
    expect((await d.$1.synchronize(_u1)).wasSkipped, isTrue);
    expect((await s.remoteRow('a'))?.name, 'a-v1');

    // A signed-out event changes nothing; signing in resumes and re-syncs.
    auth.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(d.$1.currentStatus.status, DatumSyncStatus.paused);
    final resynced = d.$1.onSyncCompleted.first;
    auth.add(true);
    await resynced.timeout(const Duration(seconds: 10));
    expect(await d.$1.getPendingCount(_u1), 0);
    expect((await s.remoteRow('a'))?.name, 'a-v3');
    expect((await s.remoteRow('b'))?.name, 'b-v2');
    expect(d.$1.currentStatus.status, isNot(DatumSyncStatus.paused), reason: 'unpaused');
  }, skip: s.noFaults);

  test('AuthErrorPolicy.park keeps the pre-pause behaviour', () async {
    final d = await s.device(authErrorPolicy: AuthErrorPolicy.park);
    await _seedSynced(d, ['a']);
    await _edit(d, 'a', name: 'a-v2');
    s.failEntityWrites!('a', status: 401);

    expect(await _syncCatching(d.$1), isA<AuthenticationException>());
    expect(d.$1.currentStatus.status, isNot(DatumSyncStatus.paused));
    expect((await d.$1.getParkedOperations(_u1)).map((op) => op.entityId), ['a']);
    expect(await d.$1.retryParkedOperations(_u1), 1);
    expect((await d.$1.synchronize(_u1)).failedCount, 0);
    expect((await s.remoteRow('a'))?.name, 'a-v2');
  }, skip: s.noFaults);
}

// Scenarios: sync.options (packages/datum/doc/SYNC_SCENARIOS.md)
void _syncOptionTests(_Stack s) {
  test('a retryable failure is retried by itself after the backoff delay', () async {
    final d = await s.device(
      recovery: DatumErrorRecoveryStrategy(
        shouldRetry: (e) async => e is NetworkException && e.isRetryable,
        backoffStrategy: const FixedBackoff(delay: Duration(milliseconds: 150)),
      ),
    );
    await _seedSynced(d, ['r']);
    await _edit(d, 'r', name: 'r-v2');
    s.failEntityWrites!('r', status: 503, times: 1);

    final retried = d.$1.onSyncCompleted.skip(1).first;
    await _syncCatching(d.$1);
    final waiting = (await d.$1.getPendingOperations(_u1)).single;
    expect(waiting.retryCount, 1);
    expect((await s.remoteRow('r'))?.name, 'r-v1', reason: 'not delivered yet');

    // No further sync call: the backoff timer re-syncs.
    await retried.timeout(const Duration(seconds: 5));
    expect((await s.remoteRow('r'))?.name, 'r-v2');
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
  }, skip: s.noFaults);

  test('includeDeletes: false holds deletes (and later ops of that entity) '
      'while other writes sync', () async {
    final d = await s.device(deleteBehavior: DeleteBehavior.hardDelete);
    await _seedSynced(d, ['gone', 'kept']);
    await d.$1.delete(id: 'gone', userId: _u1);
    await _edit(d, 'kept', name: 'kept-v2');

    await d.$1.synchronize(_u1, options: const DatumSyncOptions(includeDeletes: false));
    expect(await s.remoteIds(), {'gone', 'kept'}, reason: 'the delete was held back');
    expect((await s.remoteRow('kept'))?.name, 'kept-v2');
    expect((await d.$1.getPendingOperations(_u1)).map((op) => op.entityId), ['gone']);

    await d.$1.synchronize(_u1);
    expect(await s.remoteIds(), {'kept'});
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
  });

  test('resolveConflicts: false reports the conflict and leaves both sides '
      'untouched', () async {
    final a = await s.device();
    final b = await s.device();
    await _seedSynced(a, ['x']);
    await b.$1.synchronize(_u1);

    final t0 = DateTime.now();
    await _edit(a, 'x', name: 'A', modifiedAt: t0);
    await a.$1.synchronize(_u1);
    await _edit(b, 'x', name: 'B', modifiedAt: t0.add(const Duration(seconds: 1)));

    final conflicts = <String>[];
    final sub = b.$1.onConflict.listen((e) => conflicts.add(e.remoteData?.name ?? ''));
    addTearDown(sub.cancel);
    await b.$1.synchronize(
      _u1,
      options: const DatumSyncOptions(direction: SyncDirection.pullOnly, resolveConflicts: false),
    );
    await Future<void>.delayed(Duration.zero);

    expect(conflicts, ['A'], reason: 'the conflict is reported');
    expect((await b.$1.read('x', userId: _u1))?.name, 'B', reason: 'local kept');
    expect((await s.remoteRow('x'))?.name, 'A', reason: 'remote kept');
    expect(await b.$1.getPendingCount(_u1), 1, reason: 'the local edit stays queued');

    // A normal sync then resolves it (later write wins).
    await b.$1.synchronize(_u1);
    await a.$1.synchronize(_u1);
    expect(await _converge([a, b], 'x'), 'B');
  });
}

// Scenarios: sync.guard (packages/datum/doc/SYNC_SCENARIOS.md)
void _writeGuardTests(_Stack s) {
  test('push(expectedVersion:) refuses a stale edit after a pull changed the row', () async {
    final a = await s.device();
    final b = await s.device();
    await _seedSynced(a, ['x']);
    await b.$1.synchronize(_u1);
    final opened = (await b.$1.read('x', userId: _u1))!; // B opens an editor at v1

    await _edit(a, 'x', name: 'A-saved');
    await a.$1.synchronize(_u1);
    await b.$1.synchronize(_u1); // the row under B's editor is now A's

    await expectLater(
      b.$1.push(item: opened.copyWith(name: 'B-stale'), userId: _u1, expectedVersion: opened.version),
      throwsA(isA<ConflictException>()),
    );
    expect((await b.$1.read('x', userId: _u1))?.name, 'A-saved');
    expect(await b.$1.getPendingCount(_u1), 0, reason: 'nothing queued for the refused write');

    // Re-reading and saving against the current version goes through.
    final current = (await b.$1.read('x', userId: _u1))!;
    await b.$1.push(item: current.copyWith(name: 'B-rebased'), userId: _u1, expectedVersion: current.version);
    await b.$1.synchronize(_u1);
    await a.$1.synchronize(_u1);
    expect(await _converge([a, b], 'x'), 'B-rebased');
  });

  test('an edit made after seeing another one wins whatever the clocks say', () async {
    final ahead = await s.device();
    final behind = await s.device();
    await _seedSynced(ahead, ['x']);
    await behind.$1.synchronize(_u1);

    final now = DateTime.now();
    await _edit(ahead, 'x', name: 'stamped-in-the-future', modifiedAt: now.add(const Duration(minutes: 10)));
    await ahead.$1.synchronize(_u1);
    // This device sees that edit first, then makes its own: a later version,
    // although its clock reads ten minutes earlier.
    await behind.$1.synchronize(_u1);
    await _edit(behind, 'x', name: 'made-after-seeing-it', modifiedAt: now);
    await behind.$1.synchronize(_u1);
    await ahead.$1.synchronize(_u1);

    expect(await _converge([ahead, behind], 'x'), 'made-after-seeing-it');
    expect((await s.remoteRow('x'))?.name, 'made-after-seeing-it');
    expect((await s.remoteRow('x'))?.version, 3);
  });

  test('RemotePriorityResolver decides concurrent edits without device '
      'clocks: first push wins when pulling first, last push wins when pushing first', () async {
    // (sync direction of the second device, expected winner). A remote that
    // guards writes refuses the second upload either way.
    for (final (direction, winner) in [
      (SyncDirection.pushThenPull, s.guardsWrites ? 'first' : 'second'),
      (SyncDirection.pullThenPush, 'first'),
    ]) {
      final id = 'k-${direction.name}';
      final resolver = RemotePriorityResolver<ConformanceEntity>();
      final first = await s.device(resolver: resolver);
      final second = await s.device(resolver: resolver);
      await _seedSynced(first, [id]);
      await second.$1.synchronize(_u1);

      // The side that must lose gets a clock 10 minutes fast: under
      // last-write-wins it would win.
      final now = DateTime.now(), fast = now.add(const Duration(minutes: 10));
      await _edit(first, id, name: 'first', modifiedAt: winner == 'first' ? now : fast);
      await _edit(second, id, name: 'second', modifiedAt: winner == 'second' ? now : fast);
      await first.$1.synchronize(_u1);
      await second.$1.synchronize(_u1, options: DatumSyncOptions(direction: direction));
      await first.$1.synchronize(_u1);

      expect(await _converge([first, second], id), winner, reason: direction.name);
      expect((await s.remoteRow(id))?.name, winner);
      expect(await second.$1.getPendingOperations(_u1), isEmpty, reason: 'a losing edit is dropped, not left queued');
    }
  });

  test('a rate-limited write (429) is retried, not parked', () async {
    final d = await s.device(
      recovery: DatumErrorRecoveryStrategy(
        shouldRetry: (e) async => e is NetworkException && e.isRetryable,
        backoffStrategy: const FixedBackoff(delay: Duration(milliseconds: 50)),
      ),
    );
    await _seedSynced(d, ['t']);
    await _edit(d, 't', name: 't-v2');
    s.failEntityWrites!('t', status: 429, times: 1);

    final retried = d.$1.onSyncCompleted.skip(1).first;
    await _syncCatching(d.$1);
    expect(await d.$1.getParkedOperations(_u1), isEmpty);
    await retried.timeout(const Duration(seconds: 5));
    expect((await s.remoteRow('t'))?.name, 't-v2');
  }, skip: s.noFaults);
}

// Scenarios: sync.queue.api (packages/datum/doc/SYNC_SCENARIOS.md)
void _queueAndCompactionApiTests(_Stack s) {
  test('watchPendingCount / isPending / waitUntilSynced follow the queue live', () async {
    final d = await s.device();
    final counts = <int>[];
    final sub = d.$1.watchPendingCount(_u1).listen(counts.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    await d.$1.push(item: _make('w', name: 'w-v1'), userId: _u1);
    expect(await d.$1.isPending('w', userId: _u1), isTrue);
    await expectLater(
      d.$1.waitUntilSynced(_u1, timeout: const Duration(milliseconds: 100)),
      throwsA(isA<DatumTimeoutException>()),
      reason: 'nothing syncs on its own here',
    );

    final synced = d.$1.waitUntilSynced(_u1, timeout: const Duration(seconds: 5));
    await d.$1.synchronize(_u1);
    await synced;
    expect(await d.$1.isPending('w', userId: _u1), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(counts.first, 0);
    expect(counts, contains(1));
    expect(counts.last, 0);
  });

  test('purgeTombstones removes only old, uploaded tombstones', () async {
    final d = await s.device();
    await _seedSynced(d, ['old', 'fresh', 'queued', 'live']);
    for (final id in ['old', 'fresh', 'queued']) {
      await d.$1.delete(id: id, userId: _u1);
    }
    // 'queued' keeps a pending op: it must survive however old it is.
    await d.$1.synchronize(_u1);
    await d.$1.restore(id: 'queued', userId: _u1);
    await d.$1.delete(id: 'queued', userId: _u1);

    expect(await d.$1.purgeTombstones(_u1), 0, reason: 'nothing is 30 days old');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // Re-delete 'fresh' so its tombstone is newer than the cutoff below.
    await d.$1.restore(id: 'fresh', userId: _u1);
    await d.$1.synchronize(_u1);
    final cutoff = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await d.$1.delete(id: 'fresh', userId: _u1);
    await d.$1.synchronize(_u1);
    await d.$1.restore(id: 'queued', userId: _u1); // pending again

    final purged = await d.$1.purgeTombstones(_u1, olderThan: DateTime.now().difference(cutoff));
    expect(purged, 1);
    expect(await d.$2.read('old', userId: _u1), isNull, reason: 'physically gone');
    expect((await d.$2.read('fresh', userId: _u1))?.isDeleted, isTrue);
    expect(await d.$2.read('queued', userId: _u1), isNotNull);
    expect((await d.$1.read('live', userId: _u1))?.name, 'live-v1');
    expect((await s.remoteRow('old'))?.isDeleted, isTrue, reason: 'the remote keeps its tombstone');
  });

  test('a fresh device does not store tombstones of rows it never had', () async {
    final a = await s.device();
    await _seedSynced(a, ['kept', 'gone']);
    await a.$1.delete(id: 'gone', userId: _u1);
    await a.$1.synchronize(_u1);

    final b = await s.device();
    await b.$1.synchronize(_u1);
    expect((await b.$2.readAll(userId: _u1)).map((e) => e.id), ['kept']);

    // The row still arrives if it is restored later.
    await a.$1.restore(id: 'gone', userId: _u1);
    await a.$1.synchronize(_u1);
    await b.$1.synchronize(_u1);
    expect((await b.$1.read('gone', userId: _u1))?.name, 'gone-v1');
  });

  test('clearUserData wipes one user\'s rows and queue only', () async {
    final d = await s.device();
    await _seedSynced(d, ['mine']);
    await d.$1.push(item: _make('theirs', userId: 'u2'), userId: 'u2');
    await _edit(d, 'mine', name: 'mine-v2');

    await d.$1.clearUserData(_u1);

    expect(await d.$2.readAll(userId: _u1), isEmpty);
    expect(await d.$1.getPendingCount(_u1), 0);
    expect((await d.$2.readAll(userId: 'u2')).map((e) => e.id), ['theirs']);
    expect(await d.$1.getPendingCount('u2'), 1);
    // The next sync brings the user's synced data back.
    await d.$1.synchronize(_u1);
    expect((await d.$1.read('mine', userId: _u1))?.name, 'mine-v1');
  });
}

// Scenarios: sync.replay (packages/datum/doc/SYNC_SCENARIOS.md)
void _crashAndReplayTests(_Stack s) {
  test('an op whose remote write landed but was never dequeued (crash / lost '
      'ack) replays idempotently', () async {
    var d = await s.device();
    await _seedSynced(d, ['u']);
    d.$3.setOnline(false);
    await d.$1.push(
      item: _make('c', name: 'created', value: 1),
      userId: _u1,
    );
    await _edit(d, 'u', name: 'u-v2', value: 2);
    // The remote already applied both writes; the acks never arrived.
    final remote = await s.probe();
    await remote.create((await d.$2.read('c', userId: _u1))!);
    await remote.update((await d.$2.read('u', userId: _u1))!);
    expect((await d.$1.getPendingOperations(_u1)).length, 2);

    if (s.reopenLocal != null) d = await s.crash(d);
    d.$3.setOnline(true);
    final result = await d.$1.synchronize(_u1);
    await d.$1.synchronize(_u1);

    expect(result.failedCount, 0);
    expect(await s.remoteIds(), {'u', 'c'}, reason: 'no duplicates');
    final c = (await s.remoteRow('c'))!;
    expect((c.name, c.value, c.version), ('created', 1, 1));
    final u = (await s.remoteRow('u'))!;
    expect((u.name, u.value, u.version), ('u-v2', 2, 2));
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
    expect((await d.$2.read('u', userId: _u1))?.version, 2);
  });

  test('the first of two queued edits landed but its ack was lost: the '
      'second is still delivered, under every resolver and both directions', () async {
    for (final resolver in <DatumConflictResolver<ConformanceEntity>>[
      LastWriteWinsResolver<ConformanceEntity>(),
      LocalPriorityResolver<ConformanceEntity>(),
      RemotePriorityResolver<ConformanceEntity>(),
    ]) {
      for (final direction in [SyncDirection.pullThenPush, SyncDirection.pushThenPull]) {
        final id = 'half-${resolver.name}-${direction.name}';
        final d = await s.device(resolver: resolver, online: true);
        await _seedSynced(d, [id]);
        final conflicts = <String>[];
        final sub = d.$1.onConflict.listen((e) => conflicts.add(e.context.entityId));
        addTearDown(sub.cancel);
        d.$3.setOnline(false);
        await _edit(d, id, name: 'first edit');
        final afterFirst = (await d.$2.read(id, userId: _u1))!;
        await _edit(d, id, name: 'second edit');
        // The remote applied the first edit; nothing told the device.
        await (await s.probe()).update(afterFirst);
        d.$3.setOnline(true);

        final options = DatumSyncOptions<ConformanceEntity>(direction: direction, forceFullSync: true);
        expect((await d.$1.synchronize(_u1, options: options)).failedCount, 0);
        await d.$1.synchronize(_u1, options: options);
        await Future<void>.delayed(Duration.zero);

        final reason = '${resolver.name}, ${direction.name}';
        expect((await s.remoteRow(id))?.name, 'second edit', reason: reason);
        expect((await d.$2.read(id, userId: _u1))?.name, 'second edit', reason: reason);
        expect(await d.$1.getPendingOperations(_u1), isEmpty, reason: reason);
        expect(conflicts, isEmpty, reason: '$reason: the remote row is this device\'s own edit');
      }
    }
  });

  test(
    'a crash with a mixed offline queue resumes in order after reopen',
    () async {
      var d = await s.device(deleteBehavior: DeleteBehavior.hardDelete);
      await _seedSynced(d, ['a', 'b']);
      d.$3.setOnline(false);
      await _edit(d, 'a', name: 'a-v2');
      await d.$1.delete(id: 'b', userId: _u1);
      await d.$1.push(
        item: _make('n', name: 'new'),
        userId: _u1,
      );
      await _edit(d, 'n', name: 'new-v2');
      final queued = await d.$1.getPendingOperations(_u1);

      d = await s.crash(d, deleteBehavior: DeleteBehavior.hardDelete);

      final reopened = await d.$1.getPendingOperations(_u1);
      expect(
        reopened.map((op) => op.id),
        queued.map((op) => op.id),
        reason: 'queue order persisted',
      );
      expect((await d.$1.synchronize(_u1)).failedCount, 0);
      expect(await s.remoteIds(), {'a', 'n'});
      expect((await s.remoteRow('a'))?.name, 'a-v2');
      final n = (await s.remoteRow('n'))!;
      expect((n.name, n.version), ('new-v2', 2));
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
    },
    skip: s.noReopen,
  );
}

Future<String?> _converge(List<_Device> devices, String id) async {
  for (var round = 0; round < 3; round++) {
    for (final d in devices) {
      await d.$1.synchronize(_u1);
    }
  }
  final names = {
    for (final d in devices) (await d.$2.read(id, userId: _u1))?.name,
  };
  expect(names, hasLength(1), reason: 'devices disagree: $names');
  return names.single;
}

// Scenarios: sync.conflict (packages/datum/doc/SYNC_SCENARIOS.md)
void _conflictTests(_Stack s) {
  test(
    'concurrent same-version edits resolve by last-write-wins and converge',
    () async {
      final (manager, local, _) = await s.device();
      await manager.push(
        item: _make('c1', name: 'base'),
        userId: _u1,
      );
      await manager.synchronize(_u1);

      final base = (await local.read('c1', userId: _u1))!;
      await (await s.probe()).update(
        base.copyWith(
          name: 'remote-loser',
          modifiedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      await manager.push(
        item: base.copyWith(name: 'local-winner'),
        userId: _u1,
      );

      await manager.synchronize(_u1);
      await manager.synchronize(_u1);

      expect((await local.read('c1', userId: _u1))?.name, 'local-winner');
      expect((await s.remoteRow('c1'))?.name, 'local-winner');
    },
  );

  test('a stale remote row does not clobber a newer local one', () async {
    final (manager, local, _) = await s.device();
    await manager.push(
      item: _make('s1', name: 'newer', version: 3),
      userId: _u1,
    );
    await manager.synchronize(_u1);

    await (await s.probe()).update(
      _make(
        's1',
        name: 'stale',
        modifiedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );
    await s.bumpRemoteMeta();
    await manager.synchronize(_u1);

    expect((await local.read('s1', userId: _u1))?.name, 'newer');
  });

  test(
    'two devices editing concurrently converge on the later write',
    () async {
      final a = await s.device();
      final b = await s.device();
      await _seedSynced(a, ['x']);
      await b.$1.synchronize(_u1);

      final t0 = DateTime.now();
      await _edit(a, 'x', name: 'A-earlier', modifiedAt: t0);
      await _edit(
        b,
        'x',
        name: 'B-later',
        modifiedAt: t0.add(const Duration(seconds: 1)),
      );
      // The later writer syncs FIRST; the stale writer's push must not win.
      await b.$1.synchronize(_u1);
      await a.$1.synchronize(_u1);

      expect(await _converge([a, b], 'x'), 'B-later');
      expect((await s.remoteRow('x'))?.name, 'B-later');
      expect(await a.$1.getPendingOperations(_u1), isEmpty);
      expect(await b.$1.getPendingOperations(_u1), isEmpty);
    },
  );

  test('clock skew: LWW follows device wall clocks, so a device running '
      '10 min ahead beats a later real-time edit (documents current '
      'behavior; see API_AND_TESTING_REVIEW #10)', () async {
    final ahead = await s.device();
    final honest = await s.device();
    await _seedSynced(ahead, ['x']);
    await honest.$1.synchronize(_u1);

    final now = DateTime.now();
    await _edit(
      ahead,
      'x',
      name: 'skewed-ahead',
      modifiedAt: now.add(const Duration(minutes: 10)),
    );
    await ahead.$1.synchronize(_u1);
    // Strictly later in real time, but its clock reads 10 minutes earlier.
    await _edit(honest, 'x', name: 'real-latest', modifiedAt: now);
    await honest.$1.synchronize(_u1);

    expect(await _converge([ahead, honest], 'x'), 'skewed-ahead');
    expect((await s.remoteRow('x'))?.name, 'skewed-ahead');
  });

  test('an upload that fails leaves the edit in place for every resolver: the '
      'unchanged remote row is not a competing version', () async {
    for (final resolver in <DatumConflictResolver<ConformanceEntity>>[
      LastWriteWinsResolver<ConformanceEntity>(),
      LocalPriorityResolver<ConformanceEntity>(),
      RemotePriorityResolver<ConformanceEntity>(),
    ]) {
      final id = 'kept-${resolver.name}';
      final d = await s.device(
        resolver: resolver,
        recovery: DatumErrorRecoveryStrategy(
          shouldRetry: (e) async => e is NetworkException && e.isRetryable,
          backoffStrategy: const FixedBackoff(delay: Duration(minutes: 5)),
        ),
      );
      await _seedSynced(d, [id]);
      final conflicts = <String>[];
      final sub = d.$1.onConflict.listen((e) => conflicts.add(e.context.entityId));
      addTearDown(sub.cancel);
      await _edit(d, id, name: 'edited');
      await _edit(d, id, name: 'edited-again');

      // The server is down for writes; the pull of the same cycle still
      // returns the row as it was before the edits.
      s.failEntityWrites!(id, status: 503, times: 2);
      for (final direction in [SyncDirection.pushThenPull, SyncDirection.pullThenPush]) {
        await _syncCatching(d.$1, options: DatumSyncOptions<ConformanceEntity>(direction: direction, forceFullSync: true));
        await Future<void>.delayed(Duration.zero);
        expect((await d.$2.read(id, userId: _u1))?.name, 'edited-again', reason: '${resolver.name}, ${direction.name}: the edit must survive');
        expect(await d.$1.getPendingCount(_u1), 2, reason: '${resolver.name}, ${direction.name}: both edits stay queued');
      }
      expect(conflicts, isEmpty, reason: resolver.name);
      expect((await s.remoteRow(id))?.name, '$id-v1');

      // Back up: the edits are delivered.
      s.failEntityWrites!(id, status: 503, times: 0);
      expect((await d.$1.synchronize(_u1)).failedCount, 0);
      expect((await s.remoteRow(id))?.name, 'edited-again');
      expect(await d.$1.getPendingCount(_u1), 0);
    }
  }, skip: s.noFaults);

  test('two devices upload edits of one row without seeing each other, one '
      'of them twice: a remote that guards writes hands it to the resolver, '
      'one that accepts every write keeps the last upload', () async {
    // The first uploader insists on its own copy; the second defers.
    final first = await s.device(resolver: LocalPriorityResolver<ConformanceEntity>());
    final second = await s.device(resolver: RemotePriorityResolver<ConformanceEntity>());
    await _seedSynced(first, ['x']);
    await second.$1.synchronize(_u1);
    final conflicts = <String>[];
    for (final (name, d) in [('first', first), ('second', second)]) {
      final sub = d.$1.onConflict.listen((e) => conflicts.add(name));
      addTearDown(sub.cancel);
    }

    await _edit(first, 'x', name: 'first');
    await _edit(second, 'x', name: 'second, once');
    await _edit(second, 'x', name: 'second, twice');
    // Overlapping syncs: each uploads before it has looked.
    const upload = DatumSyncOptions<ConformanceEntity>(direction: SyncDirection.pushOnly);
    expect((await first.$1.synchronize(_u1, options: upload)).failedCount, 0);
    final overlapped = await second.$1.synchronize(_u1, options: upload);
    expect(overlapped.failedCount, 0, reason: 'a refused upload is not a failure');
    expect(await second.$1.getParkedOperations(_u1), isEmpty);
    expect(
      (await s.remoteRow('x'))?.name,
      s.guardsWrites ? 'first' : 'second, twice',
      reason: s.guardsWrites ? 'the stale upload was refused' : 'nothing stops the second upload',
    );

    for (var round = 0; round < 3; round++) {
      await second.$1.synchronize(_u1);
      await first.$1.synchronize(_u1);
    }
    await Future<void>.delayed(Duration.zero);

    // Guarded: the second device, still holding its edits, met the first
    // one's and its resolver gave way. Unguarded: the first device has
    // nothing unsynced and sees a higher version, an ordinary update (only
    // vector clocks could tell it otherwise).
    final winner = s.guardsWrites ? 'first' : 'second, twice';
    expect(await _converge([first, second], 'x'), winner);
    expect((await s.remoteRow('x'))?.name, winner);
    expect(conflicts, s.guardsWrites ? ['second'] : isEmpty);
    expect(await first.$1.getPendingCount(_u1), 0);
    expect(await second.$1.getPendingCount(_u1), 0);
  });

  test('a remote edit of a row this device never touched is taken as is, '
      'whatever the resolver; an unsynced local edit of it is a conflict', () async {
    final author = await s.device();
    final reader = await s.device(resolver: LocalPriorityResolver<ConformanceEntity>());
    await _seedSynced(author, ['x']);
    await reader.$1.synchronize(_u1);
    final conflicts = <String>[];
    final sub = reader.$1.onConflict.listen((e) => conflicts.add(e.remoteData?.name ?? ''));
    addTearDown(sub.cancel);

    // Edited twice elsewhere. The reader has no edit of its own for "local
    // wins" to keep, so the newer row simply replaces the one it has.
    await _edit(author, 'x', name: 'first');
    await _edit(author, 'x', name: 'second');
    await author.$1.synchronize(_u1);
    final caughtUp = await reader.$1.synchronize(_u1);
    await Future<void>.delayed(Duration.zero);
    expect((await reader.$1.read('x', userId: _u1))?.name, 'second');
    expect(caughtUp.conflictsResolved, 0);
    expect(conflicts, isEmpty);
    expect(await reader.$1.getPendingCount(_u1), 0, reason: 'the old copy is not pushed back over the edit');
    expect((await s.remoteRow('x'))?.name, 'second');

    // Both edit it: the reader's unsynced edit is a real conflict, and its
    // resolver decides.
    await _edit(author, 'x', name: 'third');
    await author.$1.synchronize(_u1);
    await _edit(reader, 'x', name: 'mine');
    await reader.$1.synchronize(_u1, options: const DatumSyncOptions(direction: SyncDirection.pullThenPush));
    await Future<void>.delayed(Duration.zero);
    expect(conflicts, ['third']);
    expect((await reader.$1.read('x', userId: _u1))?.name, 'mine');
    expect((await s.remoteRow('x'))?.name, 'mine');
  });

  for (final (label, resolver, expected, bug) in [
    (
      'local wins',
      LocalPriorityResolver<ConformanceEntity>(),
      'local-edit',
      null,
    ),
    (
      'remote wins',
      RemotePriorityResolver<ConformanceEntity>(),
      'remote-edit',
      null,
    ),
  ]) {
    test('pullThenPush conflict with $label converges on both sides', () async {
      final d = await s.device(resolver: resolver);
      await _seedSynced(d, ['x']);
      final base = (await d.$2.read('x', userId: _u1))!;
      await (await s.probe()).update(base.copyWith(name: 'remote-edit'));
      await s.bumpRemoteMeta();
      await _edit(d, 'x', name: 'local-edit');

      const options = DatumSyncOptions<ConformanceEntity>(
        direction: SyncDirection.pullThenPush,
      );
      await d.$1.synchronize(_u1, options: options);
      await d.$1.synchronize(_u1, options: options);

      expect((await d.$2.read('x', userId: _u1))?.name, expected);
      expect((await s.remoteRow('x'))?.name, expected);
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
    }, skip: bug);
  }
}

/// The policies the conflict matrix runs under. Every device follows the
/// same policy, seen from its own side: where one device's resolver keeps
/// its own edits, the others accept them. (Devices whose resolvers disagree
/// about who wins push a row back and forth forever; no engine can settle
/// that for them.) The observer never edits anything.
typedef _Policy = ({
  String label,
  DatumConflictResolver<ConformanceEntity> Function() device,
  DatumConflictResolver<ConformanceEntity> Function() author,
  DatumConflictResolver<ConformanceEntity> Function() observer,
  // What the eight rows changed on BOTH sides must end as, in matrix order;
  // null = must only be the same everywhere.
  List<String?> pullFirst,
  List<String?> pushFirst,
});

/// One row of the matrix: the names each side gave it since both were in
/// sync (null = deleted it), and what it must end as everywhere.
typedef _Case = ({String id, List<String?> remote, List<String?> local, String? winner});

const _deleted = '<deleted>';

String _shown(ConformanceEntity? e) => e == null || e.isDeleted ? _deleted : e.name;

/// Deterministic and symmetric, so two devices merging the same pair agree.
ConformanceEntity _mergeBoth(ConformanceEntity local, ConformanceEntity remote) => ConformanceEntity(
  id: local.id,
  userId: local.userId,
  name: ([_shown(local), _shown(remote)]..sort()).join('+'),
  value: local.value,
  createdAt: local.createdAt,
  isDeleted: local.isDeleted && remote.isDeleted,
  version: (local.version > remote.version ? local.version : remote.version) + 1,
  modifiedAt: (local.modifiedAt.isAfter(remote.modifiedAt) ? local.modifiedAt : remote.modifiedAt).add(const Duration(seconds: 1)),
);

MergeResolver<ConformanceEntity> _merging() => MergeResolver<ConformanceEntity>(onMerge: (local, remote, _) => _mergeBoth(local, remote));

// Rows changed on both sides, in this order: both created it; both edited
// once; both edited twice; local once vs remote twice; local twice vs remote
// once; local edit vs remote delete; local delete vs remote edit; both
// deleted.
final _policies = <_Policy>[
  (
    label: 'last write wins everywhere',
    device: LastWriteWinsResolver<ConformanceEntity>.new,
    author: LastWriteWinsResolver<ConformanceEntity>.new,
    observer: LastWriteWinsResolver<ConformanceEntity>.new,
    // The higher version, then the later write (deletes are the latest).
    pullFirst: ['l1', 'l1', 'l2', 'r2', 'l2', _deleted, _deleted, _deleted],
    pushFirst: ['l1', 'l1', 'l2', 'r2', 'l2', _deleted, _deleted, _deleted],
  ),
  (
    label: 'this device wins (local priority here, remote priority elsewhere)',
    device: LocalPriorityResolver<ConformanceEntity>.new,
    author: RemotePriorityResolver<ConformanceEntity>.new,
    observer: RemotePriorityResolver<ConformanceEntity>.new,
    pullFirst: ['l1', 'l1', 'l2', 'l1', 'l2', 'l1', _deleted, _deleted],
    pushFirst: ['l1', 'l1', 'l2', 'l1', 'l2', 'l1', _deleted, _deleted],
  ),
  (
    label: 'the other device wins (remote priority here, local priority there)',
    device: RemotePriorityResolver<ConformanceEntity>.new,
    author: LocalPriorityResolver<ConformanceEntity>.new,
    observer: RemotePriorityResolver<ConformanceEntity>.new,
    pullFirst: ['r1', 'r1', 'r2', 'r2', 'r1', _deleted, 'r1', _deleted],
    // Uploaded before looking, this device's two edits make a newer version
    // than the other device's one: that device, which has nothing unsynced,
    // takes it as an ordinary update. Pull first (the default) or vector
    // clocks let its resolver decide instead.
    pushFirst: ['r1', 'r1', 'r2', 'r2', null, _deleted, 'r1', _deleted],
  ),
  (
    label: 'merge everywhere',
    device: _merging,
    author: _merging,
    observer: _merging,
    pullFirst: [null, null, null, null, null, null, null, _deleted],
    pushFirst: [null, null, null, null, null, null, null, _deleted],
  ),
];

List<_Case> _matrixCases(List<String?> both) => [
  (id: 'remote-edit', remote: ['r1'], local: [], winner: 'r1'),
  (id: 'remote-edit-twice', remote: ['r1', 'r2'], local: [], winner: 'r2'),
  (id: 'remote-delete', remote: [null], local: [], winner: _deleted),
  (id: 'local-edit', remote: [], local: ['l1'], winner: 'l1'),
  (id: 'local-edit-twice', remote: [], local: ['l1', 'l2'], winner: 'l2'),
  (id: 'local-delete', remote: [], local: [null], winner: _deleted),
  (id: _bothCreate, remote: ['r1'], local: ['l1'], winner: both[0]),
  (id: 'both-edit', remote: ['r1'], local: ['l1'], winner: both[1]),
  (id: 'both-edit-twice', remote: ['r1', 'r2'], local: ['l1', 'l2'], winner: both[2]),
  (id: 'local-edit-remote-twice', remote: ['r1', 'r2'], local: ['l1'], winner: both[3]),
  (id: 'local-twice-remote-edit', remote: ['r1'], local: ['l1', 'l2'], winner: both[4]),
  (id: 'local-edit-remote-delete', remote: [null], local: ['l1'], winner: both[5]),
  (id: 'local-delete-remote-edit', remote: ['r1'], local: [null], winner: both[6]),
  (id: 'both-delete', remote: [null], local: [null], winner: both[7]),
];

/// The one row nobody has at the start: each side creates it.
const _bothCreate = 'both-create';

/// Every combination of "untouched / edited once / edited twice / deleted"
/// on the two sides that follows a different rule, for every resolver policy
/// and both sync directions. For each row: all replicas and the server end
/// the same, the documented side wins, a conflict is reported only when both
/// sides changed, and nothing keeps being rewritten afterwards.
// Scenarios: sync.conflict.matrix (packages/datum/doc/SYNC_SCENARIOS.md)
void _conflictMatrixTests(_Stack s) {
  for (final policy in _policies) {
    for (final direction in [SyncDirection.pullThenPush, SyncDirection.pushThenPull]) {
      test('conflict matrix: ${policy.label}, ${direction.name}', () => _runConflictMatrix(s, policy, direction));
    }
  }
}

Future<void> _runConflictMatrix(_Stack s, _Policy policy, SyncDirection direction) async {
  // A device meets the other side's change before it overwrites anything
  // when it pulls first, or when the remote refuses the stale upload.
  final seesFirst = direction == SyncDirection.pullThenPush || s.guardsWrites;
  final cases = _matrixCases(seesFirst ? policy.pullFirst : policy.pushFirst);
  final author = await s.device(resolver: policy.author());
  final device = await s.device(resolver: policy.device());
  await _seedSynced(author, [
    for (final c in cases)
      if (c.id != _bothCreate) c.id,
  ]);
  await device.$1.synchronize(_u1);
  final conflicts = <String, Set<String>>{'device': {}, 'author': {}};
  for (final (name, d) in [('device', device), ('author', author)]) {
    final sub = d.$1.onConflict.listen((e) => conflicts[name]!.add(e.context.entityId));
    addTearDown(sub.cancel);
  }

  // Edits carry rising timestamps from an hour ago, so a later edit is the
  // later write and a delete (stamped now) is later than any edit. The other
  // device's changes are uploaded; this device's are not.
  var at = DateTime.now().subtract(const Duration(hours: 1));
  DateTime next() => at = at.add(const Duration(seconds: 1));
  for (final c in cases) {
    await _applyChanges(author, c.id, c.remote, next);
  }
  await author.$1.synchronize(_u1);
  for (final c in cases) {
    await _applyChanges(device, c.id, c.local, next);
  }

  final replicas = {'device': device, 'author': author, 'observer': await s.device(resolver: policy.observer())};
  final options = DatumSyncOptions<ConformanceEntity>(direction: direction);
  Future<void> everyoneSyncs() async {
    for (final replica in replicas.values) {
      await replica.$1.synchronize(_u1, options: options);
    }
  }

  // A resolution travels one hop per round.
  for (var round = 0; round < 6; round++) {
    await everyoneSyncs();
  }
  await Future<void>.delayed(Duration.zero);

  final reported = conflicts.values.expand((ids) => ids).toSet();
  for (final c in cases) {
    await _expectSameEverywhere(s, replicas, c);
    if (c.local.isEmpty || c.remote.isEmpty) {
      expect(reported, isNot(contains(c.id)), reason: '${c.id}: one side did not change, so nothing conflicts');
    }
  }
  if (seesFirst) {
    expect(
      conflicts['device'],
      containsAll([_bothCreate, 'both-edit', 'both-edit-twice', 'local-edit-remote-twice', 'local-twice-remote-edit', 'local-edit-remote-delete', 'local-delete-remote-edit']),
      reason: 'an unsynced change against a changed row is reported before anything is overwritten',
    );
  }
  await _expectSettled(replicas, everyoneSyncs);
}

/// Applies [changes] to [id] on [d]: a name edits it (or creates it when the
/// device does not have it), null deletes it.
Future<void> _applyChanges(_Device d, String id, List<String?> changes, DateTime Function() next) async {
  for (final name in changes) {
    if (name == null) {
      await d.$1.delete(id: id, userId: _u1);
    } else if (await d.$2.read(id, userId: _u1) == null) {
      await d.$1.push(item: _make(id, name: name, modifiedAt: next()), userId: _u1);
    } else {
      await _edit(d, id, name: name, modifiedAt: next());
    }
  }
}

/// Every replica and the server show [c] the same, as its expected winner.
Future<void> _expectSameEverywhere(_Stack s, Map<String, _Device> replicas, _Case c) async {
  final states = {
    for (final MapEntry(key: name, value: d) in replicas.entries) name: _shown(await d.$2.read(c.id, userId: _u1)),
    'remote': _shown(await s.remoteRow(c.id)),
  };
  expect(states.values.toSet(), hasLength(1), reason: '${c.id} must be the same everywhere: $states');
  if (c.winner != null) expect(states['remote'], c.winner, reason: c.id);
}

/// Nobody has anything left to send, and another round writes nothing
/// anywhere.
Future<void> _expectSettled(Map<String, _Device> replicas, Future<void> Function() everyoneSyncs) async {
  final writes = <String>[];
  for (final MapEntry(key: name, value: d) in replicas.entries) {
    expect(await d.$1.getPendingCount(_u1), 0, reason: '$name still has uploads queued');
    final changes = d.$1.onDataChange.listen((e) => writes.add('$name:${e.data?.id}'));
    addTearDown(changes.cancel);
  }
  await everyoneSyncs();
  await Future<void>.delayed(Duration.zero);
  expect(writes, isEmpty, reason: 'replicas keep rewriting each other');
}

// Scenarios: sync.delete (packages/datum/doc/SYNC_SCENARIOS.md)
void _deleteAndWatchTests(_Stack s) {
  test('soft deletes propagate local -> remote -> other device', () async {
    final a = await s.device();
    final b = await s.device();
    await _seedSynced(a, ['d1', 'd2']);
    await b.$1.synchronize(_u1);

    await a.$1.delete(id: 'd1', userId: _u1);
    await a.$1.synchronize(_u1);

    final remoteRow = await s.remoteRow('d1');
    expect(remoteRow == null || remoteRow.isDeleted, isTrue);
    expect(await a.$1.read('d1', userId: _u1), isNull);

    await b.$1.synchronize(_u1);
    expect(
      await b.$1.read('d1', userId: _u1),
      isNull,
      reason: 'deletion reached the other device',
    );
    expect((await b.$1.read('d2', userId: _u1))?.name, 'd2-v1');
  });

  test('a remote soft delete propagates to the local store', () async {
    final d = await s.device();
    await _seedSynced(d, ['x', 'y']);
    final row = (await s.remoteRow('x'))!;
    await (await s.probe()).update(row.copyWith(isDeleted: true));
    await s.bumpRemoteMeta();

    await d.$1.synchronize(_u1);

    expect(await d.$1.read('x', userId: _u1), isNull);
    final raw = await d.$2.read('x', userId: _u1);
    expect(raw == null || raw.isDeleted, isTrue);
    expect((await d.$1.read('y', userId: _u1))?.name, 'y-v1');
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
  });

  test('watch streams emit the post-sync state', () async {
    final d = await s.device();
    await _seedSynced(d, ['w1']);
    await (await s.probe()).create(_make('w2', name: 'remote-born'));
    final w1 = (await s.remoteRow('w1'))!;
    await (await s.probe()).update(w1.copyWith(name: 'w1-remote-edit'));
    await s.bumpRemoteMeta();

    final all = expectLater(
      d.$1.watchAll(userId: _u1),
      emitsThrough(
        predicate<List<ConformanceEntity>>(
          (items) =>
              items.map((e) => e.id).toSet().containsAll({'w1', 'w2'}) &&
              items.any((e) => e.name == 'w1-remote-edit'),
          'contains the pulled rows',
        ),
      ),
    );
    final one = expectLater(
      d.$1.watchById('w1', userId: _u1),
      emitsThrough(
        predicate<ConformanceEntity?>((e) => e?.name == 'w1-remote-edit'),
      ),
    );

    await d.$1.synchronize(_u1);

    await all.timeout(const Duration(seconds: 5));
    await one.timeout(const Duration(seconds: 5));
  });
}

// Scenarios: sync.isolation (packages/datum/doc/SYNC_SCENARIOS.md)
void _isolationAndScaleTests(_Stack s) {
  test(
    'users are isolated end to end, across a mid-session user switch',
    () async {
      final (manager, local, net) = await s.device();
      final switches = <UserSwitchedEvent<ConformanceEntity>>[];
      final sub = manager.onUserSwitched.listen(switches.add);
      net.setOnline(false);
      await manager.push(item: _make('mine'), userId: _u1);
      await manager.push(item: _make('mine2'), userId: _u1);
      await manager.push(
        item: _make('theirs', userId: 'u2'),
        userId: 'u2',
      );

      net.setOnline(true);
      final u2Result = await manager.synchronize('u2');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(u2Result.failedCount, 0);
      expect(await s.remoteIds(userId: 'u2'), {'theirs'});
      expect(await s.remoteIds(), isEmpty, reason: "u1's queue untouched");
      expect((await manager.getPendingOperations(_u1)).length, 2);
      expect(await manager.getPendingOperations('u2'), isEmpty);
      expect(switches, isNotEmpty);
      expect(switches.last.newUserId, 'u2');

      await manager.synchronize(_u1);
      expect(await s.remoteIds(), {'mine', 'mine2'});
      expect(await s.remoteIds(userId: 'u2'), {'theirs'});
      expect((await local.readAll(userId: _u1)).map((e) => e.id).toSet(), {
        'mine',
        'mine2',
      });
      expect((await local.readAll(userId: 'u2')).map((e) => e.id), ['theirs']);
      expect(await manager.getParkedOperations('u2'), isEmpty);
    },
  );

  test("one user's parked op never blocks another user's sync", () async {
    final (manager, _, _) = await s.device();
    await manager.push(
      item: _make('a', name: 'a-v1'),
      userId: _u1,
    );
    await manager.synchronize(_u1);
    final a = (await manager.read('a', userId: _u1))!;
    await manager.push(
      item: a.copyWith(name: 'a-v2'),
      userId: _u1,
    );
    s.failEntityWrites!('a', status: 403);
    await _syncCatching(manager);
    expect(await manager.getParkedOperations(_u1), hasLength(1));

    await manager.push(
      item: _make('b', userId: 'u2'),
      userId: 'u2',
    );
    final result = await manager.synchronize('u2');

    expect(result.failedCount, 0);
    expect(await s.remoteIds(userId: 'u2'), {'b'});
    expect(await manager.getParkedOperations('u2'), isEmpty);
    expect(await manager.getParkedOperations(_u1), hasLength(1));
  }, skip: s.noFaults);

  test(
    'a 2000-op queue drains completely with per-entity order kept',
    () async {
      const n = 1000;
      final d = await s.device();
      d.$3.setOnline(false);
      for (var i = 0; i < n; i++) {
        await d.$1.push(
          item: _make('q$i', name: 'v1', value: i),
          userId: _u1,
        );
      }
      for (var i = 0; i < n; i++) {
        await _edit(d, 'q$i', name: 'v2', value: i * 2);
      }
      expect((await d.$1.getPendingOperations(_u1)).length, 2 * n);
      d.$3.setOnline(true);

      final result = await d.$1.synchronize(_u1);

      expect(result.failedCount, 0);
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
      final rows = {
        for (final e in await (await s.probe()).readAll(userId: _u1)) e.id: e,
      };
      expect(rows.length, n);
      for (var i = 0; i < n; i++) {
        final row = rows['q$i']!;
        expect((row.name, row.value, row.version), ('v2', i * 2, 2));
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a sync requested while one is in flight never double-pushes', () async {
    final d = await s.device();
    for (var i = 0; i < 20; i++) {
      await d.$1.push(
        item: _make('c$i', value: i),
        userId: _u1,
      );
    }

    final results = await Future.wait([
      d.$1.synchronize(_u1),
      d.$1.synchronize(_u1),
      d.$1.synchronize(_u1),
    ]);

    expect(results.map((r) => r.failedCount), everyElement(0));
    expect(
      results.fold<int>(0, (sum, r) => sum + r.syncedCount),
      20,
      reason: 'each op pushed exactly once across the overlapping calls',
    );
    expect(await d.$1.getPendingOperations(_u1), isEmpty);
    expect((await s.remoteIds()).length, 20);
  });
}

// Scenarios: sync.pull (packages/datum/doc/SYNC_SCENARIOS.md)
void _pullTests(_Stack s) {
  test('an idle sync never hides a remote change: incremental remotes are '
      'asked every time, others skip only while the metadata beacon matches', () async {
    final d = await s.device();
    await _seedSynced(d, ['x']);
    final probe = await s.probe();
    final incremental = probe is DeltaSyncCapable<ConformanceEntity> || probe is CursorSyncCapable<ConformanceEntity>;
    Future<String?> local() async => (await d.$1.read('x', userId: _u1))?.name;

    final idle = await d.$1.synchronize(_u1);
    expect(idle.wasSkipped, !incremental, reason: 'only a remote without incremental pulls relies on the beacon');
    expect(idle.failedCount, 0);

    await _edit(d, 'x', name: 'local-change');
    final pushed = await d.$1.synchronize(_u1);
    expect(pushed.wasSkipped, isFalse, reason: 'pending ops defeat the skip');
    expect((await s.remoteRow('x'))?.name, 'local-change');

    final x = (await s.remoteRow('x'))!;
    await probe.update(x.copyWith(name: 'remote-change'));
    await s.bumpRemoteMeta();
    await d.$1.synchronize(_u1);
    expect(await local(), 'remote-change', reason: 'a changed remote beacon defeats the skip');

    // A silent backend write: another writer, or a client that was killed
    // before it wrote the metadata beacon.
    final y = (await s.remoteRow('x'))!;
    await probe.update(y.copyWith(name: 'silent-change'));
    await d.$1.synchronize(_u1);
    if (incremental) {
      expect(await local(), 'silent-change', reason: 'an incremental pull asks the server, not the beacon');
    } else {
      expect(await local(), 'remote-change', reason: 'a beacon-only remote cannot see it (documented limit)...');
      await d.$1.synchronize(_u1, options: const DatumSyncOptions(forceFullSync: true));
      expect(await local(), 'silent-change', reason: '...until a forced sync');
    }
  });

  test(
    'incremental pulls (when capable) still deliver later remote changes',
    () async {
      final (manager, local, _) = await s.device();
      await manager.push(
        item: _make('i1', name: 'first'),
        userId: _u1,
      );
      await manager.synchronize(_u1);

      final current = (await local.read('i1', userId: _u1))!;
      await (await s.probe()).update(current.copyWith(name: 'second-wave'));
      await s.bumpRemoteMeta();

      await manager.synchronize(_u1);

      expect((await local.read('i1', userId: _u1))?.name, 'second-wave');
    },
  );

  test(
    'incremental pulls do not miss rows stamped exactly at the watermark',
    () async {
      final d = await s.device();
      final stamp = DateTime.now().subtract(const Duration(minutes: 1));
      final remote = await s.probe();
      await remote.create(_make('w1', name: 'first', modifiedAt: stamp));
      await s.bumpRemoteMeta();
      await d.$1.synchronize(_u1);
      expect((await d.$2.read('w1', userId: _u1))?.name, 'first');

      // Same timestamp as the watermark the previous pull derived.
      await remote.create(_make('w2', name: 'same-instant', modifiedAt: stamp));
      await remote.update(
        (await remote.read(
          'w1',
          userId: _u1,
        ))!.copyWith(name: 'first-edited', modifiedAt: stamp),
      );
      await s.bumpRemoteMeta();
      await d.$1.synchronize(_u1);

      expect((await d.$2.read('w2', userId: _u1))?.name, 'same-instant');
      expect((await d.$2.read('w1', userId: _u1))?.name, 'first-edited');
    },
  );

  test('incremental pulls deliver a late write from a writer whose clock '
      'is 10 min behind', () async {
    final d = await s.device();
    final remote = await s.probe();
    await remote.create(_make('fresh', name: 'fresh'));
    await s.bumpRemoteMeta();
    await d.$1.synchronize(_u1);

    await remote.create(
      _make(
        'late',
        name: 'from-slow-clock',
        modifiedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    );
    await s.bumpRemoteMeta();
    await d.$1.synchronize(_u1);

    expect((await d.$2.read('late', userId: _u1))?.name, 'from-slow-clock');
  });
}

// Scenarios: sync.scope (packages/datum/doc/SYNC_SCENARIOS.md)
void _scopeTests(_Stack s) {
  DatumSyncScope valued(int value) => DatumSyncScope(
    query: DatumQuery(filters: [Filter('value', FilterOperator.equals, value)]),
  );

  test('scoped syncs pull their own rows; a different scope is never skipped '
      'as "nothing changed", and rows outside the scope are left alone', () async {
    final remote = await s.probe();
    await remote.create(_make('a1', name: 'a1', value: 1));
    await remote.create(_make('a2', name: 'a2', value: 1));
    await remote.create(_make('b1', name: 'b1', value: 2));
    await s.bumpRemoteMeta();
    // The rows are older than any overlap: a pull that starts from another
    // scope's position can no longer reach them by accident.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final device = await s.device(deltaSyncOverlap: const Duration(milliseconds: 1));
    final (manager, local, _) = device;
    Future<List<String>> localIds() async => [for (final e in await local.readAll(userId: _u1)) e.id]..sort();

    await manager.synchronize(_u1, scope: valued(1));
    expect(await localIds(), ['a1', 'a2']);

    // Nothing changed on the server, but this scope was never synced.
    final other = await manager.synchronize(_u1, scope: valued(2));
    expect(other.wasSkipped, isFalse);
    expect(await localIds(), ['a1', 'a2', 'b1'], reason: 'the first scope\'s rows stay');

    // Idle, same scope: nothing is written again.
    final writes = <DataChangeEvent<ConformanceEntity>>[];
    final sub = manager.onDataChange.listen(writes.add);
    addTearDown(sub.cancel);
    await manager.synchronize(_u1, scope: valued(1));
    await manager.synchronize(_u1, scope: valued(2));
    await Future<void>.delayed(Duration.zero);
    expect(writes, isEmpty);
    expect(await localIds(), ['a1', 'a2', 'b1']);

    // A change inside one scope arrives through that scope.
    final a1 = (await remote.read('a1', userId: _u1))!;
    await remote.update(_make('a1', name: 'a1-edited', value: 1, version: a1.version + 1));
    await remote.create(_make('c1', name: 'c1', value: 3));
    await s.bumpRemoteMeta();
    await manager.synchronize(_u1, scope: valued(1));
    expect((await local.read('a1', userId: _u1))?.name, 'a1-edited');
    expect(await localIds(), ['a1', 'a2', 'b1'], reason: 'c1 is in no synced scope');

    // A local edit uploads whatever scope the sync pulls.
    await _edit(device, 'b1', name: 'b1-local');
    await manager.synchronize(_u1, scope: valued(1));
    expect((await s.remoteRow('b1'))?.name, 'b1-local');
    expect(await manager.getPendingCount(_u1), 0);

    // An unscoped sync brings the rest.
    await manager.synchronize(_u1);
    expect(await localIds(), ['a1', 'a2', 'b1', 'c1']);
  });

  test('devices syncing different scopes do not hide each other\'s changes', () async {
    final all = await s.device();
    final onlyOnes = await s.device();
    await all.$1.push(item: _make('a1', name: 'a1', value: 1), userId: _u1);
    await all.$1.push(item: _make('b1', name: 'b1', value: 2), userId: _u1);
    await all.$1.synchronize(_u1);
    await onlyOnes.$1.synchronize(_u1, scope: valued(1));
    expect([for (final e in await onlyOnes.$2.readAll(userId: _u1)) e.id], ['a1']);

    // Each keeps syncing its own way; an edit by either reaches the other.
    for (var round = 1; round <= 3; round++) {
      await _edit(all, 'a1', name: 'from-all-$round');
      await all.$1.synchronize(_u1);
      await onlyOnes.$1.synchronize(_u1, scope: valued(1));
      expect((await onlyOnes.$2.read('a1', userId: _u1))?.name, 'from-all-$round');

      await _edit(onlyOnes, 'a1', name: 'from-scoped-$round');
      await onlyOnes.$1.synchronize(_u1, scope: valued(1));
      await all.$1.synchronize(_u1);
      expect((await all.$2.read('a1', userId: _u1))?.name, 'from-scoped-$round');
    }
    expect((await all.$2.read('b1', userId: _u1))?.name, 'b1', reason: 'untouched by the scoped device');
    expect(await onlyOnes.$2.read('b1', userId: _u1), isNull);
  });

  test('pull positions are remembered for a bounded number of scopes; a '
      'forgotten scope is simply read in full again', () async {
    const scopes = 24;
    final remote = await s.probe();
    for (var value = 0; value < scopes; value++) {
      await remote.create(_make('r$value', name: 'r$value', value: value));
    }
    await s.bumpRemoteMeta();
    final (manager, local, _) = await s.device();
    for (var value = 0; value < scopes; value++) {
      await manager.synchronize(_u1, scope: valued(value));
    }
    expect(await local.readAll(userId: _u1), hasLength(scopes));
    final tracked = (await local.getSyncMetadata(_u1))?.customMetadata?[DatumSyncEngine.syncScopesKey] as Map?;
    expect(tracked, isNotNull);
    expect(tracked!.length, lessThan(scopes), reason: 'a scope whose filter changes every sync must not grow the metadata forever');

    // The first scope's position is long gone; a change in it still arrives.
    await remote.update(_make('r0', name: 'r0-edited', value: 0, version: 2));
    await s.bumpRemoteMeta();
    await manager.synchronize(_u1, scope: valued(0));
    expect((await local.read('r0', userId: _u1))?.name, 'r0-edited');
    expect((await s.remoteRow('r0'))?.name, 'r0-edited');
    expect(await manager.getPendingCount(_u1), 0);
  });
}

// Scenarios: sync.queue.hygiene (packages/datum/doc/SYNC_SCENARIOS.md)
void _queueHygieneTests(_Stack s) {
  test(
    'an entity held back by retryable failures does not grow the queue',
    () async {
      final d = await s.device();
      await _seedSynced(d, ['x']);
      await _edit(d, 'x', name: 'x-v2');
      s.failEntityWrites!('x', status: 503, times: 100);

      for (var i = 0; i < 3; i++) {
        await d.$1.synchronize(_u1);
      }

      expect(
        await d.$1.getPendingOperations(_u1),
        hasLength(1),
        reason:
            'pulls must not enqueue resolution pushes for an entity '
            'whose own local op is still pending',
      );
      s.failEntityWrites!('x', status: 503, times: 0);
      expect((await d.$1.synchronize(_u1)).failedCount, 0);
      expect((await s.remoteRow('x'))?.name, 'x-v2');
    },
    skip: s.noFaults,
  );

  test(
    "a held-back entity's later delete must not overtake it inside a batch",
    () async {
      final d = await s.device(deleteBehavior: DeleteBehavior.hardDelete);
      await _seedSynced(d, ['x', 'y']);
      await _edit(d, 'x', name: 'x-v2');
      await d.$1.delete(id: 'x', userId: _u1);
      await d.$1.delete(id: 'y', userId: _u1);
      s.failEntityWrites!('x', status: 503);

      await d.$1.synchronize(_u1);
      await d.$1.synchronize(_u1);
      await d.$1.synchronize(_u1);

      expect(
        await s.remoteIds(),
        isEmpty,
        reason:
            'x must stay deleted, not be resurrected by its older '
            'update replaying after the delete',
      );
      expect(await d.$1.read('x', userId: _u1), isNull);
      expect(await d.$1.getPendingOperations(_u1), isEmpty);
    },
    skip: s.noFaults,
  );

  test('a still-pending local hard delete is not undone by the pull', () async {
    final d = await s.device(deleteBehavior: DeleteBehavior.hardDelete);
    await _seedSynced(d, ['x', 'y']);
    await d.$1.delete(id: 'x', userId: _u1);
    s.failEntityWrites!('x', status: 503);

    await d.$1.synchronize(_u1);

    expect(
      await d.$1.read('x', userId: _u1),
      isNull,
      reason: 'the remote copy predates the queued delete',
    );
    expect((await d.$1.getPendingOperations(_u1)).single.entityId, 'x');
    await d.$1.synchronize(_u1);
    expect(await s.remoteIds(), {'y'});
    expect(await d.$1.read('x', userId: _u1), isNull);
  }, skip: s.noFaults);
}
