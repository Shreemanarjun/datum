// Datum performance micro-benchmarks.
//
// A dependency-free, pure-Dart benchmark suite that exercises the real,
// CPU-bound hot paths of the `datum` core engine. These are the operations the
// sync engine spends most of its time in for every entity it pushes, pulls,
// hashes, or queries.
//
// Run with:
//   dart run benchmark/datum_benchmark.dart
//   dart run benchmark/datum_benchmark.dart --scale=4   # 4x iterations
//   dart run benchmark/datum_benchmark.dart --json      # machine-readable output
//
// The harness warms up each case (to let the JIT settle), then measures a fixed
// number of iterations and reports ops/sec and ns/op. Numbers are only
// comparable on the same machine/run; use them to catch regressions, not as
// absolute guarantees. See benchmark/README.md for the full strategy and the
// Tier-B (end-to-end manager/sync) benchmarks described in the test plan.

import 'dart:convert';

import 'package:datum/datum.dart';
// LRUCache is an internal utility (not exported from the barrel), imported
// directly so we can benchmark it. If it is ever promoted to the public API,
// switch this to `package:datum/datum.dart`.
import 'package:datum/source/core/utils/lru_cache.dart';

// ---------------------------------------------------------------------------
// Minimal benchmark harness (no external benchmark_harness dependency).
// ---------------------------------------------------------------------------

class BenchResult {
  BenchResult(this.name, this.iterations, this.elapsedMicros);
  final String name;
  final int iterations;
  final int elapsedMicros;

  double get opsPerSec => iterations / (elapsedMicros / 1e6);
  double get nsPerOp => (elapsedMicros * 1000) / iterations;

  Map<String, Object> toJson() => {
        'name': name,
        'iterations': iterations,
        'elapsed_us': elapsedMicros,
        'ops_per_sec': opsPerSec.round(),
        'ns_per_op': nsPerOp.round(),
      };
}

