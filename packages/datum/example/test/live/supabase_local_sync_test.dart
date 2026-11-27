// Live sync journeys against a LOCAL Supabase stack (no Docker needed):
//
//   cd packages/datum/example
//   supabase start --runtime native        # once; schema from supabase/migrations
//   flutter test test/live --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
//     --dart-define=SUPABASE_ANON_KEY=<PUBLISHABLE_KEY from `supabase status --env`>
//
// Two "devices" (separate clients + local stores, same account) exercise the
// real example SupabaseRemoteAdapter: push, pull, realtime fan-out, soft
// deletes, concurrent edits, offline replay and an expired session. Each step
// is timed and printed. Skipped when SUPABASE_URL isn't defined.
import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart' show TestConnectivityChecker;
import 'package:example/const/secrets.dart';
import 'package:example/features/auth/data/adapters/supabase_adapter.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _live = bool.hasEnvironment('SUPABASE_URL');

typedef _Device = ({DatumManager<Task> manager, SupabaseClient client, TestConnectivityChecker net, _CountingRemote remote});

/// Counts rows each pull returns, to prove delta pulls stay small.
class _CountingRemote extends SupabaseRemoteAdapter<Task> {
  _CountingRemote(SupabaseClient client) : super(tableName: 'tasks', fromMap: Task.fromMap, clientOverride: client);
  int fullPulls = 0;
  int deltaRows = 0;

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) {
    fullPulls++;
    return super.readAll(userId: userId, scope: scope);
  }

  @override
  Future<List<Task>> readSince(DateTime since, {String? userId, DatumSyncScope? scope}) async {
    final rows = await super.readSince(since, userId: userId, scope: scope);
    deltaRows += rows.length;
    return rows;
  }
}

// Implicit flow: PKCE needs persistent storage these headless clients lack.
const _auth = AuthClientOptions(authFlowType: AuthFlowType.implicit, autoRefreshToken: false);

final _timings = <String, Duration>{};

/// Ids are UUIDs (global primary keys); a stable one per name in this run.
final _ids = <String, String>{};
String _id(String name) => _ids.putIfAbsent(name, () => const Uuid().v4());

Future<R> _timed<R>(String step, Future<R> Function() body) async {
  final watch = Stopwatch()..start();
  final result = await body();
  _timings[step] = watch.elapsed;
  return result;
}

Future<_Device> _device(String email, String password, {DatumConflictResolver<Task>? resolver}) async {
  final client = SupabaseClient(Secrets.SUPABASE_URL, Secrets.SUPABASE_ANON_KEY, authOptions: _auth);
  await client.auth.signInWithPassword(email: email, password: password);
  final net = TestConnectivityChecker();
  final remote = _CountingRemote(client);
  final manager = DatumManager<Task>(
    localAdapter: InMemoryLocalAdapter<Task>(fromMap: Task.fromMap),
    remoteAdapter: remote,
    connectivity: net,
    datumConfig: DatumConfig<Task>(
      enableLogging: false,
      defaultConflictResolver: resolver,
      // Local stack shares one clock; a tight overlap keeps delta pulls small.
      deltaSyncOverlap: const Duration(seconds: 1),
      authState: client.auth.onAuthStateChange.map((s) => s.session != null),
    ),
  );
  await manager.initialize();
  return (manager: manager, client: client, net: net, remote: remote);
}

Task _task(String userId, String title, {String? id}) {
  final now = DateTime.now();
  return Task(id: id ?? const Uuid().v4(), userId: userId, title: title, createdAt: now, modifiedAt: now);
}

Future<List<Map<String, dynamic>>> _serverRows(SupabaseClient client) => client.from('tasks').select();

