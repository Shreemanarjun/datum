import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

// Scenarios: sync.live (packages/datum/doc/SYNC_SCENARIOS.md)
void main() {
  test('changes applied from the remote change stream are reported per batch, without a sync cycle', () async {
    final online = MockConnectivityChecker();
    when(() => online.isConnected).thenAnswer((_) async => true);
    when(() => online.onStatusChange).thenAnswer((_) => const Stream.empty());
    final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final manager = DatumManager<TestEntity>(
      localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
      remoteAdapter: remote,
      connectivity: online,
      datumConfig: const DatumConfig<TestEntity>(enableLogging: false, remoteEventDebounceTime: Duration(milliseconds: 20)),
    );
    await manager.initialize();
    addTearDown(manager.dispose);
    final live = <LiveChangesAppliedEvent<TestEntity>>[];
    final cycles = <DatumSyncCompletedEvent<TestEntity>>[];
    final progress = <DatumSyncProgressEvent<TestEntity>>[];
    final subscriptions = [manager.onLiveChangesApplied.listen(live.add), manager.onSyncCompleted.listen(cycles.add), manager.onSyncProgress.listen(progress.add)];
    addTearDown(() => Future.wait([for (final s in subscriptions) s.cancel()]));

    // Two edits made on another device 300 ms and 200 ms ago arrive together.
    final now = DateTime.now();
    TestEntity madeAgo(String id, int ms) => TestEntity.create(id, 'u1', id).copyWith(modifiedAt: now.subtract(Duration(milliseconds: ms)));
    DatumChangeDetail<TestEntity> change(TestEntity e, [DatumOperationType type = DatumOperationType.create]) =>
        DatumChangeDetail(type: type, entityId: e.id, userId: e.userId, timestamp: e.modifiedAt, data: e);
    final first = madeAgo('r1', 300), second = madeAgo('r2', 200);
    remote
      ..emitChange(change(first))
      ..emitChange(change(second));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(live, hasLength(1), reason: 'one event for the batch');
    expect((live.single.userId, live.single.count), ('u1', 2));
    expect(live.single.lastChangedAt, second.modifiedAt, reason: 'the most recent edit in the batch');
    expect(live.single.timestamp.difference(live.single.lastChangedAt!), greaterThanOrEqualTo(const Duration(milliseconds: 200)), reason: 'how long the change took to get here');
    expect(live.single.duration, lessThan(const Duration(seconds: 1)));
    expect((await manager.readAll(userId: 'u1')).map((e) => e.id), unorderedEquals(['r1', 'r2']));
    expect(cycles, isEmpty, reason: 'no sync cycle ran, so nothing else would tell the app');
    expect(await manager.getLastSyncResult('u1'), isNull, reason: 'receiving a change is not a sync: no result is made up for it');
    expect(await manager.getPendingCount('u1'), 0, reason: 'a received change is not queued for upload');

    // The same change delivered again applies nothing and reports nothing.
    remote.emitChange(change(first));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(live, hasLength(1));

    // A delete that carries the row's last state (as most feeds do) is a new
    // change, not a repeat of the upsert it follows.
    remote.emitChange(change(first, DatumOperationType.delete));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(live, hasLength(2));
    expect(live.last.count, 1);
    expect(await manager.read('r1', userId: 'u1'), isNull);

    // Re-created, then deleted again within the dedupe window, with a feed
    // that sends no row on delete: the second delete must still apply.
    DatumChangeDetail<TestEntity> bareDelete(String id) =>
        DatumChangeDetail(type: DatumOperationType.delete, entityId: id, userId: 'u1', timestamp: DateTime.now());
    remote.emitChange(bareDelete('r2'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    remote.emitChange(change(madeAgo('r2', 0)));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await manager.read('r2', userId: 'u1'), isNotNull);
    remote.emitChange(bareDelete('r2'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await manager.read('r2', userId: 'u1'), isNull, reason: 'a row deleted twice in a few seconds stays deleted here too');
    expect(live, hasLength(5));

    // This device's own writes are not received changes: neither the local
    // store's echo of them, nor the feed returning them with the timestamp
    // in UTC and at the server's precision.
    progress.clear();
    final mine = TestEntity.create('mine', 'u1', 'mine').copyWith(modifiedAt: DateTime.now());
    expect(mine.modifiedAt.isUtc, isFalse);
    await manager.push(item: mine, userId: 'u1');
    final edited = mine.copyWith(name: 'edited', version: 2, modifiedAt: DateTime.now());
    await manager.push(item: edited, userId: 'u1');
    final fromServer = DateTime.fromMillisecondsSinceEpoch(edited.modifiedAt.millisecondsSinceEpoch, isUtc: true);
    remote.emitChange(change(edited.copyWith(modifiedAt: fromServer), DatumOperationType.update));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(live, hasLength(5), reason: 'an echo is not a change from another device');
    expect(progress, isEmpty, reason: 'and nothing was downloaded');
    expect((await manager.read('mine', userId: 'u1'))?.name, 'edited');
    expect(await manager.getPendingCount('u1'), 2, reason: 'each write is queued once');

    // Once the device has synced, bytes received live join its running
    // totals: most of a realtime app's data arrives this way.
    await manager.synchronize('u1');
    final before = (await manager.getLastSyncResult('u1'))!;
    remote.emitChange(change(madeAgo('r9', 10)));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final after = (await manager.getLastSyncResult('u1'))!;
    expect(after.totalBytesPulled, greaterThan(before.totalBytesPulled));
    expect((after.totalBytesPushed, after.syncedCount, after.duration), (before.totalBytesPushed, before.syncedCount, before.duration), reason: 'the rest of the last sync is as it was');
  });
  test('a live change follows the pull rules: stale rows are ignored and a row competing with an unsynced edit goes to the resolver', () async {
    final online = MockConnectivityChecker();
    when(() => online.isConnected).thenAnswer((_) async => true);
    when(() => online.onStatusChange).thenAnswer((_) => const Stream.empty());
    Future<(DatumManager<TestEntity>, MockRemoteAdapter<TestEntity>, List<String>)> device(DatumConflictResolver<TestEntity> resolver) async {
      final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final manager = DatumManager<TestEntity>(
        localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson),
        remoteAdapter: remote,
        connectivity: online,
        datumConfig: DatumConfig<TestEntity>(enableLogging: false, defaultConflictResolver: resolver, remoteEventDebounceTime: Duration.zero),
      );
      await manager.initialize();
      addTearDown(manager.dispose);
      final conflicts = <String>[];
      final sub = manager.onConflict.listen((e) => conflicts.add(e.remoteData?.name ?? ''));
      addTearDown(sub.cancel);
      return (manager, remote, conflicts);
    }

    final t0 = DateTime(2030);
    TestEntity row(String name, int version, {int minute = 0, bool deleted = false}) =>
        TestEntity(id: 'x', userId: 'u1', name: name, value: 0, modifiedAt: t0.add(Duration(minutes: minute)), createdAt: t0, version: version, isDeleted: deleted);
    DatumChangeDetail<TestEntity> live(TestEntity e) => DatumChangeDetail(type: DatumOperationType.update, entityId: e.id, userId: e.userId, timestamp: e.modifiedAt, data: e);
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
    Future<String?> shown(DatumManager<TestEntity> m) async => (await m.read('x', userId: 'u1', includeDeleted: true))?.name;

    // Every device starts from the same synced row (version 3).
    Future<(DatumManager<TestEntity>, MockRemoteAdapter<TestEntity>, List<String>)> synced(DatumConflictResolver<TestEntity> resolver) async {
      final d = await device(resolver);
      d.$2.emitChange(live(row('synced', 3)));
      await settle();
      expect(await shown(d.$1), 'synced');
      expect(await d.$1.getPendingCount('u1'), 0);
      return d;
    }

    // 1. A late or repeated event for an older state does not roll the row
    //    back, whatever the resolver.
    final (plain, plainFeed, plainConflicts) = await synced(LastWriteWinsResolver<TestEntity>());
    plainFeed.emitChange(live(row('older', 2, minute: 9)));
    await settle();
    expect(await shown(plain), 'synced');
    expect(plainConflicts, isEmpty);
    // A newer one is taken.
    plainFeed.emitChange(live(row('newer', 4, minute: 1)));
    await settle();
    expect(await shown(plain), 'newer');
    expect(await plain.getPendingCount('u1'), 0);

    // 2. An unsynced local edit, and the feed delivers the row it started
    //    from once more: not news. The edit and its queue entry stay.
    for (final resolver in [LastWriteWinsResolver<TestEntity>(), RemotePriorityResolver<TestEntity>(), LocalPriorityResolver<TestEntity>()]) {
      final (manager, feed, conflicts) = await synced(resolver);
      final received = <int>[];
      final liveSub = manager.onLiveChangesApplied.listen((e) => received.add(e.count));
      addTearDown(liveSub.cancel);
      await manager.push(item: row('mine', 4, minute: 5), userId: 'u1');
      feed.emitChange(live(row('synced', 3)));
      await settle();
      expect(await shown(manager), 'mine', reason: resolver.name);
      expect(await manager.getPendingCount('u1'), 1, reason: resolver.name);
      expect(conflicts, isEmpty, reason: resolver.name);

      // 3. Now another device's edit of the same row arrives: a conflict,
      //    decided by the resolver, with the queue left matching the row.
      feed.emitChange(live(row('theirs', 4, minute: 2)));
      await settle();
      expect(conflicts, ['theirs'], reason: resolver.name);
      final remoteWins = resolver is RemotePriorityResolver<TestEntity>;
      expect(await shown(manager), remoteWins ? 'theirs' : 'mine', reason: resolver.name);
      expect(await manager.getPendingCount('u1'), remoteWins ? 0 : 1, reason: '${resolver.name}: the losing edit is not uploaded later');
      // A row the resolver took from the feed is a received change, like
      // any other; one it turned down is not.
      expect(received, remoteWins ? [1] : isEmpty, reason: '${resolver.name}: live batches reported (rows each)');
    }

    // 4. Two unsynced edits here (version 5) against one edit elsewhere
    //    (version 4): the lower version is still news, not a late event,
    //    because it is past the version the local edits started from.
    final (twice, twiceFeed, twiceConflicts) = await synced(RemotePriorityResolver<TestEntity>());
    await twice.push(item: row('mine', 4, minute: 5), userId: 'u1');
    await twice.push(item: row('mine again', 5, minute: 6), userId: 'u1');
    twiceFeed.emitChange(live(row('theirs', 4, minute: 2)));
    await settle();
    expect(twiceConflicts, ['theirs']);
    expect(await shown(twice), 'theirs');
    expect(await twice.getPendingCount('u1'), 0);
  });
}
