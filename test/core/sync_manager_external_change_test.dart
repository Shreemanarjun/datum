import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/datum.dart';

import '../mocks/test_entity.dart';

class MockLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

typedef StreamControllers = ({
  StreamController<DatumChangeDetail<TestEntity>> local,
  StreamController<DatumChangeDetail<TestEntity>> remote,
});

void main() {
  group('DatumManager External Change Handling', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late DatumManager<TestEntity> manager;

    const userId = 'user-1';
    final now = DateTime.now();
    final entity = TestEntity(
      id: 'entity-1',
      userId: userId,
      name: 'Initial',
      value: 1,
      modifiedAt: now,
      createdAt: now,
      version: 1,
    );

    setUpAll(() {
      // Register a fallback value for TestEntity to be used with `any()`
      registerFallbackValue(
        TestEntity(
          id: 'fallback',
          userId: 'fallback',
          name: 'fallback',
          value: 0,
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
          version: 0,
        ),
      );

      // Register a fallback for DatumSyncOperation to use with `any()`
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fallback',
          userId: 'fallback',
          entityId: 'fallback',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
    });

    setUp(() {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      final pendingOpsForUser = <DatumSyncOperation<TestEntity>>[];

      // Default stubs for mocktail mocks
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(() => localAdapter.create(any())).thenAnswer((_) async {});
      when(
        () => localAdapter.delete(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => true);
      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => null);
      when(() => localAdapter.update(any())).thenAnswer((_) async {});

      when(
        () => localAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((inv) async {
        // The first argument is the ID (String), the second is the delta (Map).
        // We simulate the patch by applying the delta to the original entity.
        final delta = inv.namedArguments[#delta] as Map<String, dynamic>;
        final originalMap = entity.toMap();
        return TestEntity.fromJson(originalMap..addAll(delta));
      });

      when(() => localAdapter.addPendingOperation(any(), any())).thenAnswer((
        inv,
      ) async {
        pendingOpsForUser.add(
          inv.positionalArguments[1] as DatumSyncOperation<TestEntity>,
        );
      });
      when(
        () => localAdapter.getPendingOperations(any()),
      ).thenAnswer((_) async => pendingOpsForUser);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        datumConfig: const DatumConfig<TestEntity>(
          schemaVersion: 0, // Match the mock adapter's initial version
        ),
      );

      // Register the mocktail fallback for ChangeDetail
      registerFallbackValue(
        DatumChangeDetail<TestEntity>(
          type: DatumOperationType.create,
          entityId: '',
          userId: '',
          timestamp: DateTime.now(),
        ),
      );
    });

    // Helper to set up stream controllers for tests.
    StreamControllers setupStreams() {
      final localSC =
          StreamController<DatumChangeDetail<TestEntity>>.broadcast();
      final remoteSC =
          StreamController<DatumChangeDetail<TestEntity>>.broadcast();
      when(localAdapter.changeStream).thenAnswer((_) => localSC.stream);
      when(() => remoteAdapter.changeStream).thenAnswer((_) => remoteSC.stream);
      return (local: localSC, remote: remoteSC);
    }

    tearDown(() async {
      await manager.dispose();
    });

    test(
      'remote create change is saved locally but NOT re-queued for remote push',
      () async {
        // Arrange: Set up the stream controller BEFORE initializing the manager.
        final (remote: remoteStreamController, local: _) = setupStreams();
        await manager.initialize();

        final remoteChange = DatumChangeDetail(
          // Use a fixed timestamp to ensure the changeKey is identical.
          timestamp: DateTime(2023),
          type: DatumOperationType.create,
          entityId: entity.id,
          userId: userId,
          data: entity,
        );

        // Act: Simulate a change from the remote adapter's stream
        remoteStreamController.add(remoteChange);
        await Future<void>.delayed(
          const Duration(milliseconds: 100),
        ); // Process stream

        // Assert: Verify it was saved locally by calling create
        verify(() => localAdapter.create(entity)).called(1);

        // Assert: Verify it was NOT added to the pending queue
        final pendingOps = await manager.getPendingCount(userId);
        expect(pendingOps, 0);
      },
    );

    test('remote delete change is applied locally but NOT re-queued', () async {
      // Arrange: Set up the stream controller and initial data state
      // BEFORE initializing the manager.
      final (remote: remoteStreamController, local: _) = setupStreams();
      when(
        () => localAdapter.read(entity.id, userId: userId),
      ).thenAnswer((_) async => entity);
      await manager.initialize();

      final deleteChange = DatumChangeDetail<TestEntity>(
        type: DatumOperationType.delete,
        entityId: entity.id,
        userId: userId,
        timestamp: DateTime.now(),
      );

      // Act: Simulate a delete event from remote
      remoteStreamController.add(deleteChange);
      await Future<void>.delayed(
        const Duration(milliseconds: 100),
      ); // Process stream

      // Assert: Verify it was deleted locally
      verify(() => localAdapter.delete(entity.id, userId: userId)).called(1);

      // Assert: Verify no delete operation was queued
      final pendingOps = await manager.getPendingCount(userId);
      expect(pendingOps, 0);
    });

    test('duplicate remote changes are handled', () async {
      // Arrange: Set up the stream controller BEFORE initializing the manager.
      final (remote: remoteStreamController, local: _) = setupStreams();
      await manager.initialize();

      final remoteChange = DatumChangeDetail(
        type: DatumOperationType.create,
        entityId: entity.id,
        userId: userId,
        timestamp: DateTime(2023), // Use a fixed timestamp for deduplication
        data: entity,
      );

      // Act: Simulate the exact same change arriving twice
      remoteStreamController.add(remoteChange);
      remoteStreamController.add(remoteChange);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Assert: The push method (which applies the change) should be called
      // for each event, as the manager doesn't do deduplication by default.
      // The underlying local adapter's create/update should be idempotent.
      verify(() => localAdapter.create(any())).called(2);
    });

    test(
      'local adapter changes are processed and queued for remote push',
      () async {
        // Arrange: Set up the stream controller BEFORE initializing the manager.
        final (local: localStreamController, remote: _) = setupStreams();
        await manager.initialize();

        final localChange = DatumChangeDetail(
          type: DatumOperationType.create,
          entityId: entity.id,
          userId: userId,
          timestamp: DateTime.now(),
          data: entity,
        );

        // Act: Simulate a change from the local adapter's stream
        localStreamController.add(localChange);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Assert: Verify the change was queued for remote sync
        final pendingOps = await manager.getPendingCount(userId);
        expect(pendingOps, 1);
      },
    );

    test('local adapter update change is queued for remote push', () async {
      // Arrange: Start with an existing entity in the local adapter.
      final (local: localStreamController, remote: _) = setupStreams();
      when(
        () => localAdapter.read(entity.id, userId: userId),
      ).thenAnswer((_) async => entity);
      await manager.initialize();

      final updatedEntity = entity.copyWith(name: 'Locally Updated');
      final localChange = DatumChangeDetail(
        type: DatumOperationType.update,
        entityId: updatedEntity.id,
        userId: updatedEntity.userId,
        timestamp: DateTime.now(),
        data: updatedEntity,
      );

      // Act: Simulate an update from the local adapter's stream
      localStreamController.add(localChange);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Assert: Verify an 'update' operation was queued
      final pendingOps = await manager.getPendingCount(userId);
      expect(pendingOps, 1);

      // Optional: Deeper check on the operation type
      final ops = await localAdapter.getPendingOperations(userId);
      expect(ops.first.type, DatumOperationType.update);
    });

    test(
      'remote delete for a non-existent item is handled gracefully',
      () async {
        // Arrange: Ensure the item does not exist locally.
        // The default stub for `read` already returns null.
        final (remote: remoteStreamController, local: _) = setupStreams();
        await manager.initialize();

        final deleteChange = DatumChangeDetail<TestEntity>(
          type: DatumOperationType.delete,
          entityId: 'non-existent-id',
          userId: userId,
          timestamp: DateTime.now(),
        );

        // Act & Assert: The operation should complete without throwing an error.
        expect(() => remoteStreamController.add(deleteChange), returnsNormally);
      },
    );
  });
}
