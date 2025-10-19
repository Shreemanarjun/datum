import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// Define mocktail mocks directly in the test file for clarity and correctness.
class MockLocalAdapter<T extends DatumEntity> extends Mock
    implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock
    implements RemoteAdapter<T> {}

class MockMiddleware<T extends DatumEntity> extends Mock
    implements DatumMiddleware<T> {}

class MockObserver<T extends DatumEntity> extends Mock
    implements DatumObserver<T> {}

void main() {
  group('DatumMiddleware', () {
    late DatumManager<TestEntity> manager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockMiddleware<TestEntity> middleware;

    const userId = 'user1';
    final now = DateTime.now();
    final entity = TestEntity(
      id: 'e1',
      userId: userId,
      name: 'Test',
      value: 0,
      modifiedAt: now,
      createdAt: now,
      version: 1,
    );

    setUpAll(() {
      // Register fallback values for custom types used with `any()` in mocktail.
      registerFallbackValue(
        TestEntity(
          id: 'fb',
          userId: 'fb',
          name: 'fb',
          value: 0,
          modifiedAt: now,
          createdAt: now,
          version: 1,
        ),
      );

      registerFallbackValue(
        DatumSyncOperation<TestEntity>(
          id: 'fallback',
          userId: 'fallback',
          entityId: 'fallback',
          type: DatumOperationType.create,
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

      registerFallbackValue(const DatumQuery());
    });

    setUp(() async {
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      middleware = MockMiddleware<TestEntity>();

      // Stub lifecycle methods that are called by the manager
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(
        () => localAdapter.getStoredSchemaVersion(),
      ).thenAnswer((_) async => 0);
      when(
        () => remoteAdapter.changeStream,
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => localAdapter.addPendingOperation(any(), any()),
      ).thenAnswer((_) async {});

      // Stub default behaviors for the new mocktail mocks
      when(() => localAdapter.create(any())).thenAnswer((_) async {});
      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => entity);
      when(
        () => localAdapter.readAll(userId: any(named: 'userId')),
      ).thenAnswer((_) async => [entity]);
      when(
        () => localAdapter.changeStream(),
      ).thenAnswer((_) => const Stream<DatumChangeDetail<TestEntity>>.empty());
      when(
        () => localAdapter.patch(
          id: any(named: 'id'),
          delta: any(named: 'delta'),
          userId: any(named: 'userId'),
        ),
      ).thenAnswer((_) async => entity);

      when(
        () => middleware.transformBeforeSave(any()),
      ).thenAnswer((inv) async => inv.positionalArguments.first as TestEntity);
      when(
        () => middleware.transformAfterFetch(any()),
      ).thenAnswer((inv) async => inv.positionalArguments.first as TestEntity);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: MockConnectivityChecker(),
        datumConfig: DatumConfig(
          errorRecoveryStrategy: DatumErrorRecoveryStrategy(
            maxRetries: 0,
            shouldRetry: (e) async => false,
          ),
          schemaVersion: 0,
        ),
        middlewares: [middleware],
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('transformBeforeSave is called on push()', () async {
      await manager.push(item: entity, userId: userId);

      verify(() => middleware.transformBeforeSave(entity)).called(1);
    });

    test('transformAfterFetch is called on read()', () async {
      await localAdapter.create(entity);

      await manager.read(entity.id, userId: userId);

      verify(() => middleware.transformAfterFetch(entity)).called(1);
    });

    test('transformAfterFetch is called on readAll()', () async {
      await localAdapter.create(entity);

      await manager.readAll(userId: userId);

      verify(() => middleware.transformAfterFetch(entity)).called(1);
    });

    test('transformAfterFetch is called on watchById() stream', () async {
      // Arrange: Middleware adds a suffix on fetch
      final stored = TestEntity(
        id: 'e1',
        userId: userId,
        name: 'Stored',
        value: 0,
        modifiedAt: now,
        createdAt: now,
        version: 1,
      );
      await localAdapter.create(stored);
      when(() => middleware.transformAfterFetch(any())).thenAnswer((inv) async {
        final item = inv.positionalArguments.first as TestEntity;
        return item.copyWith(name: '${item.name} - WatchedById');
      });
      final streamController = StreamController<TestEntity?>.broadcast();
      when(
        () => localAdapter.watchById(stored.id, userId: userId),
      ).thenAnswer((_) => streamController.stream);

      // Act & Assert
      final stream = manager.watchById(stored.id, userId);
      expect(
        stream,
        emitsInOrder([
          // The middleware should transform the initial item from the stream
          isA<TestEntity>().having(
            (e) => e.name,
            'name',
            'Stored - WatchedById',
          ),
        ]),
      );

      // Simulate the initial data being emitted
      streamController.add(stored);
      await streamController.close();
    });

    test('transformAfterFetch is called on query()', () async {
      // Arrange
      await localAdapter.create(entity);
      when(
        () => localAdapter.query(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => [entity]);
      await manager.query(
        const DatumQuery(),
        source: DataSource.local,
        userId: userId,
      );
      verify(() => middleware.transformAfterFetch(entity)).called(1);
    });

    test('Middleware can transform data on push', () async {
      // Arrange: Middleware adds a prefix to the name
      final original = TestEntity(
        id: 'e1',
        userId: userId,
        name: 'Original',
        value: 0,
        modifiedAt: now,
        createdAt: now,
        version: 1,
      );
      // Stub read to find the existing entity for an update
      when(
        () => localAdapter.read(original.id, userId: userId),
      ).thenAnswer((_) async => original);
      when(() => middleware.transformBeforeSave(any())).thenAnswer((inv) async {
        final item = inv.positionalArguments.first as TestEntity;
        return item.copyWith(name: 'Transformed: ${item.name}');
      });

      // Act
      await manager.push(item: original, userId: userId);

      // Assert: Verify that the transformed item was passed to the adapter
      final captured = verify(
        () => localAdapter.patch(
          id: 'e1',
          delta: captureAny(named: 'delta'),
          userId: userId,
        ),
      ).captured;
      final delta = captured.first as Map<String, dynamic>;
      expect(delta['name'], 'Transformed: Original');
    });

    test('Middleware can transform data on fetch', () async {
      // Arrange: Middleware adds a suffix to the name on fetch
      final stored = TestEntity(
        id: 'e1',
        userId: userId,
        name: 'Stored',
        value: 0,
        modifiedAt: now,
        createdAt: now,
        version: 1,
      );
      when(
        () => localAdapter.read(stored.id, userId: userId),
      ).thenAnswer((_) async => stored);
      when(() => middleware.transformAfterFetch(any())).thenAnswer((inv) async {
        final item = inv.positionalArguments.first as TestEntity;
        return item.copyWith(name: '${item.name} - Fetched');
      });

      // Act
      final result = await manager.read(stored.id, userId: userId);

      // Assert
      expect(result, isNotNull);
      expect(result!.name, 'Stored - Fetched');
    });

    test('Chained middlewares are executed in order', () async {
      // Arrange: Set up two middlewares
      final middleware1 = MockMiddleware<TestEntity>();
      final middleware2 = MockMiddleware<TestEntity>();

      // Stub read to find the existing entity for an update
      when(
        () => localAdapter.read(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async => entity);
      // Middleware 1 adds a prefix
      when(() => middleware1.transformBeforeSave(any())).thenAnswer((
        inv,
      ) async {
        final item = inv.positionalArguments.first as TestEntity;
        return item.copyWith(name: 'M1: ${item.name}');
      });
      // Middleware 2 adds a suffix
      when(() => middleware2.transformBeforeSave(any())).thenAnswer((
        inv,
      ) async {
        final item = inv.positionalArguments.first as TestEntity;
        return item.copyWith(name: '${item.name} :M2');
      });

      // Re-initialize manager with both middlewares
      await manager.dispose();
      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: MockConnectivityChecker(),
        middlewares: [middleware1, middleware2],
      );
      await manager.initialize();

      final original = TestEntity(
        id: 'e1',
        userId: userId,
        name: 'Original',
        value: 0,
        modifiedAt: now,
        createdAt: now,
        version: 1,
      );

      // Act
      await manager.push(item: original, userId: userId);

      // Assert: Verify the final transformed item in the database
      final captured = verify(
        () => localAdapter.patch(
          id: 'e1',
          delta: captureAny(named: 'delta'),
          userId: userId,
        ),
      ).captured;
      final delta = captured.first as Map<String, dynamic>;
      expect(delta['name'], 'M1: Original :M2');

      // Verify that the middlewares were called in the correct order
      verifyInOrder([
        () => middleware1.transformBeforeSave(original),
        () => middleware2.transformBeforeSave(
              any(
                  that: predicate(
                      (e) => (e as TestEntity).name == 'M1: Original')),
            ),
      ]);
    });

    test('transformAfterFetch is called on watchAll() stream', () async {
      // Arrange: Middleware adds a suffix on fetch
      final stored = TestEntity(
        id: 'e1',
        userId: userId,
        name: 'Stored',
        value: 0,
        modifiedAt: now,
        createdAt: now,
        version: 1,
      );
      await localAdapter.create(stored);
      when(() => middleware.transformAfterFetch(any())).thenAnswer((inv) async {
        final item = inv.positionalArguments.first as TestEntity;
        return item.copyWith(name: '${item.name} - Watched');
      });

      final streamController = StreamController<List<TestEntity>>.broadcast();
      when(
        () => localAdapter.watchAll(
          userId: userId,
          includeInitialData: any(named: 'includeInitialData'),
        ),
      ).thenAnswer((_) => streamController.stream);

      // Act & Assert
      final stream = manager.watchAll(userId: userId);
      expect(
        stream,
        emitsInOrder([
          // The middleware should transform the items from the stream
          isA<List<TestEntity>>().having(
            (list) => list.first.name,
            'name',
            'Stored - Watched',
          ),
        ]),
      );

      // Simulate the initial data being emitted
      streamController.add([stored]);
      await streamController.close();
    });
  });
}
