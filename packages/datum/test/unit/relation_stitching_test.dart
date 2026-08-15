/// Relation stitching integrity (2026-08 audit fixes):
///
/// 1. `InMemoryLocalAdapter` hands out fresh instances per read, so eager
///    stitching (`withRelated`) can never write relation state into the
///    stored copy, and memoized `Relation.fetch()` caches die with the
///    instance instead of serving stale lists forever.
/// 2. `RelationLoader` falls back to the PARENT's userId when the caller
///    passed none, so stitching never attaches other users' rows whose
///    foreign keys happen to collide.
library;

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import 'schema/datum_relation_spec_cascade_test.dart' show Library, Shelf;

void main() {
  late DatumManager<Library> libraries;
  late DatumManager<Shelf> shelves;
  late InMemoryLocalAdapter<Library> libraryStore;

  setUp(() async {
    final connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
    libraryStore = InMemoryLocalAdapter<Library>(fromMap: Library.fromMap);
    final result = await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: connectivity,
      registrations: [
        DatumRegistration<Library>(
          localAdapter: libraryStore,
          remoteAdapter: MockRemoteAdapter<Library>(fromJson: Library.fromMap),
        ),
        DatumRegistration<Shelf>(
          localAdapter: InMemoryLocalAdapter<Shelf>(fromMap: Shelf.fromMap),
          remoteAdapter: MockRemoteAdapter<Shelf>(fromJson: Shelf.fromMap),
        ),
      ],
    );
    expect(result.isSuccess(), isTrue, reason: '${result.errorOrNull}');
    libraries = Datum.manager<Library>();
    shelves = Datum.manager<Shelf>();

    await libraries.push(item: Library(id: 'L1'), userId: 'u1');
    await shelves.push(item: Shelf(id: 's1', libraryId: 'L1'), userId: 'u1');
  });

  tearDown(() => Datum.instance.dispose());

  test('the adapter returns fresh instances, never the stored one', () async {
    final first = await libraryStore.read('L1', userId: 'u1');
    final second = await libraryStore.read('L1', userId: 'u1');
    expect(identical(first, second), isFalse, reason: 'shared instances let callers mutate the store');
  });

  test('eager stitching does not leak into later plain reads', () async {
    final eager = (await libraries.read('L1', userId: 'u1', withRelated: [Library.shelvesRel].names))!;
    expect(Library.shelvesRel.listOf(eager)?.map((s) => s.id).toList(), ['s1']);

    // A later PLAIN read must come back unstitched — previously the stored
    // instance carried the stitched state forever.
    final plain = (await libraries.read('L1', userId: 'u1'))!;
    expect(Library.shelvesRel.listOf(plain), isNull, reason: 'stitched relation state must not survive into fresh reads');
  });

  test('re-reading after a mutation yields current relations, not a stale memoized cache', () async {
    // Prime a lazy-fetch cache on a first read.
    final before = (await libraries.read('L1', userId: 'u1'))!;
    expect((await Library.shelvesRel.fetchListFor(before)).map((s) => s.id).toList(), ['s1']);

    await shelves.push(item: Shelf(id: 's2', libraryId: 'L1'), userId: 'u1');

    // A re-read gets a fresh instance whose fetch sees the new shelf.
    // (The OLD instance's memoized cache still answers ['s1'] by design —
    // per-instance memoization — which is exactly why reads must be fresh.)
    final after = (await libraries.read('L1', userId: 'u1'))!;
    expect((await Library.shelvesRel.fetchListFor(after)).map((s) => s.id).toSet(), {'s1', 's2'});
    expect((await Library.shelvesRel.fetchListFor(before)).map((s) => s.id).toList(), ['s1'], reason: 'the old instance keeps its own snapshot');
  });

  test('eager loading in watch/readAll emissions stays fresh across writes', () async {
    final first = await libraries.readAll(userId: 'u1', withRelated: [Library.shelvesRel].names);
    expect(Library.shelvesRel.listOf(first.single)?.length, 1);

    await shelves.push(item: Shelf(id: 's2', libraryId: 'L1'), userId: 'u1');

    final second = await libraries.readAll(userId: 'u1', withRelated: [Library.shelvesRel].names);
    expect(Library.shelvesRel.listOf(second.single)?.map((s) => s.id).toSet(), {'s1', 's2'}, reason: 'each readAll stitches onto fresh instances');
  });

  test('stitching an unscoped read uses the parent\'s userId', () async {
    // u2 owns a shelf whose foreign-key VALUE collides with u1's library id.
    await shelves.push(item: Shelf(id: 'sx', libraryId: 'L1', userId: 'u2'), userId: 'u2');

    final unscoped = (await libraries.read('L1', withRelated: [Library.shelvesRel].names))!;
    expect(
      Library.shelvesRel.listOf(unscoped)?.map((s) => s.id).toList(),
      ['s1'],
      reason: "u2's colliding row must not stitch onto u1's library",
    );
  });
}
