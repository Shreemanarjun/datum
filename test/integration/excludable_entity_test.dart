import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/datum.dart';

import '../mocks/mock_connectivity_checker.dart';

class MockedLocalAdapter<T extends DatumEntity> extends Mock implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntity> extends Mock implements RemoteAdapter<T> {}

void main() {
  group('ExcludableEntity Integration Tests', () {
    late DatumManager<ExcludableEntity> manager;
    late MockedLocalAdapter<ExcludableEntity> localAdapter;
    late MockedRemoteAdapter<ExcludableEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUpAll(() {
      registerFallbackValue(
        ExcludableEntity(
          id: 'fb',
          userId: 'fb',
          name: 'fb',
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
          version: 0,
        ),
      );
      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'));
      registerFallbackValue(
        DatumSyncOperation<ExcludableEntity>(
          id: 'fb-op',
          userId: 'fb',
          entityId: 'fb-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        const DatumSyncResult<ExcludableEntity>(
          userId: 'fallback-user',
          duration: Duration.zero,
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        ),
      );
    });

    setUp(() async {
      localAdapter = MockedLocalAdapter<ExcludableEntity>();
      remoteAdapter = MockedRemoteAdapter<ExcludableEntity>();
      final pendingOps = <DatumSyncOperation<ExcludableEntity>>[];

      connectivityChecker = MockConnectivityChecker();
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.changeStream()).thenAnswer(
        (_) => const Stream<DatumChangeDetail<ExcludableEntity>>.empty(),
      );

      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.changeStream).thenAnswer(
        (_) => const Stream<DatumChangeDetail<ExcludableEntity>>.empty(),
      );
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((
        _,
      ) async {
        return List.from(pendingOps);
      });
      when(
        () => localAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(() => localAdapter.addPendingOperation(any(), any())).thenAnswer((
        inv,
      ) async {
        pendingOps.add(
          inv.positionalArguments[1] as DatumSyncOperation<ExcludableEntity>,
        );
      });
      when(
        () => localAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (_) async => ExcludableEntity(
          id: 'patched',
          userId: 'patched',
          name: 'patched',
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
          version: 0,
        ),
      );
      when(() => localAdapter.create(any())).thenAnswer((_) async {});
      when(() => localAdapter.update(any())).thenAnswer((_) async {});
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(() => localAdapter.removePendingOperation(any())).thenAnswer((
        inv,
      ) async {
        pendingOps.removeWhere((op) => op.id == inv.positionalArguments.first);
      });
      when(
        () => localAdapter.getLastSyncResult(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.saveLastSyncResult(any(), any()),
      ).thenAnswer((_) async {});

      manager = DatumManager<ExcludableEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
      );

      await manager.initialize();
    });

    group('Unit-level model tests', () {
      test('fromJson creates a correct object', () {
        final json = {
          'id': 'e1',
          'userId': 'u1',
          'name': 'Test',
          'modifiedAt': DateTime(2023).toIso8601String(),
          'createdAt': DateTime(2023).toIso8601String(),
          'version': 1,
          'isDeleted': false,
          'localOnlyFields': {'local': 'abc'},
          'remoteOnlyFields': {'remote': 'xyz'},
        };

        final entity = ExcludableEntity.fromJson(json);

        expect(entity.id, 'e1');
        expect(entity.name, 'Test');
        expect(entity.localOnlyFields, containsPair('local', 'abc'));
        expect(entity.remoteOnlyFields, containsPair('remote', 'xyz'));
      });

      test('toMap respects MapTarget', () {
        final entity = ExcludableEntity(
          id: 'e1',
          userId: 'u1',
          name: 'Test',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
          version: 1,
          localOnlyFields: const {'local': 'abc'},
          remoteOnlyFields: const {'remote': 'xyz'},
        );

        final localMap = entity.toDatumMap();
        expect(localMap, containsPair('local', 'abc'));
        expect(localMap.containsKey('remote'), isFalse);

        final remoteMap = entity.toDatumMap(target: MapTarget.remote);
        expect(remoteMap, containsPair('remote', 'xyz'));
        expect(remoteMap.containsKey('local'), isFalse);
      });

      test('copyWith creates a correct copy', () {
        final original = ExcludableEntity(
          id: 'e1',
          userId: 'u1',
          name: 'Original',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
          version: 1,
          localOnlyFields: const {'local': 'a'},
          remoteOnlyFields: const {'remote': 'b'},
        );

        final updated = original.copyWith(
          name: 'Updated',
          version: 2,
          localOnlyFields: const {'local': 'c'},
        );

        expect(updated.id, original.id);
        expect(updated.name, 'Updated');
        expect(updated.version, 2);
        expect(updated.localOnlyFields, containsPair('local', 'c'));
        expect(updated.remoteOnlyFields, original.remoteOnlyFields);
      });

      test('diff includes remoteOnlyFields changes', () {
        final initial = ExcludableEntity(
          id: 'e1',
          userId: 'u1',
          name: 'Initial',
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
          remoteOnlyFields: const {'remoteKey': 'value-abc'},
        );
        final updated = initial.copyWith(
          remoteOnlyFields: const {'remoteKey': 'value-xyz'},
          name: 'Updated',
        );

        final delta = updated.diff(initial);

        expect(delta, isNotNull);
        // Verify that remote-only fields are in the diff.
        expect(delta!.containsKey('remoteKey'), isTrue);
        expect(delta['remoteKey'], 'value-xyz');
        expect(delta.containsKey('name'), isTrue);
        expect(delta['name'], 'Updated');
      });

      test('operator == correctly compares entities based on all fields', () {
        final now = DateTime.now();
        final entity1 = ExcludableEntity(
          id: 'e1',
          userId: 'u1',
          name: 'Entity One',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        // Create an identical copy.
        final entity1Copy = entity1.copyWith();

        // Create a copy with different data.
        final entity2 = entity1.copyWith(
          name: 'Entity One Updated',
          version: 2,
          modifiedAt: now.add(const Duration(seconds: 1)),
        );

        // Create an entity with a different ID.
        final entity3 = ExcludableEntity(
          id: 'e2',
          userId: 'u1',
          name: 'Entity One',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        // Assert that identical entities are equal.
        expect(entity1 == entity1Copy, isTrue);

        // Assert that entities with different properties are not equal.
        expect(entity1 == entity2, isFalse);

        // Assert that entities with different IDs are not equal.
        expect(entity1 == entity3, isFalse);
      });

      test('hashCode is consistent for equal objects', () {
        final now = DateTime.now();
        final entity1 = ExcludableEntity(
          id: 'e1',
          userId: 'u1',
          name: 'Entity One',
          modifiedAt: now,
          createdAt: now,
          version: 1,
        );

        // Create an identical copy.
        final entity1Copy = entity1.copyWith();

        // Create a different entity.
        final entity2 = entity1.copyWith(
          name: 'Entity One Updated',
          version: 2,
        );

        // Equal objects must have equal hash codes.
        expect(entity1.hashCode, equals(entity1Copy.hashCode));

        // Unequal objects should ideally have different hash codes.
        expect(entity1.hashCode, isNot(equals(entity2.hashCode)));
      });
    });

    test(
      'remoteOnlyFields are included in data for a remote push (create)',
      () async {
        // Arrange
        when(() => remoteAdapter.create(any())).thenAnswer((inv) async {});

        // 1. Test push (create)
        final initial = ExcludableEntity(
          id: 'e2',
          userId: 'u1',
          name: 'Remote Test',
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
          remoteOnlyFields: const {'sessionToken': 'token-123'},
        );
        await manager.push(item: initial, userId: 'u1');

        // Assert that the pending operation's data, when mapped for the remote,
        // includes the remote-only field by checking what is sent to the remote.
        await manager.synchronize('u1');

        final captured = verify(() => remoteAdapter.create(captureAny())).captured.single as ExcludableEntity;

        final remoteMap = captured.toDatumMap(target: MapTarget.remote);
        expect(remoteMap, containsPair('sessionToken', 'token-123'));
        expect(remoteMap.containsKey('localOnlyFields'), isFalse);
      },
    );

    test('remoteOnlyFields are included in remote patch delta', () async {
      // Arrange
      when(() => remoteAdapter.create(any())).thenAnswer(
        (inv) async => inv.positionalArguments.first as ExcludableEntity,
      );
      when(
        () => remoteAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (_) async => ExcludableEntity(
          id: 'patched-remote',
          userId: 'u1',
          name: 'Patched on Remote',
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 2,
        ),
      );
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});
      when(
        () => localAdapter.readAll(userId: 'u1'),
      ).thenAnswer((_) async => []);

      // 1. Create and sync an initial entity
      final initial = ExcludableEntity(
        id: 'e-patch',
        userId: 'u1',
        name: 'Initial',
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );
      // Stub the read for the diff calculation inside push()
      when(
        () => localAdapter.read(initial.id, userId: 'u1'),
      ).thenAnswer((_) async => initial);

      await manager.push(item: initial, userId: 'u1');
      await manager.synchronize('u1');

      // 2. Update the entity with a remote-only field and sync again
      final updated = initial.copyWith(
        remoteOnlyFields: const {
          'sessionToken': 'token-456',
        }, // Change remote field
        name: 'Updated Name', // Change common field
      );
      await manager.push(item: updated, userId: 'u1');
      await manager.synchronize('u1');
      // Assert that the map sent to the remote adapter for the patch includes the remote field
      final captured = verify(
        () => remoteAdapter.patch(
          id: 'e-patch',
          userId: 'u1',
          delta: captureAny(named: 'delta'),
        ),
      ).captured.single as Map<String, dynamic>;

      expect(captured, containsPair('sessionToken', 'token-456'));
      expect(captured, containsPair('name', 'Updated Name'));
    });

    test('localOnlyFields are saved locally but not sent to remote', () async {
      // Arrange
      when(() => remoteAdapter.create(any())).thenAnswer(
        (inv) async => inv.positionalArguments.first as ExcludableEntity,
      );
      when(
        () => remoteAdapter.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      final entity = ExcludableEntity(
        id: 'e3',
        userId: 'u1',
        name: 'Local Only Test',
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
        localOnlyFields: const {'localCacheKey': 'cache-data'},
      );

      // Act
      await manager.push(item: entity, userId: 'u1');
      await manager.synchronize('u1');

      // Assert: The data saved to the local adapter should contain the field.
      final capturedLocal = verify(() => localAdapter.create(captureAny())).captured.single as ExcludableEntity;
      final localMap = capturedLocal.toDatumMap(target: MapTarget.local);

      expect(localMap, containsPair('localCacheKey', 'cache-data'));
      // Assert: The data pushed to the remote adapter should NOT contain the field.
      final captured = verify(
        () => remoteAdapter.create(captureAny()),
      ).captured;
      expect(
        (captured.first as ExcludableEntity).toDatumMap(target: MapTarget.remote),
        isNot(contains('localCacheKey')),
      );
    });
  });
}