/// Polls [read] until [done] holds or [timeout] passes; returns the wait.
Future<Duration> _until(Future<bool> Function() done, {Duration timeout = const Duration(seconds: 10)}) async {
  final watch = Stopwatch()..start();
  while (!await done()) {
    if (watch.elapsed > timeout) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return watch.elapsed;
}

Future<({String id, String email})> _signUp(String email, String password) async {
  final client = SupabaseClient(Secrets.SUPABASE_URL, Secrets.SUPABASE_ANON_KEY, authOptions: _auth);
  final id = (await client.auth.signUp(email: email, password: password)).user!.id;
  await client.dispose();
  return (id: id, email: email);
}

// Scenarios: backend.supabase (packages/datum/doc/SYNC_SCENARIOS.md)
void main() {
  late _Device a;
  late _Device b;
  late String userId;
  final email = 'datum-${DateTime.now().microsecondsSinceEpoch}@example.com';
  const password = 'datum-local-pass';

  setUpAll(() async {
    if (!_live) return;
    userId = (await _signUp(email, password)).id;
    a = await _device(email, password);
    b = await _device(email, password);
  });

  tearDownAll(() async {
    if (!_live) return;
    for (final d in [a, b]) {
      await d.manager.dispose();
      await d.client.dispose();
    }
    // ignore: avoid_print
    print(['', '| step | ms |', '|---|---:|', for (final MapEntry(:key, :value) in _timings.entries) '| $key | ${value.inMilliseconds} |'].join('\n'));
  });

  test('two devices on one account: push, pull, realtime, deletes, conflicts, offline, expired session', () async {
    // 1. Device A creates 50 tasks offline-first and pushes them.
    final created = [for (var i = 0; i < 50; i++) _task(userId, 'task $i', id: _id('live-$i'))];
    await _timed('A: 50 local writes', () async {
      for (final t in created) {
        await a.manager.push(item: t);
      }
    });
    expect(await a.manager.getPendingCount(userId), 50);
    final pushed = await _timed('A: push 50', () => a.manager.synchronize(userId));
    expect(pushed.failedCount, 0);
    expect(await a.manager.getPendingCount(userId), 0, reason: 'push result: $pushed skipped=${pushed.wasSkipped} cancelled=${pushed.wasCancelled} error=${pushed.error}');
    expect(await _serverRows(a.client), hasLength(50));

    // 2. Device B pulls them.
    final pulled = await _timed('B: first pull (50 rows)', () => b.manager.synchronize(userId));
    expect(pulled.failedCount, 0);
    expect((await b.manager.readAll(userId: userId)).map((t) => t.id).toSet(), created.map((t) => t.id).toSet());

    // Sync metadata is one row per (user, entity table), never shared.
    final meta = await a.client.from('sync_metadata').select('entity_table').eq('user_id', userId);
    expect(meta.map((r) => r['entity_table']), ['tasks']);

    // 3. Realtime: A's edit reaches B's store with no sync call on B.
    final edited = (await a.manager.read(_id('live-0'), userId: userId))!.copyWith(title: 'edited on A', modifiedAt: DateTime.now());
    await a.manager.push(item: edited);
    await _timed('A: push 1 edit', () => a.manager.synchronize(userId));
    _timings['B: realtime arrival of A\'s edit'] = await _until(() async => (await b.manager.read(_id('live-0'), userId: userId))?.title == 'edited on A');

    // 4. Idle sync cost (nothing changed anywhere), and delta pulls: after
    //    the first full pull B only ever fetches rows the server changed.
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // past the overlap window
    await b.manager.synchronize(userId);
    final fullPullsBefore = b.remote.fullPulls;
    b.remote.deltaRows = 0;
    await _timed('B: idle delta sync', () => b.manager.synchronize(userId));
    expect(b.remote.fullPulls, fullPullsBefore, reason: 'no full-table pull once synced');
    expect(b.remote.deltaRows, lessThan(5), reason: 'only the overlap window, not 50 rows');
    // forceFullSync is the explicit way to re-read everything.
    await b.manager.synchronize(userId, options: const DatumSyncOptions(forceFullSync: true));
    expect(b.remote.fullPulls, fullPullsBefore + 1, reason: 'a forced sync re-reads the table');
    b.remote.fullPulls = fullPullsBefore;

    // 5. Soft delete on B propagates to A as a tombstone.
    await b.manager.delete(id: _id('live-1'), userId: userId, behavior: DeleteBehavior.softDelete);
    await _timed('B: push soft delete', () => b.manager.synchronize(userId));
    expect((await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-1'))['is_deleted'], isTrue);
    await a.manager.synchronize(userId);
    expect(await a.manager.read(_id('live-1'), userId: userId), isNull, reason: 'tombstone hidden from default reads');
    expect((await a.manager.read(_id('live-1'), userId: userId, includeDeleted: true))?.isDeleted, isTrue);

    // 6. Concurrent edits while both are offline converge on one value.
    a.net.setOnline(false);
    b.net.setOnline(false);
    final base = (await a.manager.read(_id('live-2'), userId: userId))!;
    await a.manager.push(item: base.copyWith(title: 'A offline', modifiedAt: DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final bBase = (await b.manager.read(_id('live-2'), userId: userId))!;
    await b.manager.push(item: bBase.copyWith(title: 'B offline (later)', modifiedAt: DateTime.now()));
    a.net.setOnline(true);
    b.net.setOnline(true);
    await _timed('conflict: A then B sync', () async {
      await a.manager.synchronize(userId);
      await b.manager.synchronize(userId);
      await a.manager.synchronize(userId);
    });
    final server = (await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-2'))['title'];
    expect((await a.manager.read(_id('live-2'), userId: userId))?.title, server);
    expect((await b.manager.read(_id('live-2'), userId: userId))?.title, server);
    expect(server, 'B offline (later)', reason: 'last write wins by modifiedAt');

    // 7. Offline queue replays once connectivity returns.
    a.net.setOnline(false);
    for (var i = 0; i < 10; i++) {
      await a.manager.push(item: _task(userId, 'offline $i', id: _id('off-$i')));
    }
    expect(await a.manager.getPendingCount(userId), 10);
    a.net.setOnline(true);
    await _timed('A: replay 10 offline writes', () => a.manager.synchronize(userId));
    expect(await a.manager.getPendingCount(userId), 0);
    expect((await _serverRows(a.client)).map((r) => r['id']), containsAll([for (var i = 0; i < 10; i++) _id('off-$i')]));

    // 8. Expired session: sync pauses with the write queued (not parked),
    //    and signing back in resumes and delivers it with no app code.
    await a.client.auth.signOut(scope: SignOutScope.local);
    await a.manager.push(item: _task(userId, 'written while signed out', id: _id('auth-1')));
    await expectLater(a.manager.synchronize(userId), throwsA(isA<AuthenticationException>()));
    expect(a.manager.currentStatus.status, DatumSyncStatus.paused);
    expect(await a.manager.getParkedOperations(userId), isEmpty);
    expect((await a.manager.getPendingOperations(userId)).map((o) => o.entityId), contains(_id('auth-1')));
    final resumed = a.manager.onSyncCompleted.first;
    await _timed('A: sign in → auto-resume push', () async {
      await a.client.auth.signInWithPassword(email: email, password: password);
      await resumed.timeout(const Duration(seconds: 10));
    });
    expect(await a.manager.getPendingCount(userId), 0);
    expect((await _serverRows(a.client)).map((r) => r['id']), contains(_id('auth-1')));

    // 9. Another account can't touch these rows: RLS rejects it as an
    //    authorization error and the write parks instead of being retried.
    final mallory = await _signUp('mallory-${DateTime.now().microsecondsSinceEpoch}@example.com', password);
    final m = await _device(mallory.email, password);
    addTearDown(() async {
      await m.manager.dispose();
      await m.client.dispose();
    });
    final stolen = _task(mallory.id, 'overwrite attempt', id: _id('live-3'));
    await m.manager.push(item: stolen);
    await m.manager.synchronize(mallory.id).then<void>((_) {}, onError: (_) {});
    expect((await m.manager.getParkedOperations(mallory.id)).map((o) => o.entityId), [_id('live-3')]);
    expect((await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-3'))['title'], 'task 3');
  }, skip: _live ? null : 'pass --dart-define=SUPABASE_URL=… (see header)', timeout: const Timeout(Duration(minutes: 3)));

  test('what is and is not a conflict, and scoped sync, against real Postgres', () async {
    Future<String?> onServer(String name) async => (await _serverRows(a.client)).firstWhere((r) => r['id'] == _id(name))['title'] as String?;
    Future<void> edit(_Device d, String name, String title) async {
      final current = (await d.manager.read(_id(name), userId: userId))!;
      await d.manager.push(item: current.copyWith(title: title, modifiedAt: DateTime.now()));
    }

    Future<({_Device device, List<String> conflicts})> join(DatumConflictResolver<Task> resolver) async {
      final device = await _device(email, password, resolver: resolver);
      addTearDown(() async {
        await device.manager.dispose();
        await device.client.dispose();
      });
      await device.manager.synchronize(userId);
      final conflicts = <String>[];
      final sub = device.manager.onConflict.listen((e) => conflicts.add(e.context.entityId));
      addTearDown(sub.cancel);
      return (device: device, conflicts: conflicts);
    }

    // 1. A device that insists on its own copy still takes an edit made
    //    elsewhere to a row it never touched.
    final local = await join(LocalPriorityResolver<Task>());
    await edit(a, 'live-10', 'edited once on A');
    await edit(a, 'live-10', 'edited twice on A');
    await a.manager.synchronize(userId);
    await local.device.manager.synchronize(userId, options: const DatumSyncOptions(forceFullSync: true));
    expect((await local.device.manager.read(_id('live-10'), userId: userId))?.title, 'edited twice on A');
    expect(local.conflicts, isEmpty);
    expect(await local.device.manager.getPendingCount(userId), 0, reason: 'its old copy is not pushed back');
    expect(await onServer('live-10'), 'edited twice on A');

    // 2. A device that defers to the server keeps its own unsynced edit when
    //    the server row has not changed (it is re-read here: a forced pull).
    final remote = await join(RemotePriorityResolver<Task>());
    await edit(remote.device, 'live-11', 'edited on the deferring device');
    await remote.device.manager.synchronize(userId, options: const DatumSyncOptions(forceFullSync: true));
    expect(remote.conflicts, isEmpty);
    expect(await onServer('live-11'), 'edited on the deferring device');
    expect(await remote.device.manager.getPendingCount(userId), 0);

    // 3. Both edit the same row: that is a conflict, and each device's
    //    resolver decides. Pull first, so the other edit is seen before
    //    anything is overwritten.
    await edit(a, 'live-12', 'A got there first');
    await a.manager.synchronize(userId);
    await edit(remote.device, 'live-12', 'the deferring device, later');
    await edit(local.device, 'live-13', 'the insisting device');
    await edit(a, 'live-13', 'A, uploaded first');
    await a.manager.synchronize(userId);
    await remote.device.manager.synchronize(userId);
    await local.device.manager.synchronize(userId);
    expect(remote.conflicts, [_id('live-12')]);
    expect(await onServer('live-12'), 'A got there first');
    expect((await remote.device.manager.read(_id('live-12'), userId: userId))?.title, 'A got there first');
    expect(local.conflicts, [_id('live-13')]);
    expect(await onServer('live-13'), 'the insisting device');
    expect(await remote.device.manager.getPendingCount(userId), 0);
    expect(await local.device.manager.getPendingCount(userId), 0);

    // 4. The server itself refuses a stale write, in one statement: the
    //    guard that makes overlapping uploads safe.
    final server = (await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-15'));
    final version = server['version'] as int;
    await expectLater(
      a.remote.patchIfUnchanged(id: _id('live-15'), delta: {'title': 'stale write', 'version': version}, baseVersion: version - 1),
      throwsA(isA<ConflictException>()),
    );
    expect(await onServer('live-15'), server['title'], reason: 'a refused write changes nothing');
    await a.remote.patchIfUnchanged(id: _id('live-15'), delta: {'title': 'current write', 'version': version + 1}, baseVersion: version);
    expect(await onServer('live-15'), 'current write');
    await expectLater(a.remote.patchIfUnchanged(id: const Uuid().v4(), delta: {'title': 'nobody'}, baseVersion: 1), throwsA(isA<EntityNotFoundException>()));
    // A create never replaces a row that is already there.
    final current = (await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-15'));
    final taken = await a.remote.createAllIfAbsent([
      _task(userId, 'created once', id: _id('guard-new')),
      _task(userId, 'must not replace', id: _id('live-15')),
    ]);
    expect(taken, {_id('live-15')});
    expect(await onServer('guard-new'), 'created once');
    expect((await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-15')), current);
    await expectLater(a.remote.deleteIfUnchanged(_id('live-15'), baseVersion: version), throwsA(isA<ConflictException>()));
    expect(await onServer('live-15'), 'current write', reason: 'a refused delete deletes nothing');
    await a.manager.synchronize(userId, options: const DatumSyncOptions(forceFullSync: true));
    expect((await a.manager.read(_id('live-15'), userId: userId))?.title, 'current write');

    // 5. Overlapping uploads: A edits once, the deferring device twice, and
    //    each uploads without looking first. Whichever way the race with
    //    realtime goes, the second upload must not replace A's: the server
    //    refuses it, or the live change reaches the device first.
    await edit(a, 'live-16', 'A, one edit');
    await edit(remote.device, 'live-16', 'deferring device, first edit');
    await edit(remote.device, 'live-16', 'deferring device, second edit');
    const upload = DatumSyncOptions<Task>(direction: SyncDirection.pushOnly);
    expect((await a.manager.synchronize(userId, options: upload)).failedCount, 0);
    expect((await remote.device.manager.synchronize(userId, options: upload)).failedCount, 0, reason: 'a refused upload is not a failure');
    expect(await onServer('live-16'), 'A, one edit');
    await remote.device.manager.synchronize(userId);
    expect((await remote.device.manager.read(_id('live-16'), userId: userId))?.title, 'A, one edit');
    expect(await remote.device.manager.getPendingCount(userId), 0);
    expect(await remote.device.manager.getParkedOperations(userId), isEmpty);
    expect(remote.conflicts.where((id) => id == _id('live-16')), hasLength(1));
    expect(await onServer('live-16'), 'A, one edit');

    // 6. What the three phones did by hand: a device goes offline holding a
    //    queued edit; the same row changes twice elsewhere and arrives over
    //    realtime. The offline device takes the newer row, its own edit
    //    leaves the queue, and reconnecting uploads nothing over it.
    final offline = await join(LastWriteWinsResolver<Task>());
    final liveBatches = <LiveChangesAppliedEvent<Task>>[];
    final liveSub = offline.device.manager.onLiveChangesApplied.listen(liveBatches.add);
    addTearDown(liveSub.cancel);
    offline.device.net.setOnline(false);
    await edit(offline.device, 'live-17', 'edited while offline');
    expect(await offline.device.manager.getPendingCount(userId), 1);
    await edit(a, 'live-17', 'A, first');
    await a.manager.synchronize(userId);
    await edit(a, 'live-17', 'A, second');
    await a.manager.synchronize(userId);
    await _until(() async => (await offline.device.manager.read(_id('live-17'), userId: userId))?.title == 'A, second');
    expect(await offline.device.manager.getPendingCount(userId), 0, reason: 'the edit that lost is not uploaded later');
    expect(offline.conflicts, contains(_id('live-17')));
    await _until(() async => liveBatches.isNotEmpty); // the app is told a live change arrived
    final before = (await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-17'));
    offline.device.net.setOnline(true);
    await offline.device.manager.synchronize(userId);
    final after = (await _serverRows(a.client)).firstWhere((r) => r['id'] == _id('live-17'));
    expect((after['title'], after['version']), (before['title'], before['version']));
    expect(after['title'], 'A, second');

    // 7. Scopes: a fresh device syncs the completed tasks, then the open
    //    ones. The second scope must not start from the first one's position.
    await a.manager.push(item: (await a.manager.read(_id('live-14'), userId: userId))!.copyWith(isCompleted: true, modifiedAt: DateTime.now()));
    await a.manager.synchronize(userId);
    DatumSyncScope completed(bool value) => DatumSyncScope(query: DatumQuery(filters: [Filter('is_completed', FilterOperator.equals, value)]));
    final scoped = (await _device(email, password));
    addTearDown(() async {
      await scoped.manager.dispose();
      await scoped.client.dispose();
    });
    await scoped.manager.synchronize(userId, scope: completed(true));
    expect((await scoped.manager.readAll(userId: userId)).map((t) => t.id), [_id('live-14')]);
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // past the overlap window
    await scoped.manager.synchronize(userId, scope: completed(false));
    final open = (await _serverRows(a.client)).where((r) => r['is_completed'] == false && r['is_deleted'] != true).length;
    expect(await scoped.manager.readAll(userId: userId), hasLength(open + 1), reason: 'every open task, plus the completed one');
    // A change inside the first scope still arrives through it.
    await edit(a, 'live-14', 'completed and renamed');
    await a.manager.synchronize(userId);
    await scoped.manager.synchronize(userId, scope: completed(true));
    expect((await scoped.manager.read(_id('live-14'), userId: userId))?.title, 'completed and renamed');
  }, skip: _live ? null : 'pass --dart-define=SUPABASE_URL=… (see header)', timeout: const Timeout(Duration(minutes: 3)));
}
