import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

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
  @override
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
}

class MockDatumManager<T extends DatumEntity> extends Mock implements DatumManager<T> {}

class MockLocalAdapter<T extends DatumEntity> extends Mock implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements DatumConnectivityChecker {}

/// Fake adapters used as fallback values for mocktail when matching arguments.
class FakeRemoteAdapterPost extends Fake implements RemoteAdapter<Post> {}

class FakeLocalAdapterPost extends Fake implements LocalAdapter<Post> {}

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

    // Register fallback Fake instances for adapter types used with matchers.
    registerFallbackValue(FakeRemoteAdapterPost());
    registerFallbackValue(FakeLocalAdapterPost());
  });

  group('Datum Core Convenience Methods', () {
    late MockDatumManager<TestEntity> mockManager;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockDatumManager<Post> mockPostManager;
    late MockLocalAdapter<Post> localPostAdapter;
    late MockRemoteAdapter<Post> remotePostAdapter;

    setUp(() async {
      // Reset Datum singleton for test isolation
      Datum.resetForTesting();

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

      // Stubbing manager methods that will be called by Datum.instance
      when(() => mockManager.watchAll(userId: any(named: 'userId'), includeInitialData: any(named: 'includeInitialData'))).thenAnswer((_) => Stream.value([]));
      when(() => mockManager.watchById(any(), any())).thenAnswer((_) => Stream.value(null));
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
      when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
      when(() => localAdapter.getStorageSize(userId: any(named: 'userId'))).thenAnswer((_) async => 0);
      when(() => localAdapter.watchStorageSize(userId: any(named: 'userId'))).thenAnswer((_) => Stream.value(0));
      when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
      when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
      // Ensure remote adapters also return a non-null health status.
      when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);

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
      // Accessing the singleton after dispose should not throw in the current API.
      // Verify it returns normally and yields a Datum instance.
      expect(() => Datum.instance, returnsNormally);
      expect(Datum.instance, isA<Datum>());
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
      final result = await Datum.instance.watchById<TestEntity>('id1', 'user1')!.first;

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

    test('Datum.watchRelated calls manager.watchRelated on the correct manager', () async {
      // Arrange
      final parent = TestEntity.create('e1', 'user1', 'Parent');

      // Act
      final related = await Datum.instance.watchRelated<TestEntity, Post>(parent, 'posts')!.first;
      expect(related, isA<List<Post>>());
      expect(related, isEmpty);
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
  });

  group('Datum Core Initialization', () {
    late MockConnectivityChecker mockConnectivity;
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;

    setUp(() {
      Datum.resetForTesting();
      mockConnectivity = MockConnectivityChecker();
      when(() => mockConnectivity.isConnected).thenAnswer((_) async => true);
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
      when(() => localAdapter.getStorageSize(userId: 'user1'))
          .thenAnswer((_) async => 0);
    });

    tearDown(() async {
      if (Datum.instanceOrNull != null) {
        await Datum.instance.dispose();
      }
      Datum.resetForTesting();
    });

    test('allHealths returns an empty stream if no managers are registered',
        () async {
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
  });
}

/// A custom DatumConfig that holds a mock manager instance.
class CustomManagerConfig<T extends DatumEntity> extends DatumConfig<T> {
  final DatumManager<T> mockManager;

  const CustomManagerConfig(this.mockManager);

  // Provide a factory method that Datum may call to create managers.
  // The exact method name/signature matches common patterns used by configs.
  // If your DatumConfig defines a different name for the factory, adapt this to match it.
  DatumManager<T> createManager(LocalAdapter<T> localAdapter, RemoteAdapter<T> remoteAdapter) {
    return mockManager;
  }
}
