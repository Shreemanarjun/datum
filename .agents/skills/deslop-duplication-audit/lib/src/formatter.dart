/// Formats Deslop duplication reports into token-efficient Markdown summaries.
library;

import 'dart:io';

import 'diff_parser.dart';
import 'models.dart';

String _resolveAbsolutePath(String baseDir, String relativePath) {
  final file = File(relativePath);
  if (file.isAbsolute) {
    return file.absolute.path;
  }
  final combined = baseDir.endsWith(Platform.pathSeparator)
      ? '$baseDir$relativePath'
      : '$baseDir${Platform.pathSeparator}$relativePath';
  return File(combined).absolute.path;
}

/// Formats the summary overview header. Returns true if early exit (e.g. clean delta).
bool _writeOverviewHeader(
  StringBuffer buffer, {
  required DeslopReport report,
  required List<DeslopCluster> candidateClusters,
  required bool hasDiffFilter,
  required Map<String, List<LineSpan>>? changedRanges,
  required String? htmlReportPath,
}) {
  if (hasDiffFilter) {
    buffer.writeln('### 🔬 Deslop Code Duplication Report (CL Delta)');
    buffer.writeln();

    if (candidateClusters.isEmpty) {
      buffer.writeln(
        '* **Status**: ✅ **Clean** — 0 duplicate code clusters detected in modified code.',
      );
      if (report.clusters.isNotEmpty) {
        buffer.writeln(
          '* _Note: ${report.clusters.length} pre-existing cluster(s) in package outside modified lines._',
        );
      }
      return true;
    }

    final newCount = candidateClusters
        .where((c) => c.isNewlyIntroduced(changedRanges!))
        .length;
    final crossCount = candidateClusters.length - newCount;

    buffer.writeln(
      '* **Duplication in Changed Code**: **${candidateClusters.length} cluster(s)** intersect modified code.',
    );
    if (newCount > 0) {
      buffer.writeln(
        '  * ⚠️ **$newCount newly introduced clone(s)** (all copies within CL changes)',
      );
    }
    if (crossCount > 0) {
      buffer.writeln(
        '  * ℹ️ **$crossCount cross-file clone(s)** (CL changes share code with existing files)',
      );
    }
  } else {
    final totalLoc = report.metrics.analysedLoc;
    final dupLoc = report.metrics.duplicatedLoc;
    final dupPercent = report.metrics.duplicationPercent.toStringAsFixed(1);
    final totalFiles = report.filesAnalysed;
    final dupFiles = report.metrics.duplicatedFiles;
    final totalClusters = report.metrics.clustersTotal;

    buffer.writeln('### 🔬 Deslop Code Duplication Report');
    buffer.writeln();
    buffer.writeln(
      '* **Duplication Score**: **$dupPercent%** ($dupLoc / $totalLoc LOC across $dupFiles / $totalFiles files)',
    );

    final breakdown = _buildBucketBreakdown(candidateClusters);
    final breakdownText = breakdown.isNotEmpty ? ' ($breakdown)' : '';
    buffer.writeln('* **Total Clusters**: $totalClusters$breakdownText');
  }

  if (htmlReportPath != null && File(htmlReportPath).existsSync()) {
    final htmlUri = Uri.file(File(htmlReportPath).absolute.path).toString();
    buffer.writeln('* **Interactive HTML Report**: [report.html]($htmlUri)');
  }

  buffer.writeln();
  return false;
}

String _buildBucketBreakdown(List<DeslopCluster> clusters) {
  final bucketCounts = <String, int>{};
  for (final cluster in clusters) {
    bucketCounts[cluster.bucket] = (bucketCounts[cluster.bucket] ?? 0) + 1;
  }

  final parts = <String>[];
  if (bucketCounts.containsKey('identical')) {
    parts.add('${bucketCounts['identical']} identical [Type-1/2]');
  }
  if (bucketCounts.containsKey('nearly_identical')) {
    parts.add('${bucketCounts['nearly_identical']} near-identical [Type-3]');
  }
  if (bucketCounts.containsKey('structural_only')) {
    parts.add(
      '${bucketCounts['structural_only']} structural-only shape matches',
    );
  }
  if (bucketCounts.containsKey('loosely_similar')) {
    parts.add('${bucketCounts['loosely_similar']} loosely similar');
  }
  if (bucketCounts.containsKey('same_behavior')) {
    parts.add('${bucketCounts['same_behavior']} AI semantic matches');
  }
  return parts.join(', ');
}

List<DeslopCluster> _filterClusters(
  List<DeslopCluster> clusters,
  String categoryFilter,
  String bucketFilter,
) {
  var filtered = List<DeslopCluster>.of(clusters);
  if (categoryFilter != 'all') {
    filtered = filtered.where((c) => c.category == categoryFilter).toList();
  }
  if (bucketFilter != 'all') {
    filtered = filtered.where((c) => c.bucket == bucketFilter).toList();
  }
  filtered.sort((a, b) => b.weight.compareTo(a.weight));
  return filtered;
}

void _renderClusterOccurrence(
  StringBuffer buffer,
  ClusterOccurrence occ,
  String absTargetDir,
  bool hasDiffFilter,
  Map<String, List<LineSpan>>? changedRanges,
) {
  final relPath = occ.path;
  final absFilePath = _resolveAbsolutePath(absTargetDir, relPath);
  final lineSuffix = occ.lineSpan;
  final linkText = '$relPath:$lineSuffix';
  final targetUrl = '${Uri.file(absFilePath)}#$lineSuffix';

  var statusBadge = '';
  if (hasDiffFilter) {
    statusBadge = occ.intersectsDiff(changedRanges!)
        ? ' `[CL Modified]`'
        : ' `[Existing Code]`';
  }

  buffer.writeln('* [$linkText]($targetUrl)$statusBadge');
}

