import 'package:datum/datum.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:datum_test/src/convergence_fuzz.dart';

/// Self-test: the convergence fuzz suite run over datum's own reference stack
/// (InMemoryLocalAdapter over LocalSyncServer). Seeded random multi-device
/// workloads must always converge after quiescence — in BOTH pull modes:
/// full pulls (maximal convergence checking) and the cursor change feed
/// (incremental pulls whose sequence numbers deliver late stale writes).
void main() {
  Future<LocalAdapter<ConformanceEntity>> createLocal() async {
    final adapter = InMemoryLocalAdapter<ConformanceEntity>(
      fromMap: ConformanceEntity.fromMap,
    );
    await adapter.initialize();
    return adapter;
  }

  runConvergenceFuzzTests(
    name: 'InMemory + HTTP (full pulls)',
    createLocal: createLocal,
  );

  runConvergenceFuzzTests(
    name: 'InMemory + HTTP (cursor feed)',
    createLocal: createLocal,
    useCursorFeed: true,
  );
}
