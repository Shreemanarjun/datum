// Pure-Dart sync engine benchmarks. Run JIT and AOT via tool/bench.sh, or:
//   dart run benchmark/sync_benchmark.dart --runs 3,10
// The src import keeps these runnable against older checkouts whose
// datum_test barrel predates bench.dart (see tool/bench.sh).
// ignore_for_file: implementation_imports, avoid_print, unnecessary_import, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_test/src/bench.dart';

import '../test/mocks/mock_adapters.dart';

class Item extends DatumEntity {
  const Item(this.id, this.name, {this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  DateTime get modifiedAt => DateTime.utc(2026);
  @override
  DateTime get createdAt => DateTime.utc(2026);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static Item fromMap(Map<String, dynamic> m) => Item(m['id'] as String, m['name'] as String, userId: m['userId'] as String);

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => old is Item && old.name == name ? null : {'name': name};
}

class ItemB extends Item {
  const ItemB(super.id, super.name, {super.userId});
  static ItemB fromMap(Map<String, dynamic> m) => ItemB(m['id'] as String, m['name'] as String, userId: m['userId'] as String);
}

class ItemC extends Item {
  const ItemC(super.id, super.name, {super.userId});
  static ItemC fromMap(Map<String, dynamic> m) => ItemC(m['id'] as String, m['name'] as String, userId: m['userId'] as String);
}

/// A remote with a fixed per-call round-trip, so fewer calls show up as time.
class SlowRemote<T extends DatumEntityInterface> extends MockRemoteAdapter<T> {
  SlowRemote({super.fromJson});
  static const rtt = Duration(milliseconds: 2);

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    await Future<void>.delayed(rtt);
    return super.getSyncMetadata(userId);
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    await Future<void>.delayed(rtt);
    return super.updateSyncMetadata(metadata, userId);
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    await Future<void>.delayed(rtt);
    return super.readAll(userId: userId, scope: scope);
  }

  @override
  Future<void> create(T entity) async {
    await Future<void>.delayed(rtt);
    return super.create(entity);
  }
}

class Online implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

Future<DatumManager<Item>> newManager({RemoteAdapter<Item>? remote}) async {
  final m = DatumManager<Item>(
    localAdapter: InMemoryLocalAdapter<Item>(fromMap: Item.fromMap),
    remoteAdapter: remote ?? MockRemoteAdapter<Item>(fromJson: Item.fromMap),
    connectivity: Online(),
    datumConfig: const DatumConfig(enableLogging: false),
  );
  await m.initialize();
  return m;
}

Future<Duration> timed(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  return sw.elapsed;
}

/// Longest gap between 1ms ticks on this isolate while [body] runs: how long
/// the UI isolate would be frozen.
Future<Duration> maxStall(Future<void> Function() body) async {
  var worst = Duration.zero;
  final sw = Stopwatch()..start();
  var last = sw.elapsed;
  final t = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = sw.elapsed;
    if (now - last > worst) worst = now - last;
    last = now;
  });
  await body();
  t.cancel();
  // The run may end inside a stall, before the next tick could observe it.
  final tail = sw.elapsed - last;
  return tail > worst ? tail : worst;
}

Future<DatumManager<Item>> store5000PlusOne() async {
  final m = await newManager();
  await m.localAdapter.createAll([for (var i = 0; i < 5000; i++) Item('s$i', 'n$i')]);
  await m.synchronize('u1');
  await m.push(item: const Item('new', 'x'), userId: 'u1');
  return m;
}

