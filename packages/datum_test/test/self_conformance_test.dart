import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart';
import 'package:test/test.dart';

/// The kit certifying datum's own reference implementations is the kit's
/// self-test: InMemoryLocalAdapter for the local suite, and the
/// HttpRemoteAdapter + LocalSyncServer pair for the remote suite.
void main() {
  runLocalAdapterConformanceTests(
    name: 'InMemoryLocalAdapter',
    create: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
    // In-memory storage holds typed entities, not raw maps, so columns the
    // entity does not model cannot survive an overwrite round-trip.
    preservesUnknownColumns: false,
  );

  runWatchConformanceTests(
    name: 'InMemoryLocalAdapter',
    create: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );

  group('HttpRemoteAdapter over LocalSyncServer', () {
    late LocalSyncServer server;

    setUpAll(() async {
      server = LocalSyncServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    runRemoteAdapterConformanceTests(
      name: 'HttpRemoteAdapter',
      create: () async {
        server.storage.clear();
        server.metadata.clear();
        return HttpRemoteAdapter<ConformanceEntity>(
          baseUri: server.baseUri,
          fromMap: ConformanceEntity.fromMap,
        );
      },
    );
  });
}
