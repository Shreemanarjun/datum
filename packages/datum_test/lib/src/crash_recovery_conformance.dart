import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';
import 'http_remote_adapter.dart';
import 'local_sync_server.dart';
import 'sync_stack_conformance.dart';

/// Runs the Datum **crash recovery conformance suite**: certifies that a
/// PERSISTENT local adapter carries the full sync state — queued operations,
/// entity rows, sync metadata, schema version — across a process crash, and
/// that resuming sync afterwards delivers every queued write exactly once.
///
/// Contract:
/// - [openLocal] opens a fresh, initialized adapter over PERSISTENT storage.
///   Calling it again after the previous instance was disposed must see the
///   same persisted state (same file/database). In-memory adapters cannot
///   satisfy this contract.
/// - [wipeStorage] resets the persistent storage completely; it runs before
///   every test so tests are independent.
///
/// A "crash" is modelled as disposing the manager (which disposes its
/// adapters) without syncing or flushing anything first, then reopening the
/// storage through [openLocal] and building a brand-new manager over it.
///
/// ```dart
/// runCrashRecoveryConformanceTests(
///   name: 'SqliteLocalAdapter (file database)',
///   openLocal: () async {
///     db?.dispose(); // adapter.dispose() never closes the caller-owned DB
///     db = sqlite3.open(path);
///     final adapter = SqliteLocalAdapter<ConformanceEntity>(
///       database: db!,
///       table: 'conformance',
///       fromMap: ConformanceEntity.fromMap,
///       columns: const {'name': 'TEXT', 'value': 'INTEGER'},
///     );
///     await adapter.initialize();
///     return adapter;
///   },
///   wipeStorage: () async {
///     db?.dispose();
///     db = null;
///     File(path).deleteSync();
///   },
/// );
/// ```
void runCrashRecoveryConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() openLocal,
  Future<void> Function()? wipeStorage,
}) {
  group('$name crash recovery conformance', () {
    late LocalSyncServer server;
    final cleanups = <Future<void> Function()>[];

    /// Builds a manager over an already-open [local] adapter. Disposal is
    /// registered for teardown, but tests may (and do) dispose the manager
    /// early themselves to model a crash — disposal is idempotent.
    Future<DatumManager<ConformanceEntity>> bootManager(
      LocalAdapter<ConformanceEntity> local, {
      bool online = true,
    }) async {
      final connectivity = TestConnectivityChecker()..setOnline(online);
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
        ),
      );
      await manager.initialize();
      cleanups.add(() async {
        await manager.dispose();
        await connectivity.dispose();
      });
      return manager;
    }

    setUp(() async {
      await wipeStorage?.call();
      server = LocalSyncServer();
      await server.start();
    });

    tearDown(() async {
      for (final cleanup in cleanups.reversed) {
        await cleanup();
      }
      cleanups.clear();
      await server.stop();
    });

    test(
      'queued offline ops survive a crash and deliver exactly once after reopen',
      () async {
        final local1 = await openLocal();
        final manager1 = await bootManager(local1, online: false);

        for (var i = 0; i < 3; i++) {
          await manager1.push(
            item: ConformanceEntity.make(
              'q$i',
              userId: 'u1',
              name: 'queued-$i',
              value: i,
            ),
            userId: 'u1',
          );
        }
        expect((await manager1.getPendingOperations('u1')).length, 3);

        // Crash: dispose without ever syncing.
        await manager1.dispose();

        // Reopen the same storage; assert persistence straight on the adapter,
        // before any manager touches it.
        final local2 = await openLocal();
        expect(
          (await local2.getPendingOperations('u1')).length,
          3,
          reason: 'pending queue must survive the crash',
        );

        final manager2 = await bootManager(local2);
        expect((await manager2.getPendingOperations('u1')).length, 3);

        final result = await manager2.synchronize('u1');
        expect(result.failedCount, 0);
        expect(
          await manager2.getPendingOperations('u1'),
          isEmpty,
          reason: 'queue drained after recovery sync',
        );

        final serverRows =
            server.storage['u1'] ?? const <String, Map<String, dynamic>>{};
        expect(
          serverRows.keys.toSet(),
          {'q0', 'q1', 'q2'},
          reason: 'exactly one copy of each entity on the server',
        );
        for (var i = 0; i < 3; i++) {
          expect(serverRows['q$i']!['name'], 'queued-$i');
          expect(serverRows['q$i']!['value'], i);
          expect(
            (await local2.read('q$i', userId: 'u1'))?.name,
            'queued-$i',
            reason: 'local content converged',
          );
        }
      },
    );

    test(
      'crash mid-sync over severed sockets recovers with exactly-once delivery',
      () async {
        final local1 = await openLocal();
        final manager1 = await bootManager(local1);

        // Baseline: one entity fully synced.
        await manager1.push(
          item: ConformanceEntity.make(
            'stable',
            userId: 'u1',
            name: 'v1',
            value: 1,
          ),
          userId: 'u1',
        );
        final clean = await manager1.synchronize('u1');
        expect(clean.failedCount, 0);
        expect(server.storage['u1']?.keys, contains('stable'));

        // Queue an update to the synced entity and a brand-new entity, then
        // sever every socket so the next sync fails mid-flight.
        final current = (await local1.read('stable', userId: 'u1'))!;
        await manager1.push(
          item: current.copyWith(name: 'v2'),
          userId: 'u1',
        );
        await manager1.push(
          item: ConformanceEntity.make(
            'fresh',
            userId: 'u1',
            name: 'fresh-born',
            value: 2,
          ),
          userId: 'u1',
        );
        server.dropConnections = true;
        try {
          await manager1.synchronize('u1');
        } on Object {
          // Expected: the severed sockets surface as connection errors.
        }
        expect(
          await manager1.getPendingOperations('u1'),
          isNotEmpty,
          reason: 'failed ops must stay queued',
        );

        // Crash while the network fault is still active.
        await manager1.dispose();
        server.dropConnections = false;

        final local2 = await openLocal();
        expect(
          await local2.getPendingOperations('u1'),
          isNotEmpty,
          reason: 'pending ops survive the crash',
        );

        final manager2 = await bootManager(local2);
        final recovery = await manager2.synchronize('u1');
        expect(recovery.failedCount, 0);
        await manager2.synchronize('u1'); // let any push-back settle

        final serverRows =
            server.storage['u1'] ?? const <String, Map<String, dynamic>>{};
        expect(
          serverRows.keys.toSet(),
          {'stable', 'fresh'},
          reason: 'no duplicates, no losses on the server',
        );
        expect(
          serverRows['stable']!['name'],
          'v2',
          reason: 'queued update delivered',
        );
        expect(
          serverRows['stable']!['version'],
          2,
          reason: 'update applied exactly once',
        );
        expect(serverRows['fresh']!['name'], 'fresh-born');
        expect(
          serverRows['fresh']!['version'],
          1,
          reason: 'create applied exactly once',
        );

        final localStable = await local2.read('stable', userId: 'u1');
        expect(localStable?.name, 'v2');
        expect(
          localStable?.version,
          2,
          reason: 'local and remote versions agree',
        );
        expect(
          await manager2.getPendingOperations('u1'),
          isEmpty,
          reason: 'queue drained',
        );
      },
    );

    test('schema version and sync metadata survive a crash', () async {
      final local1 = await openLocal();
      final manager1 = await bootManager(local1);

      await manager1.push(
        item: ConformanceEntity.make(
          's1',
          userId: 'u1',
          name: 'persisted',
          value: 9,
        ),
        userId: 'u1',
      );
      final result = await manager1.synchronize('u1');
      expect(result.failedCount, 0);

      final metaBefore = await local1.getSyncMetadata('u1');
      expect(
        metaBefore?.dataHash,
        isNotNull,
        reason: 'a successful sync stamps local metadata',
      );
      await local1.setStoredSchemaVersion(42);

      // Crash.
      await manager1.dispose();

      final local2 = await openLocal();
      expect(
        await local2.getStoredSchemaVersion(),
        42,
        reason: 'schema version survives the crash',
      );

      final metaAfter = await local2.getSyncMetadata('u1');
      expect(
        metaAfter?.dataHash,
        metaBefore?.dataHash,
        reason: 'sync metadata survives the crash',
      );
      expect(
        await local2.getLastSyncResult('u1'),
        isNotNull,
        reason: 'last sync result survives the crash',
      );
      expect(
        (await local2.read('s1', userId: 'u1'))?.name,
        'persisted',
        reason: 'entity rows survive the crash',
      );

      await local2.dispose();
    });
  });
}
