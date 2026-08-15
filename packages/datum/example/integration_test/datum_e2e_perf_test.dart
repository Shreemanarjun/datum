// End-to-end integration + performance benchmark suite for the Datum sync
// engine, running on a real device/simulator.
//
// The full journey — local writes, queries, reactive watch, push/pull sync,
// incremental cycles, conflict convergence, offline replay, soft deletes,
// user isolation, and schema migrations — runs twice against a real
// in-process HTTP sync server (LocalSyncServer from datum_test):
//
//   1. SQLite (datum_sqlite — file-backed, query pushdown, real DDL migration)
//   2. Hive   (datum_hive — box-backed, raw-map migration)
//
// Every phase is timed; a benchmark table is printed at the end and reported
// through the integration_test binding for machine consumption.
//
// Run on an iOS simulator:
//   flutter test integration_test/datum_e2e_perf_test.dart -d <simulator-udid>
import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// ---------------------------------------------------------------------------
// Entity
// ---------------------------------------------------------------------------

class BenchItem extends DatumEntity {
  const BenchItem({
    required this.id,
    required this.userId,
    required this.title,
    this.priority = 0,
    this.done = false,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  factory BenchItem.fromMap(Map<String, dynamic> map) => BenchItem(
        id: map['id'] as String? ?? '',
        userId: map['userId'] as String? ?? '',
        title: map['title'] as String? ?? '',
        priority: (map['priority'] as num?)?.toInt() ?? 0,
        done: map['done'] as bool? ?? false,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime(2000),
        modifiedAt: DateTime.tryParse(map['modifiedAt'] as String? ?? '') ?? DateTime(2000),
        version: (map['version'] as num?)?.toInt() ?? 1,
        isDeleted: map['isDeleted'] as bool? ?? false,
      );

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final int priority;
  final bool done;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'priority': priority,
        'done': done,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! BenchItem) return toDatumMap(target: MapTarget.remote);
    final delta = <String, dynamic>{};
    if (title != oldVersion.title) delta['title'] = title;
    if (priority != oldVersion.priority) delta['priority'] = priority;
    if (done != oldVersion.done) delta['done'] = done;
    if (delta.isEmpty) return null;
    delta['modifiedAt'] = modifiedAt.toIso8601String();
    delta['version'] = version;
    return delta;
  }

  BenchItem copyWith({String? title, int? priority, bool? done, bool? isDeleted, DateTime? modifiedAt, int? version}) =>
      BenchItem(
        id: id,
        userId: userId,
        title: title ?? this.title,
        priority: priority ?? this.priority,
        done: done ?? this.done,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? DateTime.now(),
        version: version ?? this.version + 1,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  List<Object?> get props => [...super.props, title, priority, done];
}

BenchItem make(String id, {String userId = 'u1', String title = 'item', int priority = 0}) {
  final now = DateTime.now();
  return BenchItem(
    id: id,
    userId: userId,
    title: title,
    priority: priority,
    createdAt: now,
    modifiedAt: now,
    version: 1,
  );
}

// ---------------------------------------------------------------------------
// Benchmark collector
// ---------------------------------------------------------------------------

class Bench {
  final entries = <({String section, String label, Duration elapsed, int ops})>[];
  String section = '';

  Future<R> run<R>(String label, Future<R> Function() body, {int ops = 1}) async {
    final sw = Stopwatch()..start();
    final result = await body();
    sw.stop();
    entries.add((section: section, label: label, elapsed: sw.elapsed, ops: ops));
    return result;
  }

  Map<String, dynamic> toReport() => {
        for (final e in entries)
          '${e.section} / ${e.label}': {
            'totalMicros': e.elapsed.inMicroseconds,
            'ops': e.ops,
            'microsPerOp': e.elapsed.inMicroseconds / e.ops,
          },
      };