/// Runs [body] [iterations] times after [warmup] warmup iterations and returns
/// the measured wall-clock result.
BenchResult bench(
  String name,
  int iterations,
  void Function() body, {
  int? warmup,
}) {
  final warmupCount = warmup ?? (iterations ~/ 10).clamp(1, 100000);
  for (var i = 0; i < warmupCount; i++) {
    body();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  sw.stop();
  return BenchResult(name, iterations, sw.elapsedMicroseconds);
}

void printTable(List<BenchResult> results) {
  const nameW = 42;
  const opsW = 16;
  const nsW = 14;
  String pad(String s, int w) => s.length >= w ? s : s + ' ' * (w - s.length);
  String padl(String s, int w) => s.length >= w ? s : ' ' * (w - s.length) + s;

  final sep = '${'-' * nameW}  ${'-' * opsW}  ${'-' * nsW}';
  print(sep);
  print('${pad('benchmark', nameW)}  ${padl('ops/sec', opsW)}  ${padl('ns/op', nsW)}');
  print(sep);
  for (final r in results) {
    final ops = _grouped(r.opsPerSec.round());
    final ns = _grouped(r.nsPerOp.round());
    print('${pad(r.name, nameW)}  ${padl(ops, opsW)}  ${padl(ns, nsW)}');
  }
  print(sep);
}

String _grouped(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// A representative entity, written the way generated `.g.dart` code wires up a
// real DatumEntity (toDatumMap / diff / fromMap). Exercises the serialization
// hot path the sync engine hits for every item.
// ---------------------------------------------------------------------------

class BenchTask extends DatumEntity {
  const BenchTask({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.priority,
    required this.completed,
    required this.tags,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  factory BenchTask.fromMap(Map<String, dynamic> map) => BenchTask(
        id: map['id'] as String? ?? '',
        userId: map['userId'] as String? ?? '',
        title: map['title'] as String? ?? '',
        description: map['description'] as String? ?? '',
        priority: map['priority'] as int? ?? 0,
        completed: map['completed'] as bool? ?? false,
        tags: (map['tags'] as List?)?.cast<String>() ?? const [],
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(map['modifiedAt'] as int? ?? 0),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
        version: map['version'] as int? ?? 0,
        isDeleted: map['isDeleted'] as bool? ?? false,
      );

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final String description;
  final int priority;
  final bool completed;
  final List<String> tags;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'description': description,
        'priority': priority,
        'completed': completed,
        'tags': tags,
        'modifiedAt': target == MapTarget.remote ? modifiedAt.toIso8601String() : modifiedAt.millisecondsSinceEpoch,
        'createdAt': target == MapTarget.remote ? createdAt.toIso8601String() : createdAt.millisecondsSinceEpoch,
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! BenchTask) return toDatumMap(target: MapTarget.remote);
    final d = <String, dynamic>{};
    if (title != oldVersion.title) d['title'] = title;
    if (description != oldVersion.description) d['description'] = description;
    if (priority != oldVersion.priority) d['priority'] = priority;
    if (completed != oldVersion.completed) d['completed'] = completed;
    if (!_listEq(tags, oldVersion.tags)) d['tags'] = tags;
    return d.isEmpty ? null : d;
  }

  BenchTask copyWith({String? title, int? priority, bool? completed}) => BenchTask(
        id: id,
        userId: userId,
        title: title ?? this.title,
        description: description,
        priority: priority ?? this.priority,
        completed: completed ?? this.completed,
        tags: tags,
        modifiedAt: modifiedAt,
        createdAt: createdAt,
        version: version + 1,
        isDeleted: isDeleted,
      );

  @override
  List<Object?> get props => [...super.props, title, description, priority, completed, tags];

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

BenchTask makeTask(int i) => BenchTask(
      id: 'task-$i',
      userId: 'user-${i % 8}',
      title: 'Task number $i',
      description: 'A reasonably sized description for entity number $i used to make serialization realistic.',
      priority: i % 5,
      completed: i.isEven,
      tags: ['tag-${i % 3}', 'tag-${i % 7}', 'priority-${i % 5}'],
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1690000000000 + i * 1000),
      version: 1 + (i % 10),
    );

// ---------------------------------------------------------------------------
// Benchmark cases.
// ---------------------------------------------------------------------------

List<BenchResult> run(int scale) {
  final results = <BenchResult>[];

  // --- Serialization hot path -------------------------------------------------
  final task = makeTask(42);
  final taskRemoteMap = task.toDatumMap(target: MapTarget.remote);
  final localMap = task.toDatumMap();

  results.add(bench('entity.toDatumMap (local)', 1000000 * scale, () {
    task.toDatumMap();
  }));
  results.add(bench('entity.toDatumMap (remote)', 1000000 * scale, () {
    task.toDatumMap(target: MapTarget.remote);
  }));
  results.add(bench('entity.fromMap', 1000000 * scale, () {
    BenchTask.fromMap(localMap);
  }));
  results.add(bench('jsonEncode(toDatumMap remote)', 500000 * scale, () {
    jsonEncode(taskRemoteMap);
  }));

  // --- Diff (change detection on update) -------------------------------------
  final original = makeTask(42);
  final changed = original.copyWith(title: 'Renamed', priority: 4);
  results.add(bench('entity.diff (changed)', 1000000 * scale, () {
    changed.diff(original);
  }));
  results.add(bench('entity.diff (no change)', 1000000 * scale, () {
    original.diff(original);
  }));

  // --- Vector clock (causality tracking) -------------------------------------
  const clockA = VectorClock({'device-a': 5, 'device-b': 3, 'device-c': 9});
  const clockB = VectorClock({'device-b': 7, 'device-c': 2, 'device-d': 4});
  results.add(bench('VectorClock.increment', 2000000 * scale, () {
    clockA.increment('device-a');
  }));
  results.add(bench('VectorClock.merge', 1000000 * scale, () {
    clockA.merge(clockB);
  }));
  results.add(bench('VectorClock.isConcurrent', 2000000 * scale, () {
    clockA.isConcurrent(clockB);
  }));

  // --- Query building + SQL conversion ---------------------------------------
  results.add(bench('DatumQueryBuilder build (4 filters)', 500000 * scale, () {
    (DatumQueryBuilder<BenchTask>()
          ..where('completed', isEqualTo: false)
          ..where('priority', isGreaterThanOrEqualTo: 2)
          ..where('userId', isEqualTo: 'user-1')
          ..orderBy('priority', descending: true)
          ..limit(50))
        .build();
  }));

  final query = (DatumQueryBuilder<BenchTask>()
        ..where('completed', isEqualTo: false)
        ..where('priority', isGreaterThanOrEqualTo: 2)
        ..where('userId', isEqualTo: 'user-1')
        ..orderBy('priority', descending: true)
        ..limit(50))
      .build();
  results.add(bench('DatumQuery.toSql (sqlite)', 500000 * scale, () {
    query.toSql('tasks');
  }));
  results.add(bench('DatumQuery.toSql (postgres)', 500000 * scale, () {
    query.toSql('tasks', dialect: SqlDialect.postgresql);
  }));

  // --- Data-integrity hashing (used during sync to detect drift) -------------
  const hasher = DatumHashGenerator();
  for (final n in [10, 100, 1000]) {
    final batch = List.generate(n, makeTask);
    final iters = (200000 ~/ n) * scale;
    results.add(bench('DatumHashGenerator.hashEntities (n=$n)', iters, () {
      hasher.hashEntities(batch);
    }));
  }

  // Phase 4: order-independent (no sort) + incremental hashing.
  final batch1000 = List.generate(1000, makeTask);
  results.add(bench('hashEntitiesUnordered (n=1000)', 200 * scale, () {
    hasher.hashEntitiesUnordered(batch1000);
  }));
  // One incremental update (remove old + add new) is O(1) — independent of the
  // 1000-entity set size — versus the full O(n) rehash above.
  final rolling = DatumRollingHash()..addAll(batch1000);
  final item = makeTask(500);
  results.add(bench('DatumRollingHash update (set=1000)', 500000 * scale, () {
    rolling
      ..remove(item)
      ..add(item);
  }));

  // --- LRU cache (relationship + query result caching) -----------------------
  final cache = LRUCache<String, int>(1000);
  for (var i = 0; i < 1000; i++) {
    cache.put('k$i', i);
  }
  var counter = 0;
  results.add(bench('LRUCache.put (eviction)', 2000000 * scale, () {
    cache.put('k${counter++ % 2000}', counter);
  }));
  results.add(bench('LRUCache.get (hit)', 5000000 * scale, () {
    cache.get('k500');
  }));

  return results;
}

void main(List<String> args) {
  var scale = 1;
  var asJson = false;
  for (final a in args) {
    if (a.startsWith('--scale=')) {
      scale = int.tryParse(a.substring('--scale='.length)) ?? 1;
    } else if (a == '--json') {
      asJson = true;
    }
  }
  if (scale < 1) scale = 1;

  final results = run(scale);

  if (asJson) {
    print(const JsonEncoder.withIndent('  ').convert({
      'scale': scale,
      'results': results.map((r) => r.toJson()).toList(),
    }));
    return;
  }

  print('');
  print('Datum core micro-benchmarks  (scale=$scale)');
  print('Higher ops/sec is better; lower ns/op is better.');
  print('');
  printTable(results);
  print('');
  print('Note: micro-benchmarks measure isolated CPU hot paths, not end-to-end');
  print('sync latency. See benchmark/README.md for the Tier-B manager/sync plan.');
}
