import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

class Author extends RelationalDatumEntity {
  Author({required this.id, required this.name, DateTime? at})
      : userId = 'u1',
        modifiedAt = at ?? DateTime(2024),
        createdAt = at ?? DateTime(2024);

  factory Author.fromJson(Map<String, dynamic> j) => Author(id: j['id'] as String, name: j['name'] as String);

  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  late final Map<String, Relation> _relations = {'books': HasMany<Book>(this, 'authorId')};
  @override
  Map<String, Relation> get relations => _relations;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'name': name};

  @override
  Author copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Author(id: id, name: name);

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Book extends RelationalDatumEntity {
  Book({required this.id, required this.authorId, required this.title, DateTime? at})
      : userId = 'u1',
        modifiedAt = at ?? DateTime(2024),
        createdAt = at ?? DateTime(2024);

  factory Book.fromJson(Map<String, dynamic> j) => Book(id: j['id'] as String, authorId: j['authorId'] as String, title: j['title'] as String);

  @override
  final String id;
  @override
  final String userId;
  final String authorId;
  final String title;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  late final Map<String, Relation> _relations = {'author': BelongsTo<Author>(this, 'authorId')};
  @override
  Map<String, Relation> get relations => _relations;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'authorId': authorId, 'title': title};

  @override
  Book copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Book(id: id, authorId: authorId, title: title);

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

void main() {
  late DatumManager<Author> authorManager;
  late DatumManager<Book> bookManager;

  setUp(() async {
    final connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => Stream.value(true));

    Datum.resetForTesting();
    await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: connectivity,
      registrations: [
        DatumRegistration<Author>(localAdapter: MockLocalAdapter<Author>(fromJson: Author.fromJson), remoteAdapter: MockRemoteAdapter<Author>()),
        DatumRegistration<Book>(localAdapter: MockLocalAdapter<Book>(fromJson: Book.fromJson), remoteAdapter: MockRemoteAdapter<Book>()),
      ],
    );
    authorManager = Datum.manager<Author>();
    bookManager = Datum.manager<Book>();
  });

  tearDown(() {
    Datum.resetForTesting();
    DatumRelationSchema.clear();
  });

  test('#22 nested relations (books.author) are eagerly loaded via dot-path', () async {
    await authorManager.push(item: Author(id: 'a1', name: 'Ada'), userId: 'u1');
    await bookManager.push(item: Book(id: 'b1', authorId: 'a1', title: 'Algorithms'), userId: 'u1');
    await bookManager.push(item: Book(id: 'b2', authorId: 'a1', title: 'Notes'), userId: 'u1');

    final author = await authorManager.read('a1', userId: 'u1', withRelated: ['books.author']);
    expect(author, isNotNull);

    // Top-level: books are loaded.
    final books = (author!.relations['books'] as HasMany).value;
    expect(books, hasLength(2));

    // Nested: each book's author is loaded (dot-path traversal).
    for (final book in books!) {
      final loadedAuthor = ((book as Book).relations['author'] as BelongsTo).value;
      expect(loadedAuthor, isNotNull);
      expect((loadedAuthor as Author).id, 'a1');
    }
  });

  test('#22 top-level relation still works without a nested path', () async {
    await authorManager.push(item: Author(id: 'a1', name: 'Ada'), userId: 'u1');
    await bookManager.push(item: Book(id: 'b1', authorId: 'a1', title: 'Algorithms'), userId: 'u1');

    final author = await authorManager.read('a1', userId: 'u1', withRelated: ['books']);
    final books = (author!.relations['books'] as HasMany).value;
    expect(books, hasLength(1));
  });

  group('#21 static relation schema', () {
    test('a relation describes itself instance-free', () {
      final schema = Author(id: 'a1', name: 'Ada').relationSchema;
      expect(schema.keys, ['books']);
      expect(schema['books']!.kind, RelationKind.hasMany);
      expect(schema['books']!.targetType, Book);
      expect(schema['books']!.foreignKey, 'authorId');
    });

    test('manual registration enables type-level access without an instance', () {
      DatumRelationSchema.register(Author, Author(id: 's', name: 's').relationSchema);
      DatumRelationSchema.register(Book, Book(id: 's', authorId: 's', title: 's').relationSchema);

      // Traverse the chain Author -> books -> Book -> author -> Author by type only.
      final booksTarget = DatumRelationSchema.descriptor(Author, 'books')!.targetType;
      expect(booksTarget, Book);
      final authorTarget = DatumRelationSchema.descriptor(booksTarget, 'author')!.targetType;
      expect(authorTarget, Author);
      expect(DatumRelationSchema.descriptor(Book, 'author')!.kind, RelationKind.belongsTo);
    });

    test('schema auto-registers when the engine first sees an instance (push)', () async {
      expect(DatumRelationSchema.isRegistered(Author), isFalse);
      await authorManager.push(item: Author(id: 'a1', name: 'Ada'), userId: 'u1');
      expect(DatumRelationSchema.isRegistered(Author), isTrue);
      expect(DatumRelationSchema.of(Author)!['books']!.targetType, Book);
    });
  });

  group('#34 relation-preserving mutation', () {
    test('copyWith loses relations; preserveRelationsFrom restores the references', () {
      final author = Author(id: 'a1', name: 'Ada');
      final books = [Book(id: 'b1', authorId: 'a1', title: 'One')];
      (author.relations['books'] as HasMany).setRaw(books);
      expect((author.relations['books'] as HasMany).value, hasLength(1));

      // A plain copyWith produces a fresh instance whose relations are empty.
      final updated = author.copyWith(version: 2);
      expect((updated.relations['books'] as HasMany).value, isNull);

      // Carry the loaded relations across — no refetch, same list reference.
      updated.preserveRelationsFrom(author);
      final preserved = (updated.relations['books'] as HasMany).value;
      expect(preserved, hasLength(1));
      // The related entity reference is carried over (no refetch/re-instantiation).
      expect(identical(preserved!.first, books.first), isTrue);
    });

    test('cascade form reads naturally and only copies loaded relations', () {
      final author = Author(id: 'a1', name: 'Ada'); // no relations loaded
      final updated = author.copyWith(version: 2)..preserveRelationsFrom(author);
      // Nothing was loaded, so nothing to preserve (still null, no error).
      expect((updated.relations['books'] as HasMany).value, isNull);
    });
  });
}
