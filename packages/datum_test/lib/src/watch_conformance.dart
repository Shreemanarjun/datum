import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// Runs the Datum **watch-stream conformance suite** against an adapter.
///
/// Certifies the reactive contract every `WatchableAdapter` must honor:
///
/// - `watchAll` delivers a CURRENT snapshot to every listener that attaches —
///   including a second listener joining an already-watched stream — and
///   suppresses it when `includeInitialData: false`.
/// - Every create/update/delete triggers a fresh emission.
/// - `watchQuery` applies the query to every emission.
/// - `watchById` tracks a single entity and reports its deletion as `null`.
/// - Emissions are scoped to the requested user.
///
/// ```dart
/// runWatchConformanceTests(
///   name: 'HiveLocalAdapter',
///   create: () async { ... },
/// );
/// ```
void runWatchConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() create,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroy,
}) {
  group('$name watch conformance', () {
    late LocalAdapter<ConformanceEntity> adapter;

    ConformanceEntity make(
      String id, {
      String userId = 'u1',
      String name = 'entity',
      int value = 0,
    }) => ConformanceEntity.make(id, userId: userId, name: name, value: value);

    Set<String> ids(List<ConformanceEntity> list) =>
        list.map((e) => e.id).toSet();

    setUp(() async {
      adapter = await create();
    });

    tearDown(() async {
      await adapter.dispose();
      await destroy?.call(adapter);
    });

    test('watchAll emits a current snapshot to a new listener', () async {
      await adapter.create(make('a'));
      await adapter.create(make('b'));

      final first = await adapter
          .watchAll(userId: 'u1')!
          .first
          .timeout(const Duration(seconds: 5));
      expect(ids(first), {'a', 'b'});
    });

    test('includeInitialData: false emits only after the next write', () async {
      await adapter.create(make('a'));

      final events = <List<ConformanceEntity>>[];
      final sub = adapter
          .watchAll(userId: 'u1', includeInitialData: false)!
          .listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events, isEmpty, reason: 'no snapshot was requested');

      await adapter.create(make('b'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events, isNotEmpty, reason: 'a write must wake the stream');
      expect(ids(events.last), {'a', 'b'});
      await sub.cancel();
    });

    test('a second concurrent listener receives its own snapshot', () async {
      await adapter.create(make('a'));

      final stream = adapter.watchAll(userId: 'u1')!;
      final firstListener = <List<ConformanceEntity>>[];
      final sub = stream.listen(firstListener.add);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        firstListener,
        isNotEmpty,
        reason: 'first listener got its snapshot',
      );

      // While the first listener stays attached, a second one joins — it
      // must not stay silent until the next write.
      final second = await stream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('second listener never received a snapshot'),
      );
      expect(ids(second), {'a'});
      await sub.cancel();
    });

    test('watchAll re-emits on create, update, and delete', () async {
      final events = <List<ConformanceEntity>>[];
      final sub = adapter.watchAll(userId: 'u1')!.listen(events.add);

      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 120));

      await settle();
      await adapter.create(make('a', value: 1));
      await settle();
      expect(ids(events.last), {'a'}, reason: 'create must emit');

      await adapter.update(make('a', value: 2));
      await settle();
      expect(
        events.last.single.value,
        2,
        reason: 'update must emit the new state',
      );

      await adapter.delete('a', userId: 'u1');
      await settle();
      expect(events.last, isEmpty, reason: 'delete must emit');
      await sub.cancel();
    });

    test('watchQuery applies the query to every emission', () async {
      await adapter.create(make('low', value: 1));
      await adapter.create(make('high', value: 9));

      final stream = adapter.watchQuery(
        const DatumQuery(
          filters: [Filter('value', FilterOperator.greaterThan, 5)],
        ),
        userId: 'u1',
      )!;
      final first = await stream.first.timeout(const Duration(seconds: 5));
      expect(ids(first), {'high'});

      final events = <List<ConformanceEntity>>[];
      final sub = stream.listen(events.add);
      await adapter.create(make('higher', value: 11));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(ids(events.last), {'high', 'higher'});
      await sub.cancel();
    });

    test('watchById tracks one entity and reports deletion as null', () async {
      await adapter.create(make('a', value: 1));

      final stream = adapter.watchById('a', userId: 'u1');
      expect(
        stream,
        isNotNull,
        reason: 'a watchable adapter must support watchById',
      );

      final events = <ConformanceEntity?>[];
      final sub = stream!.listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events.last?.value, 1, reason: 'initial value delivered');

      await adapter.update(make('a', value: 2));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events.last?.value, 2);

      await adapter.delete('a', userId: 'u1');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events.last, isNull, reason: 'deletion must surface as null');
      await sub.cancel();
    });

    test('emissions are scoped to the requested user', () async {
      await adapter.create(make('mine', userId: 'u1'));
      await adapter.create(make('theirs', userId: 'u2'));

      final events = <List<ConformanceEntity>>[];
      final sub = adapter.watchAll(userId: 'u1')!.listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      await adapter.create(make('theirs-2', userId: 'u2'));
      await adapter.create(make('mine-2', userId: 'u1'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(events, isNotEmpty);
      for (final emission in events) {
        expect(
          emission.every((e) => e.userId == 'u1'),
          isTrue,
          reason: "another user's rows must never appear in a scoped stream",
        );
      }
      expect(ids(events.last), {'mine', 'mine-2'});
      await sub.cancel();
    });
  });
}
