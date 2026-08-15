/// Soft-delete semantics through the manager (2026-08 audit fixes):
///
/// - Tombstones (`isDeleted: true`) are invisible to every default read path
///   (read / readAll / query / watchAll / watchQuery / watchById) while the
///   row survives underneath for sync; `includeDeleted: true` opts back in.
/// - A query that explicitly filters on `isDeleted` states intent and is
///   never rewritten.
/// - Tombstone pushdown means `limit` counts live rows only.
/// - The tombstone delta bumps `version` (conflict detection must see the
///   delete as newer) and carries `vectorClock` ONLY for entities that
///   actually serialize one.
/// - Cascade `restrict` ignores already-soft-deleted blockers.
library;

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../test_utils/test_datum_entity.dart';

final _epoch = DateTime.utc(2026, 1, 1);

/// An entity whose `toDatumMap` has NO `vectorClock` key — the tombstone
/// delta must not invent one for it.
class PlainNote extends DatumEntity {
  const PlainNote({required this.id, required this.userId, this.text = '', this.version = 1, this.isDeleted = false});

  @override
  final String id;
  @override
  final String userId;
  final String text;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  final int version;
  @override
  final bool isDeleted;

  factory PlainNote.fromMap(Map<String, dynamic> map) => PlainNote(
        id: map['id'] as String,
        userId: map['userId'] as String,
        text: map['text'] as String? ?? '',
        version: map['version'] as int? ?? 1,
        isDeleted: map['isDeleted'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  PlainNote copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => PlainNote(id: id, userId: userId, text: text, version: version ?? this.version, isDeleted: isDeleted ?? this.isDeleted);

  @override
  List<Object?> get props => [id, userId, text, version, isDeleted];
}

class Root extends RelationalDatumEntity with MemoizedRelations {
  Root({required this.id, this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final blockersRel = DatumRelationSpec<Root, Blocker>.hasMany(
    'blockers',
    foreignKey: Blocker.rootIdField,
    cascadeDelete: CascadeDeleteBehavior.restrict,
  );

  factory Root.fromMap(Map<String, dynamic> map) => Root(id: map['id'] as String, userId: map['userId'] as String? ?? 'u1');

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Root copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Root(id: id, userId: userId);

  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [blockersRel]);
}

class Blocker extends RelationalDatumEntity with MemoizedRelations {
  Blocker({required this.id, required this.rootId, this.userId = 'u1', this.version = 1, this.isDeleted = false});

  @override
  final String id;
  @override
  final String userId;
  final String rootId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  final int version;
  @override
  final bool isDeleted;

  static final rootIdField = DatumFieldSpec<Blocker, String>('rootId', getter: (b) => b.rootId);

  factory Blocker.fromMap(Map<String, dynamic> map) => Blocker(
        id: map['id'] as String,
        rootId: map['rootId'] as String? ?? '',
        userId: map['userId'] as String? ?? 'u1',
        version: map['version'] as int? ?? 1,
        isDeleted: map['isDeleted'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'rootId': rootId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Blocker copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Blocker(id: id, rootId: rootId, userId: userId, version: version ?? this.version, isDeleted: isDeleted ?? this.isDeleted);

  @override
  Map<String, Relation> buildRelations() => const {};
}

void main() {
  late DatumManager<TestDatumEntity> entities;
  late DatumManager<PlainNote> notes;
  late DatumManager<Root> roots;
  late DatumManager<Blocker> blockers;
  late MockLocalAdapter<TestDatumEntity> entityAdapter;
  late MockLocalAdapter<PlainNote> noteAdapter;

  setUp(() async {
    final connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
    entityAdapter = MockLocalAdapter<TestDatumEntity>(fromJson: TestDatumEntity.fromMap);
    noteAdapter = MockLocalAdapter<PlainNote>(fromJson: PlainNote.fromMap);
    final result = await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: connectivity,
      registrations: [
        DatumRegistration<TestDatumEntity>(
          localAdapter: entityAdapter,
          remoteAdapter: MockRemoteAdapter<TestDatumEntity>(fromJson: TestDatumEntity.fromMap),
        ),
        DatumRegistration<PlainNote>(
          localAdapter: noteAdapter,
          remoteAdapter: MockRemoteAdapter<PlainNote>(fromJson: PlainNote.fromMap),
        ),
        DatumRegistration<Root>(
          localAdapter: MockLocalAdapter<Root>(fromJson: Root.fromMap),
          remoteAdapter: MockRemoteAdapter<Root>(fromJson: Root.fromMap),
        ),
        DatumRegistration<Blocker>(
          localAdapter: MockLocalAdapter<Blocker>(fromJson: Blocker.fromMap),
          remoteAdapter: MockRemoteAdapter<Blocker>(fromJson: Blocker.fromMap),
        ),
      ],
    );
    expect(result.isSuccess(), isTrue, reason: '${result.errorOrNull}');
    entities = Datum.manager<TestDatumEntity>();
    notes = Datum.manager<PlainNote>();
    roots = Datum.manager<Root>();
    blockers = Datum.manager<Blocker>();
    // The mock adapter's watch streams are driven by an external change feed.
    entityAdapter.externalChangeStream = entities.onDataChange;

    await entities.saveMany(items: [
      TestDatumEntity(id: 'e1', userId: 'u1', value: 'b'),
      TestDatumEntity(id: 'e2', userId: 'u1', value: 'c'),
      TestDatumEntity(id: 'e3', userId: 'u1', value: 'd'),
      TestDatumEntity(id: 'gone', userId: 'u1', value: 'a'),
    ], userId: 'u1');
    await entities.delete(id: 'gone', userId: 'u1', behavior: DeleteBehavior.softDelete);
  });

  tearDown(() => Datum.instance.dispose());

  test('read hides the tombstone; includeDeleted reveals it with a bumped version', () async {
    expect(await entities.read('gone', userId: 'u1'), isNull);

    final tombstone = await entities.read('gone', userId: 'u1', includeDeleted: true);
    expect(tombstone, isNotNull);
    expect(tombstone!.isDeleted, isTrue);
    expect(tombstone.version, 2, reason: 'the tombstone must be a newer write than the live row');
  });

  test('readAll excludes tombstones by default and includes them on request', () async {
    final live = await entities.readAll(userId: 'u1');
    expect(live.map((e) => e.id).toSet(), {'e1', 'e2', 'e3'});

    final all = await entities.readAll(userId: 'u1', includeDeleted: true);
    expect(all.map((e) => e.id).toSet(), {'e1', 'e2', 'e3', 'gone'});
  });

  test('query excludes tombstones; an explicit isDeleted filter is respected', () async {
    final live = await entities.query(const DatumQuery(), userId: 'u1');
    expect(live.map((e) => e.id).toSet(), {'e1', 'e2', 'e3'});

    final tombstones = await entities.query(
      const DatumQuery(filters: [Filter('isDeleted', FilterOperator.equals, true)]),
      userId: 'u1',
    );
    expect(tombstones.map((e) => e.id).toList(), ['gone'], reason: 'explicit intent about tombstones must not be rewritten');
  });

  test('limit counts live rows only (tombstones are excluded by pushdown, not post-filtering)', () async {
    // The tombstone sorts FIRST by value ('a') — post-filtering would waste
    // a limit slot on it and return only two live rows.
    final firstThree = await entities.query(
      const DatumQuery(sorting: [SortDescriptor('value')], limit: 3),
      userId: 'u1',
    );
    expect(firstThree.map((e) => e.id).toList(), ['e1', 'e2', 'e3']);
  });

  test('OR queries keep their semantics under the tombstone rewrite', () async {
    final result = await entities.query(
      const DatumQuery(
        filters: [
          Filter('value', FilterOperator.equals, 'b'),
          Filter('value', FilterOperator.equals, 'a'),
        ],
        logicalOperator: LogicalOperator.or,
      ),
      userId: 'u1',
    );
    expect(result.map((e) => e.id).toList(), ['e1'], reason: "the tombstone matches value=='a' but must stay hidden");
  });

  test('watchAll and watchQuery emissions exclude tombstones; watchById emits null', () async {
    final watched = await entities.watchAll(userId: 'u1').first;
    expect(watched.map((e) => e.id).toSet(), {'e1', 'e2', 'e3'});

    final queried = await entities.watchQuery(const DatumQuery(sorting: [SortDescriptor('value')]), userId: 'u1').first;
    expect(queried.map((e) => e.id).toList(), ['e1', 'e2', 'e3']);

    expect(await entities.watchById('gone', 'u1').first, isNull);
    expect((await entities.watchById('gone', 'u1', includeDeleted: true).first)?.isDeleted, isTrue);
  });

  test('the tombstone delta increments the vector clock only for clock entities', () async {
    // TestDatumEntity serializes a vectorClock — but this Datum instance has
    // no deviceId, so no clock is stamped either way. What matters here is
    // the plain entity: its serialized form has NO vectorClock key, and the
    // tombstone must not invent one (fixed-schema adapters with strict
    // columns would throw on the phantom column).
    await notes.push(item: const PlainNote(id: 'n1', userId: 'u1', text: 'x'), userId: 'u1');
    await notes.delete(id: 'n1', userId: 'u1', behavior: DeleteBehavior.softDelete);

    final raw = await noteAdapter.getAllRawData(userId: 'u1');
    final tombstone = raw.singleWhere((r) => r['id'] == 'n1');
    expect(tombstone['isDeleted'], isTrue);
    expect(tombstone['version'], 2);
    expect(tombstone.containsKey('vectorClock'), isFalse, reason: 'no phantom clock column for entities that do not serialize one');
  });

  test('cascade restrict ignores blockers that are already soft-deleted', () async {
    await roots.push(item: Root(id: 'r1'), userId: 'u1');
    await blockers.push(item: Blocker(id: 'b1', rootId: 'r1'), userId: 'u1');

    final blocked = await roots.cascadeDelete(id: 'r1', userId: 'u1');
    expect(blocked.success, isFalse, reason: 'a live blocker restricts the delete');

    await blockers.delete(id: 'b1', userId: 'u1', behavior: DeleteBehavior.softDelete);

    final retried = await roots.cascadeDelete(id: 'r1', userId: 'u1');
    expect(retried.success, isTrue, reason: 'a soft-deleted blocker is already gone and must not restrict: ${retried.errors.join('; ')}');
    expect(await roots.read('r1', userId: 'u1'), isNull);
  });
}
