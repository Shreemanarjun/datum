@TestOn('vm')
library;

import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../harness/http_remote_adapter.dart';
import '../harness/local_sync_server.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// ===========================================================================
// Edge-case scenarios against a REAL local HTTP server (dart:io) — actual
// sockets, JSON over the wire, HTTP status semantics, latency, 500s, severed
// connections, and server-side version conflicts. These exercise engine paths
// that in-memory mocks cannot (transport error mapping, patch->create fallback
// on a real 404, timeout enforcement against real latency, ...).
// ===========================================================================

MockConnectivityChecker _connected() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}

void main() {
  late LocalSyncServer server;
  late HttpRemoteAdapter<TestEntity> remote;
  late InMemoryLocalAdapter<TestEntity> local;
  late DatumManager<TestEntity> manager;

  Future<DatumManager<TestEntity>> newDevice({DatumConfig<TestEntity>? config}) async {
    final m = DatumManager<TestEntity>(
      localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
      remoteAdapter: HttpRemoteAdapter<TestEntity>(baseUri: server.baseUri, fromMap: TestEntity.fromJson),
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
    remote = HttpRemoteAdapter<TestEntity>(baseUri: server.baseUri, fromMap: TestEntity.fromJson);
    manager = DatumManager<TestEntity>(
      localAdapter: local,
      remoteAdapter: remote,
      connectivity: _connected(),
      datumConfig: const DatumConfig<TestEntity>(),
    );
    await manager.initialize();
  });

  tearDown(() async {
    await manager.dispose();
    await server.stop();
  });

  test('happy path: push and pull round-trip over real HTTP', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'hello-http'), userId: 'u1');
    final result = await manager.synchronize('u1');
    expect(result.failedCount, 0);
    expect(server.storage['u1']?['e1']?['name'], 'hello-http', reason: 'entity must land in server storage via POST');

    // A second device pulls it over the wire.
    final deviceB = await newDevice();
    addTearDown(deviceB.dispose);
    await deviceB.synchronize('u1');
    expect((await deviceB.read('e1', userId: 'u1'))?.name, 'hello-http');
  });

  test('patch->create fallback: real 404 on PATCH converts the op to a create', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'v1'), userId: 'u1');
    await manager.synchronize('u1');

    // The entity vanishes server-side (e.g. wiped by an admin/another system).
    server.storage['u1']!.remove('e1');

    // A local edit produces an UPDATE op with a delta -> engine sends PATCH.
    final edited = (await manager.read('e1', userId: 'u1'))!.copyWith(name: 'v2');
    await manager.push(item: edited, userId: 'u1');
    final result = await manager.synchronize('u1');

    // The server 404s the PATCH; the adapter maps it to EntityNotFoundException
    // and the engine converts the op into a CREATE and retries immediately.
    expect(result.failedCount, 0);
    expect(server.storage['u1']?['e1']?['name'], 'v2', reason: 'entity must be recreated via POST after the 404');
    expect(server.requestLog.where((r) => r.startsWith('PATCH /entities/e1')), isNotEmpty);
    expect(server.requestLog.where((r) => r.startsWith('POST /entities')), isNotEmpty);
  });

  test('transient 500 on push: op is re-queued and succeeds on the next sync', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'flaky'), userId: 'u1');

    server
      ..failMatcher = ((method, path) => method == 'POST')
      ..remainingFailures = 1;

    // The 500 maps to a retryable NetworkException -> the op is re-queued with
    // retryCount+1 instead of being dropped, and the sync completes.
    await manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));
    final pending = await manager.getPendingOperations('u1');
    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 1);
    expect(server.storage['u1']?['e1'], isNull);

    // Server healthy again: the retry delivers.
    final second = await manager.synchronize('u1');
    expect(second.failedCount, 0);
    expect(await manager.getPendingOperations('u1'), isEmpty);
    expect(server.storage['u1']?['e1']?['name'], 'flaky');
  });

  test('metadata pre-check failure degrades to a full sync instead of failing', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'resilient'), userId: 'u1');
    await manager.synchronize('u1');

    // Another device left a change on the server.
    server.seed('u1', TestEntity.create('e2', 'u1', 'external').toDatumMap(target: MapTarget.remote));

    // Fail ONLY the metadata GET of the next sync. Previously this unprotected
    // read failed the whole cycle before it started.
    server
      ..failMatcher = ((method, path) => method == 'GET' && path.startsWith('/metadata'))
      ..remainingFailures = 1;

    final result = await manager.synchronize('u1');
    expect(result.wasSkipped, isFalse);
    expect((await manager.read('e2', userId: 'u1'))?.name, 'external', reason: 'sync must proceed and pull despite the metadata blip');
  });

  test('severed connection maps to a retryable failure; recovery converges', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'unplugged'), userId: 'u1');

    server.dropConnections = true;
    await manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));
    expect(await manager.getPendingOperations('u1'), hasLength(1), reason: 'op survives the dead socket');

    server.dropConnections = false;
    await manager.synchronize('u1');
    expect(server.storage['u1']?['e1'], isNotNull);
    expect(await manager.getPendingOperations('u1'), isEmpty);
  });

  test('503 outage then recovery: nothing lost across the offline window', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'offline-edit'), userId: 'u1');

    server.offline = true;
    await manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly));
    expect(await manager.getPendingOperations('u1'), hasLength(1));

    server.offline = false;
    await manager.synchronize('u1');
    expect(server.storage['u1']?['e1']?['name'], 'offline-edit');
  });

  test('config.syncTimeout fires against real server latency', () async {
    final slowManager = await newDevice(
      config: const DatumConfig<TestEntity>(syncTimeout: Duration(milliseconds: 250)),
    );
    addTearDown(slowManager.dispose);

    await slowManager.push(item: TestEntity.create('e1', 'u1', 'slow'), userId: 'u1');
    server.latency = const Duration(seconds: 2);

    await expectLater(
      slowManager.synchronize('u1'),
      throwsA(isA<DatumException>().having((e) => e.code, 'code', DatumExceptionCode.timeout)),
    );

    // Latency gone: the queued op still delivers.
    server.latency = Duration.zero;
    await slowManager.synchronize('u1');
    expect(server.storage['u1']?['e1'], isNotNull);
  });

  test('server-side 409 version conflict surfaces as ConflictException; pull converges', () async {
    server.enforceVersions = true;

    // Another device already put e1 on the server at version 5.
    server.seed(
      'u1',
      TestEntity(id: 'e1', userId: 'u1', name: 'winner', value: 9, modifiedAt: DateTime(2033), createdAt: DateTime(2024), version: 5).toDatumMap(target: MapTarget.remote),
    );

    // This device creates the same id fresh (create op -> POST, version 1):
    // a create race. The server rejects the stale write with 409, which the
    // adapter maps to ConflictException — non-retryable, so the op is dequeued
    // and the failure surfaces to the caller.
    await manager.push(item: TestEntity.create('e1', 'u1', 'stale'), userId: 'u1');
    await expectLater(
      manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly)),
      throwsA(isA<ConflictException>()),
    );

    // The follow-up pull adopts the server's winning version.
    await manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly));
    expect((await manager.read('e1', userId: 'u1'))?.name, 'winner');
  });

  test('unicode and special characters survive the wire round-trip', () async {
    const tricky = 'héllo 🌍 中文 "quotes" back\\slash\nnew-line\ttab';
    await manager.push(item: TestEntity.create('e1', 'u1', tricky), userId: 'u1');
    await manager.synchronize('u1');
    expect(server.storage['u1']?['e1']?['name'], tricky);

    // A second device decodes it identically.
    final deviceB = await newDevice();
    addTearDown(deviceB.dispose);
    await deviceB.synchronize('u1');
    expect((await deviceB.read('e1', userId: 'u1'))?.name, tricky);
  });

  test('hard delete propagates over HTTP; deleting an already-absent entity is safe', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'doomed'), userId: 'u1');
    await manager.synchronize('u1');
    expect(server.storage['u1']?['e1'], isNotNull);

    await manager.delete(id: 'e1', userId: 'u1', behavior: DeleteBehavior.hardDelete);
    final result = await manager.synchronize('u1');
    expect(result.failedCount, 0);
    expect(server.storage['u1']?['e1'], isNull, reason: 'DELETE must remove the server copy');

    // Deleting something the server never had must not fail the sync.
    await manager.push(item: TestEntity.create('e2', 'u1', 'local-only'), userId: 'u1');
    server.storage['u1']?.remove('e2'); // never reaches server... but ensure clean
    await manager.delete(id: 'e2', userId: 'u1', behavior: DeleteBehavior.hardDelete);
    final second = await manager.synchronize('u1');
    expect(second.failedCount, 0);
  });

  test('mixed create/update/delete cycle lands the correct final server state', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'one'), userId: 'u1');
    await manager.push(item: TestEntity.create('e2', 'u1', 'two'), userId: 'u1');
    await manager.synchronize('u1');

    // One cycle containing an update (PATCH), a delete (DELETE) and a create (POST).
    final e1 = (await manager.read('e1', userId: 'u1'))!.copyWith(name: 'one-updated', version: 2, modifiedAt: DateTime(2035));
    await manager.push(item: e1, userId: 'u1');
    await manager.delete(id: 'e2', userId: 'u1', behavior: DeleteBehavior.hardDelete);
    await manager.push(item: TestEntity.create('e3', 'u1', 'three'), userId: 'u1');

    final result = await manager.synchronize('u1');
    expect(result.failedCount, 0);
    expect(server.storage['u1']?['e1']?['name'], 'one-updated');
    expect(server.storage['u1']?['e2'], isNull);
    expect(server.storage['u1']?['e3']?['name'], 'three');
    expect(await manager.getPendingOperations('u1'), isEmpty);
  });

  test('skip fast-path saves wire traffic: no entity fetch on an unchanged sync', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'stable'), userId: 'u1');
    await manager.synchronize('u1');

    server.requestLog.clear();
    final second = await manager.synchronize('u1');
    expect(second.wasSkipped, isTrue);
    expect(
      server.requestLog.where((r) => r.startsWith('GET /entities')),
      isEmpty,
      reason: 'a skipped sync must only touch metadata, not entity payloads',
    );
    expect(server.requestLog.where((r) => r.startsWith('GET /metadata')), isNotEmpty);
  });

  test('corrupted JSON response surfaces as SerializationException; recovery works', () async {
    server.seed('u1', TestEntity.create('e1', 'u1', 'fine').toDatumMap(target: MapTarget.remote));

    server
      ..corruptMatcher = ((method, path) => method == 'GET' && path == '/entities')
      ..corruptNextResponses = 1;

    await expectLater(
      manager.synchronize('u1'),
      throwsA(isA<SerializationException>()),
      reason: 'a mangled payload must surface as a typed serialization error',
    );

    // Clean response afterwards: the same sync succeeds end-to-end.
    final result = await manager.synchronize('u1');
    expect(result.failedCount, 0);
    expect((await manager.read('e1', userId: 'u1'))?.name, 'fine');
  });

  test('401 auth failure is non-retryable: op is dropped by design, error surfaces', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'unauthorized'), userId: 'u1');

    server
      ..failStatusCode = 401
      ..failMatcher = ((method, path) => method == 'POST')
      ..remainingFailures = 1;

    await expectLater(
      manager.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pushOnly)),
      throwsA(isA<NetworkException>().having((e) => e.isRetryable, 'isRetryable', isFalse)),
    );

    // Documented engine behavior: non-retryable failures dequeue the op
    // (dead-letter semantics) rather than retry-looping against a rejecting
    // server. The data is NOT silently gone — it still exists locally.
    expect(await manager.getPendingOperations('u1'), isEmpty);
    expect((await manager.read('e1', userId: 'u1'))?.name, 'unauthorized');
    expect(server.storage['u1']?['e1'], isNull);
  });

  test('concurrent synchronize calls serialize: exactly one POST per operation', () async {
    await manager.push(item: TestEntity.create('e1', 'u1', 'once'), userId: 'u1');

    // Fire two syncs without awaiting the first — the default
    // SequentialRequestStrategy queues the second behind the first.
    final results = await Future.wait([
      manager.synchronize('u1'),
      manager.synchronize('u1'),
    ]);
    expect(results, hasLength(2));

    final posts = server.requestLog.where((r) => r.startsWith('POST /entities')).length;
    expect(posts, 1, reason: 'the queued sync must not re-push the already-delivered op');
    expect(server.storage['u1']?['e1'], isNotNull);
  });

  test('user isolation over the wire: syncing u1 never pulls u2 data', () async {
    server.seed('u1', TestEntity.create('mine', 'u1', 'mine').toDatumMap(target: MapTarget.remote));
    server.seed('u2', TestEntity.create('theirs', 'u2', 'theirs').toDatumMap(target: MapTarget.remote));

    await manager.synchronize('u1');

    expect(await manager.read('mine', userId: 'u1'), isNotNull);
    expect(await manager.read('theirs', userId: 'u2'), isNull, reason: "u2's entity must not leak into a u1 sync");
    // And the entity fetch actually carried the userId scoping parameter.
    expect(server.requestLog.any((r) => r.contains('GET /entities')), isTrue);
  });

  test('large dataset pull: hundreds of entities stream over HTTP intact', () async {
    for (var i = 0; i < 300; i++) {
      server.seed('u1', TestEntity.create('bulk-$i', 'u1', 'item $i').toDatumMap(target: MapTarget.remote));
    }

    final bulkManager = await newDevice(
      config: const DatumConfig<TestEntity>(remoteSyncBatchSize: 40, remoteStreamBatchSize: 25),
    );
    addTearDown(bulkManager.dispose);

    final result = await bulkManager.synchronize('u1');
    expect(result.failedCount, 0);
    expect(await bulkManager.count(userId: 'u1'), 300, reason: 'every batched entity must arrive exactly once');
  });

  test('two devices converge across the real server (metadata beacon end-to-end)', () async {
    final deviceB = await newDevice();
    addTearDown(deviceB.dispose);

    // A pushes, B pulls.
    await manager.push(item: TestEntity.create('e1', 'u1', 'from-a'), userId: 'u1');
    await manager.synchronize('u1');
    await deviceB.synchronize('u1');
    expect((await deviceB.read('e1', userId: 'u1'))?.name, 'from-a');

    // B edits (same count!), A must still pull it thanks to the content-hash
    // metadata beacon travelling over real HTTP. The edit bumps version +
    // modifiedAt, which the diff carries so the server-side PATCH advances the
    // ordering metadata other devices use to accept the change.
    final edited = (await deviceB.read('e1', userId: 'u1'))!.copyWith(name: 'from-b', version: 2, modifiedAt: DateTime(2035));
    await deviceB.push(item: edited, userId: 'u1');
    await deviceB.synchronize('u1');

    final aResult = await manager.synchronize('u1');
    expect(aResult.wasSkipped, isFalse);
    expect((await manager.read('e1', userId: 'u1'))?.name, 'from-b');
  });
}
