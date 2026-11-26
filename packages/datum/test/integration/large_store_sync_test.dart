import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

class Item extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;
  Item(this.id, this.name, {this.userId = 'u1', DateTime? at, this.version = 1, this.isDeleted = false})
      : modifiedAt = at ?? DateTime.utc(2026),
        createdAt = at ?? DateTime.utc(2026);
  static Item fromMap(Map<String, dynamic> m) => Item(m['id'] as String, m['name'] as String,
      userId: m['userId'] as String,
      at: DateTime.parse(m['modifiedAt'] as String),
      version: m['version'] as int? ?? 1,
      isDeleted: m['isDeleted'] as bool? ?? false);
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
  Item copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Item(id, name, userId: userId, at: modifiedAt ?? this.modifiedAt, version: version ?? this.version, isDeleted: isDeleted ?? this.isDeleted);
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => old is Item && old.name == name ? null : {'name': name};
}

/// A store above the isolate-rehash threshold syncs end to end: every op is
/// pushed, metadata carries the exact content hash, a second sync skips, and
/// a 500-write burst re-reads a watched list only a couple of times.
void main() {
  const n = 500;

  test('600-item store syncs, stamps the exact hash, then skips', () async {
    final conn = MockConnectivityChecker();
    when(() => conn.isConnected).thenAnswer((_) async => true);
    when(() => conn.onStatusChange).thenAnswer((_) => const Stream.empty());
    final m = DatumManager<Item>(
      localAdapter: InMemoryLocalAdapter<Item>(fromMap: Item.fromMap),
      remoteAdapter: MockRemoteAdapter<Item>(fromJson: Item.fromMap),
      connectivity: conn,
    );
    await m.initialize();
    for (var i = 0; i < 600; i++) {
      await m.push(item: Item('s$i', 'n$i'), userId: 'u1');
    }
    final r = await m.synchronize('u1');
    expect(r.failedCount, 0);
    expect(r.syncedCount, 600);
    final meta = await m.localAdapter.getSyncMetadata('u1');
    expect(meta!.dataHash, const DatumHashGenerator().hashEntitiesUnordered(await m.localAdapter.readAll(userId: 'u1')));
    final again = await m.synchronize('u1');
    expect(again.wasSkipped, isTrue, reason: 'metadata now matches and the queue is empty');
    await m.dispose();
  });

  test('content hash tracks local writes between syncs (create, update, delete)', () async {
    final conn = MockConnectivityChecker();
    when(() => conn.isConnected).thenAnswer((_) async => true);
    when(() => conn.onStatusChange).thenAnswer((_) => const Stream.empty());
    final m = DatumManager<Item>(
      localAdapter: InMemoryLocalAdapter<Item>(fromMap: Item.fromMap),
      remoteAdapter: MockRemoteAdapter<Item>(fromJson: Item.fromMap),
      connectivity: conn,
    );
    await m.initialize();
    addTearDown(m.dispose);

    Future<void> expectExactHash(String step) async {
      await m.synchronize('u1');
      final meta = await m.localAdapter.getSyncMetadata('u1');
      final expected = const DatumHashGenerator().hashEntitiesUnordered(await m.localAdapter.readAll(userId: 'u1'));
      expect(meta!.dataHash, expected, reason: 'stale hash after $step');
    }

    await m.push(item: Item('a', 'A'));
    await m.push(item: Item('b', 'B'));
    await expectExactHash('initial creates');
    await m.push(item: Item('c', 'C'));
    await expectExactHash('create');
    await m.push(item: Item('a', 'A2', version: 2));
    await expectExactHash('update');
    await m.delete(id: 'b', userId: 'u1');
    await expectExactHash('delete');
  });

  test('watchAll coalesces a $n-write burst', () async {
    final a = InMemoryLocalAdapter<Item>(fromMap: Item.fromMap);
    var emissions = 0;
    final sub = a.watchAll(userId: 'u1')!.listen((_) => emissions++);
    await Future<void>.delayed(Duration.zero);
    await Future.wait([for (var i = 0; i < n; i++) a.create(Item('id$i', 'n$i'))]);
    // Let queued re-reads drain.
    var last = -1;
    while (last != emissions) {
      last = emissions;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(emissions, lessThan(10));
    expect((await a.readAll(userId: 'u1')).length, n);
    await sub.cancel();
  });
}
