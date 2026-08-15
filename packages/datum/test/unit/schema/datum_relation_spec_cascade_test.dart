/// Cascade-delete behavior through typed relation specs.
///
/// Every relation in this world is declared with [DatumRelationSpec], so the
/// suite certifies that the behavior carried on a spec (`cascadeDelete:`)
/// drives the engine exactly like a hand-written relations map:
///
///   Library ─ hasMany(cascade) → Shelf ─ hasMany(cascade) → Book
///     │            Book ─ hasMany(cascade) → BookTag (pivot) ─ m2m → Sticker
///     ├─ hasMany(none)    → Draft   (orphaned, never deleted)
///     ├─ hasMany(setNull) → Card    (detached: foreign key nulled)
///     └─ hasMany(restrict)→ Gem     (blocks the delete while present)
///            Book ─ hasMany(restrict) → Gem (via bookId — deep restrict)
library;

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../mocks/mock_adapters.dart';
import '../../mocks/mock_connectivity_checker.dart';

final _epoch = DateTime.utc(2026, 1, 1);

class Library extends RelationalDatumEntity with MemoizedRelations {
  Library({required this.id, this.userId = 'u1'});

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

  static final shelvesRel = DatumRelationSpec<Library, Shelf>.hasMany(
    'shelves',
    foreignKey: Shelf.libraryIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );
  static final draftsRel = DatumRelationSpec<Library, Draft>.hasMany('drafts', foreignKey: Draft.libraryIdField);
  static final cardsRel = DatumRelationSpec<Library, Card>.hasMany(
    'cards',
    foreignKey: Card.libraryIdField,
    cascadeDelete: CascadeDeleteBehavior.setNull,
  );
  static final gemsRel = DatumRelationSpec<Library, Gem>.hasMany(
    'gems',
    foreignKey: Gem.libraryIdField,
    cascadeDelete: CascadeDeleteBehavior.restrict,
  );

  factory Library.fromMap(Map<String, dynamic> map) => Library(id: map['id'] as String, userId: map['userId'] as String? ?? 'u1');

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
  Library copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Library(id: id, userId: userId);

  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [shelvesRel, draftsRel, cardsRel, gemsRel]);
}

