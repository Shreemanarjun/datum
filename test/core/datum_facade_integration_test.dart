import 'dart:async';

import 'package:datum/datum.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// A second entity type for multi-manager tests
class TestEntity2 extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String description;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TestEntity2({
    required this.id,
    required this.userId,
    required this.description,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  TestEntity2 copyWith({
    String? id,
    String? userId,
    String? description,
    DateTime? modifiedAt,
    DateTime? createdAt,
    int? version,
    bool? isDeleted,
  }) {
    return TestEntity2(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      description: description ?? this.description,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) {
    if (oldVersion is! TestEntity2) {
      return toDatumMap(target: MapTarget.remote);
    }
    final diffMap = <String, dynamic>{};
    if (description != oldVersion.description) {
      diffMap['description'] = description;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diffMap['isDeleted'] = isDeleted;
    }
    return diffMap.isEmpty ? null : diffMap;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'description': description,
      'modifiedAt': modifiedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
    };
  }
}

/// A dummy entity used specifically to test behavior for unregistered types.
class UnregisteredEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const UnregisteredEntity({
    required this.id,
    required this.userId,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  UnregisteredEntity copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {};
}

class MockedLocalAdapter<T extends DatumEntity> extends Mock implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntity> extends Mock implements RemoteAdapter<T> {}

void main() {
  group('Datum Facade Integration Tests', () {
    // Mocks for TestEntity
    late MockedLocalAdapter<TestEntity> localAdapter1;
    late MockedRemoteAdapter<TestEntity> remoteAdapter1;

    // Mocks for TestEntity2
    late MockedLocalAdapter<TestEntity2> localAdapter2;
    late MockedRemoteAdapter<TestEntity2> remoteAdapter2;

    late MockConnectivityChecker connectivityChecker;

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(
        TestEntity2(
          id: 'fb',
          userId: 'fb',
          description: 'fb',
          modifiedAt: _fallbackDate,
          createdAt: _fallbackDate,
          version: 0,
        ),
      );
      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'));
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb-op',
          userId: 'fb',
          entityId: 'fb-entity',
          type: DatumOperationType.create,
          timestamp: _fallbackDate,
        ),
      );
      registerFallbackValue(
        const DatumSyncResult<TestEntity>(
          userId: 'fallback-user',
          duration: Duration.zero,
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        ),
      );
      registerFallbackValue(
        DatumSyncOperation<TestEntity2>(
          id: 'fb-op-2',
          userId: 'fb',
          entityId: 'fb-entity-2',
          type: DatumOperationType.create,
          timestamp: _fallbackDate,
        ),
      );
      registerFallbackValue(
        const DatumSyncResult<TestEntity2>(
          userId: 'fallback-user',
          duration: Duration.zero,
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: [],
        ),
      );
    });

    void stubDefaultBehaviors() {
      // Stub for TestEntity
      _stubAdapterBehaviors(localAdapter1, remoteAdapter1);
      when(() => localAdapter1.sampleInstance).thenReturn(
        TestEntity.create('sample', 'sample', 'sample'),
      );

      // Stub for TestEntity2
      _stubAdapterBehaviors(localAdapter2, remoteAdapter2);
      when(() => localAdapter2.sampleInstance).thenReturn(
        // ignore: avoid_redundant_argument_values
        TestEntity2(
          id: 'sample',
          userId: 'sample',
          description: 'sample',
          modifiedAt: _fallbackDate,
          createdAt: _fallbackDate,
          version: 0,
        ),
      );

      // Stub connectivity
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
    }

    setUp(() {
      localAdapter1 = MockedLocalAdapter<TestEntity>();
      remoteAdapter1 = MockedRemoteAdapter<TestEntity>();
      localAdapter2 = MockedLocalAdapter<TestEntity2>();
      remoteAdapter2 = MockedRemoteAdapter<TestEntity2>();
      connectivityChecker = MockConnectivityChecker();
      stubDefaultBehaviors();
    });

    tearDown(() async {
      if (Datum.instanceOrNull != null) {
        await Datum.instance.dispose();
        Datum.resetForTesting();
      }
    });

    Future<void> initializeDatum() async {
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter1,
            remoteAdapter: remoteAdapter1,
          ),
          DatumRegistration<TestEntity2>(
            localAdapter: localAdapter2,
            remoteAdapter: remoteAdapter2,
          ),
        ],
      );
    }

    test('Datum.initialize creates a singleton and initializes all managers', () async {
      // Act
      await initializeDatum();

      // Assert
      expect(Datum.instance, isNotNull);
      verify(() => localAdapter1.initialize()).called(1);
      verify(() => remoteAdapter1.initialize()).called(1);
      verify(() => localAdapter2.initialize()).called(1);
      verify(() => remoteAdapter2.initialize()).called(1);
    });

    test('Datum.manager<T>() returns the correct manager instance', () async {
      // Arrange
      await initializeDatum();

      // Act
      final manager1 = Datum.manager<TestEntity>();
      final manager2 = Datum.manager<TestEntity2>();

      // Assert
      expect(manager1, isA<DatumManager<TestEntity>>());
      expect(manager2, isA<DatumManager<TestEntity2>>());
      expect(
        () => Datum.manager<UnregisteredEntity>(),
        throwsStateError,
        reason: 'Should throw for an unregistered type',
      );
    });

    group('Facade CRUD methods', () {
      test('Datum.create() delegates to the correct manager', () async {
        // Override the default read stub for this test to ensure `create` is called.
        when(() => localAdapter1.read('e1', userId: 'u1')).thenAnswer((_) async => null);
        when(() => localAdapter2.read('e2', userId: 'u1')).thenAnswer((_) async => null);

        // Arrange
        await initializeDatum();
        final entity1 = TestEntity.create('e1', 'u1', 'Item 1');
        final entity2 = TestEntity2(
          id: 'e2',
          userId: 'u1',
          description: 'Item 2',
          modifiedAt: _fallbackDate,
          createdAt: _fallbackDate,
          version: 1,
        );

        // Act
        await Datum.instance.create(entity1);
        await Datum.instance.create(entity2);

        // Assert
        verify(() => localAdapter1.create(entity1)).called(1);
        verify(() => localAdapter2.create(entity2)).called(1);
        verifyNever(() => localAdapter1.create(any(that: isA<TestEntity2>())));
        verifyNever(() => localAdapter2.create(any(that: isA<TestEntity>())));
      });

      test('Datum.read<T>() delegates to the correct manager', () async {
        // Arrange
        await initializeDatum();

        // Act
        await Datum.instance.read<TestEntity>('e1', userId: 'u1');
        await Datum.instance.read<TestEntity2>('e2', userId: 'u1');

        // Assert
        verify(() => localAdapter1.read('e1', userId: 'u1')).called(1);
        verify(() => localAdapter2.read('e2', userId: 'u1')).called(1);
      });

      test('Datum.readAll<T>() delegates to the correct manager', () async {
        // Arrange
        await initializeDatum();

        // Act
        await Datum.instance.readAll<TestEntity>(userId: 'u1');
        await Datum.instance.readAll<TestEntity2>(userId: 'u1');

        // Assert
        verify(() => localAdapter1.readAll(userId: 'u1')).called(1);
        verify(() => localAdapter2.readAll(userId: 'u1')).called(1);
      });

      test('Datum.update<T>() delegates to the correct manager', () async {
        // Arrange
        await initializeDatum();
        final entity1 = TestEntity.create('e1', 'u1', 'Item 1');

        // Act: update is an alias for push, which will call patch/update on the adapter
        await Datum.instance.update(entity1);

        // Assert
        verify(() => localAdapter1.patch(id: 'e1', delta: any(named: 'delta'), userId: 'u1')).called(1);
        verifyNever(() => localAdapter2.patch(id: any(named: 'id'), delta: any(named: 'delta'), userId: any(named: 'userId')));
      });

      test('Datum.delete<T>() delegates to the correct manager', () async {
        // Arrange
        await initializeDatum();
        final entity1 = TestEntity.create('e1', 'u1', 'Item 1');
        when(() => localAdapter1.read('e1', userId: 'u1')).thenAnswer((_) async => entity1);

        // Act
        await Datum.instance.delete<TestEntity>(id: 'e1', userId: 'u1');

        // Assert
        verify(() => localAdapter1.delete('e1', userId: 'u1')).called(1);
        verifyNever(() => localAdapter2.delete(any(), userId: any(named: 'userId')));
      });
    });

    group('Facade "AndSync" methods', () {
      test('Datum.pushAndSync() delegates and performs both actions', () async {
        // Arrange
        await initializeDatum();
        final entity1 = TestEntity.create('e1', 'u1', 'Item 1');

        // Override the default read stub for this test to ensure `create` is called.
        when(() => localAdapter1.read('e1', userId: 'u1')).thenAnswer((_) async => null);

        // Arrange: When synchronize is called, it will ask for pending operations.
        // We must stub this to return the operation that was just pushed.
        when(() => localAdapter1.getPendingOperations('u1')).thenAnswer(
          (_) async => [
            DatumSyncOperation(
              id: 'op-e1',
              userId: 'u1',
              entityId: 'e1',
              type: DatumOperationType.create,
              timestamp: _fallbackDate,
              data: entity1,
            ),
          ],
        );
        // Act
        final (savedItem, syncResult) = await Datum.instance.pushAndSync<TestEntity>(item: entity1, userId: 'u1');

        // Assert
        // 1. Push was called
        verify(() => localAdapter1.create(entity1)).called(1);
        verify(() => localAdapter1.addPendingOperation('u1', any())).called(1);

        // 2. Sync was called
        verify(() => remoteAdapter1.create(entity1)).called(1);

        // 3. Check results
        expect(savedItem.id, 'e1');
        expect(syncResult.isSuccess, isTrue);
        expect(syncResult.syncedCount, 1);
      });

      test('Datum.updateAndSync() delegates and performs both actions', () async {
        // Arrange
        await initializeDatum();
        final initialEntity = TestEntity.create('e1', 'u1', 'Item 1');
        final updatedEntity = initialEntity.copyWith(name: 'Item 1 Updated');

        // Stub the initial state in the local adapter
        when(() => localAdapter1.read('e1', userId: 'u1')).thenAnswer((_) async => initialEntity);

        // Stub the patch call that will happen during the 'push' phase
        when(
          () => localAdapter1.patch(
            id: 'e1',
            delta: any(named: 'delta'),
            userId: 'u1',
          ),
        ).thenAnswer((_) async => updatedEntity);

        // Arrange: Stub the pending update operation for the sync phase.
        when(() => localAdapter1.getPendingOperations('u1')).thenAnswer(
          (_) async => [
            DatumSyncOperation(
              id: 'op-e1-update',
              userId: 'u1',
              entityId: 'e1',
              type: DatumOperationType.update,
              timestamp: _fallbackDate,
              data: updatedEntity,
              delta: updatedEntity.diff(initialEntity),
            ),
          ],
        );

        // Act
        final (savedItem, syncResult) = await Datum.instance.updateAndSync<TestEntity>(item: updatedEntity, userId: 'u1');

        // Assert
        // 1. Update was called (via patch)
        verify(
          () => localAdapter1.patch(
            id: 'e1',
            delta: any(named: 'delta'),
            userId: 'u1',
          ),
        ).called(1);
        verify(() => localAdapter1.addPendingOperation('u1', any())).called(1);

        // 2. Sync was called (via patch on remote)
        verify(
          () => remoteAdapter1.patch(id: 'e1', delta: any(named: 'delta'), userId: 'u1'),
        ).called(1);

        // 3. Check results
        expect(savedItem.name, 'Item 1 Updated');
        expect(syncResult.isSuccess, isTrue);
        expect(syncResult.syncedCount, 1);
      });

      test('Datum.deleteAndSync() delegates and performs both actions', () async {
        // Arrange
        await initializeDatum();
        final entity1 = TestEntity.create('e1', 'u1', 'Item 1');
        entity1.copyWith(name: 'Item 1 Updated');
        when(() => localAdapter1.read('e1', userId: 'u1')).thenAnswer((_) async => entity1);
        // Arrange: Stub the pending delete operation for the sync phase.
        when(() => localAdapter1.getPendingOperations('u1')).thenAnswer(
          (_) async => [
            DatumSyncOperation(
              id: 'op-e1-del',
              userId: 'u1',
              entityId: 'e1',
              type: DatumOperationType.delete,
              timestamp: _fallbackDate,
              data: entity1,
            ),
          ],
        );

        // Act
        final (wasDeleted, syncResult) = await Datum.instance.deleteAndSync<TestEntity>(id: 'e1', userId: 'u1');

        // Assert
        // 1. Delete was called
        verify(() => localAdapter1.delete('e1', userId: 'u1')).called(1);
        verify(() => localAdapter1.addPendingOperation('u1', any())).called(1);

        // 2. Sync was called
        verify(() => remoteAdapter1.delete('e1', userId: 'u1')).called(1);

        // 3. Check results
        expect(wasDeleted, isTrue);
        expect(syncResult.isSuccess, isTrue);
        expect(syncResult.syncedCount, 1);
      });
    });

    test('Global event stream receives events from all managers', () async {
      // Arrange
      await initializeDatum();
      final entity1 = TestEntity.create('e1', 'u1', 'Item 1');
      final entity2 = TestEntity2(
        id: 'e2',
        userId: 'u1',
        description: 'Item 2',
        modifiedAt: _fallbackDate,
        createdAt: _fallbackDate,
        version: 1,
      );

      final events = <DataChangeEvent>[];
      Datum.instance.events.whereType<DataChangeEvent>().listen(events.add);

      // Act
      await Datum.instance.create(entity1);
      await Datum.instance.create(entity2);

      // Allow stream to emit
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(events, hasLength(2));
      expect(
        events.any((e) => e.data is TestEntity && e.data?.id == 'e1'),
        isTrue,
      );
      expect(
        events.any((e) => e.data is TestEntity2 && e.data?.id == 'e2'),
        isTrue,
      );
    });

    test('Global synchronize triggers sync on all managers', () async {
      // Arrange
      await initializeDatum();
      // Stub sync for manager 1
      when(() => localAdapter1.getPendingOperations('u1')).thenAnswer(
        (_) async => [
          DatumSyncOperation(
            id: 'op1',
            userId: 'u1',
            entityId: 'e1',
            type: DatumOperationType.create,
            timestamp: _fallbackDate,
            data: TestEntity.create('e1', 'u1', 'Item 1'),
          ),
        ],
      );
      // Stub sync for manager 2
      when(() => localAdapter2.getPendingOperations('u1')).thenAnswer(
        (_) async => [
          DatumSyncOperation(
            id: 'op2',
            userId: 'u1',
            entityId: 'e2',
            type: DatumOperationType.create,
            timestamp: _fallbackDate,
            data: TestEntity2(
              id: 'e2',
              userId: 'u1',
              description: 'Item 2',
              modifiedAt: _fallbackDate,
              createdAt: _fallbackDate,
              version: 1,
            ),
          ),
        ],
      );

      // Act
      await Datum.instance.synchronize('u1');

      // Assert
      verify(() => remoteAdapter1.create(any(that: isA<TestEntity>()))).called(1);
      verify(() => remoteAdapter2.create(any(that: isA<TestEntity2>()))).called(1);
    });

    group('Global synchronize with different directions', () {
      const userId = 'u1';

      test('with pushOnly performs only push on all managers', () async {
        // Arrange
        await initializeDatum();

        // --- PUSH setup ---
        // Local has pending operations for both entity types
        final localEntity1 = TestEntity.create('local-e1', userId, 'Local Item 1');
        final localEntity2 = TestEntity2(id: 'local-e2', userId: userId, description: 'Local Item 2', modifiedAt: _fallbackDate, createdAt: _fallbackDate, version: 1);
        when(() => localAdapter1.getPendingOperations(userId)).thenAnswer((_) async => [DatumSyncOperation(id: 'op1', userId: userId, entityId: 'local-e1', type: DatumOperationType.create, timestamp: _fallbackDate, data: localEntity1)]);
        when(() => localAdapter2.getPendingOperations(userId)).thenAnswer((_) async => [DatumSyncOperation(id: 'op2', userId: userId, entityId: 'local-e2', type: DatumOperationType.create, timestamp: _fallbackDate, data: localEntity2)]);

        // --- PULL setup (to verify it's NOT called) ---
        final remoteEntity1 = TestEntity.create('remote-e1', userId, 'Remote Item 1');
        when(() => remoteAdapter1.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => [remoteEntity1]);

        // Act
        final result = await Datum.instance.synchronize(
          userId,
          options: const DatumSyncOptions(direction: SyncDirection.pushOnly),
        );

        // Assert
        // 1. Verify push was performed for both managers
        verify(() => remoteAdapter1.create(localEntity1)).called(1);
        verify(() => remoteAdapter2.create(localEntity2)).called(1);

        // 2. Verify pull was NOT performed
        verifyNever(() => remoteAdapter1.readAll(userId: userId, scope: any(named: 'scope')));
        verifyNever(() => localAdapter1.create(remoteEntity1));

        // 3. Check result aggregation
        expect(result.syncedCount, 2);
        expect(result.failedCount, 0);
      });

      test('with pullOnly performs only pull on all managers', () async {
        // Arrange
        await initializeDatum();

        // --- PUSH setup (to verify it's NOT called) ---
        final localEntity1 = TestEntity.create('local-e1', userId, 'Local Item 1');
        when(() => localAdapter1.getPendingOperations(userId)).thenAnswer((_) async => [DatumSyncOperation(id: 'op1', userId: userId, entityId: 'local-e1', type: DatumOperationType.create, timestamp: _fallbackDate, data: localEntity1)]);

        // --- PULL setup ---
        final remoteEntity1 = TestEntity.create('remote-e1', userId, 'Remote Item 1');
        final remoteEntity2 = TestEntity2(id: 'remote-e2', userId: userId, description: 'Remote Item 2', modifiedAt: _fallbackDate, createdAt: _fallbackDate, version: 1);
        when(() => remoteAdapter1.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => [remoteEntity1]);
        when(() => remoteAdapter2.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => [remoteEntity2]);

        // Act
        final result = await Datum.instance.synchronize(
          userId,
          options: const DatumSyncOptions(direction: SyncDirection.pullOnly),
        );

        // Assert
        // 1. Verify pull was performed for both managers
        verify(() => remoteAdapter1.readAll(userId: userId, scope: any(named: 'scope'))).called(1);
        verify(() => remoteAdapter2.readAll(userId: userId, scope: any(named: 'scope'))).called(1);
        verify(() => localAdapter1.create(remoteEntity1)).called(1);
        verify(() => localAdapter2.create(remoteEntity2)).called(1);

        // 2. Verify push was NOT performed
        verifyNever(() => remoteAdapter1.create(localEntity1));

        // 3. Check result aggregation
        // Pull operations don't currently contribute to syncedCount in the global result,
        // as the individual manager results are what matter. This is expected.
        expect(result.syncedCount, 0);
        expect(result.failedCount, 0);
      });

      test('with pullThenPush performs pull then push on all managers', () async {
        // Arrange
        await initializeDatum();

        // --- PULL setup ---
        final remoteEntity1 = TestEntity.create('remote-e1', userId, 'Remote Item 1');
        final remoteEntity2 = TestEntity2(id: 'remote-e2', userId: userId, description: 'Remote Item 2', modifiedAt: _fallbackDate, createdAt: _fallbackDate, version: 1);
        when(() => remoteAdapter1.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => [remoteEntity1]);
        when(() => remoteAdapter2.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => [remoteEntity2]);

        // --- PUSH setup ---
        final localEntity1 = TestEntity.create('local-e1', userId, 'Local Item 1');
        final localEntity2 = TestEntity2(id: 'local-e2', userId: userId, description: 'Local Item 2', modifiedAt: _fallbackDate, createdAt: _fallbackDate, version: 1);
        when(() => localAdapter1.getPendingOperations(userId)).thenAnswer((_) async => [DatumSyncOperation(id: 'op1', userId: userId, entityId: 'local-e1', type: DatumOperationType.create, timestamp: _fallbackDate, data: localEntity1)]);
        when(() => localAdapter2.getPendingOperations(userId)).thenAnswer((_) async => [DatumSyncOperation(id: 'op2', userId: userId, entityId: 'local-e2', type: DatumOperationType.create, timestamp: _fallbackDate, data: localEntity2)]);

        // Act
        final result = await Datum.instance.synchronize(
          userId,
          options: const DatumSyncOptions(direction: SyncDirection.pullThenPush),
        );

        // Assert
        // 1. Verify pull was performed for both managers
        verify(() => localAdapter1.create(remoteEntity1)).called(1);
        verify(() => localAdapter2.create(remoteEntity2)).called(1);

        // 2. Verify push was performed for both managers
        verify(() => remoteAdapter1.create(localEntity1)).called(1);
        verify(() => remoteAdapter2.create(localEntity2)).called(1);

        // 3. Verify core interactions for pullThenPush occurred for each manager.
        // We avoid a strict global ordering check (verifyInOrder) because the engine
        // may perform additional metadata/save operations in between steps.
        verify(() => remoteAdapter1.readAll(userId: userId, scope: any(named: 'scope'))).called(1);
        verify(() => localAdapter1.readByIds([remoteEntity1.id], userId: userId)).called(1);
        verify(() => localAdapter1.getPendingOperations(userId)).called(greaterThanOrEqualTo(1));
        verify(() => localAdapter1.removePendingOperation('op1')).called(1);
        verify(() => localAdapter1.saveLastSyncResult(userId, any())).called(greaterThanOrEqualTo(1));

        verify(() => remoteAdapter2.readAll(userId: userId, scope: any(named: 'scope'))).called(1);
        verify(() => localAdapter2.readByIds([remoteEntity2.id], userId: userId)).called(1);
        verify(() => localAdapter2.getPendingOperations(userId)).called(greaterThanOrEqualTo(1));
        verify(() => localAdapter2.removePendingOperation('op2')).called(1);
        verify(() => localAdapter2.saveLastSyncResult(userId, any())).called(greaterThanOrEqualTo(1));

        // 4. Check result aggregation
        expect(result.syncedCount, 2);
        expect(result.failedCount, 0);
      });
    });
  });
}

