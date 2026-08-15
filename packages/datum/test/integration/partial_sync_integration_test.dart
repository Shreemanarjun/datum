import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

/// Integration test demonstrating partial sync with complex queries
/// This test creates mock data and shows how DatumQuery filters work
/// in real-world scenarios

class MockLocalAdapter<T extends DatumEntityInterface> extends Mock implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

class MockConnectivityChecker extends Mock implements DatumConnectivityChecker {}

void main() {
  late MockConnectivityChecker mockConnectivity;
  late MockLocalAdapter<TestEntity> localAdapter;
  late MockRemoteAdapter<TestEntity> remoteAdapter;

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
        lastSyncTime: null,
        dataHash: null,
        deviceId: null,
        devices: null,
        entityCounts: {},
      ),
    );
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
  });

  setUp(() {
    Datum.resetForTesting();
    mockConnectivity = MockConnectivityChecker();
    localAdapter = MockLocalAdapter<TestEntity>();
    remoteAdapter = MockRemoteAdapter<TestEntity>();

    when(() => mockConnectivity.isConnected).thenAnswer((_) async => true);
    when(() => mockConnectivity.onStatusChange).thenAnswer((_) => Stream.value(true));
    when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
    when(() => localAdapter.initialize()).thenAnswer((_) async {});
    when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
    when(() => localAdapter.dispose()).thenAnswer((_) async {});
    when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
    when(() => localAdapter.getPendingOperations(any())).thenAnswer((_) async => []);
    when(() => localAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
    when(() => localAdapter.getLastSyncResult(any())).thenAnswer((_) async => null);
    when(() => localAdapter.getAllUserIds()).thenAnswer((_) async => ['test-user']);
    when(() => localAdapter.getStorageSize(userId: 'test-user')).thenAnswer((_) async => 0);
    when(() => localAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
    when(() => remoteAdapter.checkHealth()).thenAnswer((_) async => AdapterHealthStatus.healthy);
    when(() => remoteAdapter.getSyncMetadata(any())).thenAnswer((_) async => null);
  });

  tearDown(() async {
    if (Datum.isInitialized) {
      await Datum.instance.dispose();
    }
    Datum.resetForTesting();
  });

  group('Partial Sync Integration Tests', () {
    /// Mock data representing 10 test entities with various properties
    final mockData = [
      TestEntity(id: 'task-1', userId: 'test-user', name: 'Complete project proposal', value: 10, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: false),
      TestEntity(id: 'task-2', userId: 'test-user', name: 'Review code changes', value: 8, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: false),
      TestEntity(id: 'task-3', userId: 'test-user', name: 'Update documentation', value: 6, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: true),
      TestEntity(id: 'task-4', userId: 'test-user', name: 'Fix critical bug', value: 9, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: false),
      TestEntity(id: 'task-5', userId: 'test-user', name: 'Plan sprint meeting', value: 4, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: false),
      TestEntity(id: 'task-6', userId: 'test-user', name: 'Deploy to production', value: 7, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: false),
      TestEntity(id: 'task-7', userId: 'test-user', name: 'Write unit tests', value: 5, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: true),
      TestEntity(id: 'task-8', userId: 'test-user', name: 'Optimize database queries', value: 8, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: false),
      TestEntity(id: 'task-9', userId: 'test-user', name: 'Setup CI/CD pipeline', value: 3, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: false),
      TestEntity(id: 'task-10', userId: 'test-user', name: 'Conduct code review', value: 6, modifiedAt: DateTime.now(), createdAt: DateTime.now(), version: 1, completed: true),
    ];

    setUp(() async {
      // Setup mock adapters to return our test data
      when(() => localAdapter.readAll(userId: 'test-user')).thenAnswer((_) async => mockData);
      when(() => localAdapter.query(any(), userId: 'test-user')).thenAnswer((invocation) async {
        final query = invocation.positionalArguments[0] as DatumQuery;
        return _filterEntities(mockData, query);
      });
      when(() => remoteAdapter.readAll(userId: 'test-user', scope: any(named: 'scope'))).thenAnswer((invocation) async {
        final scope = invocation.namedArguments[#scope] as DatumSyncScope?;
        if (scope?.query != null) {
          return _filterEntities(mockData, scope!.query);
        }
        return mockData;
      });

      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: true),
        connectivityChecker: mockConnectivity,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      if (result case Failure(value: final e, stackTrace: final s)) {
        fail('Datum initialization failed: $e\n$s');
      }
    });

    test('Use Case 1: Query incomplete tasks (completed filter)', () async {
      // Arrange: Query for incomplete tasks only (completed = false)
      const incompleteTasksQuery = DatumQuery(filters: [
        Filter('completed', FilterOperator.equals, false),
      ]);

      // Act: Query the data directly
      final queriedData = await Datum.instance.query<TestEntity>(
        incompleteTasksQuery,
        source: DataSource.local,
        userId: 'test-user',
      );

      // Assert: Should return 7 incomplete tasks (task-1, task-2, task-4, task-5, task-6, task-8, task-9)
      expect(queriedData.length, 7);
      expect(queriedData.every((task) => task.completed == false), isTrue);
    });

    test('Use Case 2: Query high-priority tasks (value > 7)', () async {
      // Arrange: Query for high-priority tasks (value > 7)
      const highPriorityQuery = DatumQuery(filters: [
        Filter('value', FilterOperator.greaterThan, 7),
      ]);

      // Act: Query the data directly
      final queriedData = await Datum.instance.query<TestEntity>(
        highPriorityQuery,
        source: DataSource.local,
        userId: 'test-user',
      );

      // Assert: Should return 4 high-priority tasks (task-1:10, task-2:8, task-4:9, task-8:8)
      expect(queriedData.length, 4);
      expect(queriedData.every((task) => task.value > 7), isTrue);
    });

    test('Use Case 3: Query incomplete tasks with medium priority (complex AND query)', () async {
      // Arrange: Query for incomplete tasks with medium priority (value between 5-8)
      const mediumPriorityIncompleteQuery = DatumQuery(filters: [
        Filter('completed', FilterOperator.equals, false),
        Filter('value', FilterOperator.greaterThanOrEqual, 5),
        Filter('value', FilterOperator.lessThanOrEqual, 8),
      ]);

      // Act: Query the data directly
      final queriedData = await Datum.instance.query<TestEntity>(
        mediumPriorityIncompleteQuery,
        source: DataSource.local,
        userId: 'test-user',
      );

      // Assert: Should return 3 tasks (task-2:8, task-6:7, task-8:8)
      expect(queriedData.length, 3);
      expect(queriedData.every((task) => task.completed == false && task.value >= 5 && task.value <= 8), isTrue);
    });

    test('Use Case 4: Query tasks that are either completed OR low priority (complex OR query)', () async {
      // Arrange: Query for completed tasks OR low priority tasks (value <= 4)
      const completedOrLowPriorityQuery = DatumQuery(
        filters: [
          Filter('completed', FilterOperator.equals, true),
          Filter('value', FilterOperator.lessThanOrEqual, 4),
        ],
        logicalOperator: LogicalOperator.or,
      );

      // Act: Query the data directly
      final queriedData = await Datum.instance.query<TestEntity>(
        completedOrLowPriorityQuery,
        source: DataSource.local,
        userId: 'test-user',
      );

      // Assert: Should return 5 tasks (3 completed + 2 low priority: task-5:4, task-9:3)
      expect(queriedData.length, 5);
      expect(queriedData.every((task) => task.completed == true || task.value <= 4), isTrue);
    });

    test('Use Case 5: Query tasks containing specific text in name (contains filter)', () async {
      // Arrange: Query for tasks containing "code" in the name
      const codeRelatedTasksQuery = DatumQuery(filters: [
        Filter('name', FilterOperator.contains, 'code'),
      ]);

      // Act: Query the data directly
      final queriedData = await Datum.instance.query<TestEntity>(
        codeRelatedTasksQuery,
        source: DataSource.local,
        userId: 'test-user',
      );

      // Assert: Should return 2 tasks (task-2: "Review code changes", task-10: "Conduct code review")
      expect(queriedData.length, 2);
      expect(queriedData.every((task) => task.name.toLowerCase().contains('code')), isTrue);
    });

    test('Use Case 6: Query tasks that are NOT completed (not equals filter)', () async {
      // Arrange: Query for tasks that are NOT completed
      const incompleteTasksQuery = DatumQuery(filters: [
        Filter('completed', FilterOperator.notEquals, true),
      ]);

      // Act: Query the data directly
      final queriedData = await Datum.instance.query<TestEntity>(
        incompleteTasksQuery,
        source: DataSource.local,
        userId: 'test-user',
      );

      // Assert: Should return 7 tasks (all except task-3, task-7, task-10 which are completed)
      expect(queriedData.length, 7);
      expect(queriedData.every((task) => task.completed != true), isTrue);
    });

    test('Use Case 7: Complex business logic - Query urgent incomplete tasks (high priority AND incomplete)', () async {
      // Arrange: Query for urgent tasks (high priority incomplete tasks that need immediate attention)
      const urgentTasksQuery = DatumQuery(filters: [
        Filter('completed', FilterOperator.equals, false),
        Filter('value', FilterOperator.greaterThan, 8), // High priority threshold
        Filter('name', FilterOperator.contains, 'bug'), // Contains critical issues
      ]);

      // Act: Query the data directly
      final queriedData = await Datum.instance.query<TestEntity>(
        urgentTasksQuery,
        source: DataSource.local,
        userId: 'test-user',
      );

      // Assert: Should return 1 task (task-4: "Fix critical bug" with value 9)
      expect(queriedData.length, 1);
      expect(queriedData.first.name, 'Fix critical bug');
      expect(queriedData.first.value, 9);
      expect(queriedData.first.completed, false);
    });
  });
}

/// Helper function to simulate query filtering on mock data
List<TestEntity> _filterEntities(List<TestEntity> entities, DatumQuery query) {
  bool matchesCondition(TestEntity entity, FilterCondition condition) {
    if (condition is Filter) {
      return _matchesFilter(_getFieldValue(entity, condition.field), condition);
    }
    if (condition is CompositeFilter) {
      // The manager wraps queries in composites (e.g. tombstone exclusion),
      // so the fake must recurse like a real adapter's matcher.
      return condition.operator == LogicalOperator.and ? condition.conditions.every((c) => matchesCondition(entity, c)) : condition.conditions.any((c) => matchesCondition(entity, c));
    }
    return false;
  }

  return entities.where((entity) {
    if (query.filters.isEmpty) return true;
    return query.logicalOperator == LogicalOperator.and ? query.filters.every((c) => matchesCondition(entity, c)) : query.filters.any((c) => matchesCondition(entity, c));
  }).toList();
}

/// Helper function to get field value from entity
dynamic _getFieldValue(TestEntity entity, String field) {
  switch (field) {
    case 'id':
      return entity.id;
    case 'userId':
      return entity.userId;
    case 'name':
      return entity.name;
    case 'value':
      return entity.value;
    case 'completed':
      return entity.completed;
    case 'createdAt':
      return entity.createdAt;
    case 'modifiedAt':
      return entity.modifiedAt;
    case 'version':
      return entity.version;
    case 'isDeleted':
      return entity.isDeleted;
    default:
      return null;
  }
}

/// Helper function to check if a value matches a filter
bool _matchesFilter(dynamic value, Filter filter) {
  switch (filter.operator) {
    case FilterOperator.equals:
      return value == filter.value;
    case FilterOperator.notEquals:
      return value != filter.value;
    case FilterOperator.greaterThan:
      return value is num && filter.value is num && value > filter.value;
    case FilterOperator.greaterThanOrEqual:
      return value is num && filter.value is num && value >= filter.value;
    case FilterOperator.lessThan:
      return value is num && filter.value is num && value < filter.value;
    case FilterOperator.lessThanOrEqual:
      return value is num && filter.value is num && value <= filter.value;
    case FilterOperator.contains:
      return value is String && filter.value is String && value.toLowerCase().contains(filter.value.toLowerCase());
    case FilterOperator.isNull:
      return value == null;
    case FilterOperator.isNotNull:
      return value != null;
    default:
      return false;
  }
}
