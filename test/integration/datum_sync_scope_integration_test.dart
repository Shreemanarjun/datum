import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// Re-using mocks from other tests for consistency
class MockedLocalAdapter<T extends DatumEntity> extends Mock implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntity> extends Mock implements RemoteAdapter<T> {}

void main() {
  group('DatumSyncScope Integration Test', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    const userId = 'user-scope-test';

    setUpAll(() {
      // Register fallbacks for mocktail
      registerFallbackValue(
        const DatumSyncMetadata(userId: 'fb', dataHash: 'fb'),
      );
      registerFallbackValue(TestEntity.create('fb', 'fb', 'fb'));
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

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Stub default behaviors for adapters
      _stubDefaultBehaviors(localAdapter, remoteAdapter, connectivityChecker);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: const DatumConfig(enableLogging: false),
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('synchronize with scope passes filters to remote adapter', () async {
      // Arrange
      const query = DatumQuery(filters: [
        Filter('status', FilterOperator.equals, 'active'),
        Filter('minDate', FilterOperator.equals, '2023-01-01'),
      ]);
      const scope = DatumSyncScope(query: query);

      // Act
      await manager.synchronize(userId, scope: scope);

      // Assert
      final captured = verify(
        () => remoteAdapter.readAll(
          userId: userId,
          scope: captureAny(named: 'scope'),
        ),
      ).captured;

      expect(captured, hasLength(1));
      final capturedScope = captured.first as DatumSyncScope?;
      expect(capturedScope, isNotNull);
      expect(capturedScope, scope);
      expect(capturedScope!.query.filters, hasLength(2));
    });

    test(
      'synchronize without scope passes null scope to remote adapter',
      () async {
        // Act
        await manager.synchronize(userId);

        // Assert
        final captured = verify(
          () => remoteAdapter.readAll(
            userId: userId,
            scope: captureAny(named: 'scope'),
          ),
        ).captured;

        expect(captured, hasLength(1));
        final capturedScope = captured.first as DatumSyncScope?;
        expect(capturedScope, isNull);
      },
    );

    test('synchronize with empty filter scope passes empty map to remote', () async {
      // Arrange
      const scope = DatumSyncScope(query: DatumQuery(filters: []));

      // Act
      await manager.synchronize(userId, scope: scope);

      // Assert
      final captured = verify(
        () => remoteAdapter.readAll(
          userId: userId,
          scope: captureAny(named: 'scope'),
        ),
      ).captured;

      expect(captured, hasLength(1));
      final capturedScope = captured.first as DatumSyncScope?;
      expect(capturedScope, isNotNull);
      expect(capturedScope!.query.filters, isEmpty);
    });
  });
}

/// Helper to stub common adapter methods.
void _stubDefaultBehaviors(
  MockedLocalAdapter<TestEntity> local,
  MockedRemoteAdapter<TestEntity> remote,
  MockConnectivityChecker connectivity,
) {
  when(() => connectivity.isConnected).thenAnswer((_) async => true);
  when(() => local.initialize()).thenAnswer((_) async {});
  when(() => local.dispose()).thenAnswer((_) async {});
  when(() => remote.initialize()).thenAnswer((_) async {});
  when(() => remote.dispose()).thenAnswer((_) async {});
  when(() => local.getStoredSchemaVersion()).thenAnswer((_) async => 0);
  when(() => local.getPendingOperations(any())).thenAnswer((_) async => []);
  when(
    () => local.readByIds(any(), userId: any(named: 'userId')),
  ).thenAnswer((_) async => {});
  when(
    () => local.readAll(userId: any(named: 'userId')),
  ).thenAnswer((_) async => []);
  when(() => local.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
  when(() => remote.updateSyncMetadata(any(), any())).thenAnswer((_) async {});
  when(
    () => remote.readAll(
      userId: any(named: 'userId'),
      scope: any(named: 'scope'),
    ),
  ).thenAnswer((_) async => []);
  when(() => local.changeStream()).thenAnswer((_) => const Stream.empty());
  when(() => remote.changeStream).thenAnswer((_) => const Stream.empty());

  when(
    () => local.saveLastSyncResult(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => local.getLastSyncResult(any()),
  ).thenAnswer((_) async => null);
}
