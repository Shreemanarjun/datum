import 'dart:math' as math;

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// One timed phase of [measureAdapterPerformance].
class PerformancePhase {
  const PerformancePhase({
    required this.name,
    required this.operations,
    required this.elapsed,
  });

  /// Phase name: `create`, `readAll`, `readById`, `query`, `patch`, `delete`.
  final String name;

  /// Verified operations completed in this phase (bulk phases like `readAll`
  /// and `query` count as one operation).
  final int operations;

  /// Wall-clock time the phase took.
  final Duration elapsed;

  /// Throughput in operations per second.
  double get opsPerSec => operations == 0
      ? 0
      : operations * 1e6 / math.max(elapsed.inMicroseconds, 1);
}

/// The result of [measureAdapterPerformance]: per-phase timings and an
/// aligned text table via [printTable].
class AdapterPerformanceReport {
  AdapterPerformanceReport({
    required this.adapterName,
    required this.entityCount,
    required List<PerformancePhase> phases,
  }) : phases = List.unmodifiable(phases);

  /// The adapter's self-reported [LocalAdapter.name].
  final String adapterName;

  /// The `entityCount` the measurement ran with.
  final int entityCount;

  /// Measured phases, in execution order.
  final List<PerformancePhase> phases;

  /// The phase named [name]; throws [ArgumentError] for unknown names.
  PerformancePhase phase(String name) => phases.firstWhere(
    (p) => p.name == name,
    orElse: () => throw ArgumentError.value(
      name,
      'name',
      'unknown phase; expected one of: ${phases.map((p) => p.name).join(', ')}',
    ),
  );

  static String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);

  /// The report as an aligned text table.
  String renderTable() {
    const columns = ['phase', 'ops', 'elapsed (ms)', 'ops/sec'];
    final rows = [
      for (final p in phases)
        [
          p.name,
          '${p.operations}',
          _ms(p.elapsed),
          p.opsPerSec.toStringAsFixed(1),
        ],
    ];
    final widths = [
      for (var c = 0; c < columns.length; c++)
        [columns[c].length, ...rows.map((r) => r[c].length)].reduce(math.max),
    ];
    String line(List<String> cells) => [
      cells[0].padRight(widths[0]),
      for (var c = 1; c < cells.length; c++) cells[c].padLeft(widths[c]),
    ].join('  ');

    final divider = ''.padRight(
      widths.reduce((a, b) => a + b) + 2 * (columns.length - 1),
      '-',
    );
    return [
      '$adapterName performance ($entityCount entities)',
      divider,
      line(columns),
      divider,
      for (final row in rows) line(row),
      divider,
    ].join('\n');
  }

  /// Prints [renderTable] to stdout.
  void printTable() => print(renderTable());
}

void _verify(bool condition, String message) {
  if (!condition) {
    throw StateError(
      'Adapter performance measurement failed integrity check: $message',
    );
  }
}

