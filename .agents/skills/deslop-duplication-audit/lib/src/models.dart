/// Data models representing Deslop duplicate code analysis reports.
library;

import 'diff_parser.dart';

/// Represents the top-level Deslop JSON report structure.
class DeslopReport {
  final String toolVersion;
  final int minNodes;
  final int filesAnalysed;
  final int clustersHidden;
  final DeslopMetrics metrics;
  final List<ActionHint> actionHints;
  final List<DeslopCluster> clusters;

  DeslopReport({
    required this.toolVersion,
    required this.minNodes,
    required this.filesAnalysed,
    required this.clustersHidden,
    required this.metrics,
    required this.actionHints,
    required this.clusters,
  });

  factory DeslopReport.fromJson(Map<String, dynamic> json) {
    final metricsJson = json['metrics'] as Map<String, dynamic>? ?? {};
    final actionHintsList = json['action_hints'] as List<dynamic>? ?? [];
    final clustersList = json['clusters'] as List<dynamic>? ?? [];

    return DeslopReport(
      toolVersion: json['tool_version'] as String? ?? 'unknown',
      minNodes: json['min_nodes'] as int? ?? 30,
      filesAnalysed: json['files_analysed'] as int? ?? 0,
      clustersHidden: json['clusters_hidden'] as int? ?? 0,
      metrics: DeslopMetrics.fromJson(metricsJson),
      actionHints: actionHintsList
          .map((e) => ActionHint.fromJson(e as Map<String, dynamic>))
          .toList(),
      clusters: clustersList
          .map((e) => DeslopCluster.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tool_version': toolVersion,
    'min_nodes': minNodes,
    'files_analysed': filesAnalysed,
    'clusters_hidden': clustersHidden,
    'metrics': metrics.toJson(),
    'action_hints': actionHints.map((e) => e.toJson()).toList(),
    'clusters': clusters.map((e) => e.toJson()).toList(),
  };
}

/// Overall duplication metrics and per-file statistics.
class DeslopMetrics {
  final int analysedLoc;
  final int duplicatedLoc;
  final double duplicationPercent;
  final int clustersTotal;
  final int duplicatedFiles;
  final List<FileMetric> perFile;

  DeslopMetrics({
    required this.analysedLoc,
    required this.duplicatedLoc,
    required this.duplicationPercent,
    required this.clustersTotal,
    required this.duplicatedFiles,
    required this.perFile,
  });

  factory DeslopMetrics.fromJson(Map<String, dynamic> json) {
    final perFileList = json['per_file'] as List<dynamic>? ?? [];
    return DeslopMetrics(
      analysedLoc: json['analysed_loc'] as int? ?? 0,
      duplicatedLoc: json['duplicated_loc'] as int? ?? 0,
      duplicationPercent:
          (json['duplication_percent'] as num?)?.toDouble() ?? 0.0,
      clustersTotal: json['clusters_total'] as int? ?? 0,
      duplicatedFiles: json['duplicated_files'] as int? ?? 0,
      perFile: perFileList
          .map((e) => FileMetric.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'analysed_loc': analysedLoc,
    'duplicated_loc': duplicatedLoc,
    'duplication_percent': duplicationPercent,
    'clusters_total': clustersTotal,
    'duplicated_files': duplicatedFiles,
    'per_file': perFile.map((e) => e.toJson()).toList(),
  };
}

/// Duplication statistics for an individual source file.
class FileMetric {
  final String path;
  final int analysedLoc;
  final int duplicatedLoc;
  final double duplicationPercent;

  FileMetric({
    required this.path,
    required this.analysedLoc,
    required this.duplicatedLoc,
    required this.duplicationPercent,
  });

  factory FileMetric.fromJson(Map<String, dynamic> json) {
    return FileMetric(
      path: json['path'] as String? ?? '',
      analysedLoc: json['analysed_loc'] as int? ?? 0,
      duplicatedLoc: json['duplicated_loc'] as int? ?? 0,
      duplicationPercent:
          (json['duplication_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'analysed_loc': analysedLoc,
    'duplicated_loc': duplicatedLoc,
    'duplication_percent': duplicationPercent,
  };
}

/// Generic action recommendation hint emitted by Deslop.
class ActionHint {
  final String pattern;
  final String recommendation;

  ActionHint({required this.pattern, required this.recommendation});

  factory ActionHint.fromJson(Map<String, dynamic> json) {
    return ActionHint(
      pattern: json['pattern'] as String? ?? '',
      recommendation: json['recommendation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'pattern': pattern,
    'recommendation': recommendation,
  };
}

/// A cluster of duplicated code blocks identified by Deslop.
class DeslopCluster {
  final String id;
  final double weight;
  final int size;
  final int canonicalNodeCount;
  final Map<String, double> signals;
  final String bucket;
  final String category;
  final List<ClusterOccurrence> occurrences;
  final int occurrencesTotal;
  final String summary;
  final String interpretation;

  DeslopCluster({
    required this.id,
    required this.weight,
    required this.size,
    required this.canonicalNodeCount,
    required this.signals,
    required this.bucket,
    required this.category,
    required this.occurrences,
    required this.occurrencesTotal,
    required this.summary,
    required this.interpretation,
  });

  factory DeslopCluster.fromJson(Map<String, dynamic> json) {
    final signalsMap = <String, double>{};
    final rawSignals = json['signals'] as Map<String, dynamic>? ?? {};
    for (final entry in rawSignals.entries) {
      if (entry.value is num) {
        signalsMap[entry.key] = (entry.value as num).toDouble();
      }
    }

    final occList = json['occurrences'] as List<dynamic>? ?? [];

    return DeslopCluster(
      id: json['id'] as String? ?? '',
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      size: json['size'] as int? ?? 0,
      canonicalNodeCount: json['canonical_node_count'] as int? ?? 0,
      signals: signalsMap,
      bucket: json['bucket'] as String? ?? '',
      category: json['category'] as String? ?? 'logic',
      occurrences: occList
          .map((e) => ClusterOccurrence.fromJson(e as Map<String, dynamic>))
          .toList(),
      occurrencesTotal: json['occurrences_total'] as int? ?? occList.length,
      summary: json['summary'] as String? ?? '',
      interpretation: json['interpretation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'weight': weight,
    'size': size,
    'canonical_node_count': canonicalNodeCount,
    'signals': signals,
    'bucket': bucket,
    'category': category,
    'occurrences': occurrences.map((e) => e.toJson()).toList(),
    'occurrences_total': occurrencesTotal,
    'summary': summary,
    'interpretation': interpretation,
  };

  /// Human-readable label for the duplication bucket.
  String get bucketLabel {
    return switch (bucket) {
      'identical' => 'Identical [Type-1/2]',
      'nearly_identical' => 'Nearly Identical [Type-3]',
      'structural_only' => 'Structural-Only',
      'loosely_similar' => 'Loosely Similar',
      'same_behavior' => 'Same Behavior [AI]',
      _ => bucket,
    };
  }

  /// Checks if any occurrence in this cluster intersects with the given diff line ranges.
  bool intersectsDiff(Map<String, List<LineSpan>> changedRanges) {
    if (changedRanges.isEmpty) return false;
    return occurrences.any((occ) => occ.intersectsDiff(changedRanges));
  }

  /// Counts how many occurrences in this cluster intersect with the given diff line ranges.
  int occurrencesIntersectingDiff(Map<String, List<LineSpan>> changedRanges) {
    if (changedRanges.isEmpty) return 0;
    return occurrences.where((occ) => occ.intersectsDiff(changedRanges)).length;
  }

  /// Returns true if all occurrences in this cluster are within modified diff hunks.
  bool isNewlyIntroduced(Map<String, List<LineSpan>> changedRanges) {
    if (changedRanges.isEmpty) return false;
    final intersecting = occurrencesIntersectingDiff(changedRanges);
    return intersecting >= 2 && intersecting == occurrences.length;
  }
}

/// A specific file and line-range occurrence within a duplication cluster.
class ClusterOccurrence {
  final String path;
  final int startByte;
  final int endByte;
  final int startLine;
  final int endLine;
  final bool hidden;

  ClusterOccurrence({
    required this.path,
    required this.startByte,
    required this.endByte,
    required this.startLine,
    required this.endLine,
    required this.hidden,
  });

  factory ClusterOccurrence.fromJson(Map<String, dynamic> json) {
    return ClusterOccurrence(
      path: json['path'] as String? ?? '',
      startByte: json['start_byte'] as int? ?? 0,
      endByte: json['end_byte'] as int? ?? 0,
      startLine: json['start_line'] as int? ?? 1,
      endLine: json['end_line'] as int? ?? 1,
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'start_byte': startByte,
    'end_byte': endByte,
    'start_line': startLine,
    'end_line': endLine,
    'hidden': hidden,
  };

  /// Returns the line span as a string, e.g. `L10-25` or `L10`.
  String get lineSpan =>
      startLine == endLine ? 'L$startLine' : 'L$startLine-$endLine';

  /// Checks if this occurrence intersects with any changed line spans in [changedRanges].
  bool intersectsDiff(Map<String, List<LineSpan>> changedRanges) {
    if (changedRanges.isEmpty) return false;
    for (final entry in changedRanges.entries) {
      if (pathsMatch(path, entry.key)) {
        if (entry.value.any((span) => span.overlaps(startLine, endLine))) {
          return true;
        }
      }
    }
    return false;
  }
}
