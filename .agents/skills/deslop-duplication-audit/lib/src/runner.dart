/// Orchestrates the discovery and execution of the Deslop CLI binary.
library;

import 'dart:convert';
import 'dart:io';

import 'diff_parser.dart';
import 'models.dart';

/// Result from executing a Deslop CLI scan.
class DeslopRunResult {
  final String targetDir;
  final String outputPrefix;
  final String jsonPath;
  final String txtPath;
  final String htmlPath;
  final DeslopReport report;

  DeslopRunResult({
    required this.targetDir,
    required this.outputPrefix,
    required this.jsonPath,
    required this.txtPath,
    required this.htmlPath,
    required this.report,
  });
}

/// Locates the `deslop` binary on `$PATH` or common installation paths.
String? findDeslopExecutable() {
  // 1. Check if deslop is already available on PATH
  final envPath = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  final paths = envPath.split(separator);

  final exeName = Platform.isWindows ? 'deslop.exe' : 'deslop';

  for (final dir in paths) {
    if (dir.trim().isEmpty) continue;
    final candidate = File(
      dir.endsWith(Platform.pathSeparator)
          ? '$dir$exeName'
          : '$dir${Platform.pathSeparator}$exeName',
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }

  // 2. Check common known locations
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (home.isNotEmpty) {
    final candidatePaths = [
      '$home/.cargo/bin/$exeName',
      '$home/.local/share/mise/shims/$exeName',
      '/opt/homebrew/bin/$exeName',
      '/usr/local/bin/$exeName',
    ];

    for (final path in candidatePaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }
  }

  return null;
}

/// Runs a Deslop scan over [targetDir] and parses the generated report.
Future<DeslopRunResult> runDeslopScan({
  required String targetDir,
  String? outputPrefix,
  int minNodes = 30,
  String? configPath,
}) async {
  final targetDirectory = Directory(targetDir);
  if (!targetDirectory.existsSync()) {
    throw FileSystemException(
      'Target directory does not exist',
      targetDirectory.path,
    );
  }

  final executable = findDeslopExecutable();
  if (executable == null) {
    throw StateError(
      'Could not find "deslop" executable on PATH or common installation directories.\n'
      'Install via: cargo install deslop (or cargo binstall deslop / mise use -g github:Nimblesite/deslop@latest)',
    );
  }

  // Determine output prefix
  final effectiveOutputPrefix =
      outputPrefix ??
      '${Directory.systemTemp.createTempSync('deslop_').path}${Platform.pathSeparator}report';

  final parentDir = File(effectiveOutputPrefix).parent;
  if (!parentDir.existsSync()) {
    parentDir.createSync(recursive: true);
  }

  final args = <String>[
    targetDirectory.path,
    '--output',
    effectiveOutputPrefix,
    '--min-nodes',
    minNodes.toString(),
    '--no-incremental',
    '--no-fail-over',
    '--log-to-console',
    '--log-level',
    'warn',
  ];

  if (configPath != null && configPath.isNotEmpty) {
    args.addAll(['--config', configPath]);
  }

  final result = await Process.run(executable, args);
  if (result.exitCode != 0 && result.exitCode != 3) {
    // Note: exitCode 3 is fail-over threshold if tripped, but we passed --no-fail-over
    throw ProcessException(
      executable,
      args,
      'deslop failed with exit code ${result.exitCode}:\n${result.stderr}\n${result.stdout}',
      result.exitCode,
    );
  }

  final jsonFile = File('$effectiveOutputPrefix.json');
  if (!jsonFile.existsSync()) {
    throw StateError(
      'Deslop finished but JSON report was not found at ${jsonFile.path}',
    );
  }

  final jsonContent = await jsonFile.readAsString();
  final dynamic parsed = jsonDecode(jsonContent);
  if (parsed is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object root in Deslop report');
  }

  final report = DeslopReport.fromJson(parsed);

  return DeslopRunResult(
    targetDir: targetDirectory.path,
    outputPrefix: effectiveOutputPrefix,
    jsonPath: jsonFile.path,
    txtPath: '$effectiveOutputPrefix.txt',
    htmlPath: '$effectiveOutputPrefix.html',
    report: report,
  );
}

/// Loads and parses an existing Deslop JSON report file.
Future<DeslopReport> loadReportJson(String filePath) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('Report JSON file does not exist', filePath);
  }
  final jsonContent = await file.readAsString();
  final dynamic parsed = jsonDecode(jsonContent);
  if (parsed is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object root in Deslop report');
  }
  return DeslopReport.fromJson(parsed);
}

/// Resolves changed line ranges from a diff command, diff file, literal diff string, or list of touched files.
Future<Map<String, List<LineSpan>>> resolveDiffRanges({
  String? diffCmd,
  String? diffFilePath,
  String? diffString,
  String? touchedFilesString,
  String? workingDir,
}) async {
  if (diffCmd != null && diffCmd.trim().isNotEmpty) {
    final parts = diffCmd.trim().split(RegExp(r'\s+'));
    final exe = parts.first;
    final cmdArgs = parts.sublist(1);
    final res = await Process.run(
      exe,
      cmdArgs,
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (res.exitCode != 0) {
      throw ProcessException(
        exe,
        cmdArgs,
        'diff command failed with exit code ${res.exitCode}:\n${res.stderr}',
        res.exitCode,
      );
    }
    return parseUnifiedDiff(res.stdout as String);
  }

  if (diffFilePath != null && diffFilePath.trim().isNotEmpty) {
    final file = File(diffFilePath);
    if (!file.existsSync()) {
      throw FileSystemException('Diff file does not exist', diffFilePath);
    }
    return parseUnifiedDiff(await file.readAsString());
  }

  if (diffString != null && diffString.trim().isNotEmpty) {
    return parseUnifiedDiff(diffString);
  }

  if (touchedFilesString != null && touchedFilesString.trim().isNotEmpty) {
    final files = touchedFilesString
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return createTouchedFilesMap(files);
  }

  return {};
}
