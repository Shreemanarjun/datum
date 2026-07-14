import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

DatumManager<TestEntity> _manager(MockLocalAdapter<TestEntity> local, DatumConfig<TestEntity> config) {
  final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
  final connectivity = MockConnectivityChecker();
  when(() => connectivity.isConnected).thenAnswer((_) async => true);
  when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return DatumManager<TestEntity>(
    localAdapter: local,
    remoteAdapter: remote,
    connectivity: connectivity,
    datumConfig: config,
  );
}

void main() {
  test('local query caching is OFF by default — fresh data is always returned', () async {
    final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final manager = _manager(local, const DatumConfig<TestEntity>());
    await manager.initialize();
    addTearDown(manager.dispose);

    local.addLocalItem('u1', TestEntity.create('e1', 'u1', 'A'));
    const q = DatumQuery();

    final first = await manager.query(q, source: DataSource.local, userId: 'u1');
    expect(first, hasLength(1));

    // Data changes directly in the store (e.g. arriving via sync/realtime).
    local.addLocalItem('u1', TestEntity.create('e2', 'u1', 'B'));

    // With the old always-on cache this would have returned the stale 1-item
    // list; now the query re-reads and sees both items.
    final second = await manager.query(q, source: DataSource.local, userId: 'u1');
    expect(second, hasLength(2));

    // The query cache is never populated when disabled.
    expect(manager.getCacheStats()['queries'], 0);
  });

  test('enabling the query cache restores caching behavior', () async {
    final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final manager = _manager(local, const DatumConfig<TestEntity>(enableQueryCache: true));
    await manager.initialize();
    addTearDown(manager.dispose);

    local.addLocalItem('u1', TestEntity.create('e1', 'u1', 'A'));
    const q = DatumQuery();
    await manager.query(q, source: DataSource.local, userId: 'u1');

    expect(manager.getCacheStats()['queries'], greaterThan(0));
  });
}
