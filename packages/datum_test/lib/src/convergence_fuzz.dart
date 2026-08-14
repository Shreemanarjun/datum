import 'dart:math' as math;

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';
import 'http_remote_adapter.dart';
import 'local_sync_server.dart';
import 'sync_stack_conformance.dart';

/// The visible state of one entity as compared across devices and the server.
typedef _VisibleRow = ({String name, int value, bool isDeleted});

/// Runs the Datum **convergence fuzz suite**: seeded random multi-device
/// workloads (creates, updates, soft deletes, partial syncs in random order)
/// driven against a real [LocalSyncServer] over HTTP, followed by a
/// quiescence phase after which EVERY device's visible state must be
/// identical and consistent with the server.
///
/// This is a property test for the engine's convergence guarantee: no matter
/// how edits interleave and no matter which subset of devices syncs when,
/// once every device has fully synchronized the fleet must agree.
///
/// The scenario is fully deterministic per seed: entity ids come from a
/// scenario-wide counter and `modifiedAt` stamps advance a logical clock, so
/// last-write-wins ordering is total and reproducible. The whole scenario is
/// run for three derived seeds (each as its own test, named with the seed);
/// every failure message embeds the seed and round for reproduction.
///
/// ```dart
/// runConvergenceFuzzTests(
///   name: 'InMemory + HTTP',
///   createLocal: () async =>
///       InMemoryLocalAdapter(fromMap: ConformanceEntity.fromMap)..initialize(),
/// );
/// ```
void runConvergenceFuzzTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  int devices = 3,
  int rounds = 25,
  int seed = 42,
  int opsPerRound = 4,
  bool useCursorFeed = false,
}) {
  group('$name convergence fuzz', () {
    for (final scenarioSeed in [seed, seed + 1_000_003, seed + 2_000_003]) {
      test(
        '$devices devices converge after $rounds rounds of random ops (seed $scenarioSeed)',
        () async {
          final scenario = _ConvergenceScenario(
            createLocal: createLocal,
            devices: devices,
            rounds: rounds,
            opsPerRound: opsPerRound,
            seed: scenarioSeed,
            useCursorFeed: useCursorFeed,
          );
          await scenario.run();
        },
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  });
}

/// One simulated device: a fresh local store synced through a shared backend.
class _Device {
  _Device({
    required this.index,
    required this.manager,
    required this.local,
    required this.connectivity,
  });

  final int index;
  final DatumManager<ConformanceEntity> manager;
  final LocalAdapter<ConformanceEntity> local;
  final TestConnectivityChecker connectivity;
}

class _ConvergenceScenario {
  _ConvergenceScenario({
    required this.createLocal,
    required this.devices,
    required this.rounds,
    required this.opsPerRound,
    required this.seed,
    required this.useCursorFeed,
  }) : random = math.Random(seed);

  /// Pull mode: cursor feed (incremental) vs full pulls. See [_bootDevice].
  final bool useCursorFeed;

  static const String userId = 'fuzz-user';

  /// Extra full sync passes allowed for the fleet to reach a fixpoint.
  static const int maxQuiescencePasses = 10;

  final Future<LocalAdapter<ConformanceEntity>> Function() createLocal;
  final int devices;
  final int rounds;
  final int opsPerRound;
  final int seed;
  final math.Random random;

  /// Logical clock: every op gets a strictly increasing `modifiedAt`, so the
  /// last-write-wins order over (version, modifiedAt) is total and the fuzz
  /// outcome is a pure function of the seed.
  late final DateTime _clockBase = DateTime.now().toUtc();
  int _clockTicks = 0;
  DateTime _nextStamp() =>
      _clockBase.add(Duration(milliseconds: ++_clockTicks));

  int _entityCounter = 0;
  int totalOps = 0;

  String get _context =>
      'seed=$seed devices=$devices rounds=$rounds opsPerRound=$opsPerRound';

  Future<void> run() async {
    final server = LocalSyncServer();
    await server.start();
    final fleet = <_Device>[];
    try {
      for (var i = 0; i < devices; i++) {
        fleet.add(await _bootDevice(i, server));
      }

      for (var round = 1; round <= rounds; round++) {
        for (final device in fleet) {
          for (var op = 0; op < opsPerRound; op++) {
            await _randomOp(device, round);
          }
          await _assertNoDuplicates(device, 'round $round');
        }
        // A RANDOM SUBSET of the fleet syncs, in RANDOM order — everyone else
        // keeps diverging.
        final order = List<_Device>.of(fleet)..shuffle(random);
        for (final device in order) {
          if (random.nextBool()) {
            final result = await device.manager.synchronize(userId);
            expect(
              result.failedCount,
              0,
              reason:
                  'sync on device ${device.index} reported failures at round $round ($_context)',
            );
          }
        }
      }

      final passes = await _quiesce(fleet, server);
      await _assertConverged(fleet, server);

      // ignore: avoid_print
      print(
        '[convergence-fuzz] $_context: '
        '$totalOps ops, $_entityCounter entities, '
        'converged after $passes quiescence pass(es)',
      );
    } finally {
      for (final device in fleet) {
        await device.manager.dispose();
        await device.connectivity.dispose();
      }
      await server.stop();
    }
  }

  Future<_Device> _bootDevice(int index, LocalSyncServer server) async {
    final local = await createLocal();
    // Adversarial op orderings put STALE-timestamped rows on the server (a
    // queued old edit pushed after a newer one), which a timestamp-delta
    // pull can never re-deliver — exactly the documented reason
    // DeltaSyncCapable requires a server received-at column. The fuzz
    // therefore runs either with full pulls (enableDeltaSync: false —
    // maximal convergence checking) or over the cursor feed, whose
    // server-side sequence numbers DO deliver late stale writes.
    final remote = useCursorFeed
        ? CursorHttpRemoteAdapter<ConformanceEntity>(
            baseUri: server.baseUri,
            fromMap: ConformanceEntity.fromMap,
          )
        : HttpRemoteAdapter<ConformanceEntity>(
            baseUri: server.baseUri,
            fromMap: ConformanceEntity.fromMap,
          );
    final connectivity = TestConnectivityChecker();
    final manager = DatumManager<ConformanceEntity>(
      localAdapter: local,
      remoteAdapter: remote,
      connectivity: connectivity,
      datumConfig: DatumConfig<ConformanceEntity>(
        enableLogging: false,
        enableDeltaSync: useCursorFeed,
        deleteBehavior: DeleteBehavior.softDelete,
        defaultConflictResolver: LastWriteWinsResolver<ConformanceEntity>(),
      ),
    );
    await manager.initialize();
    return _Device(
      index: index,
      manager: manager,
      local: local,
      connectivity: connectivity,
    );
  }

  /// Performs one random operation on [device]: create a new entity, update a
  /// random live one from ITS OWN local store, or soft-delete a random live
  /// one. Soft deletes go through `push(copyWith(isDeleted: true))` so their
  /// `modifiedAt` also comes from the logical clock and stays deterministic.
  Future<void> _randomOp(_Device device, int round) async {
    final all = await device.local.readAll(userId: userId);
    final alive = all.where((e) => !e.isDeleted).toList();
    final roll = random.nextInt(10);
    totalOps++;

    if (roll < 4 || alive.isEmpty) {
      // Create (40%, or forced when the device sees nothing alive).
      final id = 'e${++_entityCounter}';
      await device.manager.push(
        item: ConformanceEntity.make(
          id,
          userId: userId,
          name: 'created-d${device.index}-r$round',
          value: random.nextInt(1000),
          modifiedAt: _nextStamp(),
        ),
        userId: userId,
      );
    } else if (roll < 8) {
      // Update (40%).
      final target = alive[random.nextInt(alive.length)];
      await device.manager.push(
        item: target.copyWith(
          name: 'updated-d${device.index}-r$round-t$_clockTicks',
          value: random.nextInt(1000),
          modifiedAt: _nextStamp(),
        ),
        userId: userId,
      );
    } else {
      // Soft delete (20%).
      final target = alive[random.nextInt(alive.length)];
      await device.manager.push(
        item: target.copyWith(isDeleted: true, modifiedAt: _nextStamp()),
        userId: userId,
      );
    }
  }

  /// Syncs every device twice per pass until an extra full pass changes
  /// nothing (bounded by [maxQuiescencePasses]). Returns the pass count.
  Future<int> _quiesce(List<_Device> fleet, LocalSyncServer server) async {
    String? previous;
    for (var pass = 1; pass <= maxQuiescencePasses; pass++) {
      for (final device in fleet) {
        for (var i = 0; i < 2; i++) {
          final result = await device.manager.synchronize(userId);
          expect(
            result.failedCount,
            0,
            reason:
                'quiescence sync failed on device ${device.index}, pass $pass ($_context)',
          );
        }
      }
      final fingerprint = await _fleetFingerprint(fleet, server);
      if (fingerprint == previous) return pass;
      previous = fingerprint;
    }
    fail(
      'Fleet did not reach quiescence within $maxQuiescencePasses full sync passes '
      'after $rounds rounds — possible sync live-lock ($_context, $totalOps ops)',
    );
  }

  Future<Map<String, _VisibleRow>> _deviceState(_Device device) async {
    final all = await device.local.readAll(userId: userId);
    await _assertNoDuplicates(device, 'final state');
    return {
      for (final e in all)
        e.id: (name: e.name, value: e.value, isDeleted: e.isDeleted),
    };
  }

  Map<String, _VisibleRow> _serverState(LocalSyncServer server) {
    final rows =
        server.storage[userId] ?? const <String, Map<String, dynamic>>{};
    return rows.map(
      (id, raw) => MapEntry(id, (
        name: raw['name'] as String? ?? '',
        value: (raw['value'] as num?)?.toInt() ?? 0,
        isDeleted: raw['isDeleted'] as bool? ?? false,
      )),
    );
  }

  Future<void> _assertNoDuplicates(_Device device, String when) async {
    final ids = (await device.local.readAll(
      userId: userId,
    )).map((e) => e.id).toList();
    expect(
      ids.toSet().length,
      ids.length,
      reason:
          'device ${device.index} holds duplicated entity ids at $when ($_context)',
    );
  }

  String _render(Map<String, _VisibleRow> state) {
    final keys = state.keys.toList()..sort();
    return keys.map((k) => '$k=>${state[k]}').join('; ');
  }

  Future<String> _fleetFingerprint(
    List<_Device> fleet,
    LocalSyncServer server,
  ) async {
    final parts = <String>[];
    for (final device in fleet) {
      parts.add(
        'd${device.index}:${_render(await _deviceState(device))}'
        ':pending=${(await device.manager.getPendingOperations(userId)).length}',
      );
    }
    parts.add('server:${_render(_serverState(server))}');
    return parts.join('\n');
  }

  Future<void> _assertConverged(
    List<_Device> fleet,
    LocalSyncServer server,
  ) async {
    final deviceStates = <int, Map<String, _VisibleRow>>{
      for (final device in fleet) device.index: await _deviceState(device),
    };
    final serverState = _serverState(server);

    final allIds = <String>{
      ...serverState.keys,
      for (final s in deviceStates.values) ...s.keys,
    }.toList()..sort();
    final diverged = <String>[];
    for (final id in allIds) {
      final observations = <_VisibleRow?>{
        ...deviceStates.values.map((s) => s[id]),
        serverState[id],
      };
      if (observations.length > 1) {
        diverged.add(
          '  $id: '
          '${deviceStates.entries.map((e) => 'd${e.key}=${e.value[id] ?? 'MISSING'}').join(' ')} '
          'server=${serverState[id] ?? 'MISSING'}',
        );
      }
    }
    if (diverged.isNotEmpty) {
      fail(
        'Fleet failed to converge after quiescence ($_context, $totalOps ops). '
        '${diverged.length} diverged entities:\n${diverged.join('\n')}',
      );
    }
    for (final device in fleet) {
      expect(
        await device.manager.getPendingOperations(userId),
        isEmpty,
        reason:
            'device ${device.index} still has queued operations after quiescence ($_context)',
      );
    }
  }
}
