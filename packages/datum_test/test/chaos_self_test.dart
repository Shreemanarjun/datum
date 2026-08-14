import 'package:datum/datum.dart';
import 'package:datum_test/src/chaos_profiles.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:test/test.dart';

/// Self-test: the chaos conformance suite run over datum's own reference
/// stack (InMemoryLocalAdapter + HttpRemoteAdapter over LocalSyncServer).
/// Every stock profile must inject at least one fault and the stack must
/// still converge once the profile clears.
void main() {
  final observedFaults = <String, int>{};

  tearDownAll(() {
    // Per-profile injected-fault counts, for the test log.
    // ignore: avoid_print
    print('[chaos] injected fault counts: $observedFaults');
  });

  runChaosConformanceTests(
    name: 'InMemory + HTTP',
    createLocal: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
    onFaultsObserved: (profile, faults) => observedFaults[profile] = faults,
  );
}
