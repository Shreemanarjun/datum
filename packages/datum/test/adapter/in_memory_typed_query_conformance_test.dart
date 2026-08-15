import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart';

/// InMemoryLocalAdapter certified by the typed-query conformance suite —
/// typed specs, string queries, and the reference evaluation must agree.
void main() {
  runTypedQueryConformanceTests(
    name: 'InMemoryLocalAdapter',
    createLocal: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(fromMap: ConformanceEntity.fromMap);
      await adapter.initialize();
      return adapter;
    },
    destroyLocal: (adapter) => adapter.dispose(),
  );
}
