import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

TestEntity _entity(String id, String userId, {String name = 'name'}) => TestEntity(
      id: id,
      userId: userId,
      name: name,
      value: 0,
      modifiedAt: DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      version: 1,
    );

/// A minimal concrete [RemoteAdapter] that only implements the abstract
/// members, so the base-class batch defaults ([RemoteAdapter.updateAll] and
/// [RemoteAdapter.deleteAll]) are exercised.
class _RecordingRemoteAdapter extends RemoteAdapter<TestEntity> {
  final Map<String, TestEntity> store = {};
  final List<String> updatedIds = [];
  final List<String> deletedIds = [];

  @override
  Future<void> initialize() async {}

  @override
  Stream<DatumChangeDetail<TestEntity>>? get changeStream => null;

  @override
  Future<List<TestEntity>> readAll({String? userId, DatumSyncScope? scope}) async => store.values.toList();

  @override
  Future<TestEntity?> read(String id, {String? userId}) async => store[id];

  @override
  Future<List<TestEntity>> query(DatumQuery query, {String? userId}) async => store.values.toList();

  @override
  Future<void> create(TestEntity entity) async => store[entity.id] = entity;

  @override
  Future<void> update(TestEntity entity) async {
    updatedIds.add(entity.id);
    store[entity.id] = entity;
  }

  @override
  Future<TestEntity> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async =>
      store[id]!;

  @override
  Future<bool> delete(String id, {String? userId}) async {
    deletedIds.add(id);
    return store.remove(id) != null;
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => null;

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {}

  @override
  Future<bool> isConnected() async => true;
}

void main() {
  group('LocalAdapter batch defaults (via InMemoryLocalAdapter)', () {
    late InMemoryLocalAdapter<TestEntity> adapter;

    setUp(() async {
      adapter = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
      await adapter.initialize();
    });

    tearDown(() async {
      await adapter.dispose();
    });

    test('createAll creates every entity in order', () async {
      await adapter.createAll([
        _entity('1', 'user-1', name: 'one'),
        _entity('2', 'user-1', name: 'two'),
      ]);

      final all = await adapter.readAll(userId: 'user-1');
      expect(all, hasLength(2));
      expect(all.map((e) => e.name), containsAll(['one', 'two']));
    });

    test('deleteAll removes every listed id', () async {
      await adapter.createAll([
        _entity('1', 'user-1'),
        _entity('2', 'user-1'),
        _entity('3', 'user-1'),
      ]);

      await adapter.deleteAll(['1', '3'], userId: 'user-1');

      final remaining = await adapter.readAll(userId: 'user-1');
      expect(remaining, hasLength(1));
      expect(remaining.single.id, '2');
    });
  });

  group('RemoteAdapter batch defaults', () {
    late _RecordingRemoteAdapter remote;

    setUp(() {
      remote = _RecordingRemoteAdapter();
    });

    test('updateAll delegates to update for each entity', () async {
      await remote.createAll([
        _entity('1', 'user-1', name: 'one'),
        _entity('2', 'user-1', name: 'two'),
      ]);

      await remote.updateAll([
        _entity('1', 'user-1', name: 'one-updated'),
        _entity('2', 'user-1', name: 'two-updated'),
      ]);

      expect(remote.updatedIds, ['1', '2']);
      expect(remote.store['1']!.name, 'one-updated');
      expect(remote.store['2']!.name, 'two-updated');
    });

    test('deleteAll delegates to delete for each id', () async {
      await remote.createAll([
        _entity('1', 'user-1'),
        _entity('2', 'user-1'),
      ]);

      await remote.deleteAll(['1', '2'], userId: 'user-1');

      expect(remote.deletedIds, ['1', '2']);
      expect(remote.store, isEmpty);
    });
  });
}
