import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  group('DatumSyncResult.describe / DatumHealth.describe', () {
    test('describes a successful sync', () {
      const result = DatumSyncResult<TestEntity>(
        userId: 'u1',
        duration: Duration(seconds: 2),
        syncedCount: 5,
        failedCount: 0,
        conflictsResolved: 1,
        pendingOperations: [],
        bytesPushedInCycle: 2048,
        bytesPulledInCycle: 1024,
      );
      final text = result.describe();
      expect(text, contains('Sync for u1'));
      expect(text, contains('synced:    5/5'));
      expect(text, contains('conflicts: 1'));
      expect(text, contains('2.00 KB'));
    });

    test('describes a skipped sync', () {
      final result = DatumSyncResult.skipped('u1', 3, reason: 'paused');
      expect(result.describe(), contains('Sync skipped for u1 — paused'));
    });

    test('DatumHealth describe + toString', () {
      const health = DatumHealth(
        status: DatumSyncHealth.degraded,
        localAdapterStatus: AdapterHealthStatus.healthy,
        remoteAdapterStatus: AdapterHealthStatus.unhealthy,
      );
      expect(health.toString(), contains('degraded'));
      expect(health.describe(), contains('remote adapter: unhealthy'));
    });
  });

  group('manager batch conveniences', () {
    late MockLocalAdapter<TestEntity> local;
    late DatumManager<TestEntity> manager;

    setUp(() async {
      local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final connectivity = MockConnectivityChecker();
      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
      manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: connectivity,
        datumConfig: const DatumConfig<TestEntity>(),
      );
      await manager.initialize();
    });

    tearDown(() => manager.dispose());

    test('trySaveMany returns Success with the saved items', () async {
      final result = await manager.trySaveMany(
        items: [TestEntity.create('e1', 'u1', 'A'), TestEntity.create('e2', 'u1', 'B')],
        userId: 'u1',
      );
      expect(result.isSuccess(), isTrue);
      expect(result.success, hasLength(2));
    });

    test('deleteMany removes multiple and returns deleted ids', () async {
      await manager.saveMany(items: [
        TestEntity.create('e1', 'u1', 'A'),
        TestEntity.create('e2', 'u1', 'B'),
        TestEntity.create('e3', 'u1', 'C'),
      ], userId: 'u1');

      final deleted = await manager.deleteMany(['e1', 'e3', 'missing'], userId: 'u1', behavior: DeleteBehavior.hardDelete);
      expect(deleted.toSet(), {'e1', 'e3'});
      expect(await manager.exists('e2', userId: 'u1'), isTrue);
      expect(await manager.exists('e1', userId: 'u1'), isFalse);
    });

    test('trySwitchUser returns a Success result', () async {
      final r = await manager.trySwitchUser(oldUserId: null, newUserId: 'u1', strategy: UserSwitchStrategy.keepLocal);
      expect(r.isSuccess(), isTrue);
    });

    test('tryCascadeDelete wraps the outcome in a DatumEither (never throws)', () async {
      await manager.push(item: TestEntity.create('e1', 'u1', 'A'), userId: 'u1');
      final r = await manager.tryCascadeDelete(id: 'e1', userId: 'u1');
      expect(r, isA<DatumEither<DatumError, CascadeDeleteResult<TestEntity>>>());
    });
  });
}