  void printReport() {
    String pad(String s, int w) => s.length >= w ? s : s + ' ' * (w - s.length);
    String lpad(String s, int w) => s.length >= w ? s : ' ' * (w - s.length) + s;
    final buffer = StringBuffer()
      ..writeln('')
      ..writeln('══ Datum E2E benchmarks ══════════════════════════════════════════════════')
      ..writeln('${pad('section', 9)} ${pad('phase', 38)} ${lpad('ops', 5)} '
          '${lpad('total ms', 9)} ${lpad('µs/op', 9)} ${lpad('ops/s', 9)}');
    for (final e in entries) {
      final microsPerOp = e.elapsed.inMicroseconds / e.ops;
      final opsPerSec = e.elapsed.inMicroseconds == 0 ? 0 : e.ops * 1e6 / e.elapsed.inMicroseconds;
      buffer.writeln('${pad(e.section, 9)} ${pad(e.label, 38)} ${lpad('${e.ops}', 5)} '
          '${lpad((e.elapsed.inMicroseconds / 1000).toStringAsFixed(1), 9)} '
          '${lpad(microsPerOp.toStringAsFixed(1), 9)} '
          '${lpad(opsPerSec.toStringAsFixed(0), 9)}');
    }
    buffer.writeln('══════════════════════════════════════════════════════════════════════════');
    // ignore: avoid_print
    print(buffer);
  }
}

// ---------------------------------------------------------------------------
// Per-backend suite
// ---------------------------------------------------------------------------

const batchSize = 300;
const pullSize = 100;

class SuiteContext {
  late Directory dir;
  late LocalSyncServer server;
  late TestConnectivityChecker connectivity;
  late LocalAdapter<BenchItem> local;
  late DatumManager<BenchItem> manager;
  sql.Database? database; // SQLite only.
  String table = 'bench_items';

