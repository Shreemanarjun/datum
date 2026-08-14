import 'package:datum/datum.dart';
import 'package:datum/source/core/engine/metadata_hash_cache.dart';
import 'package:test/test.dart';

import '../coverage/manager_coverage_helpers.dart' show OnlineConnectivity;
import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';

/// Counts readAll calls so tests can prove when the engine skipped the O(n)
/// re-read + rehash while stamping sync metadata.
class _CountingLocalAdapter extends MockLocalAdapter<TestEntity> {
  int readAllCalls = 0;

  @override
  Future<List<TestEntity>> readAll({String? userId}) {
    readAllCalls++;
    return super.readAll(userId: userId);
  }
}

TestEntity _entity(String id, {int value = 0}) => TestEntity(
      id: id,
      userId: 'u1',
      name: 'name-$id',
      value: value,
      modifiedAt: DateTime(2026),
      createdAt: DateTime(2026),
      version: 1,
    );

void main() {
  group('MetadataHashCache', () {
    test('peek/store/invalidate lifecycle', () {
      final cache = MetadataHashCache();
      expect(cache.peek('u1'), isNull);

      cache.store('u1', hash: 'h1', count: 3);
      expect(cache.peek('u1'), (hash: 'h1', count: 3));

      cache.invalidate('u1');
      expect(cache.peek('u1'), isNull);

      cache.store('u1', hash: 'h1', count: 1);
      cache.store('u2', hash: 'h2', count: 2);
      cache.invalidateAll();
      expect(cache.peek('u1'), isNull);
      expect(cache.peek('u2'), isNull);
    });
  });

  group('engine metadata hash caching', () {
    late _CountingLocalAdapter local;
    late MockRemoteAdapter<TestEntity> remote;
    late DatumManager<TestEntity> manager;

    Future<void> setUpManager({bool enableCache = true}) async {
      local = _CountingLocalAdapter();
      remote = MockRemoteAdapter<TestEntity>();
      manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: const OnlineConnectivity(),
        datumConfig: DatumConfig<TestEntity>(
          enableLogging: false,
          enableMetadataHashCache: enableCache,
        ),
      );
      await manager.initialize();
    }

    tearDown(() => manager.dispose());

    /// Forces the next cycle to actually run (not skip via the stored-hash
    /// fast-path) while the local store is unchanged — the case the cache
    /// exists for.
    Future<void> forceNonSkippedCycle() => remote.updateSyncMetadata(
          const DatumSyncMetadata(userId: 'u1', dataHash: 'remote-beacon-differs'),
          'u1',
        );

    test('cycles with an unchanged local store reuse the cached hash', () async {
      await setUpManager();
      await manager.push(item: _entity('a'), userId: 'u1');
      await manager.synchronize('u1');

      final afterFirst = local.readAllCalls;
      await forceNonSkippedCycle();
      await manager.synchronize('u1');
      await forceNonSkippedCycle();
      await manager.synchronize('u1');

      expect(local.readAllCalls, afterFirst, reason: 'no local writes between cycles — metadata stamping must not re-read');
    });

    test('a write between cycles invalidates and the stamped hash stays truthful', () async {
      await setUpManager();
      await manager.push(item: _entity('a'), userId: 'u1');
      await manager.synchronize('u1');
      final hashAfterFirst = (await local.getSyncMetadata('u1'))!.dataHash;

      await manager.push(item: _entity('b', value: 9), userId: 'u1');
      await manager.synchronize('u1');
      final hashAfterSecond = (await local.getSyncMetadata('u1'))!.dataHash;

      expect(hashAfterSecond, isNot(hashAfterFirst));
      expect(
        hashAfterSecond,
        const DatumHashGenerator().hashEntitiesUnordered(await local.readAll(userId: 'u1')),
        reason: 'stamped hash must describe the actual store content',
      );
    });

    test('enableMetadataHashCache: false recomputes every non-skipped cycle', () async {
      await setUpManager(enableCache: false);
      await manager.push(item: _entity('a'), userId: 'u1');
      await manager.synchronize('u1');

      final afterFirst = local.readAllCalls;
      await remote.updateSyncMetadata(
        const DatumSyncMetadata(userId: 'u1', dataHash: 'remote-beacon-differs'),
        'u1',
      );
      await manager.synchronize('u1');

      expect(local.readAllCalls, greaterThan(afterFirst), reason: 'cache disabled — stamping re-reads each cycle');
    });
  });
}