void _renderClustersSection(
  StringBuffer buffer, {
  required List<DeslopCluster> candidateClusters,
  required String absTargetDir,
  required int topCount,
  required String categoryFilter,
  required String bucketFilter,
  required bool hasDiffFilter,
  required Map<String, List<LineSpan>>? changedRanges,
}) {
  final filteredClusters = _filterClusters(
    candidateClusters,
    categoryFilter,
    bucketFilter,
  );

  if (filteredClusters.isEmpty) {
    buffer.writeln('_No duplicate clusters match the specified filters._');
    buffer.writeln();
    return;
  }

  final sectionTitle = hasDiffFilter
      ? '#### Duplication Clusters Affecting Changed Code'
      : '#### Top Duplication Clusters (Ranked by Weight & Potential Savings)';
  buffer.writeln(sectionTitle);
  buffer.writeln();

  final displayClusters = filteredClusters.take(topCount).toList();

  for (var i = 0; i < displayClusters.length; i++) {
    final c = displayClusters[i];
    final rank = i + 1;
    final weightStr = c.weight.toStringAsFixed(1);
    final categoryTag = c.category == 'data' ? ' [Data Table]' : '';
    final isNewTag = hasDiffFilter && c.isNewlyIntroduced(changedRanges!)
        ? ' ⚠️ [New in CL]'
        : '';

    buffer.writeln(
      '**#$rank ${c.bucketLabel}$categoryTag$isNewTag** — ${c.size} copies · ${c.canonicalNodeCount} AST nodes · weight $weightStr',
    );

    if (c.interpretation.isNotEmpty) {
      buffer.writeln('> ${c.interpretation}');
    }

    for (final occ in c.occurrences) {
      _renderClusterOccurrence(
        buffer,
        occ,
        absTargetDir,
        hasDiffFilter,
        changedRanges,
      );
    }
    buffer.writeln();
  }

  if (filteredClusters.length > topCount) {
    final remaining = filteredClusters.length - topCount;
    buffer.writeln(
      '_... $remaining more clusters hidden (use `--top=${filteredClusters.length}` to display all)_',
    );
    buffer.writeln();
  }
}

void _renderFileMetricsTable(
  StringBuffer buffer, {
  required DeslopReport report,
  required String absTargetDir,
  required bool hasDiffFilter,
  required Map<String, List<LineSpan>>? changedRanges,
}) {
  var duplicatedFiles = report.metrics.perFile
      .where((f) => f.duplicatedLoc > 0)
      .toList();

  if (hasDiffFilter) {
    duplicatedFiles = duplicatedFiles
        .where((f) => changedRanges!.keys.any((k) => pathsMatch(f.path, k)))
        .toList();
  }

  duplicatedFiles.sort((a, b) => b.duplicatedLoc.compareTo(a.duplicatedLoc));

  if (duplicatedFiles.isEmpty) return;

  final tableTitle = hasDiffFilter
      ? '#### Modified Files Duplication Metrics'
      : '#### Duplicated Source Files';
  buffer.writeln(tableTitle);
  buffer.writeln();
  buffer.writeln('| File | Duplicated LOC | Total LOC | Duplication % |');
  buffer.writeln('| :--- | :---: | :---: | :---: |');

  for (final file in duplicatedFiles) {
    final relPath = file.path;
    final absFilePath = _resolveAbsolutePath(absTargetDir, relPath);
    final linkText = relPath;
    final targetUrl = Uri.file(absFilePath).toString();
    final filePercent = file.duplicationPercent.toStringAsFixed(1);

    buffer.writeln(
      '| [$linkText]($targetUrl) | ${file.duplicatedLoc} | ${file.analysedLoc} | $filePercent% |',
    );
  }
  buffer.writeln();
}

/// Formats a [DeslopReport] into a high-density, token-efficient Markdown document.
String formatDeslopMarkdown({
  required DeslopReport report,
  required String targetDir,
  String? htmlReportPath,
  int topCount = 10,
  String categoryFilter = 'all',
  String bucketFilter = 'all',
  bool includeFileTable = true,
  bool includeClusters = true,
  Map<String, List<LineSpan>>? changedRanges,
  bool onlyChangedCode = false,
}) {
  final buffer = StringBuffer();
  final absTargetDir = Directory(targetDir).absolute.path;
  final hasDiffFilter = onlyChangedCode && changedRanges != null;

  var candidateClusters = List<DeslopCluster>.of(report.clusters);
  if (hasDiffFilter) {
    candidateClusters = candidateClusters
        .where((c) => c.intersectsDiff(changedRanges))
        .toList();
  }

  final isClean = _writeOverviewHeader(
    buffer,
    report: report,
    candidateClusters: candidateClusters,
    hasDiffFilter: hasDiffFilter,
    changedRanges: changedRanges,
    htmlReportPath: htmlReportPath,
  );

  if (isClean) {
    return buffer.toString().trimRight();
  }

  if (includeClusters) {
    _renderClustersSection(
      buffer,
      candidateClusters: candidateClusters,
      absTargetDir: absTargetDir,
      topCount: topCount,
      categoryFilter: categoryFilter,
      bucketFilter: bucketFilter,
      hasDiffFilter: hasDiffFilter,
      changedRanges: changedRanges,
    );
  }

  if (includeFileTable) {
    _renderFileMetricsTable(
      buffer,
      report: report,
      absTargetDir: absTargetDir,
      hasDiffFilter: hasDiffFilter,
      changedRanges: changedRanges,
    );
  }

  return buffer.toString().trimRight();
}
