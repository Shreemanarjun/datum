import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'in_memory_remote_adapter.dart';
import 'sync_stack_conformance.dart' show TestConnectivityChecker;

/// An entity whose map spells its keys in snake_case (`user_id`,
/// `is_deleted`), as `datum_generator` output does. Adapters must take the
/// owner and id from the entity, never from a hard-coded map key.
///
/// [note] is a device-only field: it is in the local map only. A local
/// adapter with a fixed schema needs a nullable text column `note` for it.
class SnakeKeyedEntity extends DatumEntity {
  SnakeKeyedEntity(this.id, this.userId, this.name, {this.version = 1, this.isDeleted = false, DateTime? modifiedAt, this.note})
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
    note: map['note'] as String?,
  );

  @override
  final String id;
  @override
  final String userId;
  final String name;

  /// Kept on this device, never uploaded.
  final String? note;

  @override
  Set<String> get deviceOnlyFields => const {'note'};

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
    if (target == MapTarget.local) 'note': note,
  };
}

/// Runs the key-naming conformance checks against a fresh adapter from
/// [create]: reads, user scoping, user listing and clearing all work for an
/// entity whose map keys are not `userId`/`isDeleted`.
// Scenarios: store.keys (packages/datum/doc/SYNC_SCENARIOS.md)
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

    test('a timestamp finer than the local store keeps is not a conflict on every pull', () async {
      final remote = InMemoryRemoteAdapter<SnakeKeyedEntity>(backend: InMemoryRemoteBackend(), fromMap: SnakeKeyedEntity.fromMap);
      final manager = DatumManager<SnakeKeyedEntity>(
        localAdapter: await create(),
        remoteAdapter: remote,
        connectivity: TestConnectivityChecker(),
        datumConfig: const DatumConfig<SnakeKeyedEntity>(enableLogging: false),
      );
      await manager.initialize();
      addTearDown(manager.dispose);
      // The remote (ISO-8601) keeps microseconds, the local map (epoch
      // milliseconds) does not: the same row reads back differently.
      final fine = DateTime.utc(2026, 5, 1, 12, 0, 0, 250, 750);
      await manager.push(item: SnakeKeyedEntity('a', 'u1', 'alpha', modifiedAt: fine), userId: 'u1');
      await manager.synchronize('u1');
      await remote.update(SnakeKeyedEntity('a', 'u1', 'alpha', modifiedAt: fine));
      expect((await remote.read('a', userId: 'u1'))?.modifiedAt, fine);

      final changes = <DataChangeEvent<SnakeKeyedEntity>>[];
      final subscription = manager.onDataChange.listen(changes.add);
      addTearDown(subscription.cancel);
      for (var pull = 0; pull < 2; pull++) {
        final result = await manager.synchronize('u1', options: const DatumSyncOptions(forceFullSync: true));
        expect(result.conflictsResolved, 0, reason: 'nobody edited the row');
      }
      expect(changes, isEmpty, reason: 'an unchanged row is not written again');

      // A real edit made elsewhere in the same millisecond still arrives.
      await remote.update(SnakeKeyedEntity('a', 'u1', 'renamed', modifiedAt: fine.add(const Duration(microseconds: 100))));
      await manager.synchronize('u1', options: const DatumSyncOptions(forceFullSync: true));
      expect((await manager.read('a', userId: 'u1'))?.name, 'renamed');
    });

    test('a device-only field stays on the device and survives whatever the remote sends', () async {
      final backend = InMemoryRemoteBackend();
      InMemoryRemoteAdapter<SnakeKeyedEntity> server() => InMemoryRemoteAdapter<SnakeKeyedEntity>(backend: backend, fromMap: SnakeKeyedEntity.fromMap);
      Future<DatumManager<SnakeKeyedEntity>> device(DatumConflictResolver<SnakeKeyedEntity> resolver) async {
        final manager = DatumManager<SnakeKeyedEntity>(
          localAdapter: await create(),
          remoteAdapter: server(),
          connectivity: TestConnectivityChecker(),
          datumConfig: DatumConfig<SnakeKeyedEntity>(enableLogging: false, defaultConflictResolver: resolver),
        );
        await manager.initialize();
        addTearDown(manager.dispose);
        return manager;
      }

      // The device defers to the server in a conflict: the hardest case for
      // a field the server knows nothing about.
      final manager = await device(RemotePriorityResolver<SnakeKeyedEntity>());
      const everything = DatumSyncOptions<SnakeKeyedEntity>(forceFullSync: true);
      final t = DateTime.utc(2026, 5, 1);
      SnakeKeyedEntity row(String name, int version, int minute, {String? note}) => SnakeKeyedEntity('a', 'u1', name, version: version, modifiedAt: t.add(Duration(minutes: minute)), note: note);
      Future<(String?, String?, int?)> local() async {
        final e = await manager.read('a', userId: 'u1', includeDeleted: true);
        return (e?.name, e?.note, e?.version);
      }

      Map<String, dynamic> uploaded() => backend.rows['u1']!['a']!;

      await manager.push(item: row('alpha', 1, 0, note: 'draft'), userId: 'u1');
      await manager.synchronize('u1');
      expect(uploaded().containsKey('note'), isFalse, reason: 'it is never uploaded');
      expect(await local(), ('alpha', 'draft', 1));

      // Editing only the note: saved and announced, nothing queued, the
      // version untouched.
      final announced = <String?>[];
      final sub = manager.onDataChange.listen((e) => announced.add(e.data?.note));
      addTearDown(sub.cancel);
      await manager.push(item: row('alpha', 1, 0, note: 'second draft'), userId: 'u1');
      await Future<void>.delayed(Duration.zero);
      expect(await local(), ('alpha', 'second draft', 1));
      expect(announced, ['second draft']);
      expect(await manager.getPendingCount('u1'), 0);

      // A full re-read finds the two sides equal (the note is not compared).
      final idle = await manager.synchronize('u1', options: everything);
      expect(idle.conflictsResolved, 0);
      expect(await manager.getPendingCount('u1'), 0);
      expect(await local(), ('alpha', 'second draft', 1));

      // Another device edits the row: its change arrives, the note stays.
      await server().update(row('renamed', 2, 1));
      await manager.synchronize('u1', options: everything);
      expect(await local(), ('renamed', 'second draft', 2));

      // Both edit and the server's version wins the conflict: still there.
      await manager.push(item: row('mine', 3, 2, note: 'second draft'), userId: 'u1');
      await server().update(row('theirs', 3, 3));
      final resolved = await manager.synchronize('u1', options: everything);
      expect(resolved.conflictsResolved, 1);
      expect(await local(), ('theirs', 'second draft', 3));
      expect(await manager.getPendingCount('u1'), 0);

      // Changed together with a shared field: one upload, without the note.
      await manager.push(item: row('both', 4, 4, note: 'third draft'), userId: 'u1');
      await manager.synchronize('u1');
      expect(uploaded()['name'], 'both');
      expect(uploaded().containsKey('note'), isFalse);
      expect(await local(), ('both', 'third draft', 4));

      // Deleting and restoring the row keeps it too.
      await manager.delete(id: 'a', userId: 'u1', behavior: DeleteBehavior.softDelete);
      await manager.restore(id: 'a', userId: 'u1');
      await manager.synchronize('u1');
      expect((await local()).$2, 'third draft');

      // A second device gets the row, and no note.
      final other = await device(LastWriteWinsResolver<SnakeKeyedEntity>());
      await other.synchronize('u1');
      final theirs = await other.read('a', userId: 'u1');
      expect((theirs?.name, theirs?.note), ('both', null));
    });
  });
}
