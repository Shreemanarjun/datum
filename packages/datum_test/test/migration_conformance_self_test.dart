import 'package:datum/datum.dart';
import 'package:datum_test/src/conformance_entity.dart';
import 'package:datum_test/src/migration_conformance.dart';

/// The migration conformance suite certifying datum's own reference adapter
/// (map path; in-memory storage has no persistence, so no reopenLocal).
void main() {
  runMigrationConformanceTests(
    name: 'InMemoryLocalAdapter',
    createLocal: () async {
      final adapter = InMemoryLocalAdapter<ConformanceEntity>(
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );
}
