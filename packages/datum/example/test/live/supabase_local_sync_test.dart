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

Future<_Device> _device(String email, String password) async {
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

    // 3. Realtime: A's edit reaches B's store with no sync call on B.
    final edited = (await a.manager.read(_id('live-0'), userId: userId))!.copyWith(title: 'edited on A', modifiedAt: DateTime.now());
    await a.manager.push(item: edited);
    await _timed('A: push 1 edit', () => a.manager.synchronize(userId));
    _timings['B: realtime arrival of A\'s edit'] = await _until(() async => (await b.manager.read(_id('live-0'), userId: userId))?.title == 'edited on A');

    // 4. Idle sync cost (nothing changed anywhere), and delta pulls: after
    //    the first full pull B only ever fetches rows the server changed.
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // past the overlap window
    await b.manager.synchronize(userId, options: const DatumSyncOptions(forceFullSync: true));
    final fullPullsBefore = b.remote.fullPulls;
    b.remote.deltaRows = 0;
    await _timed('B: idle delta sync', () => b.manager.synchronize(userId, options: const DatumSyncOptions(forceFullSync: true)));
    expect(b.remote.fullPulls, fullPullsBefore, reason: 'no full-table pull once synced');
    expect(b.remote.deltaRows, lessThan(5), reason: 'only the overlap window, not 50 rows');

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
}
