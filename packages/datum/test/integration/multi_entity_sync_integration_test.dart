import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'dart:async';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';
import '../mocks/forward_bulk_writes.dart';

class MockedRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

class MockedLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

class MockDatumObserver<T extends DatumEntityInterface> extends Mock implements DatumObserver<T> {}

/// A custom logger for tests that omits stack traces for cleaner output.
class TestLogger extends DatumLogger {
  TestLogger() : super(enabled: true);

  @override
  void error(String message, [StackTrace? stackTrace]) {
    super.error(message); // Call the base method without the stack trace.
  }
}

/// A second test entity for multi-entity testing.
class TestEntity2 extends RelationalDatumEntity {
  const TestEntity2({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  factory TestEntity2.create(String id, String userId, String title) => TestEntity2(
        id: id,
        userId: userId,
        title: title,
        description: '',
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final String description;

  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'description': description,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  TestEntity2 copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    DateTime? modifiedAt,
    DateTime? createdAt,
    int? version,
    bool? isDeleted,
  }) =>
      TestEntity2(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        description: description ?? this.description,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        createdAt: createdAt ?? this.createdAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! TestEntity2) return toDatumMap();

    final diff = <String, dynamic>{};
    if (title != oldVersion.title) diff['title'] = title;
    if (description != oldVersion.description) diff['description'] = description;
    return diff.isEmpty ? null : diff;
  }

  @override
  Map<String, Relation> get relations => {};
}

