import 'package:datum/datum.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:datum_test/src/performance_report.dart';

/// The performance suite run over datum's own reference adapter — report-only
/// (no ops/sec thresholds), so it stays green on any CI machine.
void main() {
  runAdapterPerformanceTests(
    name: 'InMemoryLocalAdapter',
    createLocal: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
    entityCount: 300,
  );
}
