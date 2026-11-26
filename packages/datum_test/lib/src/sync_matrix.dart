import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';
import 'http_remote_adapter.dart';
import 'in_memory_remote_adapter.dart';
import 'local_sync_server.dart';
import 'resource_conformance.dart';
import 'sync_stack_conformance.dart';

/// Runs [runSyncStackConformanceTests] for one local adapter against EVERY
/// bundled remote: [InMemoryRemoteAdapter] (full pulls, strict 404s),
/// [HttpRemoteAdapter] over [LocalSyncServer] (timestamp-delta pulls) and
/// [CursorHttpRemoteAdapter] (cursor change feed). Per-entity fault injection
/// is wired for all three.
///
/// ```dart
/// runSyncConformanceMatrix(
///   name: 'SqliteLocalAdapter (file)',
///   createLocal: openFreshDb,
///   reopenLocal: (crashed) => reopenSameFile(crashed),
/// );
/// ```
void runSyncConformanceMatrix({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  ReopenLocal? reopenLocal,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroyLocal,
}) {
  final backend = InMemoryRemoteBackend();
  runSyncStackConformanceTests(
    name: '$name + InMemoryRemote',
    createLocal: createLocal,
    createRemote: () async => InMemoryRemoteAdapter<ConformanceEntity>(
      backend: backend,
      fromMap: ConformanceEntity.fromMap,
    ),
    resetBackend: () async => backend.reset(),
    destroyLocal: destroyLocal,
    reopenLocal: reopenLocal,
    failEntityWrites: (id, {required status, times = 1}) =>
        backend.failWrites(id, status: status, times: times),
  );

  group('$name + HTTP', () {
    final server = LocalSyncServer();
    setUpAll(server.start);
    tearDownAll(server.stop);

    Future<void> reset() async {
      server
        ..storage.clear()
        ..metadata.clear()
        ..remainingFailures = 0
        ..failMatcher = null
        ..failStatusCode = 500;
    }

    void failEntityWrites(String id, {required int status, int times = 1}) {
      server
        ..failMatcher = ((method, path) =>
            method != 'GET' && path == '/entities/$id')
        ..remainingFailures = times
        ..failStatusCode = status;
    }

    runSyncStackConformanceTests(
      name: 'timestamp delta',
      createLocal: createLocal,
      createRemote: () async => HttpRemoteAdapter<ConformanceEntity>(
        baseUri: server.baseUri,
        fromMap: ConformanceEntity.fromMap,
      ),
      resetBackend: reset,
      destroyLocal: destroyLocal,
      reopenLocal: reopenLocal,
      failEntityWrites: failEntityWrites,
      remotePullsByTimestamp: true,
    );

    runSyncStackConformanceTests(
      name: 'cursor feed',
      createLocal: createLocal,
      createRemote: () async => CursorHttpRemoteAdapter<ConformanceEntity>(
        baseUri: server.baseUri,
        fromMap: ConformanceEntity.fromMap,
      ),
      resetBackend: reset,
      destroyLocal: destroyLocal,
      reopenLocal: reopenLocal,
      failEntityWrites: failEntityWrites,
    );
  });

  runResourceConformanceTests(name: name, createLocal: createLocal);
}
