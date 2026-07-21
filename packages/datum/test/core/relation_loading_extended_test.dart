import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

class Writer extends RelationalDatumEntity with MemoizedRelations {
  Writer({required this.id, required this.name}) : userId = 'u1';
  factory Writer.fromMap(Map<String, dynamic> j) => Writer(id: j['id'] as String, name: j['name'] as String? ?? '');
  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  @override
  Map<String, Relation> buildRelations() => {
        'bio': HasOne<Bio>(this, 'writerId'),
        'books': HasMany<Book>(this, 'writerId'),
        'tags': ManyToMany<Tag>(this, WriterTag, 'writerId', 'tagId'),
      };
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'name': name};
  @override
  Writer copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Writer(id: id, name: name);
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

class Bio extends DatumEntity {
  const Bio({required this.id, required this.writerId, required this.text}) : userId = 'u1';
  factory Bio.fromMap(Map<String, dynamic> j) => Bio(id: j['id'] as String, writerId: j['writerId'] as String, text: j['text'] as String? ?? '');
  @override
  final String id;
  @override
  final String userId;
  final String writerId;
  final String text;
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'writerId': writerId, 'text': text};
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

class Book extends DatumEntity {
  const Book({required this.id, required this.writerId, required this.title}) : userId = 'u1';
  factory Book.fromMap(Map<String, dynamic> j) => Book(id: j['id'] as String, writerId: j['writerId'] as String, title: j['title'] as String? ?? '');
  @override
  final String id;
  @override
  final String userId;
  final String writerId;
  final String title;
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'writerId': writerId, 'title': title};
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

class Tag extends DatumEntity {
  const Tag({required this.id, required this.label}) : userId = 'u1';
  factory Tag.fromMap(Map<String, dynamic> j) => Tag(id: j['id'] as String, label: j['label'] as String? ?? '');
  @override
  final String id;
  @override
  final String userId;
  final String label;
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'label': label};
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

class WriterTag extends DatumEntity {
  const WriterTag({required this.id, required this.writerId, required this.tagId}) : userId = 'u1';
  factory WriterTag.fromMap(Map<String, dynamic> j) => WriterTag(id: j['id'] as String, writerId: j['writerId'] as String, tagId: j['tagId'] as String);
  @override
  final String id;
  @override
  final String userId;
  final String writerId;
  final String tagId;
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'writerId': writerId, 'tagId': tagId};
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

MockConnectivityChecker _conn() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => Stream.value(true));
  return c;
}

void main() {
  late DatumManager<Writer> writers;

  setUp(() async {
    Datum.resetForTesting();
    await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: _conn(),
      registrations: [
        DatumRegistration<Writer>(localAdapter: InMemoryLocalAdapter<Writer>(fromMap: Writer.fromMap), remoteAdapter: MockRemoteAdapter<Writer>()),
        DatumRegistration<Bio>(localAdapter: InMemoryLocalAdapter<Bio>(fromMap: Bio.fromMap), remoteAdapter: MockRemoteAdapter<Bio>()),
        DatumRegistration<Book>(localAdapter: InMemoryLocalAdapter<Book>(fromMap: Book.fromMap), remoteAdapter: MockRemoteAdapter<Book>()),
        DatumRegistration<Tag>(localAdapter: InMemoryLocalAdapter<Tag>(fromMap: Tag.fromMap), remoteAdapter: MockRemoteAdapter<Tag>()),
        DatumRegistration<WriterTag>(localAdapter: InMemoryLocalAdapter<WriterTag>(fromMap: WriterTag.fromMap), remoteAdapter: MockRemoteAdapter<WriterTag>()),
      ],
    );
    writers = Datum.manager<Writer>();

    await writers.push(item: Writer(id: 'w1', name: 'Ada'), userId: 'u1');
    await Datum.manager<Bio>().push(item: const Bio(id: 'bio1', writerId: 'w1', text: 'about Ada'), userId: 'u1');
    await Datum.manager<Book>().push(item: const Book(id: 'bk1', writerId: 'w1', title: 'One'), userId: 'u1');
    await Datum.manager<Book>().push(item: const Book(id: 'bk2', writerId: 'w1', title: 'Two'), userId: 'u1');
    await Datum.manager<Tag>().push(item: const Tag(id: 't1', label: 'fiction'), userId: 'u1');
    await Datum.manager<Tag>().push(item: const Tag(id: 't2', label: 'classic'), userId: 'u1');
    await Datum.manager<WriterTag>().push(item: const WriterTag(id: 'wt1', writerId: 'w1', tagId: 't1'), userId: 'u1');
    await Datum.manager<WriterTag>().push(item: const WriterTag(id: 'wt2', writerId: 'w1', tagId: 't2'), userId: 'u1');
  });

  tearDown(() {
    Datum.resetForTesting();
    DatumRelationSchema.clear();
  });

  test('HasOne is eager-loaded via withRelated', () async {
    final w = await writers.read('w1', userId: 'u1', withRelated: ['bio']);
    final bio = w!.relatedOne<Bio>('bio');
    expect(bio, isNotNull);
    expect(bio!.text, 'about Ada');
  });

  test('HasOne.fetch() queries by foreign key, not by primary id (fetch bug)', () async {
    // The Bio's id ('bio1') differs from the Writer's key ('w1'). The old
    // implementation did `manager.read('w1')` — a primary-id lookup on Bio —
    // which returned null unless the child's id coincidentally equalled the
    // parent's. It must query `writerId == 'w1'` like every other HasOne path.
    final w = await writers.read('w1', userId: 'u1');
    final bio = await (w!.relations['bio'] as HasOne<Bio>).fetch();
    expect(bio, isNotNull, reason: 'lazy fetch must find the child via its foreign key');
    expect(bio!.id, 'bio1');
    expect(bio.text, 'about Ada');
  });

  test('ManyToMany is eager-loaded via withRelated (pivot traversal)', () async {
    final w = await writers.read('w1', userId: 'u1', withRelated: ['tags']);
    final tags = w!.relatedList<Tag>('tags');
    expect(tags, hasLength(2));
    expect(tags!.map((t) => t.label).toSet(), {'fiction', 'classic'});
  });

  test('multiple relation kinds load together', () async {
    final w = await writers.read('w1', userId: 'u1', withRelated: ['bio', 'books', 'tags']);
    final writer = w!;
    expect(writer.relatedOne<Bio>('bio'), isNotNull);
    expect(writer.relatedList<Book>('books'), hasLength(2));
    expect(writer.relatedList<Tag>('tags'), hasLength(2));
  });

  test('query() defaults to local source', () async {
    // No `source:` argument — should read from the local adapter.
    final result = await writers.query(const DatumQuery());
    expect(result.map((w) => w.id), ['w1']);
  });

  test('reactive watchAll eager-loads relations on each emission', () async {
    final stream = writers.watchAll(userId: 'u1', withRelated: ['books']);
    final first = await stream.first;
    expect(first, hasLength(1));
    expect(first.first.relatedList<Book>('books'), hasLength(2));
  });
}
