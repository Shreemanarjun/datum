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
/// [status]: 5xx = retryable, 401/403/4xx = non-retryable.
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
    );
    setUp(() async => resetBackend?.call());
    tearDown(s.dispose);

    _roundTripTests(s);
    _directionAndOrderingTests(s);
    _failureTests(s);
    _parkingTests(s);
    _crashAndReplayTests(s);
    _conflictTests(s);
    _deleteAndWatchTests(s);
    _isolationAndScaleTests(s);
    _pullTests(s);
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
  });

  final Future<LocalAdapter<ConformanceEntity>> Function() createLocal;
  final Future<RemoteAdapter<ConformanceEntity>> Function() createRemote;
  final Future<void> Function(LocalAdapter<ConformanceEntity>)? destroyLocal;
  final Future<void> Function(RemoteAdapter<ConformanceEntity>)? destroyRemote;
  final ReopenLocal? reopenLocal;
  final FailEntityWrites? failEntityWrites;
  final bool timestampPulls;

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
Future<Object?> _syncCatching(DatumManager<ConformanceEntity> m) async {
  try {
    await m.synchronize(_u1);
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
    skip: s.noFaults,
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

void _parkingTests(_Stack s) {
  test('non-retryable 401/403 parks the op: kept, skipped with its successors, '
      'others sync, retry re-arms, discard drops', () async {
    final d = await s.device();
    await _seedSynced(d, ['p', 'q', 'r']);
    await _edit(d, 'p', name: 'p-v2');
    await _edit(d, 'q', name: 'q-v2');
    s.failEntityWrites!('p', status: 401);

    expect(await _syncCatching(d.$1), isNotNull, reason: 'parking surfaces');

    var parked = await d.$1.getParkedOperations(_u1);
    expect(parked.map((op) => op.entityId), ['p']);
    expect(parked.single.parkedError, contains('401'));
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
    s.failEntityWrites!('p', status: 401);
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
    s.failEntityWrites!('a', status: 401);
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

void _pullTests(_Stack s) {
  test('the metadata skip path only skips when nothing differs', () async {
    final d = await s.device();
    await _seedSynced(d, ['x']);

    final idle = await d.$1.synchronize(_u1);
    expect(idle.wasSkipped, isTrue, reason: 'matching beacons skip');

    await _edit(d, 'x', name: 'local-change');
    final pushed = await d.$1.synchronize(_u1);
    expect(pushed.wasSkipped, isFalse, reason: 'pending ops defeat the skip');
    expect((await s.remoteRow('x'))?.name, 'local-change');

    final x = (await s.remoteRow('x'))!;
    await (await s.probe()).update(x.copyWith(name: 'remote-change'));
    await s.bumpRemoteMeta();
    await d.$1.synchronize(_u1);
    expect(
      (await d.$1.read('x', userId: _u1))?.name,
      'remote-change',
      reason: 'a changed remote beacon defeats the skip',
    );

    // A silent backend write (no beacon bump) is only seen by a forced sync.
    final y = (await s.remoteRow('x'))!;
    await (await s.probe()).update(y.copyWith(name: 'silent-change'));
    await d.$1.synchronize(
      _u1,
      options: const DatumSyncOptions(forceFullSync: true),
    );
    expect((await d.$1.read('x', userId: _u1))?.name, 'silent-change');
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