class Shelf extends RelationalDatumEntity with MemoizedRelations {
  Shelf({required this.id, required this.libraryId, this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;
  final String libraryId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final libraryIdField = DatumFieldSpec<Shelf, String>('libraryId', getter: (s) => s.libraryId);
  static final libraryRel = DatumRelationSpec<Shelf, Library>.belongsTo('library', foreignKey: libraryIdField);
  static final booksRel = DatumRelationSpec<Shelf, Book>.hasMany(
    'books',
    foreignKey: Book.shelfIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );

  factory Shelf.fromMap(Map<String, dynamic> map) => Shelf(
        id: map['id'] as String,
        libraryId: map['libraryId'] as String? ?? '',
        userId: map['userId'] as String? ?? 'u1',
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'libraryId': libraryId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Shelf copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Shelf(id: id, libraryId: libraryId, userId: userId);

  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [libraryRel, booksRel]);
}

class Book extends RelationalDatumEntity with MemoizedRelations {
  Book({required this.id, required this.shelfId, this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;
  final String shelfId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final shelfIdField = DatumFieldSpec<Book, String>('shelfId', getter: (b) => b.shelfId);
  static final linksRel = DatumRelationSpec<Book, BookTag>.hasMany(
    'links',
    foreignKey: BookTag.bookIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );
  static final stickersRel = DatumRelationSpec.manyToMany<Book, Sticker, BookTag>(
    'stickers',
    pivotSelfKey: BookTag.bookIdField,
    pivotOtherKey: BookTag.stickerIdField,
  );
  static final sealsRel = DatumRelationSpec<Book, Gem>.hasMany(
    'seals',
    foreignKey: Gem.bookIdField,
    cascadeDelete: CascadeDeleteBehavior.restrict,
  );

  factory Book.fromMap(Map<String, dynamic> map) => Book(
        id: map['id'] as String,
        shelfId: map['shelfId'] as String? ?? '',
        userId: map['userId'] as String? ?? 'u1',
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'shelfId': shelfId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Book copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Book(id: id, shelfId: shelfId, userId: userId);

  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [linksRel, stickersRel, sealsRel]);
}

class BookTag extends RelationalDatumEntity with MemoizedRelations {
  BookTag({required this.id, required this.bookId, required this.stickerId, this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;
  final String bookId;
  final String stickerId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final bookIdField = DatumFieldSpec<BookTag, String>('bookId', getter: (l) => l.bookId);
  static final stickerIdField = DatumFieldSpec<BookTag, String>('stickerId', getter: (l) => l.stickerId);

  factory BookTag.fromMap(Map<String, dynamic> map) => BookTag(
        id: map['id'] as String,
        bookId: map['bookId'] as String? ?? '',
        stickerId: map['stickerId'] as String? ?? '',
        userId: map['userId'] as String? ?? 'u1',
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'bookId': bookId,
        'stickerId': stickerId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  BookTag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => BookTag(id: id, bookId: bookId, stickerId: stickerId, userId: userId);

  @override
  Map<String, Relation> buildRelations() => const {};
}

class Sticker extends RelationalDatumEntity with MemoizedRelations {
  Sticker({required this.id, this.userId = 'u1'});

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

  factory Sticker.fromMap(Map<String, dynamic> map) => Sticker(id: map['id'] as String, userId: map['userId'] as String? ?? 'u1');

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
  Sticker copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Sticker(id: id, userId: userId);

  @override
  Map<String, Relation> buildRelations() => const {};
}

class Draft extends RelationalDatumEntity with MemoizedRelations {
  Draft({required this.id, required this.libraryId, this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;
  final String libraryId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final libraryIdField = DatumFieldSpec<Draft, String>('libraryId', getter: (d) => d.libraryId);

  factory Draft.fromMap(Map<String, dynamic> map) => Draft(
        id: map['id'] as String,
        libraryId: map['libraryId'] as String? ?? '',
        userId: map['userId'] as String? ?? 'u1',
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'libraryId': libraryId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Draft copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Draft(id: id, libraryId: libraryId, userId: userId);

  @override
  Map<String, Relation> buildRelations() => const {};
}

class Card extends RelationalDatumEntity with MemoizedRelations {
  Card({required this.id, required this.libraryId, this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;

  /// Nullable so the setNull behavior can detach it from its library.
  final String? libraryId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final libraryIdField = DatumFieldSpec<Card, String>('libraryId', getter: (c) => c.libraryId ?? '');

  factory Card.fromMap(Map<String, dynamic> map) => Card(
        id: map['id'] as String,
        libraryId: map['libraryId'] as String?,
        userId: map['userId'] as String? ?? 'u1',
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'libraryId': libraryId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Card copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Card(id: id, libraryId: libraryId, userId: userId);

  @override
  Map<String, Relation> buildRelations() => const {};
}

class Gem extends RelationalDatumEntity with MemoizedRelations {
  Gem({required this.id, this.libraryId = '', this.bookId = '', this.userId = 'u1'});

  @override
  final String id;
  @override
  final String userId;
  final String libraryId;
  final String bookId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final libraryIdField = DatumFieldSpec<Gem, String>('libraryId', getter: (g) => g.libraryId);
  static final bookIdField = DatumFieldSpec<Gem, String>('bookId', getter: (g) => g.bookId);

  factory Gem.fromMap(Map<String, dynamic> map) => Gem(
        id: map['id'] as String,
        libraryId: map['libraryId'] as String? ?? '',
        bookId: map['bookId'] as String? ?? '',
        userId: map['userId'] as String? ?? 'u1',
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'libraryId': libraryId,
        'bookId': bookId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Gem copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Gem(id: id, libraryId: libraryId, bookId: bookId, userId: userId);

  @override
  Map<String, Relation> buildRelations() => const {};
}

void main() {
  late DatumManager<Library> libraries;
  late DatumManager<Shelf> shelves;
  late DatumManager<Book> books;
  late DatumManager<BookTag> links;
  late DatumManager<Sticker> stickers;
  late DatumManager<Draft> drafts;
  late DatumManager<Card> cards;
  late DatumManager<Gem> gems;

  setUp(() async {
    final connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
    final result = await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: connectivity,
      registrations: [
        DatumRegistration<Library>(
          localAdapter: MockLocalAdapter<Library>(fromJson: Library.fromMap),
          remoteAdapter: MockRemoteAdapter<Library>(fromJson: Library.fromMap),
        ),
        DatumRegistration<Shelf>(
          localAdapter: MockLocalAdapter<Shelf>(fromJson: Shelf.fromMap),
          remoteAdapter: MockRemoteAdapter<Shelf>(fromJson: Shelf.fromMap),
        ),
        DatumRegistration<Book>(
          localAdapter: MockLocalAdapter<Book>(fromJson: Book.fromMap),
          remoteAdapter: MockRemoteAdapter<Book>(fromJson: Book.fromMap),
        ),
        DatumRegistration<BookTag>(
          localAdapter: MockLocalAdapter<BookTag>(fromJson: BookTag.fromMap),
          remoteAdapter: MockRemoteAdapter<BookTag>(fromJson: BookTag.fromMap),
        ),
        DatumRegistration<Sticker>(
          localAdapter: MockLocalAdapter<Sticker>(fromJson: Sticker.fromMap),
          remoteAdapter: MockRemoteAdapter<Sticker>(fromJson: Sticker.fromMap),
        ),
        DatumRegistration<Draft>(
          localAdapter: MockLocalAdapter<Draft>(fromJson: Draft.fromMap),
          remoteAdapter: MockRemoteAdapter<Draft>(fromJson: Draft.fromMap),
        ),
        DatumRegistration<Card>(
          localAdapter: MockLocalAdapter<Card>(fromJson: Card.fromMap),
          remoteAdapter: MockRemoteAdapter<Card>(fromJson: Card.fromMap),
        ),
        DatumRegistration<Gem>(
          localAdapter: MockLocalAdapter<Gem>(fromJson: Gem.fromMap),
          remoteAdapter: MockRemoteAdapter<Gem>(fromJson: Gem.fromMap),
        ),
      ],
    );
    expect(result.isSuccess(), isTrue, reason: '${result.errorOrNull}');
    libraries = Datum.manager<Library>();
    shelves = Datum.manager<Shelf>();
    books = Datum.manager<Book>();
    links = Datum.manager<BookTag>();
    stickers = Datum.manager<Sticker>();
    drafts = Datum.manager<Draft>();
    cards = Datum.manager<Card>();
    gems = Datum.manager<Gem>();

    await libraries.push(item: Library(id: 'L1'), userId: 'u1');
    await shelves.saveMany(items: [
      Shelf(id: 's1', libraryId: 'L1'),
      Shelf(id: 's2', libraryId: 'L1'),
    ], userId: 'u1');
    await books.saveMany(items: [
      Book(id: 'b1', shelfId: 's1'),
      Book(id: 'b2', shelfId: 's1'),
      Book(id: 'b3', shelfId: 's2'),
    ], userId: 'u1');
    await stickers.saveMany(items: [
      Sticker(id: 'st1'),
      Sticker(id: 'st2'),
    ], userId: 'u1');
    await links.saveMany(items: [
      BookTag(id: 'k1', bookId: 'b1', stickerId: 'st1'),
      BookTag(id: 'k2', bookId: 'b1', stickerId: 'st2'),
      BookTag(id: 'k3', bookId: 'b3', stickerId: 'st1'),
    ], userId: 'u1');
    await drafts.saveMany(items: [
      Draft(id: 'd1', libraryId: 'L1'),
      Draft(id: 'd2', libraryId: 'L1'),
    ], userId: 'u1');
    await cards.saveMany(items: [
      Card(id: 'c1', libraryId: 'L1'),
      Card(id: 'c2', libraryId: 'L1'),
    ], userId: 'u1');
  });

  tearDown(() => Datum.instance.dispose());

  test('deep cascade deletes the whole typed subtree with a per-type breakdown', () async {
    final result = await libraries.cascadeDelete(id: 'L1', userId: 'u1');

    expect(result.success, isTrue, reason: result.errors.join('; '));
    expect(result.totalDeleted, 9, reason: 'L1 + 2 shelves + 3 books + 3 pivot links');
    expect(result.deletedEntities[Library]?.length, 1);
    expect(result.deletedEntities[Shelf]?.map((e) => e.id).toSet(), {'s1', 's2'});
    expect(result.deletedEntities[Book]?.map((e) => e.id).toSet(), {'b1', 'b2', 'b3'});
    expect(result.deletedEntities[BookTag]?.map((e) => e.id).toSet(), {'k1', 'k2', 'k3'});

    expect(await libraries.read('L1', userId: 'u1'), isNull);
    expect(await shelves.read('s1', userId: 'u1'), isNull);
    expect(await books.read('b3', userId: 'u1'), isNull);
    expect(await links.read('k3', userId: 'u1'), isNull);
  });

  test('none and many-to-many far-side branches survive the cascade', () async {
    await libraries.cascadeDelete(id: 'L1', userId: 'u1');

    final orphans = await drafts.query(
      DatumQueryBuilder<Draft>().whereField(Draft.libraryIdField, isEqualTo: 'L1').build(),
      userId: 'u1',
    );
    expect(orphans.map((d) => d.id).toSet(), {'d1', 'd2'}, reason: 'CascadeDeleteBehavior.none keeps the branch');
    expect(await stickers.read('st1', userId: 'u1'), isNotNull, reason: 'm2m far side is never cascaded');
    expect(await stickers.read('st2', userId: 'u1'), isNotNull);
  });

  test('setNull detaches children instead of deleting them', () async {
    final result = await libraries.cascadeDelete(id: 'L1', userId: 'u1');

    expect(result.success, isTrue, reason: result.errors.join('; '));
    expect(result.deletedEntities.containsKey(Card), isFalse, reason: 'detached rows must not be counted as deleted');
    final c1 = await cards.read('c1', userId: 'u1');
    final c2 = await cards.read('c2', userId: 'u1');
    expect(c1, isNotNull);
    expect(c1!.libraryId, isNull, reason: 'setNull must clear the typed foreign key');
    expect(c2!.libraryId, isNull);

    final detached = await cards.query(
      DatumQueryBuilder<Card>().whereFieldNull(Card.libraryIdField).build(),
      userId: 'u1',
    );
    expect(detached.map((c) => c.id).toSet(), {'c1', 'c2'});
  });

  test('mid-node cascade preserves ancestors and sibling branches', () async {
    final result = await shelves.cascadeDelete(id: 's1', userId: 'u1');

    expect(result.success, isTrue, reason: result.errors.join('; '));
    expect(result.totalDeleted, 5, reason: 's1 + b1 + b2 + k1 + k2');
    expect(result.deletedEntities[BookTag]?.map((e) => e.id).toSet(), {'k1', 'k2'});

    expect(await libraries.read('L1', userId: 'u1'), isNotNull, reason: 'belongsTo never cascades upward');
    expect(await shelves.read('s2', userId: 'u1'), isNotNull);
    expect(await books.read('b3', userId: 'u1'), isNotNull);
    expect(await links.read('k3', userId: 'u1'), isNotNull);
  });

  test('restrict at the root blocks the delete and reports the blockers', () async {
    await gems.push(item: Gem(id: 'gm1', libraryId: 'L1'), userId: 'u1');

    final blocked = await libraries.cascadeDelete(id: 'L1', userId: 'u1');
    expect(blocked.success, isFalse);
    expect(blocked.errors, contains('Delete restricted by relationships'));
    expect(blocked.restrictedRelations[Library.gemsRel.name]?.map((e) => e.id).toList(), ['gm1']);
    expect(blocked.totalDeleted, 0);
    expect(await libraries.read('L1', userId: 'u1'), isNotNull);
    expect((await shelves.readAll(userId: 'u1')).length, 2, reason: 'nothing may be deleted on a restricted plan');

    await gems.delete(id: 'gm1', userId: 'u1');
    final retried = await libraries.cascadeDelete(id: 'L1', userId: 'u1');
    expect(retried.success, isTrue, reason: retried.errors.join('; '));
    expect(retried.totalDeleted, 9);
  });

  test('restrict deep in the subtree blocks the whole delete', () async {
    await gems.push(item: Gem(id: 'gm2', bookId: 'b3'), userId: 'u1');

    final blocked = await libraries.cascadeDelete(id: 'L1', userId: 'u1');
    expect(blocked.success, isFalse);
    expect(blocked.restrictedRelations[Book.sealsRel.name]?.map((e) => e.id).toList(), ['gm2']);
    expect(blocked.totalDeleted, 0);
    expect(await books.read('b3', userId: 'u1'), isNotNull);
    expect(await libraries.read('L1', userId: 'u1'), isNotNull);
  });

  test('cascade only touches the requesting user\'s rows', () async {
    await libraries.push(item: Library(id: 'L1', userId: 'u2'), userId: 'u2');
    await shelves.push(item: Shelf(id: 's1', libraryId: 'L1', userId: 'u2'), userId: 'u2');
    await books.push(item: Book(id: 'b1', shelfId: 's1', userId: 'u2'), userId: 'u2');

    final result = await libraries.cascadeDelete(id: 'L1', userId: 'u1');
    expect(result.success, isTrue, reason: result.errors.join('; '));
    expect(result.totalDeleted, 9);

    expect(await libraries.read('L1', userId: 'u2'), isNotNull);
    expect(await shelves.read('s1', userId: 'u2'), isNotNull);
    expect(await books.read('b1', userId: 'u2'), isNotNull);
  });
}
