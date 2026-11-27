import 'dart:async';

import 'package:datum/datum.dart';
import 'package:signals_core/signals_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../mocks/mock_connectivity_checker.dart';
import '../../mocks/test_entity.dart';
import '../../mocks/forward_bulk_writes.dart';

// Mock classes for testing
class MockLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

void main() {
  setUpAll(() {
    registerFallbackValue(DatumQueryBuilder<TestEntity>().build());
    registerFallbackValue(DataSource.local);
    registerFallbackValue(const PaginationConfig(pageSize: 10));
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
    registerFallbackValue(
      const DatumSyncMetadata(
        userId: 'fallback',
        dataHash: 'fallback',
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
  });

  late MockLocalAdapter<TestEntity> localAdapter;
  late MockRemoteAdapter<TestEntity> remoteAdapter;
  late MockConnectivityChecker connectivityChecker;
  late QueueManager<TestEntity> queueManager;
  late DatumSyncEngine<TestEntity> syncEngine;
  late StreamController<DatumSyncEvent<TestEntity>> eventController;
  late Signal<DatumSyncStatusSnapshot> statusSubject;
  late Signal<DatumSyncMetadata?> metadataSubject;

  setUp(() async {
    localAdapter = MockLocalAdapter<TestEntity>();
    remoteAdapter = MockRemoteAdapter<TestEntity>();
    connectivityChecker = MockConnectivityChecker();
    eventController = StreamController<DatumSyncEvent<TestEntity>>.broadcast();
    statusSubject = signal(DatumSyncStatusSnapshot.initial('test_user'));
    metadataSubject = signal<DatumSyncMetadata?>(null);

    when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

    // Stub default behaviors for adapters
    when(() => localAdapter.initialize()).thenAnswer((_) async {});
    when(() => localAdapter.dispose()).thenAnswer((_) async {});
    when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
    when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
    when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
    when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
    when(() => localAdapter.readByIds(any(), userId: any(named: 'userId'))).thenAnswer((_) async => {});
    when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
    when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
    when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
    when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => []);
    when(() => localAdapter.changeStream()).thenAnswer((_) => const Stream.empty());
    when(() => remoteAdapter.changeStream).thenAnswer((_) => const Stream.empty());
    when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
    when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
    when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) => Future.value(null as DatumSyncMetadata?));
    when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) => Future.value(null as DatumSyncMetadata?));

    queueManager = QueueManager<TestEntity>(
      localAdapter: localAdapter,
      logger: DatumLogger(),
    );

    syncEngine = DatumSyncEngine<TestEntity>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
      conflictResolver: LastWriteWinsResolver<TestEntity>(),
      queueManager: queueManager,
      conflictDetector: DatumConflictDetector<TestEntity>(),
      logger: DatumLogger(),
      config: const DatumConfig(
        schemaVersion: 0,
        remoteSyncBatchSize: 3, // Small batch size for testing
        remoteStreamBatchSize: 2,
        progressEventFrequency: 2,
      ),
      connectivityChecker: connectivityChecker,
      eventController: eventController,
      statusSignal: statusSubject,
      metadataSignal: metadataSubject,
      isolateHelper: const IsolateHelper(),
    );
  });

  tearDown(() {
    eventController.close();
    statusSubject.dispose();
    metadataSubject.dispose();
  });

  group('DatumSyncEngine batch processing', () {
    test('batch processing logic handles remote item streaming', () async {
      const userId = 'test_user';

      // Test that the batch processing logic exists and can handle streaming
      // This test verifies the structure of the batch processing code in _pullChanges

      // Create a simple test that exercises the sync engine
      final remoteItems = [
        TestEntity.create('item1', userId, 'Item 1'),
        TestEntity.create('item2', userId, 'Item 2'),
      ];

      when(() => remoteAdapter.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => remoteItems);

      when(() => localAdapter.readByIds(any(), userId: userId)).thenAnswer((_) async => {});

      when(() => localAdapter.create(any())).thenAnswer((_) async {});

      // Mock metadata to force sync
      when(() => localAdapter.getSyncMetadata(userId)).thenAnswer((_) async => null);
      when(() => remoteAdapter.getSyncMetadata(userId)).thenAnswer((_) async => null);
      when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => []);

      // Mock metadata update
      when(() => localAdapter.updateSyncMetadata(any(), userId)).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), userId)).thenAnswer((_) async {});

      final (_, _) = await syncEngine.synchronize(userId);

      // Verify that items were processed
      // Note: syncedCount is not incremented for pull operations
      verify(() => localAdapter.create(any())).called(2);
    });

    test('batch size configuration affects processing', () async {
      const userId = 'test_user';

      // Test with a different batch size configuration
      final customSyncEngine = DatumSyncEngine<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: LastWriteWinsResolver<TestEntity>(),
        queueManager: queueManager,
        conflictDetector: DatumConflictDetector<TestEntity>(),
        logger: DatumLogger(),
        config: const DatumConfig(
          schemaVersion: 0,
          remoteSyncBatchSize: 2, // Smaller batch size
          remoteStreamBatchSize: 1,
          progressEventFrequency: 1,
        ),
        connectivityChecker: connectivityChecker,
        eventController: eventController,
        statusSignal: statusSubject,
        metadataSignal: metadataSubject,
        isolateHelper: const IsolateHelper(),
      );

      final remoteItems = [
        TestEntity.create('item1', userId, 'Item 1'),
        TestEntity.create('item2', userId, 'Item 2'),
        TestEntity.create('item3', userId, 'Item 3'),
      ];

      when(() => remoteAdapter.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => remoteItems);

      when(() => localAdapter.readByIds(any(), userId: userId)).thenAnswer((_) async => {});

      when(() => localAdapter.create(any())).thenAnswer((_) async {});

      // Mock metadata
      when(() => localAdapter.getSyncMetadata(userId)).thenAnswer((_) async => null);
      when(() => remoteAdapter.getSyncMetadata(userId)).thenAnswer((_) async => null);
      when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => []);

      when(() => localAdapter.updateSyncMetadata(any(), userId)).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), userId)).thenAnswer((_) async {});

      final (_, _) = await customSyncEngine.synchronize(userId);

      // Note: syncedCount is not incremented for pull operations
      verify(() => localAdapter.create(any())).called(3);

      customSyncEngine; // Just to avoid unused variable warning
    });

    test('batch processing handles remaining items correctly', () async {
      const userId = 'test_user';

      // Test with 5 items and batch size 3 - should process 3 + 2
      final remoteItems = [
        TestEntity.create('item1', userId, 'Item 1'),
        TestEntity.create('item2', userId, 'Item 2'),
        TestEntity.create('item3', userId, 'Item 3'),
        TestEntity.create('item4', userId, 'Item 4'),
        TestEntity.create('item5', userId, 'Item 5'),
      ];

      when(() => remoteAdapter.readAll(userId: userId, scope: any(named: 'scope'))).thenAnswer((_) async => remoteItems);

      when(() => localAdapter.readByIds(any(), userId: userId)).thenAnswer((_) async => {});

      when(() => localAdapter.create(any())).thenAnswer((_) async {});

      // Mock metadata
      when(() => localAdapter.getSyncMetadata(userId)).thenAnswer((_) async => null);
      when(() => remoteAdapter.getSyncMetadata(userId)).thenAnswer((_) async => null);
      when(() => localAdapter.getPendingOperations(userId)).thenAnswer((_) async => []);

      when(() => localAdapter.updateSyncMetadata(any(), userId)).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), userId)).thenAnswer((_) async {});

      final (_, _) = await syncEngine.synchronize(userId);

      // Note: syncedCount is not incremented for pull operations
      verify(() => localAdapter.create(any())).called(5);
    });
  });
}
