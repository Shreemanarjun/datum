import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart';
import 'package:test/test.dart';

/// The sync-stack suite certifying datum's own reference stack
/// (InMemoryLocalAdapter + HttpRemoteAdapter over LocalSyncServer) is the
/// suite's self-test. Runs twice: once over the plain HTTP adapter, once
/// over the cursor-feed variant, proving the matrix holds for full,
/// timestamp-delta and cursor pulls alike.
void main() {
  late LocalSyncServer server;

  setUpAll(() async {
    server = LocalSyncServer();
    await server.start();
  });

  tearDownAll(() => server.stop());

  Future<LocalAdapter<ConformanceEntity>> createLocal() async {
    final adapter = InMemoryLocalAdapter<ConformanceEntity>(
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    return adapter;
  }

  Future<void> resetBackend() async {
    server.storage.clear();
    server.metadata.clear();
  }

  runSyncStackConformanceTests(
    name: 'InMemory + HTTP (timestamp delta)',
    createLocal: createLocal,
    createRemote: () async => HttpRemoteAdapter<ConformanceEntity>(
      baseUri: server.baseUri,
      fromMap: ConformanceEntity.fromMap,
    ),
    resetBackend: resetBackend,
  );

  runSyncStackConformanceTests(
    name: 'InMemory + HTTP (cursor feed)',
    createLocal: createLocal,
    createRemote: () async => CursorHttpRemoteAdapter<ConformanceEntity>(
      baseUri: server.baseUri,
      fromMap: ConformanceEntity.fromMap,
    ),
    resetBackend: resetBackend,
  );
}
