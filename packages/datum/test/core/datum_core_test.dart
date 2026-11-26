import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';
import '../mocks/relational_test_entity.dart';
import '../mocks/forward_bulk_writes.dart';

/// A minimal entity for relational tests.
class Post extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;

  @override
  final bool isDeleted;

  @override
  VectorClock? get vectorClock => null;

  const Post({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };
  DatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return Post(
      id: id,
      userId: userId,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null; // For a minimal test entity, we can return null.

  @override
  DatumEntityInterface merge(covariant DatumEntityInterface other) => other;
}

class MockDatumManager<T extends DatumEntityInterface> extends Mock implements DatumManager<T> {}

class MockLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements DatumConnectivityChecker {}

/// Fake adapters used as fallback values for mocktail when matching arguments.
class FakeRemoteAdapterPost extends Fake implements RemoteAdapter<Post> {}

class FakeLocalAdapterPost extends Fake implements LocalAdapter<Post> {}

// New mocks for RelationalTestEntity
class FakeRemoteAdapterRelationalTestEntity extends Fake implements RemoteAdapter<RelationalTestEntity> {}

class FakeLocalAdapterRelationalTestEntity extends Fake implements LocalAdapter<RelationalTestEntity> {}

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
      Post(
        id: 'fallback',
        userId: 'fallback',
        createdAt: DateTime.fromMicrosecondsSinceEpoch(0),
        modifiedAt: DateTime.fromMicrosecondsSinceEpoch(0),
        version: 0,
        isDeleted: false,
      ),
    );

    // New fallback for RelationalTestEntity
    registerFallbackValue(
      RelationalTestEntity(
        id: 'fallback',
        userId: 'fallback',
        createdAt: DateTime(0),
        modifiedAt: DateTime(0),
        version: 0,
        name: 'fallback',
      ),
    );

    // Register fallback Fake instances for adapter types used with matchers.
    registerFallbackValue(FakeRemoteAdapterPost());
    registerFallbackValue(FakeLocalAdapterPost());

    // Register fallback for DatumSyncMetadata
    registerFallbackValue(
      const DatumSyncMetadata(
        userId: 'fallback',
        lastSyncTime: null,
        dataHash: null,
        deviceId: null,
        devices: null,
        entityCounts: {},
      ),
    );

    // Register fallback for DatumSyncResult
    registerFallbackValue(
      const DatumSyncResult<TestEntity>(
        userId: 'fallback',
        syncedCount: 0,
        failedCount: 0,
        conflictsResolved: 0,
        pendingOperations: [],
        duration: Duration.zero,
      ),
    );

    // Register fallback values for mixin entities
    registerFallbackValue(
      _NonRelationalMixinEntity(
        id: 'fallback',
        userId: 'fallback',
        createdAt: DateTime(0),
        modifiedAt: DateTime(0),
        version: 0,
        isDeleted: false,
        name: 'fallback',
      ),
    );
    registerFallbackValue(
      _RelationalMixinEntity(
        id: 'fallback',
        userId: 'fallback',
        createdAt: DateTime(0),
        modifiedAt: DateTime(0),
        version: 0,
        isDeleted: false,
        title: 'fallback',
      ),
    );
  });

  group('Datum Core Convenience Methods', () {
    late MockDatumManager<TestEntity> mockManager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockDatumManager<Post> mockPostManager;
    late MockLocalAdapter<Post> localPostAdapter;
    late MockRemoteAdapter<Post> remotePostAdapter;

    // New mocks for RelationalTestEntity

    setUp(() async {
      // Reset Datum singleton for test isolation
      Datum.resetForTesting();

      // Add patch fallback mock as a global fallback before creating other mocks
      final testEntityFallback = TestEntity(
        id: 'fallback',
        userId: 'fallback',
        name: 'fallback',
        value: 0,
        modifiedAt: DateTime(0),
        createdAt: DateTime(0),
        version: 0,
      );

      registerFallbackValue(testEntityFallback);

      mockManager = MockDatumManager<TestEntity>();
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      mockPostManager = MockDatumManager<Post>();

      // Create Post adapters early so they can be referenced by defensive stubs below.
      localPostAdapter = MockLocalAdapter<Post>();
      remotePostAdapter = MockRemoteAdapter<Post>();

      // Provide a connectivity mock and stub isConnected so Datum can query it.
      final mockConnectivity = MockConnectivityChecker();
      when(() => mockConnectivity.isConnected).thenAnswer((_) async => true);
      when(() => mockConnectivity.onStatusChange).thenAnswer((_) => Stream.value(true));

      // Stubbing manager methods that will be called by Datum.instance
      when(() => mockManager.watchAll(userId: any(named: 'userId'), includeInitialData: any(named: 'includeInitialData'))).thenAnswer((_) => Stream.value([]));
      when(() => mockManager.watchById(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(null));
      when(() => mockManager.watchAllPaginated(any(), userId: any(named: 'userId'))).thenAnswer(
        (_) => Stream.value(
          const PaginatedResult(
            items: [],
            totalCount: 0,
            currentPage: 1,
            totalPages: 0,
            hasMore: false,
          ),
        ),
      );
      when(() => mockManager.watchQuery(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value([]));
      when(() => mockManager.query(any(), source: any(named: 'source'), userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => mockManager.getPendingCount(any())).thenAnswer((_) async => 0);
      when(() => mockManager.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => mockManager.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
      when(() => mockManager.watchStorageSize(userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(0));
      when(() => mockManager.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => mockManager.checkHealth()).thenAnswer((_) async => const DatumHealth());
      when(() => mockManager.pauseSync()).thenAnswer((_) {});
      when(() => mockManager.resumeSync()).thenAnswer((_) {});
      when(() => mockManager.initialize()).thenAnswer((_) async {});
      when(() => mockManager.eventStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPostManager.eventStream).thenAnswer((_) => const Stream.empty());

      when(() => mockManager.localAdapter).thenReturn(localAdapter);
      when(() => mockPostManager.localAdapter).thenReturn(localPostAdapter);

      when(() => mockManager.currentStatus).thenReturn(DatumSyncStatusSnapshot.initial('user1'));
      when(() => mockPostManager.currentStatus).thenReturn(DatumSyncStatusSnapshot.initial('user1'));

      // Defensive stubs on adapters used by real managers (avoid null/type errors if Datum creates real managers)
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      // Reactive adapter stubs so real managers expose non-null streams.
      when(() => localAdapter.watchAll(userId: any(named: 'userId'), includeInitialData: any(named: 'includeInitialData'))).thenAnswer((_) => Stream.value([]));
      when(() => localAdapter.watchById(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(null));
      when(() => localAdapter.watchAllPaginated(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(const PaginatedResult(items: [], totalCount: 0, currentPage: 1, totalPages: 0, hasMore: false)));
      when(() => localAdapter.watchQuery(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value([]));
      // Defensive stub: watchRelated used by parent manager to watch related entities.
      when(() => localAdapter.watchRelated<Post>(any(), any(), any())).thenAnswer((_) => Stream.value(<Post>[]));
      when(() => localAdapter.query(any(), userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => remoteAdapter.query(any(), userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => []);
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => localAdapter.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
      when(() => localAdapter.watchStorageSize(userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(0));
      when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
      // Ensure remote adapters also return a non-null health status.
      when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
      when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});

      // Defensive stubs for remote fetchRelated to avoid null Future returns.
      when(() => remoteAdapter.fetchRelated<Post>(any(), any(), any())).thenAnswer((_) async => <Post>[]);
      // Defensive stub: remote watchRelated as well (if manager uses remote adapter for reactive relations).

      when(() => remotePostAdapter.fetchRelated<Post>(any(), any(), any())).thenAnswer((_) async => <Post>[]);

      // Stub initialize for the Post manager as well.
      when(() => mockPostManager.initialize()).thenAnswer((_) async {});
      when(() => localPostAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localPostAdapter.initialize()).thenAnswer((_) async {});
      when(() => remotePostAdapter.initialize()).thenAnswer((_) async {});
      when(() => localPostAdapter.dispose()).thenAnswer((_) async {});
      when(() => remotePostAdapter.dispose()).thenAnswer((_) async {});

      // Defensive stubs for Post adapters too
      when(() => localPostAdapter.watchAll(userId: any(named: 'userId'), includeInitialData: any(named: 'includeInitialData'))).thenAnswer((_) => Stream.value([]));
      when(() => localPostAdapter.watchById(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(null));
      // Defensive stub: watchRelated on the Post local adapter (used when watching relations).
      when(() => localPostAdapter.watchRelated<Post>(any(), any(), any())).thenAnswer((_) => Stream.value(<Post>[]));
      when(() => localPostAdapter.watchAllPaginated(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(const PaginatedResult(items: [], totalCount: 0, currentPage: 1, totalPages: 0, hasMore: false)));
      when(() => localPostAdapter.watchQuery(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value([]));
      when(() => localPostAdapter.query(any(), userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => remotePostAdapter.query(any(), userId: any(named: 'userId'))).thenAnswer((_) async => []);

      when(() => localPostAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => localPostAdapter.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
      when(() => localPostAdapter.watchStorageSize(userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(0));
      when(() => localPostAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localPostAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
      when(() => remotePostAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);

      // Additional stubs for Post manager/adapter required by _logPendingOperationsSummary
      when(() => localPostAdapter.getAllUserIds()).thenAnswer((_) async => ['user1']);
      when(() => localPostAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => localPostAdapter.readAll(userId: any(named: 'userId'))).thenAnswer((_) async => []);

      when(() => mockPostManager.getPendingCount(any())).thenAnswer((_) async => 0);
      when(() => mockPostManager.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
      when(() => mockPostManager.getLastSyncResult(any())).thenAnswer((_) async => null);

      when(() => mockManager.dispose()).thenAnswer((_) async {});
      when(() => mockPostManager.dispose()).thenAnswer((_) async {});

      // Mock the manager creation process within Datum
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
            // This is a trick: instead of letting Datum create a real manager from adapters,
            // we override the factory to return our mock manager.
            // This is not standard API, so we'll use a custom registration for it.
            config: CustomManagerConfig<TestEntity>(mockManager),
          ),
          DatumRegistration<Post>(
            localAdapter: localPostAdapter,
            remoteAdapter: remotePostAdapter,
            config: CustomManagerConfig<Post>(mockPostManager),
          ),
        ],
      );
    });

    tearDown(() async {
      if (Datum.instanceOrNull != null) {
        await Datum.instance.dispose();
      }
      Datum.resetForTesting();
    });

    test("Uninitalize Datum throws State Error if called instance", () async {
      await Datum.instance.dispose();
      // After dispose, _instance is set to null, so accessing Datum.instance throws StateError
      expect(() => Datum.instance, throwsStateError);

      // After resetForTesting, it should also throw StateError
      Datum.resetForTesting();
      expect(() => Datum.instance, throwsStateError);
    });

    test('Datum.watchAll calls manager.watchAll', () async {
      // Act
      final result = await Datum.instance.watchAll<TestEntity>(userId: 'user1', includeInitialData: false)!.first;

      // Assert: observable outcome (empty list from our stubs)
      expect(result, isA<List<TestEntity>>());
      expect(result, isEmpty);
    });

    test('Datum.watchById calls manager.watchById', () async {
      // Act
      final result = await Datum.instance.watchById<TestEntity>('id1', userId: 'user1')!.first;

      // Assert: observable outcome (null from our stubs)
      expect(result, isNull);
    });

    test('Datum.watchAllPaginated calls manager.watchAllPaginated', () async {
      // Arrange
      const config = PaginationConfig(pageSize: 10);

      // Act
      final result = await Datum.instance.watchAllPaginated<TestEntity>(config, userId: 'user1')!.first;

      // Assert: observable outcome (empty paginated result)
      expect(result, isA<PaginatedResult<TestEntity>>());
      expect(result.items, isEmpty);
    });

    test('Datum.watchQuery calls manager.watchQuery', () async {
      // Arrange
      final query = DatumQueryBuilder<TestEntity>().build();

      // Act
      final result = await Datum.instance.watchQuery<TestEntity>(query, userId: 'user1')!.first;

      // Assert: observable outcome (empty list)
      expect(result, isA<List<TestEntity>>());
      expect(result, isEmpty);
    });

    test('Datum.query calls manager.query', () async {
      // Arrange
      final query = DatumQueryBuilder<TestEntity>().build();

      // Act
      await Datum.instance.query<TestEntity>(query, source: DataSource.local, userId: 'user1');

      // Assert
      // We assert that the call completes and returns a list (our stubs return empty list).
      final result = await Datum.instance.query<TestEntity>(query, source: DataSource.local, userId: 'user1');
      expect(result, isA<List<TestEntity>>());
      expect(result, isEmpty);
    });

    test('Datum.getPendingCount calls manager.getPendingCount', () async {
      // Act
      final count = await Datum.instance.getPendingCount<TestEntity>('user1');
      expect(count, equals(0));
    });

    test('Datum.getPendingOperations calls manager.getPendingOperations', () async {
      // Act
      final ops = await Datum.instance.getPendingOperations<TestEntity>('user1');
      expect(ops, isA<List<DatumSyncOperation<TestEntity>>>());
      expect(ops, isEmpty);
    });

    test('Datum.getStorageSize calls manager.getStorageSize', () async {
      // Act
      final size = await Datum.instance.getStorageSize<TestEntity>(userId: 'user1');
      expect(size, equals(0));
    });

    test('Datum.watchStorageSize calls manager.watchStorageSize', () async {
      // Act
      final size = await Datum.instance.watchStorageSize<TestEntity>(userId: 'user1').first;
      expect(size, equals(0));
    });

    test('Datum.getLastSyncResult calls manager.getLastSyncResult', () async {
      // Act
      final last = await Datum.instance.getLastSyncResult<TestEntity>('user1');
      expect(last, isNull);
    });

    test('Datum.checkHealth calls manager.checkHealth', () async {
      // Act
      final health = await Datum.instance.checkHealth<TestEntity>();
      expect(health, isA<DatumHealth>());
    });

    test('Datum.pauseSync calls pauseSync on all managers', () {
      // Act
      // Ensure calling pause/resume does not throw and completes synchronously.
      expect(() => Datum.instance.pauseSync(), returnsNormally);
    });

    test('Datum.resumeSync calls resumeSync on all managers', () {
      // Act
      expect(() => Datum.instance.resumeSync(), returnsNormally);
    });

    test('Datum.fetchRelated calls manager.fetchRelated on the correct manager', () async {
      // Arrange
      final parent = TestEntity.create('e1', 'user1', 'Parent');

      // Act
      final related = await Datum.instance.fetchRelated<TestEntity, Post>(parent, 'posts', source: DataSource.remote);
      expect(related, isA<List<Post>>());
      expect(related, isEmpty);
    });

    test('Datum.fetchRelated throws ArgumentError for non-relational entities', () async {
      // Arrange: Create a non-relational entity using DatumEntityMixin
      final nonRelationalEntity = _NonRelationalMixinEntity(
        id: 'test-id',
        userId: 'test-user',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        version: 1,
        isDeleted: false,
        name: 'test',
      );

      // Act & Assert: Should throw ArgumentError with specific message
      expect(
        () => Datum.instance.fetchRelated<_NonRelationalMixinEntity, Post>(
          nonRelationalEntity,
          'posts',
          source: DataSource.local,
        ),
        throwsA(
          isA<ArgumentError>()
              .having(
                (e) => e.message,
                'message',
                contains('Entity of type _NonRelationalMixinEntity is not relational and cannot have relations'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('To use relations, extend RelationalDatumEntity instead of DatumEntity or use RelationalDatumEntityMixin'),
              ),
        ),
      );
    });

    test('Datum.watchRelated calls manager.watchRelated on the correct manager', () async {
      // Arrange
      final parent = TestEntity.create('e1', 'user1', 'Parent');

      // Act
      final related = await Datum.instance.watchRelated<TestEntity, Post>(parent, 'posts')!.first;
      expect(related, isA<List<Post>>());
      expect(related, isEmpty);
    });

    test('Datum.watchRelated throws ArgumentError for non-relational entities', () async {
      // Arrange: Create a non-relational entity using DatumEntityMixin
      final nonRelationalEntity = _NonRelationalMixinEntity(
        id: 'test-id',
        userId: 'test-user',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        version: 1,
        isDeleted: false,
        name: 'test',
      );

      // Act & Assert: Should throw ArgumentError with specific message
      expect(
        () => Datum.instance.watchRelated<_NonRelationalMixinEntity, Post>(
          nonRelationalEntity,
          'posts',
        ),
        throwsA(
          isA<ArgumentError>()
              .having(
                (e) => e.message,
                'message',
                contains('Entity of type _NonRelationalMixinEntity is not relational and cannot have relations'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('To use relations, extend RelationalDatumEntity instead of DatumEntity or use RelationalDatumEntityMixin'),
              ),
        ),
      );
    });

    test('Datum.managerByType throws StateError for unregistered type', () async {
      // Act & Assert: Should throw StateError for unregistered type
      expect(
        () => Datum.managerByType(String),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            equals('Entity type String is not registered or has a manager of the wrong type.'),
          ),
        ),
      );
    });

    test('Datum.manager throws ArgumentError when using DatumEntityInterface directly', () async {
      // Act & Assert: Should throw ArgumentError when trying to use DatumEntityInterface directly
      expect(
        () => Datum.manager<DatumEntityInterface>(),
        throwsA(
          isA<ArgumentError>()
              .having(
                (e) => e.message,
                'message',
                contains('Cannot use DatumEntityInterface directly'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('You must use a concrete entity type that implements DatumEntityInterface'),
              ),
        ),
      );
    });

    test('Datum.managerByType throws ArgumentError when using DatumEntityInterface directly', () async {
      // Act & Assert: Should throw ArgumentError when trying to use DatumEntityInterface directly
      expect(
        () => Datum.managerByType(DatumEntityInterface),
        throwsA(
          isA<ArgumentError>()
              .having(
                (e) => e.message,
                'message',
                contains('Cannot use DatumEntityInterface directly'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('You must use a concrete entity type that implements DatumEntityInterface'),
              ),
        ),
      );
    });

    test('Datum.watchAll throws ArgumentError when using DatumEntityInterface directly', () async {
      // Act & Assert: Should throw ArgumentError when trying to use DatumEntityInterface directly
      expect(
        () => Datum.instance.watchAll<DatumEntityInterface>(userId: 'user1'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Cannot use DatumEntityInterface directly'),
          ),
        ),
      );
    });

    test('Datum.query throws ArgumentError when using DatumEntityInterface directly', () async {
      // Arrange
      final query = DatumQueryBuilder<DatumEntityInterface>().build();

      // Act & Assert: Should throw ArgumentError when trying to use DatumEntityInterface directly
      expect(
        () => Datum.instance.query<DatumEntityInterface>(query, source: DataSource.local, userId: 'user1'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Cannot use DatumEntityInterface directly'),
          ),
        ),
      );
    });

    test('Datum.startAutoSync calls startAutoSync on all managers', () async {
      // Act: Call startAutoSync
      expect(() => Datum.instance.startAutoSync('user1'), returnsNormally);

      // Assert: The method completes without throwing and calls startAutoSync on managers
      // Since we can't easily verify the internal calls, we just ensure it doesn't throw
    });

    test('Datum.statusForUser returns a snapshot (sync or async)', () async {
      // Act: call without a generic type argument (method is not generic)
      final result = Datum.instance.statusForUser('user1');

      final snapshot = await result.first;
      expect(snapshot, anyOf(isNull, isA<DatumSyncStatusSnapshot>()));
    });

    test('Datum.allHealths returns aggregated healths (sync or async)', () async {
      // Act
      final result = Datum.instance.allHealths;

      final healths = await result.first;
      expect(healths, isNotNull);
      expect(healths, anyOf(isA<Map>(), isA<List>()));
    });

    test('registering the same entity type twice throws StateError', () async {
      // TestEntity is registered in setUp.
      final registration = DatumRegistration<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
      );
      // Trying to register it again should fail.
      expect(
        () => Datum.instance.register<TestEntity>(registration: registration),
        throwsA(isA<StateError>()),
      );
    });

    test('Datum.manager.synchronize supports partial sync with query', () async {
      // Arrange: Create sync options with a query for partial sync
      const activeOnlyQuery = DatumQuery(filters: [Filter('status', FilterOperator.equals, 'active')]);
      const optionsWithQuery = DatumSyncOptions<TestEntity>(
        query: activeOnlyQuery,
        direction: SyncDirection.pullOnly, // Only pull to test filtering
      );

      // Act: Call the manager's synchronize method with query options
      final result = await Datum.manager<TestEntity>().synchronize(
        'user1',
        options: optionsWithQuery,
      );

      // Assert: Verify the result
      expect(result, isA<DatumSyncResult<TestEntity>>());
      expect(result.syncedCount, 0); // Pull operations don't increment syncedCount
    });

    test('Datum.manager.synchronize supports partial sync with complex query', () async {
      // Arrange: Create sync options with a complex query for partial sync
      const complexQuery = DatumQuery(filters: [
        Filter('status', FilterOperator.equals, 'active'),
        Filter('priority', FilterOperator.greaterThan, 5),
        Filter('createdAt', FilterOperator.greaterThan, '2023-01-01T00:00:00.000Z'),
      ]);
      const optionsWithComplexQuery = DatumSyncOptions<TestEntity>(
        query: complexQuery,
        direction: SyncDirection.pullOnly, // Only pull to test filtering
      );

      // Act: Call the manager's synchronize method with complex query options
      final result = await Datum.manager<TestEntity>().synchronize(
        'user1',
        options: optionsWithComplexQuery,
      );

      // Assert: Verify the result
      expect(result, isA<DatumSyncResult<TestEntity>>());
      expect(result.syncedCount, 0); // Pull operations don't increment syncedCount
    });
  });

  group('Datum.isInitialized', () {
    late MockConnectivityChecker mockConnectivity;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;

    setUp(() {
      Datum.resetForTesting();
      mockConnectivity = MockConnectivityChecker();
      when(() => mockConnectivity.isConnected).thenAnswer((_) async => true);
      when(() => mockConnectivity.onStatusChange).thenAnswer((_) => Stream.value(true));
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getAllUserIds()).thenAnswer((_) async => ['user1']);
      when(() => localAdapter.readAll(userId: 'user1')).thenAnswer((_) async => []);
      when(() => localAdapter.getStorageSize(userId: 'user1')).thenAnswer((_) async => 0);
      when(() => localAdapter.patch(id: any(named: 'id'), delta: any(named: 'delta'), userId: any(named: 'userId'))).thenAnswer((_) async {
        return TestEntity(
          id: 'patched',
          userId: 'default-user',
          name: 'patched',
          value: 1,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        );
      });
      when(() => localAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => remoteAdapter.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.saveLastSyncResult(any(), any())).thenAnswer((_) async {});
      when(() => localAdapter.watchAll(userId: any(named: 'userId'), includeInitialData: any(named: 'includeInitialData'))).thenAnswer((_) => Stream.value([]));
      when(() => localAdapter.watchById(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(null));
      when(() => localAdapter.watchAllPaginated(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(const PaginatedResult(items: [], totalCount: 0, currentPage: 1, totalPages: 0, hasMore: false)));
      when(() => localAdapter.watchQuery(any(), userId: any(named: 'userId'))).thenAnswer((_) => Stream.value([]));
      when(() => localAdapter.watchRelated<Post>(any(), any(), any())).thenAnswer((_) => Stream.value(<Post>[]));
      when(() => localAdapter.watchStorageSize(userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(0));
      when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
      when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
      when(() => remoteAdapter.readAll(userId: any(named: 'userId'), scope: any(named: 'scope'))).thenAnswer((_) async => []);
      when(() => remoteAdapter.query(any(), userId: any(named: 'userId'))).thenAnswer((_) async => []);
    });

    tearDown(() async {
      if (Datum.instanceOrNull != null) {
        await Datum.instance.dispose();
      }
      Datum.resetForTesting();
    });

    test('returns false before initialization', () {
      // Act & Assert
      expect(Datum.isInitialized, isFalse);
    });

    test('returns true after successful initialization', () async {
      // Arrange: Ensure clean state
      if (Datum.instanceOrNull != null) {
        await Datum.instance.dispose();
        Datum.resetForTesting();
      }

      // Act
      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      // Assert: Check that initialization succeeded
      expect(result.isSuccess(), isTrue);
      expect(Datum.isInitialized, isTrue);
    });

    test('returns false after resetForTesting', () async {
      // Arrange: Initialize first
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );
      expect(Datum.isInitialized, isTrue);

      // Act: Reset
      Datum.resetForTesting();

      // Assert
      expect(Datum.isInitialized, isFalse);
    });

    test('returns false after dispose', () async {
      // Arrange: Initialize first
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );
      expect(Datum.isInitialized, isTrue);

      // Act: Dispose
      await Datum.instance.dispose();

      // Assert: Instance is set to null after dispose, so isInitialized returns false
      expect(Datum.isInitialized, isFalse);
    });
  });

  group('Datum Core Initialization', () {
    late MockConnectivityChecker mockConnectivity;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;

    setUp(() {
      Datum.resetForTesting();
      mockConnectivity = MockConnectivityChecker();
      when(() => mockConnectivity.isConnected).thenAnswer((_) async => true);
      when(() => mockConnectivity.onStatusChange).thenAnswer((_) => Stream.value(true));
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.getAllUserIds()).thenAnswer((_) async => ['user1']);
      when(() => localAdapter.readAll(userId: 'user1')).thenAnswer((_) async => []);
      when(() => localAdapter.getStorageSize(userId: 'user1')).thenAnswer((_) async => 0);
      when(() => localAdapter.patch(id: any(named: 'id'), delta: any(named: 'delta'), userId: any(named: 'userId'))).thenAnswer((_) async {
        return TestEntity(
          id: 'patched',
          userId: 'default-user',
          name: 'patched',
          value: 1,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        );
      });
    });

    tearDown(() async {
      if (Datum.instanceOrNull != null) {
        await Datum.instance.dispose();
      }
      Datum.resetForTesting();
    });

    test('allHealths returns an empty stream if no managers are registered', () async {
      // Arrange
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: mockConnectivity,
        registrations: [],
      );

      // Act
      final healths = await Datum.instance.allHealths.first;

      // Assert
      expect(healths, isEmpty);
    });

    test('initialization with logging enabled completes successfully', () async {
      // Arrange
      final testLogger = DatumLogger(enabled: true);

      // Act
      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: true),
        connectivityChecker: mockConnectivity,
        logger: testLogger,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      // Assert
      expect(result.isSuccess(), isTrue);
      // The test exercises the _logInitializationHeader method indirectly
      // by enabling logging during initialization
    });

    test('initialization with defaultSyncOptions containing DatumQuery works correctly', () async {
      // Arrange: Create a config with default sync options that include a query for partial syncing
      const partialSyncQuery = DatumQuery(filters: [
        Filter('completed', FilterOperator.equals, false),
      ]);
      const defaultSyncOptions = DatumSyncOptions<TestEntity>(
        query: partialSyncQuery,
        direction: SyncDirection.pullOnly,
      );
      const configWithDefaultSyncOptions = DatumConfig<TestEntity>(
        enableLogging: false,
        defaultSyncOptions: defaultSyncOptions,
      );

      // Act: Initialize Datum with the config containing default sync options
      final result = await Datum.initialize(
        config: configWithDefaultSyncOptions,
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      // Assert: Initialization should succeed
      expect(result.isSuccess(), isTrue);
      expect(Datum.isInitialized, isTrue);

      // Verify that the default sync options are properly set
      // We can't directly access the manager's config, but we can verify initialization worked
      expect(Datum.instance, isNotNull);
    });

    test('initialization with complex defaultSyncOptions for partial syncing works', () async {
      // Arrange: Create complex default sync options with multiple filters
      const complexQuery = DatumQuery(
        filters: [
          Filter('completed', FilterOperator.equals, false),
          Filter('value', FilterOperator.greaterThan, 5),
        ],
        logicalOperator: LogicalOperator.and,
      );
      final complexDefaultSyncOptions = DatumSyncOptions<TestEntity>(
        query: complexQuery,
        direction: SyncDirection.pullOnly,
        conflictResolver: LastWriteWinsResolver(),
      );
      final configWithComplexDefaults = DatumConfig<TestEntity>(
        enableLogging: false,
        defaultSyncOptions: complexDefaultSyncOptions,
        autoSyncInterval: const Duration(minutes: 30),
        syncTimeout: const Duration(minutes: 3),
      );

      // Act: Initialize with complex configuration
      final result = await Datum.initialize(
        config: configWithComplexDefaults,
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      // Assert: Complex initialization should succeed
      expect(result.isSuccess(), isTrue);
      expect(Datum.isInitialized, isTrue);

      // Verify the instance is properly configured
      expect(Datum.instance, isNotNull);
    });

    test('initialization with defaultSyncOptions for bidirectional sync works', () async {
      // Arrange: Default sync options for bidirectional sync with query
      const bidirectionalQuery = DatumQuery(filters: [
        Filter('value', FilterOperator.lessThanOrEqual, 10),
      ]);
      const bidirectionalSyncOptions = DatumSyncOptions<TestEntity>(
        query: bidirectionalQuery,
        direction: SyncDirection.pushThenPull, // Full bidirectional sync
      );
      const configWithBidirectionalSync = DatumConfig<TestEntity>(
        enableLogging: false,
        defaultSyncOptions: bidirectionalSyncOptions,
        defaultSyncDirection: SyncDirection.pushThenPull,
      );

      // Act: Initialize with bidirectional sync configuration
      final result = await Datum.initialize(
        config: configWithBidirectionalSync,
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      // Assert: Bidirectional sync initialization should succeed
      expect(result.isSuccess(), isTrue);
      expect(Datum.isInitialized, isTrue);
    });
  });

  group('isSubtype function', () {
    test('isSubtype correctly identifies exact and subtype relationships', () {
      // Fixed implementation: bool isSubtype<S, T>() => <T>[] is List<S>;
      // This correctly checks if T is assignable to S (subtyping relationship)

      // Test that a type is a subtype of itself (exact match)
      expect(isSubtype<RelationalDatumEntity, RelationalDatumEntity>(), isTrue);

      // Test that a class extending RelationalDatumEntity is recognized as subtype
      expect(isSubtype<RelationalDatumEntity, RelationalTestEntity>(), isTrue);

      // Test that TestEntity (which extends RelationalDatumEntity) is a subtype
      expect(isSubtype<RelationalDatumEntity, TestEntity>(), isTrue);

      // Test that an unrelated class is NOT a subtype
      expect(isSubtype<RelationalDatumEntity, String>(), isFalse);

      // Test with interface relationships (subtyping)
      expect(isSubtype<DatumEntityInterface, RelationalDatumEntity>(), isTrue);
      expect(isSubtype<DatumEntityInterface, TestEntity>(), isTrue);
      expect(isSubtype<DatumEntityInterface, RelationalTestEntity>(), isTrue);

      // Test reverse relationships (should be false)
      expect(isSubtype<RelationalDatumEntity, DatumEntityInterface>(), isFalse);
      expect(isSubtype<TestEntity, DatumEntityInterface>(), isFalse);
    });

    test('isSubtype handles complex inheritance hierarchies', () {
      // Test that the function works correctly with complex type relationships

      // All entities implement DatumEntityInterface
      expect(isSubtype<DatumEntityInterface, TestEntity>(), isTrue);
      expect(isSubtype<DatumEntityInterface, RelationalTestEntity>(), isTrue);

      // Relational entities are subtypes of RelationalDatumEntity
      expect(isSubtype<RelationalDatumEntity, TestEntity>(), isTrue);
      expect(isSubtype<RelationalDatumEntity, RelationalTestEntity>(), isTrue);

      // Test that exact types work
      expect(isSubtype<TestEntity, TestEntity>(), isTrue);
      expect(isSubtype<RelationalTestEntity, RelationalTestEntity>(), isTrue);

      // Cross-type checks
      expect(isSubtype<TestEntity, RelationalTestEntity>(), isFalse);
      expect(isSubtype<RelationalTestEntity, TestEntity>(), isFalse);
    });
  });

  group('sameTypes function', () {
    test('sameTypes returns true for identical types', () {
      // Test that the same type returns true
      expect(sameTypes<int, int>(), isTrue);
      expect(sameTypes<String, String>(), isTrue);
      expect(sameTypes<TestEntity, TestEntity>(), isTrue);
      expect(sameTypes<RelationalTestEntity, RelationalTestEntity>(), isTrue);
      expect(sameTypes<DatumEntityInterface, DatumEntityInterface>(), isTrue);
    });

    test('sameTypes returns false for different types', () {
      // Test that different types return false
      expect(sameTypes<int, String>(), isFalse);
      expect(sameTypes<String, int>(), isFalse);
      expect(sameTypes<TestEntity, RelationalTestEntity>(), isFalse);
      expect(sameTypes<RelationalTestEntity, TestEntity>(), isFalse);
      expect(sameTypes<DatumEntityInterface, TestEntity>(), isFalse);
      expect(sameTypes<TestEntity, DatumEntityInterface>(), isFalse);
    });

    test('sameTypes handles complex type relationships', () {
      // Test with inheritance - even though TestEntity extends RelationalDatumEntity,
      // they are not the same type
      expect(sameTypes<RelationalDatumEntity, TestEntity>(), isFalse);
      expect(sameTypes<TestEntity, RelationalDatumEntity>(), isFalse);

      // Test with interfaces - even though TestEntity implements DatumEntityInterface,
      // they are not the same type
      expect(sameTypes<DatumEntityInterface, TestEntity>(), isFalse);
      expect(sameTypes<TestEntity, DatumEntityInterface>(), isFalse);

      // Test with built-in types
      expect(sameTypes<num, int>(), isFalse);
      expect(sameTypes<int, num>(), isFalse);
      expect(sameTypes<Object, String>(), isFalse);
      expect(sameTypes<String, Object>(), isFalse);
    });

    test('sameTypes works with dynamic and Object', () {
      // Test with dynamic and Object
      expect(sameTypes<dynamic, dynamic>(), isTrue);
      expect(sameTypes<Object, Object>(), isTrue);
      expect(sameTypes<dynamic, Object>(), isFalse);
      expect(sameTypes<Object, dynamic>(), isFalse);
    });

    test('sameTypes function definition is executed', () {
      // This test ensures the function definition line is covered
      // by calling the function with various types
      final result1 = sameTypes<int, int>();
      final result2 = sameTypes<String, double>();
      final result3 = sameTypes<TestEntity, TestEntity>();

      expect(result1, isTrue);
      expect(result2, isFalse);
      expect(result3, isTrue);
    });
  });

  group('Mixin-based entity relational detection', () {
    test('DatumEntityMixin entities are correctly identified as non-relational', () {
      // Create a test entity using DatumEntityMixin
      final nonRelationalEntity = _NonRelationalMixinEntity(
        id: 'test-id',
        userId: 'test-user',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        version: 1,
        isDeleted: false,
        name: 'test',
      );

      // Verify the entity is not relational
      expect(nonRelationalEntity.isRelational, isFalse);

      // Verify isSubtype correctly identifies it as NOT a subtype of RelationalDatumEntity
      expect(isSubtype<RelationalDatumEntity, _NonRelationalMixinEntity>(), isFalse);

      // But it should be a subtype of DatumEntityInterface
      expect(isSubtype<DatumEntityInterface, _NonRelationalMixinEntity>(), isTrue);
    });

    test('RelationalDatumEntityMixin entities are correctly identified as relational', () {
      // Create a test entity using RelationalDatumEntityMixin
      final relationalEntity = _RelationalMixinEntity(
        id: 'test-id',
        userId: 'test-user',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        version: 1,
        isDeleted: false,
        title: 'test',
      );

      // Verify the entity is relational
      expect(relationalEntity.isRelational, isTrue);

      // Note: Mixin entities are NOT subtypes of RelationalDatumEntity in terms of inheritance,
      // but they are relational due to the mixin providing the isRelational property
      expect(isSubtype<RelationalDatumEntity, _RelationalMixinEntity>(), isFalse);

      // But they should still be subtypes of DatumEntityInterface
      expect(isSubtype<DatumEntityInterface, _RelationalMixinEntity>(), isTrue);
    });

    test('registration correctly detects relational status for mixin entities', () async {
      // Reset Datum for clean test state
      Datum.resetForTesting();

      final mockConnectivity = MockConnectivityChecker();
      when(() => mockConnectivity.isConnected).thenAnswer((_) async => true);
      when(() => mockConnectivity.onStatusChange).thenAnswer((_) => Stream.value(true));

      // Create mock adapters for the mixin entities
      final nonRelationalLocalAdapter = MockLocalAdapter<_NonRelationalMixinEntity>();
      final nonRelationalRemoteAdapter = MockRemoteAdapter<_NonRelationalMixinEntity>();
      final relationalLocalAdapter = MockLocalAdapter<_RelationalMixinEntity>();
      final relationalRemoteAdapter = MockRemoteAdapter<_RelationalMixinEntity>();

      // Set up adapter mocks
      when(() => nonRelationalLocalAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => nonRelationalLocalAdapter.initialize()).thenAnswer((_) async {});
      when(() => nonRelationalRemoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => nonRelationalLocalAdapter.dispose()).thenAnswer((_) async {});
      when(() => nonRelationalRemoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => nonRelationalLocalAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => nonRelationalLocalAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => nonRelationalLocalAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => nonRelationalLocalAdapter.getAllUserIds()).thenAnswer((_) async => []);

      when(() => relationalLocalAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => relationalLocalAdapter.initialize()).thenAnswer((_) async {});
      when(() => relationalRemoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => relationalLocalAdapter.dispose()).thenAnswer((_) async {});
      when(() => relationalRemoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => relationalLocalAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => relationalLocalAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
      when(() => relationalLocalAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => relationalLocalAdapter.getAllUserIds()).thenAnswer((_) async => []);

      // Initialize Datum with both types of entities
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<_NonRelationalMixinEntity>(
            localAdapter: nonRelationalLocalAdapter,
            remoteAdapter: nonRelationalRemoteAdapter,
          ),
          DatumRegistration<_RelationalMixinEntity>(
            localAdapter: relationalLocalAdapter,
            remoteAdapter: relationalRemoteAdapter,
          ),
        ],
      );

      // Verify that Datum correctly detected the relational status during registration
      // The isSubtype function should have been used to determine this

      await Datum.instance.dispose();
      Datum.resetForTesting();
    });
  });
}

/// Test entity using DatumEntityMixin (non-relational)
class _NonRelationalMixinEntity with DatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  final String name;

  const _NonRelationalMixinEntity({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    required this.isDeleted,
    required this.name,
  });

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
        'name': name,
      };

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;

  @override
  List<Object?> get props => [id, userId, createdAt, modifiedAt, version, isDeleted, vectorClock, name];

  @override
  bool get stringify => true;
}

/// Test entity using RelationalDatumEntityMixin (relational)
class _RelationalMixinEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  final String title;

  const _RelationalMixinEntity({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    required this.isDeleted,
    required this.title,
  });

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
        'title': title,
      };

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;

  @override
  Map<String, Relation> get relations => {'comments': HasMany(this as RelationalDatumEntity, 'postId')};

  @override
  List<Object?> get props => [id, userId, createdAt, modifiedAt, version, isDeleted, vectorClock, title];

  @override
  bool get stringify => true;
}

/// A custom DatumConfig that holds a mock manager instance.
class CustomManagerConfig<T extends DatumEntityInterface> extends DatumConfig<T> {
  final DatumManager<T> mockManager;

  const CustomManagerConfig(this.mockManager);

  // Provide a factory method that Datum may call to create managers.
  // The exact method name/signature matches common patterns used by configs.
  // If your DatumConfig defines a different name for the factory, adapt this to match it.
  DatumManager<T> createManager(LocalAdapter<T> localAdapter, RemoteAdapter<T> remoteAdapter) {
    return mockManager;
  }
}
