/// Shared helpers for driving the [DatumGenerator] through build_test's
/// `testBuilder` with real package sources.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:datum_generator/datum_generator.dart';
import 'package:test/test.dart';

/// Asset id of the primary test input.
const String inputAssetId = 'a|lib/example.dart';

/// Asset id of the generated shared-part output.
const String outputAssetId = 'a|lib/example.datum.g.part';

/// Minimal stand-in for `package:datum` so entity supertypes resolve.
///
/// The generator only inspects supertype *names* (`RelationalDatumEntity`)
/// and field types, so a tiny stub keeps tests fast and hermetic.
const String datumStubSource = '''
library datum;

enum MapTarget { local, remote }

abstract class DatumEntityInterface {
  const DatumEntityInterface();
}

abstract class DatumEntity implements DatumEntityInterface {
  const DatumEntity();
}

abstract class RelationalDatumEntity extends DatumEntity {
  const RelationalDatumEntity();
}

class Relation {
  const Relation();
}

class DatumQueryBuilder<T> {
  const DatumQueryBuilder();
}
''';

/// Stub for the Flutter types the generator special-cases by display name.
const String uiStubSource = '''
library ui_stub;

class Color {
  final int value;
  const Color(this.value);
  int toARGB32() => value;
}

class Offset {
  final double dx;
  final double dy;
  const Offset(this.dx, this.dy);
}
''';

Map<String, String>? _cachedBaseAssets;

Future<String> _readPackageFile(String packageUri) async {
  final uri = await Isolate.resolvePackageUri(Uri.parse(packageUri));
  return File.fromUri(uri!).readAsString();
}

/// Real datum_generator sources (annotations + utils) plus supporting stubs,
/// keyed by asset id.
Future<Map<String, String>> baseAssets() async {
  if (_cachedBaseAssets != null) return _cachedBaseAssets!;
  _cachedBaseAssets = {
    'datum_generator|lib/annotations.dart': await _readPackageFile(
      'package:datum_generator/annotations.dart',
    ),
    'datum_generator|lib/src/core/annotations.dart': await _readPackageFile(
      'package:datum_generator/src/core/annotations.dart',
    ),
    'datum_generator|lib/src/utils/json_utils.dart': await _readPackageFile(
      'package:datum_generator/src/utils/json_utils.dart',
    ),
    'meta|lib/meta_meta.dart': await _readPackageFile(
      'package:meta/meta_meta.dart',
    ),
    'datum|lib/datum.dart': datumStubSource,
    'ui_stub|lib/ui_stub.dart': uiStubSource,
  };
  return _cachedBaseAssets!;
}

/// Collapses all whitespace runs to single spaces so `contains` matching is
/// robust to dart_style line wrapping.
String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Strips ALL whitespace and commas, so `contains` matching survives any
/// dart_style line-wrapping / trailing-comma decision.
String dense(String s) => s.replaceAll(RegExp(r'[\s,]+'), '');

/// Matcher: the (String) actual contains [expected], ignoring all whitespace.
Matcher containsCode(String expected) => predicate<String>(
  (actual) => dense(actual).contains(dense(expected)),
  'contains code (whitespace-insensitive): $expected',
);

/// Result of one generator run.
class GenerationResult {
  final TestBuilderResult builderResult;
  final String? output;

  /// Captured build log records (dynamically typed to avoid a direct
  /// dependency on package:logging).
  final List<Object> logs;

  GenerationResult(this.builderResult, this.output, this.logs);

  bool get succeeded => builderResult.succeeded;

  /// Whitespace-normalized output (empty string when no output was produced).
  String get normalized => output == null ? '' : norm(output!);

  List<String> get errors => builderResult.errors.toList();

  Iterable<String> get logMessages =>
      logs.map((l) => (l as dynamic).message as String);
}

/// Runs the datum builder over [source] (placed at [inputAssetId]).
///
/// [overrideAssets] can replace base assets (e.g. swap the annotations
/// library for a stripped variant to exercise fallback branches).
Future<GenerationResult> generate(
  String source, {
  Map<String, String>? overrideAssets,
}) async {
  final assets = <String, Object>{
    ...await baseAssets(),
    ...?overrideAssets,
    inputAssetId: source,
  };
  final logs = <Object>[];
  final result = await testBuilder(
    datumBuilder(BuilderOptions.empty),
    assets,
    rootPackage: 'a',
    generateFor: {inputAssetId},
    onLog: logs.add,
  );
  String? output;
  final candidates = [
    AssetId.parse(outputAssetId),
    AssetId('a', '.dart_tool/build/generated/a/lib/example.datum.g.part'),
  ];
  for (final id in candidates) {
    if (result.readerWriter.testing.exists(id)) {
      output = result.readerWriter.testing.readString(id);
      break;
    }
  }
  return GenerationResult(result, output, logs);
}
