import 'package:test/test.dart';

import '../tool/snippet_check.dart' as checker;

/// Every ```dart fence in content/**/*.md must compile — see
/// tool/snippet_check.dart for the snippet contract.
void main() {
  test('all documentation snippets compile', () async {
    expect(await checker.runCheck(), 0, reason: 'see analyzer output above');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