  /// A second remote adapter acting as "another device / the backend itself".
  Future<HttpRemoteAdapter<BenchItem>> seeder() async {
    final adapter = HttpRemoteAdapter<BenchItem>(baseUri: server.baseUri, fromMap: BenchItem.fromMap);
    await adapter.initialize();
    return adapter;
  }
}

void registerBackendSuite({
  required String backend,
  required Bench bench,
  required Future<LocalAdapter<BenchItem>> Function(SuiteContext ctx) createLocal,
  required Future<void> Function(SuiteContext ctx) runMigrationPhase,
}) {
  group('E2E · $backend + local HTTP sync server', () {
    final ctx = SuiteContext();

    setUpAll(() async {
      bench.section = backend;
      ctx.dir = await Directory.systemTemp.createTemp('datum_e2e_$backend');
      ctx.server = LocalSyncServer();
      await ctx.server.start();
      ctx.connectivity = TestConnectivityChecker();
      ctx.local = await createLocal(ctx);

      await bench.run('Datum.initialize', () async {
        final result = await Datum.initialize(
          config: DatumConfig<BenchItem>(enableLogging: false),
          connectivityChecker: ctx.connectivity,
          registrations: [
            DatumRegistration<BenchItem>(
              localAdapter: ctx.local,
              remoteAdapter: HttpRemoteAdapter<BenchItem>(baseUri: ctx.server.baseUri, fromMap: BenchItem.fromMap),
            ),
          ],
        );
        if (!result.isSuccess()) {
          // ignore: avoid_print
          print('Datum.initialize failed for $backend: ${result.errorOrNull}');
        }
        expect(result.isSuccess(), isTrue);
      });
      ctx.manager = Datum.manager<BenchItem>();
    });

    tearDownAll(() async {
      try {
        await Datum.instance.dispose().timeout(const Duration(seconds: 30));
      } on StateError {
        // Initialization failed earlier — nothing to dispose.
        Datum.resetForTesting();
      }
      await ctx.server.stop();
      ctx.database?.dispose();
      await ctx.dir.delete(recursive: true);
    });

    testWidgets('local batch write: saveMany × $batchSize', (tester) async {
      final items = [for (var i = 0; i < batchSize; i++) make('b$i', title: 'batch $i', priority: i % 5)];
      await bench.run('local write (saveMany)', () => ctx.manager.saveMany(items: items, userId: 'u1'), ops: batchSize);
      expect(await ctx.manager.count(userId: 'u1'), batchSize);
    });

    testWidgets('query: filter + sort + paginate', (tester) async {
      const iterations = 20;
      late List<BenchItem> page;
      await bench.run('filtered sorted page query', () async {
        for (var i = 0; i < iterations; i++) {
          page = await ctx.manager.query(
            const DatumQuery(
              filters: [Filter('priority', FilterOperator.greaterThanOrEqual, 3)],
              sorting: [SortDescriptor('priority', descending: true)],
              limit: 20,
            ),
            source: DataSource.local,
            userId: 'u1',
          );
        }
      }, ops: iterations);
      expect(page, isNotEmpty);
      expect(page.length, lessThanOrEqualTo(20));
      expect(page.every((e) => e.priority >= 3), isTrue);
    });

    testWidgets('reactive watch emits on write', (tester) async {
      // A hard timeout so a non-emitting stream fails the test instead of
      // hanging the whole simulator run for the 10-minute default timeout.
      final emitted = ctx.manager
          .watchAll(userId: 'u1')
          .firstWhere((all) => all.any((e) => e.id == 'watched'))
          .timeout(const Duration(seconds: 15));
      await bench.run('watch stream latency (1 write)', () async {
        await ctx.manager.push(item: make('watched', title: 'observe me'), userId: 'u1');
        await emitted;
      });
    });

    testWidgets('sync push: all pending operations reach the server', (tester) async {
      final result = await bench.run(
        'sync push (${batchSize + 1} ops)',
        () => ctx.manager.synchronize('u1'),
        ops: batchSize + 1,
      );
      expect(result.failedCount, 0);
      expect(ctx.server.storage['u1']?.length, batchSize + 1);
    });

    testWidgets('incremental second cycle is a near no-op', (tester) async {
      final requestsBefore = ctx.server.requestLog.length;
      final result = await bench.run('idle sync cycle (nothing changed)', () => ctx.manager.synchronize('u1'));
      expect(result.failedCount, 0);
      expect(result.syncedCount, 0, reason: 'nothing changed since the previous cycle');
      expect(ctx.server.requestLog.length - requestsBefore, lessThanOrEqualTo(4),
          reason: 'an idle cycle should only need a metadata check plus at most a light pull');
    });

    testWidgets('pull: $pullSize remote-born rows land locally', (tester) async {
      final seeder = await ctx.seeder();
      for (var i = 0; i < pullSize; i++) {
        await seeder.create(make('srv$i', title: 'server born $i'));
      }
      // Invalidate the client's cached metadata hash so the pull actually runs
      // (out-of-band server writes don't update the sync metadata on their own).
      ctx.server.pokeMetadata('u1');
      final result = await bench.run('sync pull ($pullSize remote rows)', () => ctx.manager.synchronize('u1'), ops: pullSize);
      expect(result.failedCount, 0);
      final local = await ctx.local.read('srv0', userId: 'u1');
      expect(local?.title, 'server born 0');
      expect(await ctx.manager.count(userId: 'u1'), batchSize + 1 + pullSize);
    });

    testWidgets('conflict: newer remote edit wins (LWW convergence)', (tester) async {
      final mine = (await ctx.local.read('b0', userId: 'u1'))!;
      final seeder = await ctx.seeder();
      await seeder.update(mine.copyWith(
        title: 'edited remotely',
        version: mine.version + 1,
        modifiedAt: DateTime.now().add(const Duration(seconds: 2)),
      ));
      ctx.server.pokeMetadata('u1');
      await bench.run('conflict cycle (remote newer)', () => ctx.manager.synchronize('u1'));
      expect((await ctx.local.read('b0', userId: 'u1'))?.title, 'edited remotely');
    });

    testWidgets('conflict: stale remote does not clobber newer local', (tester) async {
      final mine = (await ctx.local.read('b1', userId: 'u1'))!;
      final newerLocal = mine.copyWith(title: 'kept local');
      await ctx.manager.push(item: newerLocal, userId: 'u1');
      await ctx.manager.synchronize('u1');

      final seeder = await ctx.seeder();
      await seeder.update(mine.copyWith(
        title: 'stale remote',
        version: 1,
        modifiedAt: DateTime.now().subtract(const Duration(days: 1)),
      ));
      ctx.server.pokeMetadata('u1');
      await bench.run('conflict cycle (remote stale)', () => ctx.manager.synchronize('u1'));
      expect((await ctx.local.read('b1', userId: 'u1'))?.title, 'kept local');
    });

    testWidgets('offline queue + replay when connectivity returns', (tester) async {
      ctx.connectivity.setOnline(false);
      await ctx.manager.push(item: make('offline1', title: 'queued while offline'), userId: 'u1');
      expect(ctx.server.storage['u1']?['offline1'], isNull);
      expect(await ctx.manager.getPendingOperations('u1'), isNotEmpty);

      ctx.connectivity.setOnline(true);
      final result = await bench.run('offline replay (1 queued op)', () => ctx.manager.synchronize('u1'));
      expect(result.failedCount, 0);
      expect(ctx.server.storage['u1']?['offline1']?['title'], 'queued while offline');
    });

    testWidgets('soft delete propagates to the server', (tester) async {
      await ctx.manager.delete(id: 'offline1', userId: 'u1');
      await bench.run('delete + sync', () => ctx.manager.synchronize('u1'));
      expect(await ctx.local.read('offline1', userId: 'u1'), isNull);
      final onServer = ctx.server.storage['u1']?['offline1'];
      expect(onServer == null || onServer['isDeleted'] == true, isTrue);
    });

    testWidgets('users are isolated end to end', (tester) async {
      await ctx.manager.push(item: make('theirs', userId: 'u2', title: 'other user'), userId: 'u2');
      await ctx.manager.synchronize('u2');
      final mine = await ctx.local.readAll(userId: 'u1');
      final theirs = await ctx.local.readAll(userId: 'u2');
      expect(mine.map((e) => e.id), isNot(contains('theirs')));
      expect(theirs.map((e) => e.id), ['theirs']);
      expect(ctx.server.storage['u2']?.keys, ['theirs']);
    });

    testWidgets('schema migration: transform runs on stored rows', (tester) async {
      await runMigrationPhase(ctx);
      final all = await ctx.local.readAll(userId: 'u1');
      expect(all, isNotEmpty);
      expect(all.every((e) => e.priority >= 100), isTrue,
          reason: 'the migration chain adds 100 to every priority');
    });
  });
}

/// The one migration chain both backends run — raw-map rewrites on Hive,
/// real SQL on SQLite.
List<SchemaMigration> migrationChain() => [
      SchemaMigration(
        fromVersion: 0,
        toVersion: 1,
        operations: [
          ColumnOperation.transform(
            'priority',
            (value, row) => ((value as num?)?.toInt() ?? 0) + 100,
            sqlExpression: 'priority + 100',
          ),
        ],
      ),
    ];

// ---------------------------------------------------------------------------
// Migration deep-dive (adapter-level; no Datum singleton involved)
// ---------------------------------------------------------------------------

const migrationRows = 1000;

/// v0→1 add a column, v1→2 transform an existing one, v2→3 remove the added
/// column again — the same declarative chain runs as raw-map rewrites on Hive
/// and as ALTER TABLE / UPDATE DDL on SQLite.
List<SchemaMigration> deepChain() => [
      SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
        ColumnOperation.add('tag', defaultValue: 'general'),
      ]),
      SchemaMigration(fromVersion: 1, toVersion: 2, operations: [
        ColumnOperation.transform(
          'priority',
          (value, row) => ((value as num?)?.toInt() ?? 0) + 100,
          sqlExpression: 'priority + 100',
        ),
      ]),
      SchemaMigration(fromVersion: 2, toVersion: 3, operations: [
        ColumnOperation.remove('tag'),
      ]),
    ];

