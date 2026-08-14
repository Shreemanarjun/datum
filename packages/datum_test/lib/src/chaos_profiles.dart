import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';
import 'http_remote_adapter.dart';
import 'local_sync_server.dart';
import 'sync_stack_conformance.dart';

/// A named bundle of [LocalSyncServer] fault knobs modelling one real-world
/// degraded network, applied and removed as a unit.
///
/// [apply] turns the profile's knobs on; [clear] resets EVERY chaos knob on
/// the server back to its default (not just this profile's), so a cleared
/// server is always a healthy server.
///
/// The stock profiles are tuned so that individual requests fail often enough
/// to exercise retry paths, but rarely enough that sync cycles can still make
/// progress and eventually converge once the profile is cleared.
class ChaosProfile {
  const ChaosProfile({
    required this.name,
    this.latency,
    this.jitter,
    this.failEveryNth,
    this.failStatusCode,
    this.dropEveryNth,
    this.corruptEveryNth,
    this.offline = false,
  });

  /// Human-readable profile name, used in test descriptions.
  final String name;

  /// Fixed latency added to every response while active.
  final Duration? latency;

  /// Random extra latency (up to this much) per request while active.
  final Duration? jitter;

  /// Fail every Nth request with [failStatusCode].
  final int? failEveryNth;

  /// Status code for [failEveryNth] failures (server default 500 when null).
  final int? failStatusCode;

  /// Sever every Nth request's socket without responding.
  final int? dropEveryNth;

  /// Corrupt every Nth response body (200 status, non-JSON garbage).
  final int? corruptEveryNth;

  /// Respond 503 to everything while active — a hard offline window that
  /// lasts until [clear].
  final bool offline;

  /// A degraded cellular link: high fixed latency, heavy jitter, and an
  /// HTTP 500 on every 5th request.
  static const flaky3G = ChaosProfile(
    name: 'flaky3G',
    latency: Duration(milliseconds: 120),
    jitter: Duration(milliseconds: 200),
    failEveryNth: 5,
  );

  /// A connection that keeps dying mid-flight: every 4th request's socket is
  /// severed without any HTTP response.
  static const unstableSocket = ChaosProfile(
    name: 'unstableSocket',
    dropEveryNth: 4,
  );

  /// A mangling middlebox: every 5th response body is replaced with non-JSON
  /// garbage under a 200 status.
  static const proxyCorruption = ChaosProfile(
    name: 'proxyCorruption',
    corruptEveryNth: 5,
  );

  /// A captive portal: every 2nd request is answered with a 302 redirect
  /// instead of the API response.
  static const captivePortal = ChaosProfile(
    name: 'captivePortal',
    failEveryNth: 2,
    failStatusCode: 302,
  );

  /// A hard offline window: every request 503s until the profile is cleared,
  /// after which connectivity returns in full.
  static const offlineWindows = ChaosProfile(
    name: 'offlineWindows',
    offline: true,
  );

  /// Every stock profile, in the order the conformance suite runs them.
  static const List<ChaosProfile> defaultProfiles = [
    flaky3G,
    unstableSocket,
    proxyCorruption,
    captivePortal,
    offlineWindows,
  ];

  /// Whether this profile injects hard faults (as opposed to latency only).
  bool get injectsFaults =>
      offline ||
      failEveryNth != null ||
      dropEveryNth != null ||
      corruptEveryNth != null;

  /// Turns this profile's knobs on.
  void apply(LocalSyncServer server) {
    if (latency != null) server.latency = latency!;
    server.jitter = jitter;
    server.failEveryNth = failEveryNth;
    if (failStatusCode != null) server.failStatusCode = failStatusCode!;
    server.dropEveryNth = dropEveryNth;
    server.corruptEveryNth = corruptEveryNth;
    server.offline = offline;
  }

  /// Resets every chaos knob on [server] to its healthy default.
  void clear(LocalSyncServer server) {
    server
      ..latency = Duration.zero
      ..jitter = null
      ..failEveryNth = null
      ..dropEveryNth = null
      ..corruptEveryNth = null
      ..failStatusCode = 500
      ..offline = false
      ..dropConnections = false
      ..remainingFailures = 0
      ..failMatcher = null
      ..corruptNextResponses = 0
      ..corruptMatcher = null;
  }

