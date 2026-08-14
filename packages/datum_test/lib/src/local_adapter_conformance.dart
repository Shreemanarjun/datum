import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// Runs the Datum **local adapter conformance suite** against an adapter.
///
/// Wire the adapter under test for [ConformanceEntity] and hand a factory in;
/// every test receives a freshly created, initialized adapter and disposes it
/// afterwards:
///
/// ```dart
/// runLocalAdapterConformanceTests(
///   name: 'HiveLocalAdapter',
///   create: () async {
///     final adapter = HiveLocalAdapter<ConformanceEntity>(
///       entityBoxName: 'conformance_${i++}',
///       fromMap: ConformanceEntity.fromMap,
///     );
///     await adapter.initialize();
///     return adapter;
///   },
/// );
/// ```
///
/// Capability-gated groups (reactive watch streams, transaction rollback,
/// pagination) run automatically when the adapter mixes in the corresponding
/// marker ([WatchableAdapter], [TransactionalAdapter], [PaginatedAdapter]).
///
/// [preservesUnknownColumns] — schemaless stores must keep columns that the
/// entity does not know about through `overwriteAllRawData` (migrations add
/// columns before the model reads them). Fixed-schema (SQL) adapters cannot;
/// pass false to skip that assertion.
///
/// [destroy] — optional extra teardown after `dispose` (delete temp files,
/// drop tables).
void runLocalAdapterConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() create,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroy,
  bool preservesUnknownColumns = true,
}) {
  group('$name local adapter conformance', () {
    late LocalAdapter<ConformanceEntity> adapter;

    ConformanceEntity make(
      String id, {
      String userId = 'u1',
      String name = 'entity',
      int value = 0,
    }) => ConformanceEntity.make(id, userId: userId, name: name, value: value);

    setUp(() async {
      adapter = await create();
    });

    tearDown(() async {
      await adapter.dispose();
      await destroy?.call(adapter);
    });

    group('crud', () {
      test('create then read round-trips the entity', () async {
        final entity = make('a', name: 'created', value: 7);
        await adapter.create(entity);

        final read = await adapter.read('a', userId: 'u1');
        expect(read, isNotNull);
        expect(read!.id, 'a');
        expect(read.name, 'created');
        expect(read.value, 7);
      });

      test('read of an absent id returns null', () async {
        expect(await adapter.read('ghost', userId: 'u1'), isNull);
      });

      test('update replaces the stored entity', () async {
        await adapter.create(make('a', name: 'v1'));
        await adapter.update(make('a', name: 'v2', value: 2).copyWith());

        expect((await adapter.read('a', userId: 'u1'))!.name, 'v2');
      });

      test('patch applies a partial delta', () async {
        await adapter.create(make('a', name: 'before', value: 1));

        final patched = await adapter.patch(
          id: 'a',
          delta: {'name': 'after'},
          userId: 'u1',
        );

        expect(patched.name, 'after');
        expect(patched.value, 1, reason: 'unpatched fields survive');
        expect((await adapter.read('a', userId: 'u1'))!.name, 'after');
      });

      test(
        'delete removes the entity and reports whether it existed',
        () async {
          await adapter.create(make('a'));

          expect(await adapter.delete('a', userId: 'u1'), isTrue);
          expect(await adapter.read('a', userId: 'u1'), isNull);
          expect(
            await adapter.delete('a', userId: 'u1'),
            isFalse,
            reason: 'second delete finds nothing',
          );
        },
      );

      test('readAll returns every entity for the user', () async {
        await adapter.create(make('a'));
        await adapter.create(make('b'));

        expect((await adapter.readAll(userId: 'u1')).map((e) => e.id).toSet(), {
          'a',
          'b',
        });
      });

      test('readByIds returns only the requested existing ids', () async {
        await adapter.create(make('a'));
        await adapter.create(make('b'));

        final result = await adapter.readByIds(['a', 'ghost'], userId: 'u1');
        expect(result.keys.toSet(), {'a'});
      });
    });

    group('user scoping', () {
      test('readAll scopes to the requested user', () async {
        await adapter.create(make('a', userId: 'u1'));
        await adapter.create(make('b', userId: 'u2'));

        expect((await adapter.readAll(userId: 'u1')).map((e) => e.id), ['a']);
        expect((await adapter.readAll(userId: 'u2')).map((e) => e.id), ['b']);
      });

      test('getAllUserIds lists every user with data', () async {
        await adapter.create(make('a', userId: 'u1'));
        await adapter.create(make('b', userId: 'u2'));

        expect((await adapter.getAllUserIds()).toSet(), {'u1', 'u2'});
      });

      test('clearUserData removes exactly that user\'s entities', () async {
        await adapter.create(make('a', userId: 'u1'));
        await adapter.create(make('b', userId: 'u1'));
        await adapter.create(make('c', userId: 'u2'));

        await adapter.clearUserData('u1');

        expect(await adapter.readAll(userId: 'u1'), isEmpty);
        expect((await adapter.readAll(userId: 'u2')).map((e) => e.id), ['c']);
      });

      test('clear removes everything', () async {
        await adapter.create(make('a', userId: 'u1'));
        await adapter.create(make('b', userId: 'u2'));

        await adapter.clear();

        expect(await adapter.readAll(), isEmpty);
      });
    });

    group('query', () {
      test('filters, sorts and limits honor DatumQuery', () async {
        await adapter.create(make('a', value: 5));
        await adapter.create(make('b', value: 1));
        await adapter.create(make('c', value: 3));

        final result = await adapter.query(
          (DatumQueryBuilder<ConformanceEntity>()
                ..where('value', isGreaterThanOrEqualTo: 3)
                ..orderBy('value', descending: true))
              .build(),
          userId: 'u1',
        );

        expect(result.map((e) => e.id).toList(), ['a', 'c']);
      });

      test('limit and offset paginate query results', () async {
        for (var i = 0; i < 5; i++) {
          await adapter.create(make('e$i', value: i));
        }

        final result = await adapter.query(
          (DatumQueryBuilder<ConformanceEntity>()
                ..orderBy('value')
                ..limit(2)
                ..offset(1))
              .build(),
          userId: 'u1',
        );

        expect(result.map((e) => e.value).toList(), [1, 2]);
      });
    });

    group('pending operations', () {
      DatumSyncOperation<ConformanceEntity> op(
        String id, {
        String entityId = 'a',
      }) => DatumSyncOperation(
        id: id,
        userId: 'u1',
        entityId: entityId,
        type: DatumOperationType.update,
        timestamp: DateTime.now(),
        delta: const {'name': 'queued'},
      );

      test('add, list and remove round-trip', () async {
        await adapter.addPendingOperation('u1', op('op1'));
        await adapter.addPendingOperation('u1', op('op2', entityId: 'b'));

        expect(
          (await adapter.getPendingOperations('u1')).map((o) => o.id).toSet(),
          {'op1', 'op2'},
        );

        await adapter.removePendingOperation('op1');
        expect((await adapter.getPendingOperations('u1')).map((o) => o.id), [
          'op2',
        ]);
      });

      test(
        're-adding an operation id upserts instead of duplicating',
        () async {
          await adapter.addPendingOperation('u1', op('op1'));
          await adapter.addPendingOperation('u1', op('op1'));

          expect(await adapter.getPendingOperations('u1'), hasLength(1));
        },
      );

      test('operations are scoped per user', () async {
        await adapter.addPendingOperation('u1', op('op1'));

        expect(await adapter.getPendingOperations('u2'), isEmpty);
      });
    });

    group('sync state', () {
      test('sync metadata round-trips', () async {
        const metadata = DatumSyncMetadata(userId: 'u1', dataHash: 'hash-1');
        await adapter.updateSyncMetadata(metadata, 'u1');

        final read = await adapter.getSyncMetadata('u1');
        expect(read?.dataHash, 'hash-1');
        expect(await adapter.getSyncMetadata('u2'), isNull);
      });

      test('last sync result round-trips', () async {
        const result = DatumSyncResult<ConformanceEntity>(
          userId: 'u1',
          duration: Duration(milliseconds: 5),
          syncedCount: 2,
          failedCount: 0,
          conflictsResolved: 1,
          pendingOperations: [],
        );
        await adapter.saveLastSyncResult('u1', result);

        final read = await adapter.getLastSyncResult('u1');
        expect(read?.syncedCount, 2);
        expect(read?.conflictsResolved, 1);
      });

      test('schema version defaults to 0 and persists once set', () async {
        expect(await adapter.getStoredSchemaVersion(), 0);

        await adapter.setStoredSchemaVersion(3);
        expect(await adapter.getStoredSchemaVersion(), 3);
      });
    });

    group('raw data (migrations)', () {
      test('getAllRawData returns serialized rows', () async {
        await adapter.create(make('a', name: 'raw'));

        final raw = await adapter.getAllRawData(userId: 'u1');
        expect(raw.single, containsPair('id', 'a'));
        expect(raw.single, containsPair('name', 'raw'));
      });

      test('overwriteAllRawData replaces the store contents', () async {
        await adapter.create(make('old'));

        await adapter.overwriteAllRawData([
          make('new', name: 'migrated').toDatumMap(),
        ]);

        final all = await adapter.readAll(userId: 'u1');
        expect(all.map((e) => e.id), ['new']);
        expect(all.single.name, 'migrated');
      });

      if (preservesUnknownColumns) {
        test(
          'overwriteAllRawData preserves columns the entity does not know',
          () async {
            await adapter.overwriteAllRawData([
              {...make('a').toDatumMap(), 'migration_added': 'kept'},
            ]);

            expect(
              (await adapter.getAllRawData(userId: 'u1')).single,
              containsPair('migration_added', 'kept'),
            );
          },
        );
      }
    });

    group('storage', () {
      test('getStorageSize is non-negative and grows with data', () async {
        final empty = await adapter.getStorageSize(userId: 'u1');
        expect(empty, greaterThanOrEqualTo(0));

        await adapter.create(make('a', name: 'x' * 512));
        expect(
          await adapter.getStorageSize(userId: 'u1'),
          greaterThanOrEqualTo(empty),
        );
      });
    });

    group('capabilities', () {
      test('advertised capability mixins actually work', () async {
        if (adapter is PaginatedAdapter) {
          for (var i = 0; i < 5; i++) {
            await adapter.create(make('e$i', value: i));
          }
          final page = await adapter.readAllPaginated(
            const PaginationConfig(pageSize: 2, currentPage: 1),
            userId: 'u1',
          );
          expect(page.items, hasLength(2));
          expect(page.totalCount, 5);
          expect(page.hasMore, isTrue);
        }

        if (adapter is WatchableAdapter) {
          final stream = adapter.watchAll(userId: 'u1');
          expect(
            stream,
            isNotNull,
            reason: 'WatchableAdapter promises non-null watch streams',
          );
          final emissions = <List<ConformanceEntity>?>[];
          final sub = stream!.listen(emissions.add);
          await adapter.create(make('w1'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(
            emissions.any((e) => (e ?? []).any((x) => x.id == 'w1')),
            isTrue,
            reason: 'watchAll must emit after a create',
          );
          await sub.cancel();
        }
      });

      test(
        'transaction commits work; rollback restores state when supported',
        () async {
          await adapter.transaction(() async {
            await adapter.create(make('committed'));
          });
          expect(await adapter.read('committed', userId: 'u1'), isNotNull);

          if (adapter is TransactionalAdapter) {
            try {
              await adapter.transaction(() async {
                await adapter.create(make('rolled-back'));
                throw StateError('abort');
              });
            } on StateError {
              // expected
            }
            expect(
              await adapter.read('rolled-back', userId: 'u1'),
              isNull,
              reason: 'TransactionalAdapter promises rollback on error',
            );
          }
        },
      );
    });
  });
}
