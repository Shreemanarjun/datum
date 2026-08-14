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

  group('DatumManager.fetchById remoteFirst local-read fallback', () {
    late _FlakyReadLocalAdapter flakyLocal;
    late DatumManager<TestEntity> flakyManager;

    setUp(() async {
      flakyLocal = _FlakyReadLocalAdapter(fromJson: TestEntity.fromJson);
      final flakyRemote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final connectivity = MockConnectivityChecker();
      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
      flakyManager = DatumManager<TestEntity>(
        localAdapter: flakyLocal,
        remoteAdapter: flakyRemote,
        connectivity: connectivity,
        datumConfig: const DatumConfig<TestEntity>(),
      );
      await flakyManager.initialize();
    });

    tearDown(() => flakyManager.dispose());

    test('a local-read failure after a null remote result falls back through the catch', () async {
      // The remote has no such item, so the in-try local read runs. Its
      // failure must stay inside the try (the read is awaited) so the catch
      // can log and retry locally instead of the error escaping to the caller.
      flakyLocal.addLocalItem('u1', e('x1', 'local'));
      flakyLocal.readCalls = 0;
      flakyLocal.failuresRemaining = 1;

      final result = await flakyManager.fetchById('x1', strategy: DataFetchStrategy.remoteFirst, userId: 'u1');

      expect(result?.id, 'x1');
      expect(flakyLocal.readCalls, 2);
    });

    test('a persistent local-read failure still surfaces to the caller', () async {
      flakyLocal.failuresRemaining = 2;
      await expectLater(
        flakyManager.fetchById('x1', strategy: DataFetchStrategy.remoteFirst, userId: 'u1'),
        throwsStateError,
      );
    });
  });
}

/// A [MockLocalAdapter] whose next [failuresRemaining] reads throw, for
/// exercising the remoteFirst in-try local-read failure path.
class _FlakyReadLocalAdapter extends MockLocalAdapter<TestEntity> {
  _FlakyReadLocalAdapter({super.fromJson});

  int failuresRemaining = 0;
  int readCalls = 0;

  @override
  Future<TestEntity?> read(String id, {String? userId}) {
    readCalls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('flaky local read');
    }
    return super.read(id, userId: userId);
  }
}
