import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

MockConnectivityChecker _createConnectivityChecker() {
  final checker = MockConnectivityChecker();
  when(() => checker.isConnected).thenAnswer((_) async => true);
  when(() => checker.onStatusChange).thenAnswer((_) => Stream.value(true));
  return checker;
}

/// An author with many books.
class Author extends RelationalDatumEntity {
  const Author({
    required this.id,
    required this.userId,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

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
  final int version;
  @override
  final bool isDeleted;

  @override
  List<Object?> get props => [...super.props, name];

  @override
  Map<String, Relation> get relations => {'books': HasMany<Book>(this, 'authorId')};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Author copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Author(
        id: id,
        userId: userId,
        name: name,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        createdAt: createdAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

/// A book belonging to an author and tagged via a pivot.
class Book extends RelationalDatumEntity {
  const Book({
    required this.id,
    required this.userId,
    required this.title,
    required this.modifiedAt,
    required this.createdAt,
    this.authorId,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String? authorId;
  final String title;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  List<Object?> get props => [...super.props, authorId, title];

  @override
  Map<String, Relation> get relations => {
        'author': BelongsTo<Author>(this, 'authorId'),
        'tags': ManyToMany<BookTag2>(this, BookPivot, 'bookId', 'tagId'),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'authorId': authorId,
        'title': title,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Book copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Book(
        id: id,
        userId: userId,
        authorId: authorId,
        title: title,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        createdAt: createdAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

/// A tag that can be attached to many books through [BookPivot].
class BookTag2 extends RelationalDatumEntity {
  const BookTag2({
    required this.id,
    required this.userId,
    required this.label,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String label;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  List<Object?> get props => [...super.props, label];

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'label': label,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  BookTag2 copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => BookTag2(
        id: id,
        userId: userId,
        label: label,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        createdAt: createdAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

/// The pivot linking a [Book] to a [BookTag2].
class BookPivot extends RelationalDatumEntity {
  const BookPivot({
    required this.id,
    required this.userId,
    required this.bookId,
    required this.tagId,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String bookId;
  final String tagId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  List<Object?> get props => [...super.props, bookId, tagId];

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'bookId': bookId,
        'tagId': tagId,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  BookPivot copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => BookPivot(
        id: id,
        userId: userId,
        bookId: bookId,
        tagId: tagId,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        createdAt: createdAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

void main() {
  const userId = 'user-1';

  final author = Author(
    id: 'author-1',
    userId: userId,
    name: 'Jane Doe',
    modifiedAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  final book1 = Book(
    id: 'book-1',
    userId: userId,
    authorId: 'author-1',
    title: 'First Book',
    modifiedAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  final book2 = Book(
    id: 'book-2',
    userId: userId,
    authorId: 'author-1',
    title: 'Second Book',
    modifiedAt: DateTime(2024, 2),
    createdAt: DateTime(2024, 2),
  );

  final orphanBook = Book(
    id: 'book-orphan',
    userId: userId,
    title: 'No Author',
    modifiedAt: DateTime(2024, 3),
    createdAt: DateTime(2024, 3),
  );

  final tag1 = BookTag2(
    id: 'tag-1',
    userId: userId,
    label: 'fiction',
    modifiedAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  final tag2 = BookTag2(
    id: 'tag-2',
    userId: userId,
    label: 'bestseller',
    modifiedAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  final pivot1 = BookPivot(
    id: 'pivot-1',
    userId: userId,
    bookId: 'book-1',
    tagId: 'tag-1',
    modifiedAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  final pivot2 = BookPivot(
    id: 'pivot-2',
    userId: userId,
    bookId: 'book-1',
    tagId: 'tag-2',
    modifiedAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  setUp(() async {
    Datum.resetForTesting();
    await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: _createConnectivityChecker(),
      registrations: [
        DatumRegistration<Author>(
          localAdapter: MockLocalAdapter<Author>()..addLocalItem(userId, author),
          remoteAdapter: MockRemoteAdapter<Author>(),
        ),
        DatumRegistration<Book>(
          localAdapter: MockLocalAdapter<Book>()
            ..addLocalItem(userId, book1)
            ..addLocalItem(userId, book2)
            ..addLocalItem(userId, orphanBook),
          remoteAdapter: MockRemoteAdapter<Book>(),
        ),
        DatumRegistration<BookTag2>(
          localAdapter: MockLocalAdapter<BookTag2>()
            ..addLocalItem(userId, tag1)
            ..addLocalItem(userId, tag2),
          remoteAdapter: MockRemoteAdapter<BookTag2>(),
        ),
        DatumRegistration<BookPivot>(
          localAdapter: MockLocalAdapter<BookPivot>()
            ..addLocalItem(userId, pivot1)
            ..addLocalItem(userId, pivot2),
          remoteAdapter: MockRemoteAdapter<BookPivot>(),
        ),
      ],
    );
  });

  group('BelongsTo.fetch', () {
    test('loads the related entity through the registered manager', () async {
      final relation = BelongsTo<Author>(book1, 'authorId');
      final fetched = await relation.fetch();

      expect(fetched, isNotNull);
      expect(fetched!.id, 'author-1');
      expect(fetched.name, 'Jane Doe');
      expect(relation.value, same(fetched));

      // A second fetch serves the memoized value.
      final again = await relation.fetch();
      expect(again, same(fetched));
    });

    test('returns null when the foreign key value is null', () async {
      final relation = BelongsTo<Author>(orphanBook, 'authorId');
      expect(await relation.fetch(), isNull);
      // Not marked loaded, so the value stays unset.
      expect(relation.value, isNull);
    });
  });

  group('HasMany.fetch', () {
    test('queries related entities by foreign key', () async {
      final relation = HasMany<Book>(author, 'authorId');
      final books = await relation.fetch();

      expect(books, isNotNull);
      expect(books!.map((b) => b.id), containsAll(['book-1', 'book-2']));
      expect(books.any((b) => b.id == 'book-orphan'), isFalse);
      expect(relation.value, same(books));

      final again = await relation.fetch();
      expect(again, same(books));
    });

    test('returns an empty list when the local key value is missing', () async {
      final relation = HasMany<Book>(author, 'authorId', localKey: 'missingKey');
      expect(await relation.fetch(), isEmpty);
    });
  });

  group('ManyToMany', () {
    test('setRaw(null) clears the loaded value', () {
      final relation = ManyToMany<BookTag2>(
        book1,
        BookPivot,
        'bookId',
        'tagId',
        value: [tag1],
      );
      expect(relation.value, isNotEmpty);

      relation.setRaw(null);
      expect(relation.value, isNull);
    });

    test('setRaw with a list casts and stores it', () {
      final relation = ManyToMany<BookTag2>(book1, BookPivot, 'bookId', 'tagId');
      relation.setRaw(<dynamic>[tag1, tag2]);
      expect(relation.value, [tag1, tag2]);
    });

    test('fetch resolves the target entities through the pivot', () async {
      final relation = ManyToMany<BookTag2>(book1, BookPivot, 'bookId', 'tagId');
      final tags = await relation.fetch();

      expect(tags, isNotNull);
      expect(tags!.map((t) => t.id).toSet(), {'tag-1', 'tag-2'});
      expect(tags.map((t) => t.label).toSet(), {'fiction', 'bestseller'});
      expect(relation.value, same(tags));

      final again = await relation.fetch();
      expect(again, same(tags));
    });

    test('fetch returns an empty list when no pivot rows match', () async {
      final relation = ManyToMany<BookTag2>(book2, BookPivot, 'bookId', 'tagId');
      final tags = await relation.fetch();

      expect(tags, isEmpty);
      // The empty result is memoized as loaded.
      expect(relation.value, isEmpty);
      expect(await relation.fetch(), isEmpty);
    });

    test('fetch returns an empty list when the local key value is missing', () async {
      final relation = ManyToMany<BookTag2>(
        book1,
        BookPivot,
        'bookId',
        'tagId',
        thisLocalKey: 'missingKey',
      );
      expect(await relation.fetch(), isEmpty);
    });
  });

  group('RelationalDatumEntityMixin defaults', () {
    test('incrementClock returns the same instance', () {
      expect(author.incrementClock('replica-1'), same(author));
    });

    test('merge returns the other entity', () {
      expect(author.merge(book1), same(book1));
    });
  });
}