/// Measures [adapter]'s throughput across the standard CRUD phases and
/// returns an [AdapterPerformanceReport].
///
/// Phases (in order, each timed with a [Stopwatch]):
///
/// 1. `create`  — [entityCount] individual `create` calls
/// 2. `readAll` — one `readAll` over the full data set
/// 3. `readById` — [entityCount] individual `read` calls
/// 4. `query`   — one `DatumQuery` (`value >= entityCount / 2`, ordered by
///    `value`)
/// 5. `patch`   — `entityCount ~/ 10` partial updates
/// 6. `delete`  — `entityCount ~/ 10` deletes
///
/// Every phase's results are verified (row counts, query ordering, delete
/// acknowledgements); a mismatch throws [StateError] so a broken adapter
/// cannot produce a plausible-looking report. The adapter should be freshly
/// created and empty; it is NOT disposed by this function.
Future<AdapterPerformanceReport> measureAdapterPerformance({
  required LocalAdapter<ConformanceEntity> adapter,
  int entityCount = 1000,
}) async {
  if (entityCount < 10) {
    throw ArgumentError.value(
      entityCount,
      'entityCount',
      'must be at least 10 (patch/delete run entityCount ~/ 10 operations)',
    );
  }

  const userId = 'perf-user';
  final ids = [
    for (var i = 0; i < entityCount; i++)
      'perf-${i.toString().padLeft(7, '0')}',
  ];
  final phases = <PerformancePhase>[];
  final stopwatch = Stopwatch();

  // 1. create x N
  stopwatch.start();
  for (var i = 0; i < entityCount; i++) {
    await adapter.create(
      ConformanceEntity.make(
        ids[i],
        userId: userId,
        name: 'perf entity $i',
        value: i,
      ),
    );
  }
  stopwatch.stop();
  phases.add(
    PerformancePhase(
      name: 'create',
      operations: entityCount,
      elapsed: stopwatch.elapsed,
    ),
  );

  // 2. readAll
  stopwatch
    ..reset()
    ..start();
  final all = await adapter.readAll(userId: userId);
  stopwatch.stop();
  _verify(
    all.length == entityCount,
    'readAll returned ${all.length} of $entityCount entities',
  );
  phases.add(
    PerformancePhase(
      name: 'readAll',
      operations: 1,
      elapsed: stopwatch.elapsed,
    ),
  );

  // 3. read by id x N
  stopwatch
    ..reset()
    ..start();
  var found = 0;
  for (final id in ids) {
    if (await adapter.read(id, userId: userId) != null) found++;
  }
  stopwatch.stop();
  _verify(
    found == entityCount,
    'read-by-id found $found of $entityCount entities',
  );
  phases.add(
    PerformancePhase(
      name: 'readById',
      operations: found,
      elapsed: stopwatch.elapsed,
    ),
  );

  // 4. query: value >= N/2, ordered by value
  final threshold = entityCount ~/ 2;
  final query =
      (DatumQueryBuilder<ConformanceEntity>()
            ..where('value', isGreaterThanOrEqualTo: threshold)
            ..orderBy('value'))
          .build();
  stopwatch
    ..reset()
    ..start();
  final matched = await adapter.query(query, userId: userId);
  stopwatch.stop();
  _verify(
    matched.length == entityCount - threshold,
    'query matched ${matched.length} entities, expected ${entityCount - threshold}',
  );
  _verify(
    matched.first.value == threshold && matched.last.value == entityCount - 1,
    'query results not ordered by value ascending '
    '(first: ${matched.first.value}, last: ${matched.last.value})',
  );
  phases.add(
    PerformancePhase(name: 'query', operations: 1, elapsed: stopwatch.elapsed),
  );

  // 5. patch x N/10
  final patchCount = entityCount ~/ 10;
  stopwatch
    ..reset()
    ..start();
  for (var i = 0; i < patchCount; i++) {
    final patched = await adapter.patch(
      id: ids[i],
      delta: {'name': 'patched $i'},
      userId: userId,
    );
    _verify(
      patched.name == 'patched $i',
      'patch of ${ids[i]} did not apply the delta',
    );
  }
  stopwatch.stop();
  phases.add(
    PerformancePhase(
      name: 'patch',
      operations: patchCount,
      elapsed: stopwatch.elapsed,
    ),
  );

  // 6. delete x N/10
  final deleteCount = entityCount ~/ 10;
  stopwatch
    ..reset()
    ..start();
  var deleted = 0;
  for (var i = 0; i < deleteCount; i++) {
    if (await adapter.delete(ids[i], userId: userId)) deleted++;
  }
  stopwatch.stop();
  _verify(
    deleted == deleteCount,
    'delete acknowledged $deleted of $deleteCount entities',
  );
  phases.add(
    PerformancePhase(
      name: 'delete',
      operations: deleted,
      elapsed: stopwatch.elapsed,
    ),
  );

  return AdapterPerformanceReport(
    adapterName: adapter.name,
    entityCount: entityCount,
    phases: phases,
  );
}

/// Registers a test that measures [createLocal]'s adapter with
/// [measureAdapterPerformance], prints the table, and asserts every phase
/// completed its expected operation count.
///
/// By default the test is report-only (CI-safe: no machine-dependent
/// throughput assertions). Pass [minOpsPerSec] — phase name to minimum
/// ops/sec — to additionally enforce thresholds:
///
/// ```dart
/// runAdapterPerformanceTests(
///   name: 'InMemoryLocalAdapter',
///   createLocal: () async { ... },
///   minOpsPerSec: {'create': 1000, 'readById': 5000},
/// );
/// ```
void runAdapterPerformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  int entityCount = 500,
  Map<String, double>? minOpsPerSec,
}) {
  group('$name performance', () {
    test(
      'completes every phase over $entityCount entities',
      () async {
        final adapter = await createLocal();
        addTearDown(adapter.dispose);

        final report = await measureAdapterPerformance(
          adapter: adapter,
          entityCount: entityCount,
        );
        report.printTable();

        expect(report.phase('create').operations, entityCount);
        expect(report.phase('readAll').operations, 1);
        expect(report.phase('readById').operations, entityCount);
        expect(report.phase('query').operations, 1);
        expect(report.phase('patch').operations, entityCount ~/ 10);
        expect(report.phase('delete').operations, entityCount ~/ 10);

        if (minOpsPerSec != null) {
          for (final MapEntry(key: phaseName, value: minimum)
              in minOpsPerSec.entries) {
            expect(
              report.phase(phaseName).opsPerSec,
              greaterThanOrEqualTo(minimum),
              reason:
                  'phase "$phaseName" fell below the $minimum ops/sec threshold',
            );
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