/// A chain whose validation passes but whose execution fails mid-way.
List<SchemaMigration> gappedChain() => [
      SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
        ColumnOperation.add('tag', defaultValue: 'general'),
      ]),
      // v1→2 is missing — MigrationPlan.resolve must reject the whole chain.
      SchemaMigration(fromVersion: 2, toVersion: 3, operations: [
        ColumnOperation.remove('tag'),
      ]),
    ];

void registerMigrationSuite({
  required String backend,
  required Bench bench,
  required Future<LocalAdapter<BenchItem>> Function(String storeName) createAdapter,
  required Future<MigrationResult> Function(
    LocalAdapter<BenchItem> adapter,
    String storeName,
    List<SchemaMigration> chain,
    int targetVersion,
  ) migrate,
  required List<SchemaMigration> Function() runtimeFailingChain,
  Future<void> Function()? destroy,
}) {
  group('Migration deep-dive · $backend', () {
    late LocalAdapter<BenchItem> mainAdapter;

    tearDownAll(() async {
      await destroy?.call();
    });

    Future<LocalAdapter<BenchItem>> seeded(String storeName, int rows) async {
      final adapter = await createAdapter(storeName);
      await adapter.createAll([
        for (var i = 0; i < rows; i++) make('m$i', title: 'row $i', priority: i % 10),
      ]);
      return adapter;
    }

    testWidgets('multi-step chain (add → transform → remove) over $migrationRows rows', (tester) async {
      bench.section = backend;
      mainAdapter = await bench.run(
        'adapter createAll ($migrationRows rows)',
        () => seeded('mig_main', migrationRows),
        ops: migrationRows,
      );

      final result = await bench.run(
        'migration chain ×3 steps ($migrationRows rows)',
        () => migrate(mainAdapter, 'mig_main', deepChain(), 3),
        ops: migrationRows,
      );
      expect(result.success, isTrue, reason: 'migration failed: ${result.migrationError}');
      expect(await mainAdapter.getStoredSchemaVersion(), 3);

      final all = await mainAdapter.readAll(userId: 'u1');
      expect(all, hasLength(migrationRows));
      expect(all.every((e) => e.priority >= 100), isTrue);
      final raw = await mainAdapter.getAllRawData();
      expect(raw.any((row) => row.containsKey('tag')), isFalse,
          reason: 'the added column must be removed again by v2→3');
    });

    testWidgets('fail-fast: a gapped chain touches nothing', (tester) async {
      final adapter = await seeded('mig_gap', 50);
      final result = await migrate(adapter, 'mig_gap', gappedChain(), 3);
      expect(result.success, isFalse);
      expect(await adapter.getStoredSchemaVersion(), 0, reason: 'no step may run');
      final all = await adapter.readAll(userId: 'u1');
      expect(all.every((e) => e.priority < 10), isTrue, reason: 'data untouched');
    });

    testWidgets('rollback: a failing step restores data and version', (tester) async {
      final adapter = await seeded('mig_fail', 50);
      final result = await migrate(adapter, 'mig_fail', runtimeFailingChain(), 1);
      expect(result.success, isFalse);
      expect(await adapter.getStoredSchemaVersion(), 0);
      final all = await adapter.readAll(userId: 'u1');
      expect(all, hasLength(50));
      expect(all.every((e) => e.priority < 10), isTrue, reason: 'rolled back');
    });

    testWidgets('run-once: re-executing a completed chain is a no-op', (tester) async {
      final result = await bench.run(
        'migration re-run (already stamped)',
        () => migrate(mainAdapter, 'mig_main', deepChain(), 3),
      );
      expect(result.success, isTrue);
      final all = await mainAdapter.readAll(userId: 'u1');
      expect(all.every((e) => e.priority < 200), isTrue,
          reason: 'the transform must not run a second time');
    });
  });
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final bench = Bench();

  registerBackendSuite(
    backend: 'sqlite',
    bench: bench,
    createLocal: (ctx) async {
      ctx.database = sql.sqlite3.open('${ctx.dir.path}/bench.db');
      // Datum.initialize calls adapter.initialize(); don't pre-initialize.
      return SqliteLocalAdapter<BenchItem>(
        database: ctx.database!,
        table: ctx.table,
        fromMap: BenchItem.fromMap,
        columns: const {'title': 'TEXT', 'priority': 'INTEGER', 'done': 'BOOLEAN'},
      );
    },
    runMigrationPhase: (ctx) async {
      final result = await SqlMigrationExecutor<BenchItem>(
        localAdapter: ctx.local,
        table: ctx.table,
        migrations: migrationChain(),
        targetVersion: 1,
        dialect: SqlDialect.sqlite,
        logger: DatumLogger(enabled: false),
      ).execute();
      expect(result.success, isTrue, reason: 'SQL migration failed: ${result.migrationError}');
    },
  );

  registerBackendSuite(
    backend: 'hive',
    bench: bench,
    createLocal: (ctx) async {
      Hive.init('${ctx.dir.path}/hive');
      // HiveLocalAdapter.initialize assigns `late final` boxes and is not
      // idempotent — Datum.initialize owns the single initialize() call.
      return HiveLocalAdapter<BenchItem>(
        entityBoxName: 'bench_${DateTime.now().microsecondsSinceEpoch}',
        fromMap: BenchItem.fromMap,
      );
    },
    runMigrationPhase: (ctx) async {
      final result = await MigrationExecutor<BenchItem>(
        localAdapter: ctx.local,
        migrations: migrationChain(),
        targetVersion: 1,
        logger: DatumLogger(enabled: false),
      ).execute();
      expect(result.success, isTrue, reason: 'map migration failed: ${result.migrationError}');
    },
  );

  // --- Migration deep-dive: sqlite (real DDL) ------------------------------
  {
    late Directory dir;
    sql.Database? db;
    registerMigrationSuite(
      backend: 'sqlite',
      bench: bench,
      createAdapter: (storeName) async {
        if (db == null) {
          dir = await Directory.systemTemp.createTemp('datum_mig_sqlite');
          db = sql.sqlite3.open('${dir.path}/mig.db');
        }
        final adapter = SqliteLocalAdapter<BenchItem>(
          database: db!,
          table: storeName,
          fromMap: BenchItem.fromMap,
          columns: const {'title': 'TEXT', 'priority': 'INTEGER', 'done': 'BOOLEAN'},
        );
        await adapter.initialize();
        return adapter;
      },
      migrate: (adapter, storeName, chain, targetVersion) => SqlMigrationExecutor<BenchItem>(
        localAdapter: adapter,
        table: storeName,
        migrations: chain,
        targetVersion: targetVersion,
        dialect: SqlDialect.sqlite,
        logger: DatumLogger(enabled: false),
      ).execute(),
      // Generation succeeds, execution hits a missing column — the whole
      // transaction (DDL + DML) must roll back.
      runtimeFailingChain: () => [
        SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
          ColumnOperation.transform(
            'priority',
            (value, row) => value,
            sqlExpression: 'no_such_column + 1',
          ),
        ]),
      ],
      destroy: () async {
        db?.dispose();
        db = null;
        await dir.delete(recursive: true);
      },
    );
  }

  // --- Migration deep-dive: hive (raw-map rewrites) ------------------------
  {
    Directory? dir;
    registerMigrationSuite(
      backend: 'hive',
      bench: bench,
      createAdapter: (storeName) async {
        if (dir == null) {
          dir = await Directory.systemTemp.createTemp('datum_mig_hive');
          Hive.init('${dir!.path}/hive');
        }
        final adapter = HiveLocalAdapter<BenchItem>(
          entityBoxName: '${storeName}_${DateTime.now().microsecondsSinceEpoch}',
          fromMap: BenchItem.fromMap,
        );
        await adapter.initialize();
        return adapter;
      },
      migrate: (adapter, storeName, chain, targetVersion) => MigrationExecutor<BenchItem>(
        localAdapter: adapter,
        migrations: chain,
        targetVersion: targetVersion,
        logger: DatumLogger(enabled: false),
      ).execute(),
      // The closure blows up on a specific row — snapshot restore must kick in.
      runtimeFailingChain: () => [
        SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
          ColumnOperation.transform(
            'priority',
            (value, row) => (value as int) == 5 ? throw StateError('poison row') : value,
          ),
        ]),
      ],
      destroy: () async {
        await dir?.delete(recursive: true);
        dir = null;
      },
    );
  }

  // --- Performance: incremental sync at scale (cursor-based delta) ---------
  group('Performance · incremental sync at scale (sqlite + cursor delta)', () {
    const scaleRows = 500;
    const changedRows = 10;
    final ctx = SuiteContext();

    setUpAll(() async {
      bench.section = 'scale';
      ctx.dir = await Directory.systemTemp.createTemp('datum_scale');
      ctx.server = LocalSyncServer();
      await ctx.server.start();
      ctx.connectivity = TestConnectivityChecker();
      ctx.database = sql.sqlite3.open('${ctx.dir.path}/scale.db');
      ctx.local = SqliteLocalAdapter<BenchItem>(
        database: ctx.database!,
        table: 'scale_items',
        fromMap: BenchItem.fromMap,
        columns: const {'title': 'TEXT', 'priority': 'INTEGER', 'done': 'BOOLEAN'},
      );
      final result = await Datum.initialize(
        config: DatumConfig<BenchItem>(enableLogging: false),
        connectivityChecker: ctx.connectivity,
        registrations: [
          DatumRegistration<BenchItem>(
            localAdapter: ctx.local,
            // The cursor-capable adapter — the engine prefers the /changes
            // feed over timestamps or full pulls once a cursor is stored.
            remoteAdapter: CursorHttpRemoteAdapter<BenchItem>(baseUri: ctx.server.baseUri, fromMap: BenchItem.fromMap),
          ),
        ],
      );
      expect(result.isSuccess(), isTrue, reason: '${result.errorOrNull}');
      ctx.manager = Datum.manager<BenchItem>();
    });

    tearDownAll(() async {
      try {
        await Datum.instance.dispose().timeout(const Duration(seconds: 30));
      } on StateError {
        Datum.resetForTesting();
      }
      await ctx.server.stop();
      ctx.database?.dispose();
      await ctx.dir.delete(recursive: true);
    });

    testWidgets('baseline: $scaleRows-row dataset full sync', (tester) async {
      final items = [for (var i = 0; i < scaleRows; i++) make('s$i', title: 'scale $i', priority: i % 7)];
      await bench.run('local write ($scaleRows rows)', () => ctx.manager.saveMany(items: items, userId: 'u1'), ops: scaleRows);
      final result = await bench.run('full sync push ($scaleRows ops)', () => ctx.manager.synchronize('u1'), ops: scaleRows);
      expect(result.failedCount, 0);
      expect(ctx.server.storage['u1']?.length, scaleRows);
    });

    testWidgets('cursor delta pulls only the $changedRows changed rows', (tester) async {
      final seeder = await ctx.seeder();
      for (var i = 0; i < changedRows; i++) {
        final current = (await ctx.local.read('s$i', userId: 'u1'))!;
        await seeder.update(current.copyWith(
          title: 'delta $i',
          version: current.version + 1,
          modifiedAt: DateTime.now().add(const Duration(seconds: 2)),
        ));
      }
      ctx.server.pokeMetadata('u1');

      final mark = ctx.server.requestLog.length;
      final result = await bench.run(
        'cursor delta pull ($changedRows of $scaleRows)',
        () => ctx.manager.synchronize('u1'),
        ops: changedRows,
      );
      expect(result.failedCount, 0);
      for (var i = 0; i < changedRows; i++) {
        expect((await ctx.local.read('s$i', userId: 'u1'))?.title, 'delta $i');
      }
      final requests = ctx.server.requestLog.sublist(mark);
      expect(requests.any((r) => r.startsWith('GET /changes')), isTrue,
          reason: 'the delta cycle must use the cursor change feed');
      expect(requests.contains('GET /entities'), isFalse,
          reason: 'no full-table pull once a cursor is established');
    });

    testWidgets('idle cycle stays flat with $scaleRows rows', (tester) async {
      final mark = ctx.server.requestLog.length;
      final result = await bench.run('idle cycle at $scaleRows rows', () => ctx.manager.synchronize('u1'));
      expect(result.failedCount, 0);
      expect(result.syncedCount, 0);
      expect(ctx.server.requestLog.length - mark, lessThanOrEqualTo(4),
          reason: 'an idle cycle must stay O(1) in requests regardless of dataset size');
    });
  });

  group('CRDT · collaborative text (backend-independent)', () {
    testWidgets('RgaText typing and two-replica merge converge', (tester) async {
      bench.section = 'crdt';
      var doc = RgaText(replicaId: 'device-a');
      await bench.run('RgaText append (300 chars)', () async {
        for (var i = 0; i < 300; i++) {
          doc = doc.insert(doc.length, 'x');
        }
      }, ops: 300);
      expect(doc.length, 300);

      var other = RgaText.fromMap(doc.toMap(), replicaId: 'device-b');
      doc = doc.insert(0, 'A');
      other = other.insert(other.length, 'B');
      await bench.run('RgaText merge (divergent replicas)', () async {
        doc = doc.merge(other);
        other = other.merge(doc);
      });
      expect(doc.value, other.value);
      expect(doc.value.startsWith('A'), isTrue);
      expect(doc.value.endsWith('B'), isTrue);
    });
  });

  group('report', () {
    testWidgets('publish benchmark table', (tester) async {
      bench.printReport();
      binding.reportData = {'datum_e2e_benchmarks': bench.toReport()};
    });
  });
}
