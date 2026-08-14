// ===========================================================================
// Incremental pull (delta sync) over a REAL local HTTP server: the engine
// asks a DeltaSyncCapable remote only for rows modified since the last sync
// watermark, verified on the actual wire via the server's request log.
// ===========================================================================

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../harness/http_remote_adapter.dart';
import '../harness/local_sync_server.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

MockConnectivityChecker _connected() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}

TestEntity _entity(String id, {String name = 'n', DateTime? modifiedAt}) => TestEntity(
      id: id,
      userId: 'u1',
      name: name,
      value: 1,
      modifiedAt: modifiedAt ?? DateTime.now(),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      version: 1,
    );

void main() {
  late LocalSyncServer server;
  late DatumManager<TestEntity> manager;
  late InMemoryLocalAdapter<TestEntity> local;

  /// Entity-list GET requests that carried a modifiedSince watermark.
  List<Uri> deltaPulls() => server.requestUris.where((u) => u.path == '/entities' && u.queryParameters.containsKey('modifiedSince')).toList();

  /// Entity-list GET requests without a watermark (full pulls).
  List<Uri> fullPulls() => server.requestUris.where((u) => u.path == '/entities' && !u.queryParameters.containsKey('modifiedSince')).toList();

  Future<void> setUpManager({DatumConfig<TestEntity>? config}) async {
    local = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
    manager = DatumManager<TestEntity>(
      localAdapter: local,
      remoteAdapter: HttpRemoteAdapter<TestEntity>(baseUri: server.baseUri, fromMap: TestEntity.fromJson),
      connectivity: _connected(),
      datumConfig: config ?? const DatumConfig<TestEntity>(),
    );
    await manager.initialize();
  }

  setUp(() async {
    server = LocalSyncServer();
    await server.start();
  });

  tearDown(() async {
    await manager.dispose();
    await server.stop();
  });

  test('first sync pulls full, later syncs pull incrementally on the wire', () async {
    await setUpManager();
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));

    await manager.synchronize('u1');
    expect(fullPulls(), isNotEmpty, reason: 'no watermark yet — the first pull must be full');
    expect(deltaPulls(), isEmpty);

    // Remote gains a fresh row; the beacon differs so the next cycle runs.
    server.seed('u1', _entity('b', name: 'new-row').toDatumMap(target: MapTarget.remote));
    server.pokeMetadata('u1');
    final fullBefore = fullPulls().length;

    await manager.synchronize('u1');

    expect(deltaPulls(), hasLength(1), reason: 'second pull must carry modifiedSince');
    expect(fullPulls(), hasLength(fullBefore), reason: 'no additional full pulls');
    expect((await local.read('b', userId: 'u1'))?.name, 'new-row', reason: 'delta row applied locally');
  });

  test('the watermark is widened by deltaSyncOverlap', () async {
    await setUpManager(
      config: const DatumConfig<TestEntity>(deltaSyncOverlap: Duration(hours: 2)),
    );
    await manager.synchronize('u1');
    final syncedAt = DateTime.now();

    server.pokeMetadata('u1');
    await manager.synchronize('u1');

    final since = DateTime.parse(deltaPulls().single.queryParameters['modifiedSince']!);
    expect(syncedAt.difference(since), greaterThan(const Duration(hours: 1, minutes: 55)), reason: 'overlap subtracted from watermark');
  });

  test('rows re-delivered inside the overlap window are idempotent', () async {
    await setUpManager();
    server.seed('u1', _entity('a', name: 'original').toDatumMap(target: MapTarget.remote));
    await manager.synchronize('u1');

    // The overlap makes the server resend 'a' unchanged; nothing corrupts.
    server.pokeMetadata('u1');
    await manager.synchronize('u1');

    expect((await local.read('a', userId: 'u1'))?.name, 'original');
    expect((await local.readAll(userId: 'u1')), hasLength(1));
  });

  test('soft deletes propagate through a delta pull', () async {
    await setUpManager();
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));
    await manager.synchronize('u1');

    // Remote soft-deletes with a fresh modifiedAt and a bumped version — it
    // must ride the delta.
    final tombstone = TestEntity(
      id: 'a',
      userId: 'u1',
      name: 'n',
      value: 1,
      modifiedAt: DateTime.now().add(const Duration(seconds: 1)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      version: 2,
      isDeleted: true,
    );
    server.seed('u1', tombstone.toDatumMap(target: MapTarget.remote));
    server.pokeMetadata('u1');

    await manager.synchronize('u1');

    expect(deltaPulls(), isNotEmpty);
    expect((await local.read('a', userId: 'u1'))?.isDeleted, isTrue);
  });

  test('enableDeltaSync: false always pulls full even when the adapter is capable', () async {
    await setUpManager(config: const DatumConfig<TestEntity>(enableDeltaSync: false));
    await manager.synchronize('u1');
    server.pokeMetadata('u1');
    await manager.synchronize('u1');

    expect(deltaPulls(), isEmpty);
    expect(fullPulls().length, greaterThanOrEqualTo(2));
  });

  test('detectRemoteDeletions forces full pulls (needs the complete remote id set)', () async {
    await setUpManager(
      config: const DatumConfig<TestEntity>(detectRemoteDeletions: true),
    );
    await manager.synchronize('u1');
    server.pokeMetadata('u1');
    await manager.synchronize('u1');

    expect(deltaPulls(), isEmpty);
  });
}
