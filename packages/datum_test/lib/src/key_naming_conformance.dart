import 'package:datum/datum.dart';
import 'package:test/test.dart';

/// An entity whose map spells its keys in snake_case (`user_id`,
/// `is_deleted`), as `datum_generator` output does. Adapters must take the
/// owner and id from the entity, never from a hard-coded map key.
class SnakeKeyedEntity extends DatumEntity {
  const SnakeKeyedEntity(this.id, this.userId, this.name, {this.version = 1});

  factory SnakeKeyedEntity.fromMap(Map<String, dynamic> map) =>
      SnakeKeyedEntity(
        map['id'] as String,
        map['user_id'] as String,
        map['name'] as String,
        version: map['version'] as int? ?? 1,
      );

  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final int version;
  @override
  DateTime get createdAt => DateTime.utc(2026);
  @override
  DateTime get modifiedAt => DateTime.utc(2026);
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'user_id': userId,
    'name': name,
    'version': version,
    'is_deleted': false,
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
      await adapter.create(const SnakeKeyedEntity('a', 'u1', 'alpha'));
      await adapter.create(const SnakeKeyedEntity('b', 'u1', 'beta'));
      await adapter.create(const SnakeKeyedEntity('c', 'u2', 'gamma'));

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
  });
}
