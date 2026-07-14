import 'dart:async';

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
      datumConfig: const DatumConfig<TestEntity>(),
    );
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  TestEntity e(String id, String name) => TestEntity.create(id, 'u1', name);

  group('DatumManager.fetch (#17)', () {
    test('localOnly reads only local', () async {
      local.addLocalItem('u1', e('l1', 'local'));
      remote.addRemoteItem('u1', e('r1', 'remote'));
      final result = await manager.fetch(const DatumQuery(), strategy: DataFetchStrategy.localOnly, userId: 'u1');
      expect(result.map((x) => x.id), ['l1']);
    });

    test('remoteOnly reads only remote', () async {
      local.addLocalItem('u1', e('l1', 'local'));
      remote.addRemoteItem('u1', e('r1', 'remote'));
      final result = await manager.fetch(const DatumQuery(), strategy: DataFetchStrategy.remoteOnly, userId: 'u1');
      expect(result.map((x) => x.id), ['r1']);
    });

    test('localFirst returns local when present', () async {
      local.addLocalItem('u1', e('l1', 'local'));
      remote.addRemoteItem('u1', e('r1', 'remote'));
      final result = await manager.fetch(const DatumQuery(), strategy: DataFetchStrategy.localFirst, userId: 'u1');
      expect(result.map((x) => x.id), ['l1']);
    });

    test('localFirst falls back to remote when local is empty, and can persist', () async {
      remote.addRemoteItem('u1', e('r1', 'remote'));
      final result = await manager.fetch(
        const DatumQuery(),
        strategy: DataFetchStrategy.localFirst,
        userId: 'u1',
        persistRemoteResults: true,
      );
      expect(result.map((x) => x.id), ['r1']);
      // The remote result was cached locally.
      expect(await local.read('r1', userId: 'u1'), isNotNull);
    });

    test('remoteFirst falls back to local when remote fails', () async {
      local.addLocalItem('u1', e('l1', 'local'));
      remote.isConnectedValue = false; // remote.query throws
      final result = await manager.fetch(const DatumQuery(), strategy: DataFetchStrategy.remoteFirst, userId: 'u1');
      expect(result.map((x) => x.id), ['l1']);
    });
  });

  group('DatumManager.fetchById (#17)', () {
    test('localFirst falls back to remote by id', () async {
      remote.addRemoteItem('u1', e('r1', 'remote'));
      final result = await manager.fetchById('r1', strategy: DataFetchStrategy.localFirst, userId: 'u1');
      expect(result?.id, 'r1');
    });

    test('remoteFirst falls back to local on remote error', () async {
      local.addLocalItem('u1', e('x1', 'local'));
      remote.isConnectedValue = false;
      final result = await manager.fetchById('x1', strategy: DataFetchStrategy.remoteFirst, userId: 'u1');
      expect(result?.id, 'x1');
    });
  });
}
