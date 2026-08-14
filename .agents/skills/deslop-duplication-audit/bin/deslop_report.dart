import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:deslop_duplication_audit/deslop_report.dart';

ArgParser _buildParser() {
  return ArgParser()
    ..addOption('dir', abbr: 'C', help: 'Target repository directory to scan.')
    ..addOption(
      'report',
      help: 'Path to an existing report.json (skips running Deslop CLI).',
    )
    ..addOption(
      'top',
      defaultsTo: '10',
      help: 'Number of top duplicate clusters to display.',
    )
    ..addOption(
      'min-nodes',
      defaultsTo: '30',
      help: 'Minimum AST subtree node count passed to Deslop.',
    )
    ..addOption(
      'out-dir',
      help: 'Custom directory to store rendered Deslop reports.',
    )
    ..addOption(
      'category',
      defaultsTo: 'all',
      allowed: ['all', 'logic', 'data'],
      help: 'Filter clusters by category.',
    )
    ..addOption(
      'bucket',
      defaultsTo: 'all',
      allowed: [
        'all',
        'identical',
        'nearly_identical',
        'structural_only',
        'loosely_similar',
        'same_behavior',
      ],
      help: 'Filter clusters by bucket.',
    )
    ..addOption(
      'diff-cmd',
      help:
          'Command to execute to obtain unified diff (e.g. "jj diff" or "git diff").',
    )
    ..addOption('diff-file', help: 'Path to a file containing a unified diff.')
    ..addOption(
      'diff',
      help: 'Literal unified diff string to filter clusters against.',
    )
    ..addOption(
      'touched-files',
      help:
          'Comma-separated list of modified file paths to filter clusters against.',
    )
    ..addFlag(
      'only-changed',
      defaultsTo: false,
      negatable: true,
      help:
          'Only report clusters that intersect with changed lines or touched files in the diff.',
    )
    ..addFlag(
      'files',
      defaultsTo: true,
      negatable: true,
      help: 'Include the per-file duplication table in output.',
    )
    ..addFlag(
      'clusters',
      defaultsTo: true,
      negatable: true,
      help: 'Include the clusters list in output.',
    )
    ..addFlag(
      'json',
      defaultsTo: false,
      negatable: false,
      help:
          'Output filtered report as machine-readable JSON instead of Markdown.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );
}

Future<(DeslopReport, String?)> _resolveReport({
  required String? reportJsonPath,
  required String targetDir,
  required String? outDir,
  required int minNodes,
}) async {
  if (reportJsonPath != null) {
    final report = await loadReportJson(reportJsonPath);
    final htmlCandidate = reportJsonPath.replaceAll(
      RegExp(r'\.json$'),
      '.html',
    );
    final htmlReportPath = File(htmlCandidate).existsSync()
        ? htmlCandidate
        : null;
    return (report, htmlReportPath);
  }

  String? outputPrefix;
  if (outDir != null) {
    final dir = Directory(outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    outputPrefix = '${dir.path}${Platform.pathSeparator}report';
  }

  final result = await runDeslopScan(
    targetDir: targetDir,
    outputPrefix: outputPrefix,
    minNodes: minNodes,
  );

  return (result.report, result.htmlPath);
}

void _emitOutput({
  required DeslopReport report,
  required String? htmlReportPath,
  required String targetDir,
  required Map<String, List<LineSpan>> changedRanges,
  required bool onlyChanged,
  required ArgResults results,
}) {
  final outputJson = results.flag('json');

  if (outputJson) {
    var outputReport = report;
    if (onlyChanged && changedRanges.isNotEmpty) {
      final filtered = report.clusters
          .where((c) => c.intersectsDiff(changedRanges))
          .toList();
      outputReport = DeslopReport(
        toolVersion: report.toolVersion,
        minNodes: report.minNodes,
        filesAnalysed: report.filesAnalysed,
        clustersHidden: report.clustersHidden,
        metrics: report.metrics,
        actionHints: report.actionHints,
        clusters: filtered,
      );
    }
    const encoder = JsonEncoder.withIndent('  ');
    print(encoder.convert(outputReport.toJson()));
    return;
  }

  final markdown = formatDeslopMarkdown(
    report: report,
    targetDir: targetDir,
    htmlReportPath: htmlReportPath,
    topCount: int.tryParse(results.option('top') ?? '10') ?? 10,
    categoryFilter: results.option('category') ?? 'all',
    bucketFilter: results.option('bucket') ?? 'all',
    includeFileTable: results.flag('files'),
    includeClusters: results.flag('clusters'),
    changedRanges: changedRanges,
    onlyChangedCode: onlyChanged,
  );
  print(markdown);
}

void main(List<String> args) async {
  final parser = _buildParser();
  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (results.flag('help')) {
    print('Deslop Duplication Audit Report Generator\n');
    print(
      'Usage: dart run skills/deslop-duplication-audit/bin/deslop_report.dart [options] [target_dir]\n',
    );
    print(parser.usage);
    exit(0);
  }

  final targetDir =
      results.option('dir') ??
      (results.rest.isNotEmpty ? results.rest.first : Directory.current.path);

  final explicitOnlyChanged = results.wasParsed('only-changed')
      ? results.flag('only-changed')
      : null;

  try {
    final changedRanges = await resolveDiffRanges(
      diffCmd: results.option('diff-cmd'),
      diffFilePath: results.option('diff-file'),
      diffString: results.option('diff'),
      touchedFilesString: results.option('touched-files'),
      workingDir: targetDir,
    );

    final hasDiffArg =
        results.wasParsed('diff-cmd') ||
        results.wasParsed('diff-file') ||
        results.wasParsed('diff') ||
        results.wasParsed('touched-files');
    final onlyChanged =
        explicitOnlyChanged ?? (hasDiffArg || changedRanges.isNotEmpty);

    final (report, htmlReportPath) = await _resolveReport(
      reportJsonPath: results.option('report'),
      targetDir: targetDir,
      outDir: results.option('out-dir'),
      minNodes: int.tryParse(results.option('min-nodes') ?? '30') ?? 30,
    );

    _emitOutput(
      report: report,
      htmlReportPath: htmlReportPath,
      targetDir: targetDir,
      changedRanges: changedRanges,
      onlyChanged: onlyChanged,
      results: results,
    );
  } catch (e, st) {
    stderr.writeln('Error: $e');
    if (Platform.environment['DEBUG'] == 'true') {
      stderr.writeln(st);
    }
    exit(1);
  }
}
