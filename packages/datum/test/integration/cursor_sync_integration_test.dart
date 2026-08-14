// ===========================================================================
// Cursor-based incremental pull (delta v2) over a REAL local HTTP server:
// the engine drives CursorSyncCapable.readChanges with the persisted cursor,
// verified on the actual wire via the server's request log.
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

TestEntity _entity(String id, {String name = 'n'}) => TestEntity(
      id: id,
      userId: 'u1',
      name: name,
      value: 1,
      modifiedAt: DateTime.now(),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      version: 1,
    );

void main() {
  late LocalSyncServer server;
  late InMemoryLocalAdapter<TestEntity> local;
  late DatumManager<TestEntity> manager;

  List<Uri> changeFeedPulls() => server.requestUris.where((u) => u.path == '/changes').toList();
  List<Uri> fullEntityPulls() => server.requestUris.where((u) => u.path == '/entities' && u.queryParameters.length <= 1).toList();

  Future<DatumManager<TestEntity>> makeManager({DatumConfig<TestEntity>? config}) async {
    final m = DatumManager<TestEntity>(
      localAdapter: local,
      remoteAdapter: CursorHttpRemoteAdapter<TestEntity>(baseUri: server.baseUri, fromMap: TestEntity.fromJson),
      connectivity: _connected(),
      datumConfig: config ?? const DatumConfig<TestEntity>(),
    );
    await m.initialize();
    return m;
  }

  setUp(() async {
    server = LocalSyncServer();
    await server.start();
    local = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
    manager = await makeManager();
  });

  tearDown(() async {
    await manager.dispose();
    await server.stop();
  });

  test('first sync reads the feed from the beginning, later syncs pass the cursor', () async {
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));

    await manager.synchronize('u1');

    expect(changeFeedPulls(), hasLength(1));
    expect(changeFeedPulls().single.queryParameters.containsKey('cursor'), isFalse, reason: 'no cursor yet — from the beginning');
    expect((await local.read('a', userId: 'u1')), isNotNull);
    final firstCursor = (await local.getSyncMetadata('u1'))!.customMetadata!['__sync_cursor__'] as String;

    // Remote gains a row; next cycle must pass the stored cursor and apply
    // only the new row.
    server.seed('u1', _entity('b', name: 'fresh').toDatumMap(target: MapTarget.remote));
    server.pokeMetadata('u1');
    await manager.synchronize('u1');

    expect(changeFeedPulls(), hasLength(2));
    expect(changeFeedPulls().last.queryParameters['cursor'], firstCursor);
    expect((await local.read('b', userId: 'u1'))?.name, 'fresh');
    final secondCursor = (await local.getSyncMetadata('u1'))!.customMetadata!['__sync_cursor__'] as String;
    expect(int.parse(secondCursor), greaterThan(int.parse(firstCursor)), reason: 'cursor advances');
  });

  test('the cursor survives an app restart (new manager, same local store)', () async {
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));
    await manager.synchronize('u1');
    final storedCursor = (await local.getSyncMetadata('u1'))!.customMetadata!['__sync_cursor__'] as String;
    await manager.dispose();

    manager = await makeManager(); // same `local` adapter — simulated relaunch
    server.pokeMetadata('u1');
    await manager.synchronize('u1');

    expect(changeFeedPulls().last.queryParameters['cursor'], storedCursor);
  });

  test('cursor path wins over the timestamp path when both are advertised', () async {
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));
    await manager.synchronize('u1');
    server.pokeMetadata('u1');
    await manager.synchronize('u1');

    expect(changeFeedPulls(), isNotEmpty);
    expect(
      server.requestUris.where((u) => u.queryParameters.containsKey('modifiedSince')),
      isEmpty,
      reason: 'CursorHttpRemoteAdapter is also DeltaSyncCapable, but the cursor path takes precedence',
    );
  });

  test('the cursor is per-device: local metadata carries it, the remote beacon does not', () async {
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));
    await manager.synchronize('u1');

    final localMeta = await local.getSyncMetadata('u1');
    expect(localMeta!.customMetadata, contains('__sync_cursor__'));

    final beacon = server.metadata['u1'];
    expect(beacon, isNotNull, reason: 'beacon written');
    final beaconCustom = beacon!['customMetadata'];
    expect(
      beaconCustom is Map && beaconCustom.containsKey('__sync_cursor__'),
      isFalse,
      reason: 'a foreign device adopting this cursor would skip changes it never saw',
    );
  });

  test('detectRemoteDeletions cycles use a full pull and leave the cursor unchanged', () async {
    await manager.dispose();
    manager = await makeManager(config: const DatumConfig<TestEntity>(detectRemoteDeletions: true));
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));

    await manager.synchronize('u1');

    expect(changeFeedPulls(), isEmpty, reason: 'deletion detection needs the complete remote id set');
    expect(fullEntityPulls(), isNotEmpty);
  });

  test('soft deletes ride the feed', () async {
    server.seed('u1', _entity('a').toDatumMap(target: MapTarget.remote));
    await manager.synchronize('u1');

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

    expect((await local.read('a', userId: 'u1'))?.isDeleted, isTrue);
  });
}
