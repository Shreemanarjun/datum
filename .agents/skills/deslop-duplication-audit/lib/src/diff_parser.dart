/// Utilities for parsing unified diffs and extracting modified line ranges.
library;

/// Represents an inclusive 1-based line span `[start, end]`.
class LineSpan {
  final int start;
  final int end;

  const LineSpan(this.start, this.end) : assert(start <= end);

  /// Checks if this line span overlaps with another `[otherStart, otherEnd]` range.
  bool overlaps(int otherStart, int otherEnd) {
    return start <= otherEnd && end >= otherStart;
  }

  /// Checks if a single 1-based line number falls within this span.
  bool contains(int line) => line >= start && line <= end;

  @override
  String toString() => start == end ? 'L$start' : 'L$start-$end';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final _gitPrefixRegex = RegExp(r'^[a-z]/');

/// Normalizes a file path for robust cross-tool diff matching.
String normalizeFilePath(String path) {
  var p = path.trim().replaceAll('\\', '/');
  // Strip leading prefixes commonly found in git diffs: a/, b/, c/, i/, w/
  if (_gitPrefixRegex.hasMatch(p)) {
    p = p.substring(2);
  }
  // Strip leading slashes
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  return p;
}

/// Checks if a cluster occurrence path matches a diff file path.
bool pathsMatch(String occurrencePath, String diffPath) {
  final normOcc = normalizeFilePath(occurrencePath);
  final normDiff = normalizeFilePath(diffPath);

  if (normOcc == normDiff) return true;
  if (normOcc.endsWith('/$normDiff') || normDiff.endsWith('/$normOcc')) {
    return true;
  }

  final occBase = normOcc.split('/').last;
  final diffBase = normDiff.split('/').last;
  if (occBase.isNotEmpty && occBase == diffBase) {
    if (normOcc == diffBase || normDiff == occBase) {
      return true;
    }
  }

  return false;
}

String? _extractFilePathFromHeader(String line) {
  if (line.startsWith('+++ ')) {
    final rawPath = line.substring(4).trim();
    return rawPath == '/dev/null' ? null : normalizeFilePath(rawPath);
  }

  if (line.startsWith('Modified regular file ') ||
      line.startsWith('Added regular file ')) {
    final colonIdx = line.lastIndexOf(':');
    if (colonIdx > 0) {
      final prefixLen = line.indexOf('file ') + 5;
      final rawPath = line.substring(prefixLen, colonIdx).trim();
      return normalizeFilePath(rawPath);
    }
  }

  return null;
}

final _hunkHeaderRegex = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@');

LineSpan? _parseHunkHeader(String line) {
  if (!line.startsWith('@@ ')) return null;
  final match = _hunkHeaderRegex.firstMatch(line);
  if (match == null) return null;

  final newStart = int.parse(match.group(1)!);
  final countStr = match.group(2);
  final newCount = countStr != null ? int.parse(countStr) : 1;

  if (newCount <= 0) return null;
  return LineSpan(newStart, newStart + newCount - 1);
}

List<LineSpan> _mergeLineSpans(List<LineSpan> spans) {
  if (spans.isEmpty) return const [];
  final sorted = List<LineSpan>.from(spans)
    ..sort((a, b) => a.start.compareTo(b.start));
  final merged = <LineSpan>[sorted.first];

  for (var j = 1; j < sorted.length; j++) {
    final current = sorted[j];
    final last = merged.last;

    if (current.start <= last.end + 1) {
      final newEnd = current.end > last.end ? current.end : last.end;
      merged[merged.length - 1] = LineSpan(last.start, newEnd);
    } else {
      merged.add(current);
    }
  }
  return merged;
}

/// Parses a unified diff string and returns a map of `{ normalizedPath: List<LineSpan> }`
/// containing all added/modified line ranges in the new version of each file.
// TODO(kevmoo): Simplify/delegate to upstream if https://github.com/Nimblesite/Deslop/issues/364 lands native --diff support.
Map<String, List<LineSpan>> parseUnifiedDiff(String diffContent) {
  final rawResult = <String, List<LineSpan>>{};
  final lines = diffContent.split('\n');

  String? currentFile;

  for (final line in lines) {
    final headerFile = _extractFilePathFromHeader(line);
    if (headerFile != null) {
      currentFile = headerFile;
      rawResult.putIfAbsent(currentFile, () => []);
      continue;
    } else if (line.startsWith('+++ /dev/null')) {
      currentFile = null;
      continue;
    }

    final span = _parseHunkHeader(line);
    if (span != null && currentFile != null) {
      rawResult[currentFile]!.add(span);
    }
  }

  final mergedResult = <String, List<LineSpan>>{};
  for (final entry in rawResult.entries) {
    mergedResult[entry.key] = _mergeLineSpans(entry.value);
  }

  return mergedResult;
}

/// Converts a list of file paths into a changed ranges map covering all lines (1..max).
Map<String, List<LineSpan>> createTouchedFilesMap(List<String> filePaths) {
  final result = <String, List<LineSpan>>{};
  for (final path in filePaths) {
    final norm = normalizeFilePath(path);
    if (norm.isNotEmpty) {
      result[norm] = [const LineSpan(1, 2147483647)];
    }
  }
  return result;
}
