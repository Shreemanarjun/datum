import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// Runs the Datum **remote adapter conformance suite** against an adapter.
///
/// Same shape as `runLocalAdapterConformanceTests`: every test gets a freshly
/// created, initialized adapter for [ConformanceEntity] and disposes it
/// afterwards. When the adapter mixes in [DeltaSyncCapable], its `readSince`
/// contract (inclusive watermark, only-changed rows) is verified too.
void runRemoteAdapterConformanceTests({
  required String name,
  required Future<RemoteAdapter<ConformanceEntity>> Function() create,
  Future<void> Function(RemoteAdapter<ConformanceEntity> adapter)? destroy,
}) {
  group('$name remote adapter conformance', () {
    late RemoteAdapter<ConformanceEntity> adapter;

    ConformanceEntity make(
      String id, {
      String userId = 'u1',
      String name = 'entity',
      int value = 0,
      DateTime? modifiedAt,
    }) => ConformanceEntity.make(
      id,
      userId: userId,
      name: name,
      value: value,
      modifiedAt: modifiedAt,
    );

    setUp(() async {
      adapter = await create();
    });

    tearDown(() async {
      await adapter.dispose();
      await destroy?.call(adapter);
    });

    test('create then read round-trips the entity', () async {
      await adapter.create(make('a', name: 'created'));

      final read = await adapter.read('a', userId: 'u1');
      expect(read?.name, 'created');
    });

    test('read of an absent id returns null', () async {
      expect(await adapter.read('ghost', userId: 'u1'), isNull);
    });

    test('update replaces the stored entity', () async {
      await adapter.create(make('a', name: 'v1'));
      await adapter.update(make('a', name: 'v2').copyWith());

      expect((await adapter.read('a', userId: 'u1'))?.name, 'v2');
    });

    test(
      'patch applies a partial delta and returns the patched entity',
      () async {
        await adapter.create(make('a', name: 'before', value: 4));

        final patched = await adapter.patch(
          id: 'a',
          delta: {'name': 'after'},
          userId: 'u1',
        );

        expect(patched.name, 'after');
        expect(patched.value, 4);
      },
    );

    test('delete removes the entity', () async {
      await adapter.create(make('a'));

      expect(await adapter.delete('a', userId: 'u1'), isTrue);
      expect(await adapter.read('a', userId: 'u1'), isNull);
    });

    test('readAll scopes to the requested user', () async {
      await adapter.create(make('a', userId: 'u1'));
      await adapter.create(make('b', userId: 'u2'));

      expect((await adapter.readAll(userId: 'u1')).map((e) => e.id), ['a']);
    });

    test('readAll honors a DatumSyncScope query', () async {
      await adapter.create(make('a', value: 1));
      await adapter.create(make('b', value: 9));

      final scoped = await adapter.readAll(
        userId: 'u1',
        scope: DatumSyncScope(
          query:
              (DatumQueryBuilder<ConformanceEntity>()
                    ..where('value', isGreaterThan: 5))
                  .build(),
        ),
      );

      expect(scoped.map((e) => e.id), ['b']);
    });

    test('sync metadata round-trips', () async {
      const metadata = DatumSyncMetadata(userId: 'u1', dataHash: 'remote-hash');
      await adapter.updateSyncMetadata(metadata, 'u1');

      expect((await adapter.getSyncMetadata('u1'))?.dataHash, 'remote-hash');
      expect(await adapter.getSyncMetadata('u2'), isNull);
    });

    test('isConnected reports true for a reachable backend', () async {
      expect(await adapter.isConnected(), isTrue);
    });

    test(
      'DeltaSyncCapable.readSince returns only rows at or after the watermark',
      () async {
        if (adapter is! DeltaSyncCapable<ConformanceEntity>) {
          markTestSkipped('$name does not mix in DeltaSyncCapable');
          return;
        }
        final delta = adapter as DeltaSyncCapable<ConformanceEntity>;
        final watermark = DateTime.now();
        await adapter.create(
          make('old', modifiedAt: watermark.subtract(const Duration(days: 1))),
        );
        await adapter.create(make('boundary', modifiedAt: watermark));
        await adapter.create(
          make('fresh', modifiedAt: watermark.add(const Duration(minutes: 1))),
        );

        final since = await delta.readSince(watermark, userId: 'u1');

        expect(
          since.map((e) => e.id).toSet(),
          {'boundary', 'fresh'},
          reason: 'watermark is inclusive; older rows excluded',
        );
      },
    );
  });
}
