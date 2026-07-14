import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

/// An in-memory local adapter that supports raw projection + count queries.
class RawCapableLocalAdapter extends InMemoryLocalAdapter<TestEntity> with RawQueryCapable {
  RawCapableLocalAdapter() : super(fromMap: TestEntity.fromJson);

  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId}) async {
    final all = await readAll(userId: userId);
    if (query.count) {
      return [
        {'total': all.length}
      ];
    }
    // Projection: return only the columns named in `select` (comma-separated).
    final cols = (query.select ?? '').split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    return all.map((e) {
      final map = e.toDatumMap();
      if (cols.isEmpty) return map;
      return {for (final c in cols) c: map[c]};
    }).toList();
  }
}

void main() {
  late RawCapableLocalAdapter local;
  late DatumManager<TestEntity> manager;

  setUp(() async {
    local = RawCapableLocalAdapter();
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

  test('#11 raw projection returns only requested columns', () async {
    await local.create(TestEntity.create('e1', 'u1', 'Alice'));
    await local.create(TestEntity.create('e2', 'u1', 'Bob'));

    final rows = await manager.rawQuery(
      const DatumRawQuery(select: 'id, name'),
      source: DataSource.local,
      userId: 'u1',
    );

    expect(rows, hasLength(2));
    expect(rows.first.keys.toSet(), {'id', 'name'});
    expect(rows.map((r) => r['name']).toSet(), {'Alice', 'Bob'});
  });

  test('#11 raw count aggregation', () async {
    await local.create(TestEntity.create('e1', 'u1', 'A'));
    await local.create(TestEntity.create('e2', 'u1', 'B'));
    await local.create(TestEntity.create('e3', 'u1', 'C'));

    final rows = await manager.rawQuery(
      const DatumRawQuery(count: true),
      source: DataSource.local,
      userId: 'u1',
    );
    expect(rows.single['total'], 3);
  });

  test('#11 adapter advertises RawQueryCapable', () {
    expect(local, isA<RawQueryCapable>());
  });

  test('#11 manager throws when the adapter is not RawQueryCapable', () async {
    final plain = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
    expect(plain, isNot(isA<RawQueryCapable>()));

    final connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
    final plainManager = DatumManager<TestEntity>(
      localAdapter: plain,
      remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
      connectivity: connectivity,
      datumConfig: const DatumConfig<TestEntity>(),
    );
    await plainManager.initialize();
    addTearDown(plainManager.dispose);

    expect(
      () => plainManager.rawQuery(const DatumRawQuery(sql: 'SELECT 1'), source: DataSource.local),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
