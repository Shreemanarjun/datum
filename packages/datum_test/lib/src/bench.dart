import 'dart:math' as math;

/// Whether this process is an AOT-compiled executable (`dart compile exe`)
/// rather than the JIT VM (`dart run`).
const bool isAot = bool.fromEnvironment('dart.vm.product');

/// Summary statistics over repeated timings of one benchmark case.
class BenchStats {
  BenchStats(this.name, List<double> samplesMs)
      : samplesMs = List.unmodifiable([...samplesMs]..sort());

  final String name;

  /// Per-run timings in milliseconds, ascending.
  final List<double> samplesMs;

  int get runs => samplesMs.length;
  double get min => samplesMs.first;
  double get max => samplesMs.last;
  double get mean => samplesMs.reduce((a, b) => a + b) / runs;
  double get median => runs.isOdd
      ? samplesMs[runs ~/ 2]
      : (samplesMs[runs ~/ 2 - 1] + samplesMs[runs ~/ 2]) / 2;

  /// Sample standard deviation (0 for a single run).
  double get stdev {
    if (runs < 2) return 0;
    final m = mean;
    return math.sqrt(samplesMs.map((s) => (s - m) * (s - m)).reduce((a, b) => a + b) / (runs - 1));
  }

  static const header = '| case | mode | runs | mean ms | median ms | min ms | stdev ms |\n'
      '|---|---|---:|---:|---:|---:|---:|';

  String get row {
    String f(double v) => v.toStringAsFixed(2);
    return '| $name | ${isAot ? 'AOT' : 'JIT'} | $runs | ${f(mean)} | ${f(median)} | ${f(min)} | ${f(stdev)} |';
  }
}

/// Times [measure] [runs] times after [warmup] untimed runs.
///
/// [measure] does its own setup and returns only the duration of the part
/// under test, so per-run fixtures never pollute the numbers.
Future<BenchStats> bench(
  String name,
  Future<Duration> Function() measure, {
  int runs = 5,
  int warmup = 1,
}) async {
  for (var i = 0; i < warmup; i++) {
    await measure();
  }
  return BenchStats(name, [
    for (var i = 0; i < runs; i++) (await measure()).inMicroseconds / 1000,
  ]);
}

/// Parses `--runs 3,5,10` (default [fallback]) from [args].
List<int> parseRuns(List<String> args, {List<int> fallback = const [3, 10]}) {
  final i = args.indexOf('--runs');
  if (i < 0 || i + 1 >= args.length) return fallback;
  return args[i + 1].split(',').map(int.parse).toList();
}

/// Runs every case once per requested run count and prints a markdown table.
Future<void> runBenchSuite(
  String title,
  List<String> args,
  Map<String, Future<Duration> Function()> cases,
) async {
  print('\n### $title (${isAot ? 'AOT' : 'JIT'})\n');
  print(BenchStats.header);
  for (final runs in parseRuns(args)) {
    for (final MapEntry(:key, :value) in cases.entries) {
      print((await bench(key, value, runs: runs)).row);
    }
  }
}
