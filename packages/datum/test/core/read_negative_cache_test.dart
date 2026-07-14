import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  late MockLocalAdapter<TestEntity> local;
  late MockRemoteAdapter<TestEntity> remote;
  late DatumManager<TestEntity> manager;

  setUp(() async {
    local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());

    manager = DatumManager<TestEntity>(
      localAdapter: local,
      remoteAdapter: remote,
      connectivity: connectivity,
      datumConfig: const DatumConfig<TestEntity>(schemaVersion: 0),
    );
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  test('read() does not cache negative results — later-arriving data is visible', () async {
    // 1. Read a missing entity: returns null (and must NOT poison the cache).
    expect(await manager.read('e1', userId: 'u1'), isNull);

    // 2. Simulate the entity arriving later via sync/realtime, inserted directly
    //    into the local store (bypassing the manager's own cache invalidation).
    local.addLocalItem('u1', TestEntity.create('e1', 'u1', 'arrived'));

    // 3. Before the fix, this returned null (stale cached "does not exist").
    //    Now the read hits the store and sees the new data.
    final read = await manager.read('e1', userId: 'u1');
    expect(read, isNotNull);
    expect(read?.name, 'arrived');
  });

  test('repeated reads of a missing entity keep returning null', () async {
    expect(await manager.read('missing', userId: 'u1'), isNull);
    expect(await manager.read('missing', userId: 'u1'), isNull);
  });

  test('positive existence is still cached (stats reflect it)', () async {
    local.addLocalItem('u1', TestEntity.create('e1', 'u1', 'exists'));
    await manager.read('e1', userId: 'u1');
    expect(manager.getCacheStats()['entity_existence'], greaterThan(0));
  });
}
