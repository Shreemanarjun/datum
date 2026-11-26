import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'in_memory_remote_adapter.dart';
import 'sync_stack_conformance.dart' show TestConnectivityChecker;

/// An entity whose map spells its keys in snake_case (`user_id`,
/// `is_deleted`), as `datum_generator` output does. Adapters must take the
/// owner and id from the entity, never from a hard-coded map key.
class SnakeKeyedEntity extends DatumEntity {
  SnakeKeyedEntity(this.id, this.userId, this.name, {this.version = 1, this.isDeleted = false, DateTime? modifiedAt})
      : modifiedAt = modifiedAt ?? DateTime.utc(2026);

  factory SnakeKeyedEntity.fromMap(Map<String, dynamic> map) => SnakeKeyedEntity(
    map['id'] as String,
    map['user_id'] as String,
    map['name'] as String,
    version: map['version'] as int? ?? 1,
    isDeleted: map['is_deleted'] as bool? ?? false,
    modifiedAt: switch (map['modified_at']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      final String iso => DateTime.parse(iso),
      _ => null,
    },
  );

  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final int version;
  @override
  final bool isDeleted;
  @override
  final DateTime modifiedAt;
  @override
  DateTime get createdAt => DateTime.utc(2026);

  /// Epoch-ms timestamps locally, ISO-8601 remotely, snake_case keys in both.
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'user_id': userId,
    'name': name,
    'version': version,
    'is_deleted': isDeleted,
    'modified_at': target == MapTarget.remote ? modifiedAt.toIso8601String() : modifiedAt.millisecondsSinceEpoch,
  };
}

/// Runs the key-naming conformance checks against a fresh adapter from
/// [create]: reads, user scoping, user listing and clearing all work for an
/// entity whose map keys are not `userId`/`isDeleted`.
void runKeyNamingConformanceTests({
  required String name,
  required Future<LocalAdapter<SnakeKeyedEntity>> Function() create,
}) {
  group('$name key naming conformance', () {
    test('snake_case maps are read, scoped, listed and cleared per user',
        () async {
      final adapter = await create();
      await adapter.create(SnakeKeyedEntity('a', 'u1', 'alpha'));
      await adapter.create(SnakeKeyedEntity('b', 'u1', 'beta'));
      await adapter.create(SnakeKeyedEntity('c', 'u2', 'gamma'));

      expect((await adapter.readAll(userId: 'u1')).map((e) => e.name),
          unorderedEquals(['alpha', 'beta']));
      expect((await adapter.readAll(userId: 'u2')).single.name, 'gamma');
      expect((await adapter.readAll()).length, 3);
      expect((await adapter.read('a', userId: 'u1'))?.name, 'alpha');
      expect(await adapter.read('a', userId: 'u2'), isNull);
      expect(await adapter.getAllUserIds(), unorderedEquals(['u1', 'u2']));
      expect(await adapter.getAllRawData(userId: 'u1'), hasLength(2));

      final watched = await adapter
          .watchAll(userId: 'u1', includeInitialData: true)!
          .first;
      expect(watched, hasLength(2));

      await adapter.clearUserData('u1');
      expect(await adapter.readAll(userId: 'u1'), isEmpty);
      expect((await adapter.readAll(userId: 'u2')).single.name, 'gamma');
      await adapter.dispose();
    });

    test('soft delete, tombstone filtering and restore work through a manager', () async {
      final remote = InMemoryRemoteAdapter<SnakeKeyedEntity>(backend: InMemoryRemoteBackend(), fromMap: SnakeKeyedEntity.fromMap);
      final manager = DatumManager<SnakeKeyedEntity>(
        localAdapter: await create(),
        remoteAdapter: remote,
        connectivity: TestConnectivityChecker(),
        datumConfig: const DatumConfig<SnakeKeyedEntity>(enableLogging: false, deleteBehavior: DeleteBehavior.softDelete),
      );
      await manager.initialize();
      addTearDown(manager.dispose);
      await manager.push(item: SnakeKeyedEntity('a', 'u1', 'alpha'), userId: 'u1');
      await manager.push(item: SnakeKeyedEntity('b', 'u1', 'beta'), userId: 'u1');
      await manager.synchronize('u1');

      expect(await manager.delete(id: 'a', userId: 'u1'), isTrue);
      final tombstone = (await manager.read('a', userId: 'u1', includeDeleted: true))!;
      expect(tombstone.isDeleted, isTrue, reason: 'the flag must land under the entity\'s own key');
      expect(tombstone.version, 2);
      expect(tombstone.modifiedAt.isAfter(DateTime.utc(2026)), isTrue);
      expect(await manager.read('a', userId: 'u1'), isNull);
      expect((await manager.readAll(userId: 'u1')).map((e) => e.id), ['b']);
      expect((await manager.query(const DatumQuery(), userId: 'u1')).map((e) => e.id), ['b']);
      await manager.synchronize('u1');
      expect((await remote.read('a', userId: 'u1'))?.isDeleted, isTrue);

      final restored = await manager.restore(id: 'a', userId: 'u1');
      expect(restored?.isDeleted, isFalse);
      expect(restored?.version, 3);
      expect(await manager.isPending('a', userId: 'u1'), isTrue);
      await manager.synchronize('u1');
      expect((await remote.read('a', userId: 'u1'))?.isDeleted, isFalse);
      expect(await manager.restore(id: 'a', userId: 'u1'), isNull, reason: 'not a tombstone');
    });
  });
}
