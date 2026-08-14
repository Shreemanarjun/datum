// Verifies that every ```dart snippet in content/**/*.md compiles.
//
// For each markdown page this extracts the Dart fences and emits one
// generated library under tool/.snippets_gen/, then runs `dart analyze` over
// the folder. Compile errors in any snippet fail the check (and the
// `dart test` wrapper in test/snippets_test.dart).
//
// Snippet contract for docs authors:
//  - A fence is either a DECLARATION block (its first code line starts a
//    class/mixin/enum/extension/typedef/main/annotation) — emitted at
//    library level — or a USAGE block (statements), wrapped in an async
//    function that receives the well-known bindings from
//    tool/snippet_scaffold.dart (`manager`, `datum`, `task`, `userId`, …).
//  - `import` lines anywhere in a fence are hoisted to the page's imports.
//  - Fences importing SDKs outside the ecosystem (supabase, firebase, isar,
//    flutter, …) are skipped automatically and reported.
//  - Mark a fence ```dart no-verify to skip it explicitly (pseudo-code).
//
// Run directly: dart tool/snippet_check.dart
import 'dart:io';

const _genDirPath = 'tool/.snippets_gen';

/// Imports the scratch context can actually resolve.
const _resolvablePrefixes = ['dart:', 'package:datum/', 'package:datum_sqlite/', 'package:datum_test/'];

/// Well-known bindings injected into usage snippets (see snippet_scaffold.dart).
const _bindings = <String, String>{
  'manager': 'DatumManager<Task>',
  'datum': 'Datum',
  'task': 'Task',
  'entity': 'Task',
  'userId': 'String',
  'config': 'DatumConfig<Task>',
  'localAdapter': 'LocalAdapter<Task>',
  'remoteAdapter': 'RemoteAdapter<Task>',
  'server': 'LocalSyncServer',
  'logger': 'DatumLogger',
  'db': 'Database',
};

final _declarationStart = RegExp(r'^(@|class |abstract |sealed |base |final class |mixin |enum |extension |typedef |void main|Future<void> main|library[ ;])');

class Snippet {
  Snippet(this.page, this.index, this.info, this.lines);
  final String page;
  final int index;
  final String info;
  final List<String> lines;
}

List<Snippet> extractSnippets(File file) {
  final snippets = <Snippet>[];
  List<String>? current;
  String info = '';
  var index = 0;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trimLeft();
    if (current == null && trimmed.startsWith('```')) {
      info = trimmed.substring(3).trim();
      current = [];
    } else if (current != null && trimmed.startsWith('```')) {
      final tokens = info.split(RegExp(r'\s+'));
      if (tokens.first == 'dart') {
        snippets.add(Snippet(file.path, index++, info, current));
      }
      current = null;
    } else {
      current?.add(line);
    }
  }
  return snippets;
}

String _sanitize(String path) => path.replaceAll(RegExp(r'^content/|\.md$'), '').replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');

/// One generated compilation unit: a snippet plus any `continue`-flagged
/// follow-up snippets from the same page.
class _Unit {
  final imports = <String>{};
  final body = StringBuffer();
  int snippets = 0;
}

({List<String> sources, int verified, List<String> skipped}) generatePage(String page, List<Snippet> snippets) {
  final units = <_Unit>[];
  final skipped = <String>[];
  var verified = 0;

  for (final snippet in snippets) {
    final label = '${snippet.page} snippet #${snippet.index + 1}';
    if (snippet.info.contains('no-verify')) {
      skipped.add('$label (no-verify)');
      continue;
    }
    final code = <String>[];
    final blockImports = <String>{};
    var external = false;
    for (final line in snippet.lines) {
      final t = line.trim();
      if (t.startsWith('import ')) {
        if (_resolvablePrefixes.any((p) => t.contains("'$p") || t.contains('"$p'))) {
          blockImports.add(t);
        } else {
          external = true;
          break;
        }
      } else {
        code.add(line);
      }
    }
    if (external) {
      skipped.add('$label (external SDK import)');
      continue;
    }
    while (code.isNotEmpty && code.first.trim().isEmpty) {
      code.removeAt(0);
    }
    if (code.isEmpty) continue;

    verified++;
    // `continue` chains this snippet into the previous unit so progressive
    // tutorials can reference declarations from earlier fences; otherwise
    // every snippet is an isolated unit (same-named classes in different
    // fences never collide).
    final unit = (snippet.info.contains('continue') && units.isNotEmpty) ? units.last : (units..add(_Unit())).last;
    unit.imports.addAll(blockImports);
    final firstCodeLine = code.firstWhere((l) => l.trim().isNotEmpty && !l.trim().startsWith('//'), orElse: () => code.first).trim();
    unit.body.writeln('// --- ${snippet.page} #${snippet.index + 1} ---');
    if (_declarationStart.hasMatch(firstCodeLine)) {
      unit.body.writeln(code.join('\n'));
    } else {
      final params = _bindings.entries
          .where((b) => RegExp('\\b${b.key}\\b').hasMatch(code.join('\n')))
          .where((b) => !RegExp('\\b(final|var|late|const)\\b[^=;\\n]*\\b${b.key}\\b\\s*=').hasMatch(code.join('\n')))
          .map((b) => '${b.value} ${b.key}')
          .join(', ');
      unit.body.writeln('Future<void> snippet${snippet.index + 1}($params) async {');
      unit.body.writeln(code.join('\n'));
      unit.body.writeln('}');
    }
    unit.body.writeln();
  }

  final sources = <String>[];
  for (final unit in units) {
    final header = StringBuffer()
      ..writeln('// GENERATED by tool/snippet_check.dart — do not edit.')
      ..writeln('// Source: $page')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln('// ignore_for_file: unused_local_variable, unused_element, unused_import, dead_code, unused_field')
      ..writeln("import '../snippet_scaffold.dart';");
    for (final import in unit.imports) {
      header.writeln(import);
    }
    sources.add('$header\n${unit.body}');
  }
  return (sources: sources, verified: verified, skipped: skipped);
}

Future<int> runCheck({bool verbose = true}) async {
  final genDir = Directory(_genDirPath);
  if (genDir.existsSync()) genDir.deleteSync(recursive: true);
  genDir.createSync(recursive: true);

  final pages = Directory('content').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md')).toList()..sort((a, b) => a.path.compareTo(b.path));

  var totalVerified = 0;
  final allSkipped = <String>[];
  for (final page in pages) {
    final snippets = extractSnippets(page);
    if (snippets.isEmpty) continue;
    final result = generatePage(page.path, snippets);
    totalVerified += result.verified;
    allSkipped.addAll(result.skipped);
    for (final (i, source) in result.sources.indexed) {
      File('$_genDirPath/${_sanitize(page.path)}_u$i.dart').writeAsStringSync(source);
    }
  }

  final analyze = await Process.run('dart', ['analyze', _genDirPath]);
  final ok = analyze.exitCode == 0;
  if (verbose) {
    stdout.writeln('Verified $totalVerified snippet(s) across ${pages.length} pages; ${allSkipped.length} skipped.');
    for (final s in allSkipped) {
      stdout.writeln('  skipped: $s');
    }
    if (!ok) {
      stdout
        ..writeln('--- analyzer output ---')
        ..writeln(analyze.stdout)
        ..writeln(analyze.stderr);
    }
  }
  return ok ? 0 : 1;
}

Future<void> main() async {
  exitCode = await runCheck();
}
