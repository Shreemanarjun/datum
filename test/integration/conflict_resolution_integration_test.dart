import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/datum.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class MockedLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

void main() {
  group('Conflict Resolution Integration Tests', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    const userId = 'user-conflict';
    final baseTime = DateTime(2023);

    // Local is older, remote is newer
    final localEntity = TestEntity(
      id: 'conflict-1',
      userId: userId,
      name: 'Local Version',
      value: 1,
      modifiedAt: baseTime,
      createdAt: baseTime,
      version: 1,
    );

    final remoteEntity = localEntity.copyWith(
      name: 'Remote Version',
      value: 2,
      modifiedAt: baseTime.add(const Duration(minutes: 5)),
      version: 2,
    );

    setUpAll(() {
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(DatumSyncMetadata(userId: 'fb', dataHash: 'fb'));
      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fb-op',
          userId: 'fb',
          entityId: 'fb-entity',
          type: DatumOperationType.create,
          timestamp: DateTime(0),
        ),
      );
    });

    Future<void> setupManager(
      DatumConflictResolver<TestEntity> resolver,
    ) async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Stub basic adapter methods
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(localAdapter.changeStream).thenAnswer((_) => const Stream.empty());
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream.empty());

      // Stub methods to handle pre-populating data
      when(
        () => localAdapter.read(localEntity.id, userId: userId),
      ).thenAnswer((_) async => localEntity);
      when(
        () => remoteAdapter.readAll(
          userId: userId,
          scope: any(named: 'scope'),
        ),
      ).thenAnswer((_) async => [remoteEntity]);

      // Stub methods for conflict resolution and sync process
      when(
        () => localAdapter.readByIds(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => {remoteEntity.id: localEntity});
      when(() => localAdapter.update(any())).thenAnswer((_) async {});
      when(
        () => localAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer(
        (inv) async => TestEntity.fromJson(
          inv.namedArguments[#delta] as Map<String, dynamic>,
        ),
      );

      when(
        () => localAdapter.getPendingOperations(any()),
      ).thenAnswer((_) async => []);
      when(
        () => localAdapter.addPendingOperation(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => localAdapter.getSyncMetadata(any()),
      ).thenAnswer((_) async => null);
      when(
        () => localAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => remoteAdapter.updateSyncMetadata(any(), any()),
      ).thenAnswer((_) async {});
      // Stub migration-related methods to prevent initialization errors.
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      // Stub for metadata generation after pull.
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => []);
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: resolver,
        connectivity: connectivityChecker,
      );

      await manager.initialize();
    }

    test('LastWriteWinsResolver: remote version should win', () async {
      // Arrange
      await setupManager(LastWriteWinsResolver<TestEntity>());

      // Act
      final result = await manager.synchronize(userId);

      // Assert
      expect(result.failedCount, 0);
      expect(result.conflictsResolved, 1);

      // Verify that the local adapter was updated with the remote entity.
      final captured = verify(() => localAdapter.update(captureAny())).captured;
      expect(captured, hasLength(1));
      final savedEntity = captured.first as TestEntity;
      expect(savedEntity.name, 'Remote Version');
      expect(savedEntity.version, 2);
    });

    test('LocalPriorityResolver: local version should win', () async {
      // Arrange
      await setupManager(LocalPriorityResolver<TestEntity>());

      // Act
      final result = await manager.synchronize(userId);

      // Assert
      expect(result.failedCount, 0);
      expect(result.conflictsResolved, 1);

      // The local version should be kept. The `getById` stub will still return
      // the original local entity, which is the correct outcome.
      final localResult = await manager.read(localEntity.id, userId: userId);
      expect(localResult!.name, 'Local Version');

      // The `update` method on the local adapter should not have been called
      // because the resolution was to keep the local version.
      verifyNever(() => localAdapter.update(any()));
    });

    test('RemotePriorityResolver: remote version should win', () async {
      // Arrange
      await setupManager(RemotePriorityResolver<TestEntity>());

      // Act
      final result = await manager.synchronize(userId);

      // Assert
      expect(result.failedCount, 0);
      expect(result.conflictsResolved, 1);

      // Verify that the local adapter was updated with the remote entity.
      final captured = verify(() => localAdapter.update(captureAny())).captured;
      expect(captured, hasLength(1));
      final savedEntity = captured.first as TestEntity;
      expect(savedEntity.name, 'Remote Version');
      expect(savedEntity.version, 2);
    });

    test('MergeResolver: custom merge logic should be applied', () async {
      // Arrange: A custom resolver that merges fields
      final mergeResolver = MergeResolver<TestEntity>(
        onMerge: (local, remote, context) async {
          // Custom logic: take remote's name, but local's value, and increment version
          return local.copyWith(
            name: remote.name,
            version: remote.version, // Take the higher version
            modifiedAt: DateTime.now(),
          );
        },
      );
      await setupManager(mergeResolver);

      // Act
      final result = await manager.synchronize(userId);

      // Assert
      expect(result.failedCount, 0);
      expect(result.conflictsResolved, 1);

      // Verify that the local adapter was updated with the MERGED entity.
      final captured = verify(() => localAdapter.update(captureAny())).captured;
      expect(captured, hasLength(1));
      final mergedEntity = captured.first as TestEntity;
      expect(mergedEntity.name, 'Remote Version'); // From remote
      expect(mergedEntity.value, 1); // From local
    });

    group('Conflicts with pending local patches (diff updates)', () {
      // This group tests what happens when a local change (a patch/diff) is
      // queued, and a conflicting change is discovered during the pull phase
      // of the same sync cycle. The SyncEngine's order is PUSH -> PULL.

      late TestEntity localPatch;
      final pendingOps = <DatumSyncOperation<TestEntity>>[];

      test('LastWriteWinsResolver: remote wins, overwriting the local patch',
          () async {
        // Arrange
        await setupManager(LastWriteWinsResolver<TestEntity>());
        // Use manager.push to correctly add the operation to the queue.
        // The `getById` stub ensures the diff is calculated against the original.
        localPatch = localEntity.copyWith(
          name: 'Local Patch Update',
          modifiedAt: baseTime.add(
            const Duration(minutes: 2),
          ), // Newer than local, older than remote
          version: 2,
        );

        // Stub the local patch call that happens inside manager.push()
        when(
          () => localAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async => localPatch);

        when(
          () => localAdapter.read(localPatch.id, userId: userId),
        ).thenAnswer((_) async => localEntity);

        // Let the real push method add the operation to our mock queue
        when(() => localAdapter.addPendingOperation(userId, any())).thenAnswer((
          inv,
        ) async {
          pendingOps.add(
            inv.positionalArguments[1] as DatumSyncOperation<TestEntity>,
          );
        });
        when(
          () => localAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => pendingOps);
        when(() => localAdapter.removePendingOperation(any())).thenAnswer((
          inv,
        ) async {
          pendingOps.removeWhere(
            (op) => op.id == inv.positionalArguments.first,
          );
        });

        // This will queue the operation in `pendingOps`
        await manager.push(item: localPatch, userId: userId);

        // When the pull phase happens, the conflict is detected.
        // The local state is now `localPatch`.
        when(
          () => localAdapter.readByIds(any(), userId: userId),
        ).thenAnswer((_) async => {remoteEntity.id: localPatch});

        // Act: Sync
        // 1. PUSH phase: The `localPatch` is sent to the remote via `patch()`.
        // 2. PULL phase: `fetchAll` gets the `remoteEntity`. A conflict is
        //    detected between the just-pushed `localPatch` and the `remoteEntity`.
        // 3. RESOLVE: `LastWriteWinsResolver` sees `remoteEntity` is newer and
        //    chooses it.
        // 4. SAVE: The `remoteEntity` is saved to the local adapter, overwriting
        //    the state of `localPatch`.
        when(
          () => remoteAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta', that: isA<Map<String, dynamic>>()),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((invocation) async {
          // During the PUSH phase, the patch should succeed and return the
          // patched entity, NOT the conflicting remote one.
          return localPatch;
        });

        // Act: Sync
        await manager.synchronize(userId);

        // Assert: The local patch was sent first during the push phase.
        final capturedPatch = verify(
          () => remoteAdapter.patch(
            id: localEntity.id,
            delta: captureAny(named: 'delta'),
            userId: userId,
          ),
        ).captured.first as Map<String, dynamic>;
        expect(capturedPatch['name'], 'Local Patch Update');

        // Then, the conflict was resolved, and the remote version was saved locally.
        final capturedPush = verify(
          () => localAdapter.update(captureAny()),
        ).captured;
        expect(capturedPush, hasLength(1));
        final savedEntity = capturedPush.first as TestEntity;
        expect(savedEntity.name, 'Remote Version'); // Remote version won.
      });

      test('LocalPriorityResolver: local patch wins and is kept', () async {
        // Arrange
        await setupManager(LocalPriorityResolver<TestEntity>());
        // Use manager.push to correctly add the operation to the queue.
        localPatch = localEntity.copyWith(
          name: 'Local Patch Update',
          modifiedAt: baseTime.add(
            const Duration(minutes: 2),
          ), // Newer than local, older than remote
          version: 2,
        );

        // The `getById` stub ensures the diff is calculated against the original.
        when(
          () => localAdapter.read(localPatch.id, userId: userId),
        ).thenAnswer((_) async => localEntity);
        when(
          () => localAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta'),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async => localPatch);

        // Let the real push method add the operation to our mock queue
        when(() => localAdapter.addPendingOperation(userId, any())).thenAnswer((
          inv,
        ) async {
          pendingOps.add(
            inv.positionalArguments[1] as DatumSyncOperation<TestEntity>,
          );
        });
        when(
          () => localAdapter.getPendingOperations(userId),
        ).thenAnswer((_) async => pendingOps);
        when(() => localAdapter.removePendingOperation(any())).thenAnswer((
          inv,
        ) async {
          pendingOps.removeWhere(
            (op) => op.id == inv.positionalArguments.first,
          );
        });

        // This will queue the operation in `pendingOps`
        await manager.push(item: localPatch, userId: userId);

        // When the pull phase happens, the conflict is detected.
        when(
          () => localAdapter.readByIds(any(), userId: userId),
        ).thenAnswer((_) async => {remoteEntity.id: localEntity});

        when(
          () => remoteAdapter.patch(
            id: any(named: 'id'),
            delta: any(named: 'delta', that: isA<Map<String, dynamic>>()),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((invocation) async {
          // During the PUSH phase, the patch should succeed and return the
          // patched entity, NOT the conflicting remote one.
          return localPatch;
        });

        await manager.synchronize(userId);

        // Assert
        // The local patch was sent first.
        final capturedPatch = verify(
          () => remoteAdapter.patch(
            id: localEntity.id,
            delta: captureAny(
              named: 'delta',
              that: isA<Map<String, dynamic>>(),
            ),
            userId: userId,
          ),
        ).captured.first as Map<String, dynamic>;
        expect(capturedPatch['name'], 'Local Patch Update');

        // No subsequent update to the local adapter should have happened.
        verifyNever(() => localAdapter.update(remoteEntity));
      });
    });
  });
}
