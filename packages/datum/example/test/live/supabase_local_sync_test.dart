// Live sync journeys against a LOCAL Supabase stack (no Docker needed):
//
//   cd packages/datum/example
//   supabase start --runtime native        # once; schema from supabase/migrations
//   flutter test test/live --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
//     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | jq -r .PUBLISHABLE_KEY)
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

const _live = bool.hasEnvironment('SUPABASE_URL');

typedef _Device = ({DatumManager<Task> manager, SupabaseClient client, TestConnectivityChecker net});

// Implicit flow: PKCE needs persistent storage these headless clients lack.
const _auth = AuthClientOptions(authFlowType: AuthFlowType.implicit, autoRefreshToken: false);

final _timings = <String, Duration>{};

/// Unique per run: ids are global primary keys, and another account's row
/// with the same id is (correctly) rejected by row-level security.
final _run = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
String _id(String name) => '$_run-$name';

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
  final manager = DatumManager<Task>(
    localAdapter: InMemoryLocalAdapter<Task>(fromMap: Task.fromMap),
    remoteAdapter: SupabaseRemoteAdapter<Task>(tableName: 'tasks', fromMap: Task.fromMap, clientOverride: client),
    connectivity: net,
    datumConfig: const DatumConfig<Task>(enableLogging: false),
  );
  await manager.initialize();
  return (manager: manager, client: client, net: net);
}

Task _task(String userId, String title, {String? id}) {
  final now = DateTime.now();
  return Task(id: id ?? 'task-${now.microsecondsSinceEpoch}', userId: userId, title: title, createdAt: now, modifiedAt: now);
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

void main() {
  late _Device a;
  late _Device b;
  late String userId;
  final email = 'datum-${DateTime.now().microsecondsSinceEpoch}@example.com';
  const password = 'datum-local-pass';

  setUpAll(() async {
    if (!_live) return;
    final signUp = SupabaseClient(Secrets.SUPABASE_URL, Secrets.SUPABASE_ANON_KEY, authOptions: _auth);
    userId = (await signUp.auth.signUp(email: email, password: password)).user!.id;
    await signUp.dispose();
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

    // 4. Idle sync cost (nothing changed anywhere).
    await b.manager.synchronize(userId);
    await _timed('B: idle sync', () => b.manager.synchronize(userId));

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
    expect((await _serverRows(a.client)).where((r) => (r['id'] as String).startsWith(_id('off-'))), hasLength(10));

    // 8. Expired session: the write is kept (parked), never lost, and goes
    //    out once the user signs in again.
    await a.client.auth.signOut(scope: SignOutScope.local);
    await a.manager.push(item: _task(userId, 'written while signed out', id: _id('auth-1')));
    await a.manager.synchronize(userId).then<void>((_) {}, onError: (_) {});
    final pending = await a.manager.getPendingOperations(userId);
    expect(pending.map((o) => o.entityId), contains(_id('auth-1')), reason: 'the edit must survive an expired session');
    await a.client.auth.signInWithPassword(email: email, password: password);
    await a.manager.retryParkedOperations(userId);
    await _timed('A: push after re-login', () => a.manager.synchronize(userId));
    expect(await a.manager.getPendingCount(userId), 0);
    expect((await _serverRows(a.client)).map((r) => r['id']), contains(_id('auth-1')));
  }, skip: _live ? null : 'pass --dart-define=SUPABASE_URL=… (see header)', timeout: const Timeout(Duration(minutes: 3)));
}
