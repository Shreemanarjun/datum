import 'dart:io';

import 'package:test/test.dart';

/// Keeps `doc/SYNC_SCENARIOS.md` true: every test it names exists in the
/// suite it names, and every section id is written in that suite.
void main() {
  test('every scenario in doc/SYNC_SCENARIOS.md names a test that exists', () {
    String? id;
    String? suite;
    var named = 0;
    for (final line in File('doc/SYNC_SCENARIOS.md').readAsLinesSync()) {
      final heading = RegExp(r'^## ([a-z.]+): ').firstMatch(line);
      if (heading != null) {
        id = heading.group(1);
        suite = null;
        continue;
      }
      final path = RegExp(r'^Suite: `([^`]+)`').firstMatch(line)?.group(1);
      if (path != null) {
        // Suite paths are relative to `packages/`.
        final source = File('../$path').readAsStringSync();
        expect(source, contains('// Scenarios: $id '), reason: '$path does not carry the id of the section that describes it');
        // A test name may be written as adjacent string literals.
        suite = source.replaceAll(RegExp(r"'\s*\n\s*'"), '');
        continue;
      }
      final name = RegExp(r'^- `(.+)`$').firstMatch(line)?.group(1);
      if (name == null || suite == null) continue;
      expect(suite, contains("'$name'"), reason: 'section $id names a test that is gone');
      named++;
    }
    expect(named, greaterThan(100), reason: 'the document lost its test lists');
  });
}