  /// How many faults this profile injected while the server's request count
  /// went from [requestsBefore] to [requestsAfter].
  ///
  /// The server applies its periodic knobs by `requestCounter % N == 0`, and
  /// `requestLog.length` tracks that counter exactly, so for profiles with a
  /// single fault knob (all stock profiles) this count is exact. When several
  /// periodic knobs are combined the counts can overlap on one request, making
  /// this an upper bound.
  int estimatedFaults(int requestsBefore, int requestsAfter) {
    if (offline) return requestsAfter - requestsBefore;
    int periodic(int? n) =>
        n == null ? 0 : (requestsAfter ~/ n) - (requestsBefore ~/ n);
    return periodic(dropEveryNth) +
        periodic(failEveryNth) +
        periodic(corruptEveryNth);
  }
}

/// Retry policy for chaos runs: every failure is retryable, forever. Chaos
/// certifies EVENTUAL delivery, so an injected fault streak must never cause
/// the engine to dead-letter (permanently drop) a queued operation — with the
/// default policy a non-retryable status (e.g. a captive portal's 302) or an
/// exhausted retry budget silently discards the op, which chaos would then
/// report as a lost entity.
Future<bool> _alwaysRetry(DatumException error) async => true;

/// Runs the Datum **chaos conformance suite**: for each [ChaosProfile], a
/// fresh [LocalSyncServer] + [DatumManager] stack is seeded with local pending
/// operations and remote rows, several sync cycles run UNDER the fault profile
/// (cycles are allowed — expected — to throw), then the profile is cleared and
/// clean cycles run until the stack converges. Asserts:
///
/// - the profile actually fired at least one fault (from the request log);
/// - eventual convergence: local content == server content, id for id;
/// - the pending queue fully drained;
/// - no entity was lost or duplicated on either side.
///
/// The suite configures the manager with `detectRemoteDeletions: true` (so
/// every pull is a full pull and locally-alive entities missing remotely are
/// re-pushed — this is what heals a corrupted 200 response the server never
/// actually applied) and an always-retry error recovery strategy (see
/// [_alwaysRetry]).
///
/// [createLocal] returns a fresh, initialized local adapter per profile.
/// [destroyLocal] is optional extra teardown after the manager has disposed
/// the adapter. [profiles] defaults to [ChaosProfile.defaultProfiles].
/// [onFaultsObserved] receives the per-profile injected-fault count, for
/// logging or reporting.
void runChaosConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroyLocal,
  List<ChaosProfile>? profiles,
  void Function(String profileName, int faultsObserved)? onFaultsObserved,
}) {
  group('$name chaos conformance', () {
    for (final profile in profiles ?? ChaosProfile.defaultProfiles) {
      test(
        'converges after ${profile.name}',
        () async {
          final server = LocalSyncServer();
          await server.start();
          final local = await createLocal();
          final connectivity = TestConnectivityChecker();
          final manager = DatumManager<ConformanceEntity>(
            localAdapter: local,
            remoteAdapter: HttpRemoteAdapter<ConformanceEntity>(
              baseUri: server.baseUri,
              fromMap: ConformanceEntity.fromMap,
            ),
            connectivity: connectivity,
            datumConfig: DatumConfig<ConformanceEntity>(
              enableLogging: false,
              deleteBehavior: DeleteBehavior.softDelete,
              detectRemoteDeletions: true,
              errorRecoveryStrategy: const DatumErrorRecoveryStrategy(
                shouldRetry: _alwaysRetry,
                maxRetries: 1 << 30,
              ),
            ),
          );

          try {
            await manager.initialize();

            // Seed: rows born on the server, and local saves queued as ops.
            const remoteIds = ['remote-0', 'remote-1', 'remote-2'];
            for (var i = 0; i < remoteIds.length; i++) {
              server.seed(
                'u1',
                ConformanceEntity.make(
                  remoteIds[i],
                  userId: 'u1',
                  name: 'remote-$i',
                  value: 100 + i,
                ).toDatumMap(),
              );
            }
            server.pokeMetadata('u1');
            const localIds = [
              'local-0',
              'local-1',
              'local-2',
              'local-3',
              'local-4',
            ];
            for (var i = 0; i < localIds.length; i++) {
              await manager.push(
                item: ConformanceEntity.make(
                  localIds[i],
                  userId: 'u1',
                  name: 'local-$i',
                  value: i,
                ),
                userId: 'u1',
              );
            }

            // Chaos phase: sync under the profile; some cycles WILL throw.
            final requestsBefore = server.requestLog.length;
            profile.apply(server);
            var failedCycles = 0;
            for (var cycle = 0; cycle < 4; cycle++) {
              try {
                await manager.synchronize('u1');
              } on Object {
                failedCycles++;
              }
            }
            // If the workload was too small for the Nth-request knob to land,
            // keep cycling (bounded) until at least one fault has fired.
            var extraCycles = 0;
            while (profile.injectsFaults &&
                profile.estimatedFaults(
                      requestsBefore,
                      server.requestLog.length,
                    ) ==
                    0 &&
                extraCycles++ < 10) {
              server.pokeMetadata('u1');
              try {
                await manager.synchronize('u1');
              } on Object {
                failedCycles++;
              }
            }
            profile.clear(server);
            final faults = profile.estimatedFaults(
              requestsBefore,
              server.requestLog.length,
            );
            onFaultsObserved?.call(profile.name, faults);
            expect(
              faults,
              greaterThan(0),
              reason:
                  '${profile.name} must inject at least one fault '
                  '(requests before=$requestsBefore, after=${server.requestLog.length}, '
                  'failed cycles=$failedCycles)',
            );

            // Recovery phase: clean cycles until the stack converges.
            final expectedIds = {...remoteIds, ...localIds};
            server.pokeMetadata('u1');
            var converged = false;
            for (var attempt = 0; attempt < 10 && !converged; attempt++) {
              await manager.synchronize(
                'u1',
                options: const DatumSyncOptions(forceFullSync: true),
              );
              final pending = await manager.getPendingOperations('u1');
              final localRows = await local.readAll(userId: 'u1');
              final serverRows =
                  server.storage['u1'] ??
                  const <String, Map<String, dynamic>>{};
              converged =
                  pending.isEmpty &&
                  localRows.map((e) => e.id).toSet().containsAll(expectedIds) &&
                  serverRows.keys.toSet().containsAll(expectedIds);
            }

            // Convergence: same ids on both sides, nothing lost.
            final localRows = (await local.readAll(
              userId: 'u1',
            )).where((e) => !e.isDeleted).toList();
            final localIdSet = localRows.map((e) => e.id).toSet();
            final serverRows =
                server.storage['u1'] ?? const <String, Map<String, dynamic>>{};
            expect(
              localIdSet,
              expectedIds,
              reason: 'local converged with no lost entities (${profile.name})',
            );
            expect(
              serverRows.keys.toSet(),
              expectedIds,
              reason:
                  'server converged with no lost entities (${profile.name})',
            );

            // No duplicates: every id appears exactly once locally (the server
            // map is keyed by id and cannot duplicate).
            expect(
              localRows.length,
              localIdSet.length,
              reason: 'no duplicated local rows (${profile.name})',
            );

            // Content converged, id for id.
            for (final row in localRows) {
              final remoteRaw = serverRows[row.id]!;
              expect(
                remoteRaw['name'],
                row.name,
                reason: 'name converged for ${row.id} (${profile.name})',
              );
              expect(
                remoteRaw['value'],
                row.value,
                reason: 'value converged for ${row.id} (${profile.name})',
              );
            }

            // Queue drained.
            expect(
              await manager.getPendingOperations('u1'),
              isEmpty,
              reason: 'pending queue drained after ${profile.name}',
            );
          } finally {
            await manager.dispose();
            await destroyLocal?.call(local);
            await connectivity.dispose();
            await server.stop();
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });
}