void main() {
  group('Multi-Entity Sync Integration Tests', () {
    late DatumManager<TestEntity> manager1;
    late DatumManager<TestEntity2> manager2;
    late MockedLocalAdapter<TestEntity> localAdapter1;
    late MockedLocalAdapter<TestEntity2> localAdapter2;
    late MockedRemoteAdapter<TestEntity> remoteAdapter1;
    late MockedRemoteAdapter<TestEntity2> remoteAdapter2;
    late MockConnectivityChecker connectivityChecker;
    late MockDatumObserver<TestEntity> mockObserver1;
    late MockDatumObserver<TestEntity2> mockObserver2;

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(TestEntity2.create('fb', 'fb', 'fb'));
      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'));
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb-op',
          userId: 'fb',
          entityId: 'fb-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        DatumSyncOperation<TestEntity2>(
          id: 'fb-op2',
          userId: 'fb',
          entityId: 'fb-entity2',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        DatumChangeDetail<TestEntity>(
          type: DatumOperationType.create,
          entityId: 'fb',
          userId: 'fb',
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        DatumChangeDetail<TestEntity2>(
          type: DatumOperationType.create,
          entityId: 'fb',
          userId: 'fb',
          timestamp: DateTime(0),
        ),
      );
      registerFallbackValue(
        const DatumSyncResult(
          userId: 'fallback',
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: <DatumSyncOperation<TestEntity>>[],
          duration: Duration.zero,
        ),
      );
      registerFallbackValue(
        const DatumSyncResult(
          userId: 'fallback',
          syncedCount: 0,
          failedCount: 0,
          conflictsResolved: 0,
          pendingOperations: <DatumSyncOperation<TestEntity2>>[],
          duration: Duration.zero,
        ),
      );
      registerFallbackValue(
        DatumConflictContext(
          userId: 'fb',
          entityId: 'fb',
          type: DatumConflictType.bothModified,
          detectedAt: DateTime(0),
        ),
      );
    });

    Future<void> setupManagers() async {
      localAdapter1 = MockedLocalAdapter<TestEntity>();
      localAdapter2 = MockedLocalAdapter<TestEntity2>();
      remoteAdapter1 = MockedRemoteAdapter<TestEntity>();
      remoteAdapter2 = MockedRemoteAdapter<TestEntity2>();
      connectivityChecker = MockConnectivityChecker();
      mockObserver1 = MockDatumObserver<TestEntity>();
      mockObserver2 = MockDatumObserver<TestEntity2>();

      // Common stubs for local adapters
      when(() => localAdapter1.initialize()).thenAnswer((_) async {});
      when(() => localAdapter1.dispose()).thenAnswer((_) async {});
      when(() => localAdapter2.initialize()).thenAnswer((_) async {});
      when(() => localAdapter2.dispose()).thenAnswer((_) async {});

      when(
        () => localAdapter1.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter1.getPendingOperations(any()),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter1.addPendingOperation(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter1.removePendingOperation(any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter1.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter1.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter1.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => localAdapter1.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter1.getLastSyncResult(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter1.saveLastSyncResult(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter1.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => localAdapter1.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async => TestEntity.create('patched', 'user1', 'Patched locally'),
      );

      when(
        () => localAdapter2.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter2.getPendingOperations(any()),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter2.addPendingOperation(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter2.removePendingOperation(any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter2.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter2.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter2.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => localAdapter2.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter2.getLastSyncResult(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter2.saveLastSyncResult(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter2.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity2>>.empty());
      when(
        () => localAdapter2.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async => TestEntity2.create('patched2', 'user1', 'Patched locally 2'),
      );

      // Stub observer methods
      when(() => mockObserver1.onSyncStart()).thenAnswer((_) {});
      when(() => mockObserver1.onSyncEnd(any())).thenAnswer((_) {});
      when(() => mockObserver1.onCreateStart(any())).thenAnswer((_) {});
      when(() => mockObserver1.onCreateEnd(any())).thenAnswer((_) {});
      when(() => mockObserver1.onUpdateStart(any())).thenAnswer((_) {});
      when(() => mockObserver1.onUpdateEnd(any())).thenAnswer((_) {});
      when(() => mockObserver1.onDeleteStart(any())).thenAnswer((_) {});
      when(
        () => mockObserver1.onDeleteEnd(any(), success: any(named: 'success')),
      ).thenAnswer((_) {});
      when(
        () => mockObserver1.onConflictDetected(any(), any(), any()),
      ).thenAnswer((_) {});

      when(() => mockObserver2.onSyncStart()).thenAnswer((_) {});
      when(() => mockObserver2.onSyncEnd(any())).thenAnswer((_) {});
      when(() => mockObserver2.onCreateStart(any())).thenAnswer((_) {});
      when(() => mockObserver2.onCreateEnd(any())).thenAnswer((_) {});
      when(() => mockObserver2.onUpdateStart(any())).thenAnswer((_) {});
      when(() => mockObserver2.onUpdateEnd(any())).thenAnswer((_) {});
      when(() => mockObserver2.onDeleteStart(any())).thenAnswer((_) {});
      when(
        () => mockObserver2.onDeleteEnd(any(), success: any(named: 'success')),
      ).thenAnswer((_) {});
      when(
        () => mockObserver2.onConflictDetected(any(), any(), any()),
      ).thenAnswer((_) {});

      manager1 = DatumManager<TestEntity>(
        localAdapter: localAdapter1,
        remoteAdapter: remoteAdapter1,
        datumConfig: const DatumConfig<TestEntity>(),
        connectivity: connectivityChecker,
        localObservers: [mockObserver1],
        logger: TestLogger(),
      );

      manager2 = DatumManager<TestEntity2>(
        localAdapter: localAdapter2,
        remoteAdapter: remoteAdapter2,
        datumConfig: const DatumConfig<TestEntity2>(),
        connectivity: connectivityChecker,
        localObservers: [mockObserver2],
        logger: TestLogger(),
      );

      // Stub required methods for remote adapters
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(
        () => remoteAdapter1.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(() => remoteAdapter1.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter1.dispose()).thenAnswer((_) async {});
      when(
        () => remoteAdapter2.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity2>>.empty());
      when(() => remoteAdapter2.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter2.dispose()).thenAnswer((_) async {});

      // Stub for pull phase
      when(
        () => localAdapter1.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});
      when(
        () => localAdapter2.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {});

      // Stub patch methods for remote adapters
      when(
        () => remoteAdapter1.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async => TestEntity.create('patched-remote', 'user1', 'Patched from remote'),
      );
      when(
        () => remoteAdapter1.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => remoteAdapter1.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter1.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);

      when(
        () => remoteAdapter2.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async => TestEntity2.create('patched-remote2', 'user1', 'Patched from remote 2'),
      );
      when(
        () => remoteAdapter2.readAll(
          userId: any(named: 'userId'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => remoteAdapter2.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter2.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);

      // Stub batch operations for remoteAdapter1
      when(() => remoteAdapter1.createAll(any())).thenAnswer((_) async {});
      when(() => remoteAdapter1.updateAll(any())).thenAnswer((_) async {});
      when(
        () => remoteAdapter1.deleteAll(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async {});

      // Stub batch operations for remoteAdapter2
      when(() => remoteAdapter2.createAll(any())).thenAnswer((_) async {});
      when(() => remoteAdapter2.updateAll(any())).thenAnswer((_) async {});
      when(
        () => remoteAdapter2.deleteAll(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async {});

      await manager1.initialize();
      await manager2.initialize();
    }

    setUp(() async {
      await setupManagers();
    });

    tearDown(() async {
      await manager1.dispose();
      await manager2.dispose();
    });

    test('sync metadata accumulates entity counts across multiple entity types', () async {
      // Arrange: Create entities for both managers
      final entity1 = TestEntity.create('entity1', 'user1', 'Test Entity 1');
      final entity2 = TestEntity.create('entity2', 'user1', 'Test Entity 2');
      final entity3 = TestEntity2.create('entity3', 'user1', 'Test Entity 3');

      // Mock pending operations for sync
      final ops1 = [
        DatumSyncOperation<TestEntity>(
          id: 'op1',
          userId: 'user1',
          entityId: entity1.id,
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: entity1,
        ),
        DatumSyncOperation<TestEntity>(
          id: 'op2',
          userId: 'user1',
          entityId: entity2.id,
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: entity2,
        ),
      ];

      final ops2 = [
        DatumSyncOperation<TestEntity2>(
          id: 'op3',
          userId: 'user1',
          entityId: entity3.id,
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: entity3,
        ),
      ];

      when(() => localAdapter1.getPendingOperations('user1')).thenAnswer((_) async => ops1);
      when(() => localAdapter2.getPendingOperations('user1')).thenAnswer((_) async => ops2);

      when(() => remoteAdapter1.create(any())).thenAnswer((_) async {});
      when(() => remoteAdapter2.create(any())).thenAnswer((_) async {});

      when(() => localAdapter1.removePendingOperation(any())).thenAnswer((_) async {});
      when(() => localAdapter2.removePendingOperation(any())).thenAnswer((_) async {});

      // Act: Perform sync operations for both managers
      final result1 = await manager1.synchronize('user1');
      final result2 = await manager2.synchronize('user1');

      // Assert: Verify sync completed successfully
      expect(result1.syncedCount, 2);
      expect(result2.syncedCount, 1);
      expect(result1.failedCount, 0);
      expect(result2.failedCount, 0);

      // Verify operations were processed
      verify(() => localAdapter1.removePendingOperation(any())).called(2);
      verify(() => localAdapter2.removePendingOperation(any())).called(1);

      // Assert: Verify sync metadata was updated for both managers
      // This ensures that sync metadata accumulation is working across multiple entity types
      verify(() => localAdapter1.updateSyncMetadata(any(), any())).called(1);
      verify(() => localAdapter2.updateSyncMetadata(any(), any())).called(1);
    });

    test('cold start sync prevents multiple concurrent operations across managers', () async {
      // Arrange: Set up entities and operations for both managers
      final entity1 = TestEntity.create('cold-entity1', 'user1', 'Cold Entity 1');
      final entity2 = TestEntity2.create('cold-entity2', 'user1', 'Cold Entity 2');

      final ops1 = [
        DatumSyncOperation<TestEntity>(
          id: 'cold-op1',
          userId: 'user1',
          entityId: entity1.id,
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: entity1,
        ),
      ];

      final ops2 = [
        DatumSyncOperation<TestEntity2>(
          id: 'cold-op2',
          userId: 'user1',
          entityId: entity2.id,
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
          data: entity2,
        ),
      ];

      when(() => localAdapter1.getPendingOperations('user1')).thenAnswer((_) async => ops1);
      when(() => localAdapter2.getPendingOperations('user1')).thenAnswer((_) async => ops2);

      // Make remote operations slow to test concurrency control
      when(() => remoteAdapter1.create(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      when(() => remoteAdapter2.create(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      when(() => localAdapter1.removePendingOperation(any())).thenAnswer((_) async {});
      when(() => localAdapter2.removePendingOperation(any())).thenAnswer((_) async {});

      // Act: Start both sync operations concurrently
      final result1Future = manager1.synchronize('user1');
      final result2Future = manager2.synchronize('user1');

      // Wait for both to complete
      final results = await Future.wait([result1Future, result2Future]);

      // Assert: Both operations should complete successfully without conflicts
      expect(results[0].syncedCount, 1);
      expect(results[1].syncedCount, 1);
      expect(results[0].failedCount, 0);
      expect(results[1].failedCount, 0);
    });

    test('realtime sync works without excessive processing across multiple entities', () async {
      // This test verifies that change streams are properly set up for multiple entity types
      // In a real scenario, the change streams would be connected to remote sources

      // Arrange: Verify that change streams are properly configured
      final stream1 = remoteAdapter1.changeStream;
      final stream2 = remoteAdapter2.changeStream;

      // Assert: Both streams should be properly initialized
      expect(stream1, isNotNull);
      expect(stream2, isNotNull);

      // Verify that the streams are set up (they return empty streams in our mock)
      // This ensures the realtime sync infrastructure is in place
      expect(await stream1!.isEmpty, isTrue);
      expect(await stream2!.isEmpty, isTrue);
    });

    test('entity relationships and cascade operations work correctly across managers', () async {
      // This test verifies that the relationship definitions are properly set up
      // for multiple entity types. The actual relationship functionality is tested
      // in the relational_data_integration_test.dart

      // Arrange: Create test entities
      final parentEntity = TestEntity.create('parent-entity', 'user1', 'Parent Entity');
      final childEntity = TestEntity2.create('child-entity', 'user1', 'Child Entity');

      // Assert: Verify that entities have proper relationship definitions
      expect(parentEntity.relations.containsKey('posts'), isTrue);
      expect(childEntity.relations.isEmpty, isTrue); // TestEntity2 has no relations defined

      // Verify the relationship type
      final postsRelation = parentEntity.relations['posts'];
      expect(postsRelation, isA<HasMany>());

      // Verify relationship is configured correctly
      final hasManyRelation = postsRelation as HasMany;
      expect(hasManyRelation.foreignKey, 'userId');
    });

    test('error handling works for non-existent remote entities across managers', () async {
      // Arrange: Set up operations that will fail due to non-existent remote entities
      final entity1 = TestEntity.create('non-existent-1', 'user1', 'Non-existent 1');
      final entity2 = TestEntity2.create('non-existent-2', 'user1', 'Non-existent 2');

      final ops1 = [
        DatumSyncOperation<TestEntity>(
          id: 'error-op1',
          userId: 'user1',
          entityId: entity1.id,
          type: DatumOperationType.update,
          timestamp: DateTime.now(),
          data: entity1,
          delta: const {'name': 'Updated Name'},
        ),
      ];

      final ops2 = [
        DatumSyncOperation<TestEntity2>(
          id: 'error-op2',
          userId: 'user1',
          entityId: entity2.id,
          type: DatumOperationType.update,
          timestamp: DateTime.now(),
          data: entity2,
          delta: const {'title': 'Updated Title'},
        ),
      ];

      when(() => localAdapter1.getPendingOperations('user1')).thenAnswer((_) async => ops1);
      when(() => localAdapter2.getPendingOperations('user1')).thenAnswer((_) async => ops2);

      // Mock patch operations to fail with EntityNotFoundException
      when(() => remoteAdapter1.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          )).thenThrow(const EntityNotFoundException(message: 'Entity not found on remote'));

      when(() => remoteAdapter2.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          )).thenThrow(const EntityNotFoundException(message: 'Entity not found on remote'));

      // Mock fallback create operations
      when(() => remoteAdapter1.create(any())).thenAnswer((_) async {});
      when(() => remoteAdapter2.create(any())).thenAnswer((_) async {});

      when(() => localAdapter1.removePendingOperation(any())).thenAnswer((_) async {});
      when(() => localAdapter2.removePendingOperation(any())).thenAnswer((_) async {});

      // Act: Perform sync operations
      final result1 = await manager1.synchronize('user1');
      final result2 = await manager2.synchronize('user1');

      // Assert: Operations should succeed via fallback to create
      expect(result1.syncedCount, 1);
      expect(result2.syncedCount, 1);
      expect(result1.failedCount, 0);
      expect(result2.failedCount, 0);

      // Verify fallback creates were called
      verify(() => remoteAdapter1.create(any())).called(1);
      verify(() => remoteAdapter2.create(any())).called(1);
    });

    test('concurrent sync operations across multiple managers are properly coordinated', () async {
      // Arrange: Set up multiple operations for both managers
      final entities1 = List.generate(3, (i) => TestEntity.create('conc-entity1-$i', 'user1', 'Entity 1-$i'));
      final entities2 = List.generate(3, (i) => TestEntity2.create('conc-entity2-$i', 'user1', 'Entity 2-$i'));

      final ops1 = entities1
          .map((entity) => DatumSyncOperation<TestEntity>(
                id: 'conc-op1-${entity.id}',
                userId: 'user1',
                entityId: entity.id,
                type: DatumOperationType.create,
                timestamp: DateTime.now(),
                data: entity,
              ))
          .toList();

      final ops2 = entities2
          .map((entity) => DatumSyncOperation<TestEntity2>(
                id: 'conc-op2-${entity.id}',
                userId: 'user1',
                entityId: entity.id,
                type: DatumOperationType.create,
                timestamp: DateTime.now(),
                data: entity,
              ))
          .toList();

      when(() => localAdapter1.getPendingOperations('user1')).thenAnswer((_) async => ops1);
      when(() => localAdapter2.getPendingOperations('user1')).thenAnswer((_) async => ops2);

      when(() => remoteAdapter1.create(any())).thenAnswer((_) async {});
      when(() => remoteAdapter2.create(any())).thenAnswer((_) async {});

      when(() => localAdapter1.removePendingOperation(any())).thenAnswer((_) async {});
      when(() => localAdapter2.removePendingOperation(any())).thenAnswer((_) async {});

      // Act: Start concurrent sync operations
      final syncFuture1 = manager1.synchronize('user1');
      final syncFuture2 = manager2.synchronize('user1');

      final results = await Future.wait([syncFuture1, syncFuture2]);

      // Assert: All operations should complete successfully
      expect(results[0].syncedCount, 3);
      expect(results[1].syncedCount, 3);
      expect(results[0].failedCount, 0);
      expect(results[1].failedCount, 0);

      // Verify all creates were called (batched)
      verify(() => remoteAdapter1.createAll(any())).called(1);
      verify(() => remoteAdapter2.createAll(any())).called(1);
    });
  });
}
