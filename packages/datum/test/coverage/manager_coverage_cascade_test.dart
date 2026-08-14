import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../core/non_relational_test_entity.dart';
import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';
import 'manager_coverage_helpers.dart';

/// A relational entity whose relations use a localKey that is absent from its
/// map, so related-entity lookups short-circuit to empty results.
class NullKeyEntity extends RelationalDatumEntity {
  const NullKeyEntity({required this.id, required this.userId});

  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        // Deliberately no 'missing' key.
      };

  @override
  NullKeyEntity copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;

  @override
  Map<String, Relation> get relations => {
        'many': HasMany<TestEntity>(this, 'fk', localKey: 'missing', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        'one': HasOne<TestEntity>(this, 'fk', localKey: 'missing', cascadeDeleteBehavior: CascadeDeleteBehavior.restrict),
        // thisLocalKey is absent from the map, so the ManyToMany lookup
        // short-circuits before ever resolving the pivot manager.
        'm2m': ManyToMany<TestEntity>(
          this,
          Object,
          'fk',
          'otherFk',
          thisLocalKey: 'missing',
          cascadeDeleteBehavior: CascadeDeleteBehavior.cascade,
        ),
      };
}

void main() {
  group('cascadeDelete on non-relational entities', () {
    late FlakyLocalAdapter<NonRelationalTestEntity> localAdapter;
    late DatumManager<NonRelationalTestEntity> manager;

    NonRelationalTestEntity entity(String id) => NonRelationalTestEntity(
          id: id,
          userId: 'u1',
          name: 'n-$id',
          modifiedAt: DateTime(2024),
          createdAt: DateTime(2024),
        );

    setUp(() async {
      localAdapter = FlakyLocalAdapter<NonRelationalTestEntity>();
      manager = DatumManager<NonRelationalTestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<NonRelationalTestEntity>(),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<NonRelationalTestEntity>(enableLogging: false),
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('falls back to a regular delete and reports the deleted entity', () async {
      await manager.push(item: entity('n1'), userId: 'u1');

      final result = await manager.cascadeDelete(id: 'n1', userId: 'u1');

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(result.deletedEntities[NonRelationalTestEntity], hasLength(1));
      expect(await localAdapter.read('n1', userId: 'u1'), isNull);
    });

    test('reports failure when the fallback delete fails', () async {
      await manager.push(item: entity('n2'), userId: 'u1');
      localAdapter.deleteReturnsFalse = true;

      final result = await manager.cascadeDelete(id: 'n2', userId: 'u1');

      expect(result.success, isFalse);
      expect(result.deletedEntities, isEmpty);
      expect(result.errors, contains('Failed to delete entity'));
    });

    test('executeCascadeDeleteWithOptions returns cancelled failure for a pre-cancelled token', () async {
      await manager.push(item: entity('n3'), userId: 'u1');

      final result = await manager.deleteCascade('n3').forUser('u1').withCancellation(CancellationToken()..cancel()).execute();

      expect(result, isA<CascadeFailure<NonRelationalTestEntity>>());
      expect((result as CascadeFailure<NonRelationalTestEntity>).error.code, 'CANCELLED');
      expect(await localAdapter.read('n3', userId: 'u1'), isNotNull);
    });

    test('dry run reports the would-be delete without touching storage', () async {
      await manager.push(item: entity('n4'), userId: 'u1');

      final result = await manager.deleteCascade('n4').forUser('u1').dryRun().execute();

      expect(result, isA<CascadeSuccess<NonRelationalTestEntity>>());
      expect(result.totalDeleted, 1);
      expect(await localAdapter.read('n4', userId: 'u1'), isNotNull, reason: 'dry run must not delete');
    });

    test('execute deletes the entity and reports success', () async {
      await manager.push(item: entity('n5'), userId: 'u1');

      final result = await manager.deleteCascade('n5').forUser('u1').execute();

      expect(result, isA<CascadeSuccess<NonRelationalTestEntity>>());
      expect(result.totalDeleted, 1);
      expect(await localAdapter.read('n5', userId: 'u1'), isNull);
    });

    test('execute reports DELETE_FAILED when the underlying delete fails', () async {
      await manager.push(item: entity('n6'), userId: 'u1');
      localAdapter.deleteReturnsFalse = true;

      final result = await manager.deleteCascade('n6').forUser('u1').execute();

      expect(result, isA<CascadeFailure<NonRelationalTestEntity>>());
      expect((result as CascadeFailure<NonRelationalTestEntity>).error.code, 'DELETE_FAILED');
    });

    test('execute rethrows unexpected errors after recording them', () async {
      localAdapter.throwOnReadWithUserId = true;

      expect(
        () => manager.deleteCascade('whatever').forUser('u1').execute(),
        throwsStateError,
      );
    });

    test('watchRelated rejects non-relational parents', () {
      expect(
        () => manager.watchRelated<TestEntity>(
          NonRelationalTestEntity.create('x', 'u1', 'x'),
          'anything',
        ),
        throwsArgumentError,
      );
    });
  });

  group('cascadeDelete plan execution failures (relational entity)', () {
    late FlakyLocalAdapter<TestEntity> localAdapter;
    late DatumManager<TestEntity> manager;

    setUp(() async {
      localAdapter = FlakyLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
      );
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('a negative timeout aborts the plan with a timeout error', () async {
      await manager.push(item: makeEntity('t1'), userId: 'u1');

      final result = await manager.deleteCascade('t1').forUser('u1').withTimeout(const Duration(seconds: -1)).execute();

      expect(result, isA<CascadeFailure<TestEntity>>());
      expect(result.errors.join(), contains('Operation timed out'));
      expect(await localAdapter.read('t1', userId: 'u1'), isNotNull, reason: 'the plan aborted before deleting');
    });

    test('a throwing delete step is recorded as an error (progress execution)', () async {
      await manager.push(item: makeEntity('t2'), userId: 'u1');
      // performDeleteWithoutEvents reads WITHOUT a userId - make that throw.
      localAdapter.throwOnReadWithoutUserId = true;

      final result = await manager.deleteCascade('t2').forUser('u1').execute();

      expect(result, isA<CascadeFailure<TestEntity>>());
      expect(result.errors.join(), contains('Error deleting'));
    });

    test('cascadeDelete records a plain failure when a delete step returns false', () async {
      await manager.push(item: makeEntity('t3'), userId: 'u1');
      localAdapter.deleteReturnsFalse = true;

      final result = await manager.cascadeDelete(id: 't3', userId: 'u1');

      expect(result.success, isFalse);
      expect(result.errors.join(), contains('Failed to delete'));
    });

    test('cascadeDelete records an error when a delete step throws', () async {
      await manager.push(item: makeEntity('t4'), userId: 'u1');
      localAdapter.throwOnReadWithoutUserId = true;

      final result = await manager.cascadeDelete(id: 't4', userId: 'u1');

      expect(result.success, isFalse);
      expect(result.errors.join(), contains('Error deleting'));
    });
  });

  group('relations with missing local keys', () {
    test('cascade and restrict relations resolve to no related entities and the delete succeeds', () async {
      final localAdapter = MockLocalAdapter<NullKeyEntity>();
      final manager = DatumManager<NullKeyEntity>(
        localAdapter: localAdapter,
        remoteAdapter: MockRemoteAdapter<NullKeyEntity>(),
        connectivity: const OnlineConnectivity(),
        datumConfig: const DatumConfig<NullKeyEntity>(enableLogging: false),
      );
      await manager.initialize();

      await manager.push(item: const NullKeyEntity(id: 'k1', userId: 'u1'), userId: 'u1');

      final result = await manager.cascadeDelete(id: 'k1', userId: 'u1');

      expect(result.success, isTrue, reason: 'restrict relation found nothing, so delete proceeds');
      expect(result.restrictedRelations, isEmpty);
      expect(await localAdapter.read('k1', userId: 'u1'), isNull);

      await manager.dispose();
    });
  });
}
