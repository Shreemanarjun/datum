/// Release-UX guard: every symbol a user needs for the documented feature
/// set must be nameable through the ONE import `package:datum/datum.dart`.
///
/// This file deliberately references each release-critical type/member so a
/// missing barrel export becomes a COMPILE failure here, not a support
/// issue after publishing. (The sibling `public_api_test.dart` pins the
/// export LIST; this test proves the exported surface actually covers the
/// advertised API.)
library;

import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  test('release-critical symbols are reachable from the single barrel import', () {
    // Core setup surface.
    expect(DatumConfig, isNotNull);
    expect(DatumConfigPresets.production(), isA<DatumConfig>());
    expect(DatumConfigPresets.development(), isA<DatumConfig>());
    expect(InMemoryDatumPersistence.new, isNotNull);
    expect(InMemoryDatumPersistence(), isA<DatumPersistence>());

    // Typed schema layer.
    expect(DatumFieldSpec, isNotNull);
    expect(DatumSchema, isNotNull);
    expect(DatumFieldCodec.dateTimeIso, isNotNull);
    expect(datumCoreFieldSpecs<DatumEntity>(), isA<DatumCoreFields<DatumEntity>>());

    // Typed relations layer.
    expect(DatumRelationKind.values, contains(DatumRelationKind.manyToMany));
    expect(DatumRelationSpec, isNotNull);
    expect(CascadeDeleteBehavior.values, contains(CascadeDeleteBehavior.restrict));

    // Query surface.
    const query = DatumQuery(
      filters: [
        CompositeFilter([Filter('a', FilterOperator.equals, 1)], LogicalOperator.or),
      ],
      sorting: [SortDescriptor('a', nullSortOrder: NullSortOrder.first)],
    );
    expect(query.toSql('t').sql, isNotEmpty);
    expect(DatumQueryBuilder<DatumEntity>().build(), isA<DatumQuery>());
    expect(DatumQueryMatcher.apply<DatumEntity>(const [], const DatumQuery()), isEmpty);

    // Cascade delete surface.
    expect(const CascadeOptions(timeout: Duration(seconds: 5)), isNotNull);
    expect(CascadeSuccess, isNotNull);
    expect(CascadeFailure, isNotNull);
    expect(CascadeDeleteResult, isNotNull);

    // Sync capabilities and metadata.
    expect(DeltaSyncCapable, isNotNull);
    expect(CursorSyncCapable, isNotNull);
    expect(SchemaFingerprintCapable, isNotNull);
    expect(SqlSchemaCapable, isNotNull);
    expect(DatumSyncEngine.syncCursorKey, '__sync_cursor__');
    expect(const DatumSyncMetadata(userId: 'u').serverTimestamp, isNull);

    // Conflict resolution surface.
    const resolver = CRDTResolver<DatumEntity>();
    expect(resolver.name, 'CRDTMerge');
    expect(
      const DatumConflictResolution<DatumEntity>.abort('x').strategy,
      DatumResolutionStrategy.abort,
    );

    // CRDT toolkit.
    expect(const PNCounter().increment('r').value, 1);
    expect(const ORSet<int>().add(1, 't').value, {1});
    expect(const RgaList<String>(replicaId: 'r').insert(0, 'a').value, ['a']);
    expect(RgaText(replicaId: 'r').insert(0, 'hi').value, 'hi');
    expect(const VectorClock({'d': 1}).increment('d').toMap(), {'d': 2});

    // Migration surface.
    expect(SchemaMigration, isNotNull);
    expect(AutoMigrationExecutor, isNotNull);
    expect(diffSchema, isNotNull);
    expect(kReservedColumnNames, contains('userId'));

    // Adapters & errors.
    expect(InMemoryLocalAdapter, isNotNull);
    expect(const EntityNotFoundException(message: 'x'), isA<DatumException>());
    expect(SchemaReadException, isNotNull);
  });
}