Future<void> main(List<String> args) async {
  await runBenchSuite('datum sync engine', args, {
      'push x500': () async {
        final m = await newManager();
        final d = await timed(() async {
          for (var i = 0; i < 500; i++) {
            await m.push(item: Item('id$i', 'n$i'), userId: 'u1');
          }
        });
        await m.dispose();
        return d;
      },
      // The two cases below load the engine's state holders (sync status,
      // health, progress) the way a screen that shows them would.
      'sync 500 queued creates, state watched': () async {
        final m = await newManager();
        for (var i = 0; i < 500; i++) {
          await m.push(item: Item('id$i', 'n$i'), userId: 'u1');
        }
        var seen = 0;
        final subs = [
          m.statusStream.listen((_) => seen++),
          m.health.listen((_) => seen++),
          m.onSyncProgress.listen((_) => seen++),
        ];
        final d = await timed(() => m.synchronize('u1'));
        for (final sub in subs) {
          await sub.cancel();
        }
        await m.dispose();
        if (seen == 0) throw StateError('nothing observed the sync');
        return d;
      },
      'status written 10000 times, watched': () async {
        final m = await newManager();
        var seen = 0;
        final sub = m.statusStream.listen((_) => seen++);
        final d = await timed(() async {
          for (var i = 0; i < 5000; i++) {
            m.pauseSync();
            m.resumeSync();
          }
          // Let the watcher drain what it was sent.
          await Future<void>.delayed(Duration.zero);
        });
        await sub.cancel();
        await m.dispose();
        if (seen == 0) throw StateError('nothing observed the status');
        return d;
      },
      'watchAll, 500-write burst': () async {
        final a = InMemoryLocalAdapter<Item>(fromMap: Item.fromMap);
        final sub = a.watchAll(userId: 'u1')!.listen((_) {});
        await Future<void>.delayed(Duration.zero);
        final d = await timed(() async {
          await Future.wait([for (var i = 0; i < 500; i++) a.create(Item('id$i', 'n$i'))]);
          // Drain queued re-reads: wait until the event loop goes idle.
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        await sub.cancel();
        return d;
      },
      'sync after 1 write, 5000-item store': () async {
        final m = await store5000PlusOne();
        final d = await timed(() => m.synchronize('u1'));
        await m.dispose();
        return d;
      },
      'max isolate stall, same sync': () async {
        final m = await store5000PlusOne();
        final d = await maxStall(() => m.synchronize('u1'));
        await m.dispose();
        return d;
      },
      'pull 2000 remote items': () async {
        final remote = MockRemoteAdapter<Item>(fromJson: Item.fromMap)..silent = true;
        for (var i = 0; i < 2000; i++) {
          await remote.create(Item('r$i', 'n$i'));
        }
        final m = await newManager(remote: remote);
        final d = await timed(() => m.synchronize('u1', options: const DatumSyncOptions(direction: SyncDirection.pullOnly)));
        await m.dispose();
        return d;
      },
      'Datum.synchronize, 3 types x 1000, 20 pending, 2ms RTT': () async {
        Datum.resetForTesting();
        final datum = (await Datum.initialize(
          config: const DatumConfig(autoStartSync: false, enableLogging: false),
          connectivityChecker: Online(),
          registrations: [
            DatumRegistration<Item>(localAdapter: InMemoryLocalAdapter<Item>(fromMap: Item.fromMap), remoteAdapter: SlowRemote<Item>(fromJson: Item.fromMap)),
            DatumRegistration<ItemB>(localAdapter: InMemoryLocalAdapter<ItemB>(fromMap: ItemB.fromMap), remoteAdapter: SlowRemote<ItemB>(fromJson: ItemB.fromMap)),
            DatumRegistration<ItemC>(localAdapter: InMemoryLocalAdapter<ItemC>(fromMap: ItemC.fromMap), remoteAdapter: SlowRemote<ItemC>(fromJson: ItemC.fromMap)),
          ],
        ))
            .fold((l, s) => throw l, (r) => r);
        await Datum.manager<Item>().localAdapter.createAll([for (var i = 0; i < 1000; i++) Item('a$i', 'n')]);
        await Datum.manager<ItemB>().localAdapter.createAll([for (var i = 0; i < 1000; i++) ItemB('b$i', 'n')]);
        await Datum.manager<ItemC>().localAdapter.createAll([for (var i = 0; i < 1000; i++) ItemC('c$i', 'n')]);
        await datum.synchronize('u1');
        for (var i = 0; i < 20; i++) {
          await Datum.manager<Item>().push(item: Item('p$i', 'n'), userId: 'u1');
        }
        final d = await timed(() => datum.synchronize('u1'));
        Datum.resetForTesting();
        return d;
      },
    });
  // Datum keeps background timers/streams alive; benchmarks just exit.
  exit(0);
}