final _fallbackDate = DateTime(2023);

/// Helper function to apply all default stubs to a set of mocks.
void _stubAdapterBehaviors<T extends DatumEntity>(
  MockedLocalAdapter<T> localAdapter,
  MockedRemoteAdapter<T> remoteAdapter,
) {
  // Initialization & Disposal
  when(() => localAdapter.initialize()).thenAnswer((_) async {});
  when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
  when(() => localAdapter.dispose()).thenAnswer((_) async {});
  when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
  when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);

  // Streams
  when(() => localAdapter.changeStream()).thenAnswer((_) => Stream<DatumChangeDetail<T>>.empty());
  when(() => remoteAdapter.changeStream).thenAnswer((_) => Stream<DatumChangeDetail<T>>.empty());

  // Core Local Operations
  when(() => localAdapter.create(any())).thenAnswer((_) async {});
  when(() => localAdapter.update(any())).thenAnswer((_) async {});
  when(() => localAdapter.read(any(), userId: any(named: 'userId'))).thenAnswer((_) async => null);
  when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {});
  when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
  // Stub read for update tests to simulate an existing item
  when(() => localAdapter.read(any(that: equals('e1')), userId: any(named: 'userId'))).thenAnswer(
    (_) async => TestEntity.create('e1', 'u1', 'Existing') as T?,
  );

  when(() => localAdapter.delete(any(), userId: any(named: 'userId'))).thenAnswer((_) async => true);
  when(() => localAdapter.patch(
        id: any(named: 'id'),
        delta: any(named: 'delta'),
        userId: any(named: 'userId'),
      )).thenAnswer((_) async => localAdapter.sampleInstance);

  // Core Remote Operations
  when(() => remoteAdapter.create(any(that: isA<T>()))).thenAnswer((_) async {});
  when(() => remoteAdapter.delete(any(that: isA<String>()), userId: any(named: 'userId', that: isA<String>()))).thenAnswer((_) async {});
  when(() => remoteAdapter.readAll(
        userId: any(named: 'userId'),
        scope: any(named: 'scope'),
      )).thenAnswer((_) async => []);
  when(() => remoteAdapter.patch(
        id: any(named: 'id'),
        delta: any(named: 'delta'),
        userId: any(named: 'userId'),
      )).thenAnswer((_) async => localAdapter.sampleInstance);

  // Sync-related Operations
  when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
  when(
    () => localAdapter.addPendingOperation(any(), any()),
  ).thenAnswer((_) async {});
  when(() => localAdapter.removePendingOperation(any())).thenAnswer((_) async {});

  // Metadata
  when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
  when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
  when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
  when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
  when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
  when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
}
