import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart';

/// The sync-stack suite over datum's own InMemoryLocalAdapter against every
/// bundled remote (in-memory, HTTP timestamp delta, HTTP cursor feed). The
/// in-memory local cannot be reopened, so crash cases skip.
void main() {
  runSyncConformanceMatrix(
    name: 'InMemoryLocal',
    createLocal: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
