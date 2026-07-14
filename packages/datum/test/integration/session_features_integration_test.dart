import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

// ===========================================================================
// End-to-end integration tests for the fixes/features added this session,
// exercised through the real Datum.initialize() + Datum.manager<T>() stack.
// ===========================================================================

class Note extends DatumEntity {
  Note({
    required this.id,
    required this.userId,
    required this.title,
    this.count = 0,
    this.version = 1,
    this.isDeleted = false,
    DateTime? at,
  })  : modifiedAt = at ?? DateTime(2024, 1, 1),
        createdAt = at ?? DateTime(2024, 1, 1);

  factory Note.fromMap(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        userId: j['userId'] as String,
        title: j['title'] as String? ?? '',
        count: j['count'] as int? ?? 0,
        version: j['version'] as int? ?? 1,
        isDeleted: j['isDeleted'] as bool? ?? false,
      );

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final int count;
  @override
  final int version;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'count': count,
        'version': version,
        'isDeleted': isDeleted,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface old) {
    if (old is! Note) return toDatumMap(target: MapTarget.remote);
    final d = <String, dynamic>{};
    if (title != old.title) d['title'] = title;
    if (count != old.count) d['count'] = count;
    return d.isEmpty ? null : d;
  }

  Note copyWith({String? title, int? count, int? version}) => Note(
        id: id,
        userId: userId,
        title: title ?? this.title,
        count: count ?? this.count,
        version: version ?? this.version,
        isDeleted: isDeleted,
        at: modifiedAt,
      );
}

// Uses the MemoizedRelations mixin (#UX) so eager loading works without a
// hand-written `late final _relations` field.
class Blog extends RelationalDatumEntity with MemoizedRelations {
  Blog({required this.id, required this.name}) : userId = 'u1';
  factory Blog.fromMap(Map<String, dynamic> j) => Blog(id: j['id'] as String, name: j['name'] as String? ?? '');

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
  Map<String, Relation> buildRelations() => {'posts': HasMany<Post>(this, 'blogId')};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'name': name};
  @override
  Blog copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Blog(id: id, name: name);
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

class Post extends RelationalDatumEntity with MemoizedRelations {
  Post({required this.id, required this.blogId, required this.title}) : userId = 'u1';
  factory Post.fromMap(Map<String, dynamic> j) => Post(id: j['id'] as String, blogId: j['blogId'] as String, title: j['title'] as String? ?? '');

  @override
  final String id;
  @override
  final String userId;
  final String blogId;
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
  Map<String, Relation> buildRelations() => {'blog': BelongsTo<Blog>(this, 'blogId')};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'blogId': blogId, 'title': title};
  @override
  Post copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Post(id: id, blogId: blogId, title: title);
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

/// A resolver that honors remote deletions and otherwise keeps local.
class DeletionHonoringResolver<T extends DatumEntityInterface> implements DatumConflictResolver<T> {
  @override
  String get name => 'DeletionHonoring';
  @override
  FutureOr<DatumConflictResolution<T>> resolve({T? local, T? remote, required DatumConflictContext context}) {
    if (local != null && remote == null) return DatumConflictResolution<T>.deleteLocal();
    if (remote != null) return DatumConflictResolution.useRemote(remote);
    return DatumConflictResolution.useLocal(local as T);
  }
}

class RawNoteAdapter extends InMemoryLocalAdapter<Note> with RawQueryCapable {
  RawNoteAdapter() : super(fromMap: Note.fromMap);
  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId}) async {
    final all = await readAll(userId: userId);
    if (query.count) {
      return [
        {'total': all.length},
      ];
    }
    return all.map((e) => {'id': e.id, 'title': e.title}).toList();
  }
}

MockConnectivityChecker _connectivity({bool connected = true}) {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => connected);
  when(() => c.onStatusChange).thenAnswer((_) => Stream.value(connected));
  return c;
}

void main() {
  tearDown(() {
    Datum.resetForTesting();
    DatumRelationSchema.clear();
  });

  group('Global config propagation (#43)', () {
    test('global default resolver reaches per-entity managers and resolves conflicts', () async {
      final local = InMemoryLocalAdapter<Note>(fromMap: Note.fromMap);
      final remote = MockRemoteAdapter<Note>(fromJson: Note.fromMap);

      final init = await Datum.initialize(
        config: DatumConfig<DatumEntityInterface>(
          enableLogging: false,
          defaultConflictResolver: LocalPriorityResolver<DatumEntityInterface>(),
        ),
        connectivityChecker: _connectivity(),
        registrations: [DatumRegistration<Note>(localAdapter: local, remoteAdapter: remote)],
      );
      expect(init.isSuccess(), isTrue);

      final manager = Datum.manager<Note>();
      // Bug #43: the resolver must NOT be dropped when deriving the typed config.
      expect(manager.config.defaultConflictResolver, isNotNull);
      expect(manager.config.defaultConflictResolver, isA<DatumConflictResolver<Note>>());

      // Functional proof: conflicting versions -> the GLOBAL resolver keeps local.
      await local.create(Note(id: 'n1', userId: 'u1', title: 'LOCAL', version: 2));
      remote.addRemoteItem('u1', Note(id: 'n1', userId: 'u1', title: 'REMOTE'));

      final result = await manager.synchronize('u1');
      expect(result.conflictsResolved, 1);
      expect((await manager.read('n1', userId: 'u1'))?.title, 'LOCAL');
    });
  });

  group('Fetch strategies (#17)', () {
    test('localFirst / remoteFirst / remoteOnly end-to-end', () async {
      final local = InMemoryLocalAdapter<Note>(fromMap: Note.fromMap);
      final remote = MockRemoteAdapter<Note>(fromJson: Note.fromMap);
      await Datum.initialize(
        config: const DatumConfig<DatumEntityInterface>(enableLogging: false),
        connectivityChecker: _connectivity(),
        registrations: [DatumRegistration<Note>(localAdapter: local, remoteAdapter: remote)],
      );
      final manager = Datum.manager<Note>();

      remote.addRemoteItem('u1', Note(id: 'r1', userId: 'u1', title: 'from-remote'));

      // localFirst: local empty -> falls back to remote, and can persist.
      final lf = await manager.fetch(const DatumQuery(), strategy: DataFetchStrategy.localFirst, userId: 'u1', persistRemoteResults: true);
      expect(lf.single.id, 'r1');
      expect(await local.read('r1', userId: 'u1'), isNotNull); // persisted

      // remoteOnly returns the remote view.
      expect((await manager.fetch(const DatumQuery(), strategy: DataFetchStrategy.remoteOnly, userId: 'u1')).single.id, 'r1');

      // remoteFirst falls back to local when the remote is down.
      remote.isConnectedValue = false;
      final rf = await manager.fetch(const DatumQuery(), strategy: DataFetchStrategy.remoteFirst, userId: 'u1');
      expect(rf.single.id, 'r1'); // came from the persisted local copy
    });
  });

  group('Relations: nested load + static schema + preservation (#22, #21, #34)', () {
    late DatumManager<Blog> blogs;
    late DatumManager<Post> posts;

    setUp(() async {
      await Datum.initialize(
        config: const DatumConfig<DatumEntityInterface>(enableLogging: false),
        connectivityChecker: _connectivity(),
        registrations: [
          DatumRegistration<Blog>(localAdapter: InMemoryLocalAdapter<Blog>(fromMap: Blog.fromMap), remoteAdapter: MockRemoteAdapter<Blog>()),
          DatumRegistration<Post>(localAdapter: InMemoryLocalAdapter<Post>(fromMap: Post.fromMap), remoteAdapter: MockRemoteAdapter<Post>()),
        ],
      );
      blogs = Datum.manager<Blog>();
      posts = Datum.manager<Post>();
      await blogs.push(item: Blog(id: 'blog1', name: 'Tech'), userId: 'u1');
      await posts.push(item: Post(id: 'p1', blogId: 'blog1', title: 'One'), userId: 'u1');
      await posts.push(item: Post(id: 'p2', blogId: 'blog1', title: 'Two'), userId: 'u1');
    });

    test('#22 nested relations posts.blog load via dot-path (with typed accessors)', () async {
      final blog = await blogs.read('blog1', userId: 'u1', withRelated: ['posts.blog']);
      // Typed accessor instead of `(blog.relations['posts'] as HasMany).value`.
      final loadedPosts = blog!.relatedList<Post>('posts');
      expect(loadedPosts, hasLength(2));
      for (final p in loadedPosts!) {
        expect(p.relatedOne<Blog>('blog'), isNotNull);
      }
    });

    test('#21 relation schema is registered and traversable by type', () async {
      // Registered automatically once instances flowed through push.
      expect(DatumRelationSchema.isRegistered(Blog), isTrue);
      final postsTarget = DatumRelationSchema.descriptor(Blog, 'posts')!.targetType;
      expect(postsTarget, Post);
      expect(DatumRelationSchema.descriptor(postsTarget, 'blog')!.targetType, Blog);
    });

    test('#34 relations survive a copyWith via preserveRelationsFrom', () async {
      final blog = await blogs.read('blog1', userId: 'u1', withRelated: ['posts']);
      final updated = blog!.copyWith()..preserveRelationsFrom(blog);
      expect(updated.relatedList<Post>('posts'), hasLength(2));
    });

    test('UX: manager.count / exists work end-to-end', () async {
      expect(await blogs.exists('blog1', userId: 'u1'), isTrue);
      expect(await blogs.exists('missing', userId: 'u1'), isFalse);
      expect(await posts.count(userId: 'u1'), 2);

      final q = (DatumQueryBuilder<Post>()..where('title', isEqualTo: 'One')).build();
      expect(await posts.count(query: q, userId: 'u1'), 1);
    });
  });

  group('Offline sync: entityTable + excluded users (#16, #32)', () {
    test('offline push stamps entityTable; excluded user is skipped', () async {
      final local = InMemoryLocalAdapter<Note>(fromMap: Note.fromMap);
      final remote = MockRemoteAdapter<Note>(fromJson: Note.fromMap);
      await Datum.initialize(
        config: const DatumConfig<DatumEntityInterface>(enableLogging: false, excludedSyncUserIds: {'system'}),
        connectivityChecker: _connectivity(connected: false),
        registrations: [DatumRegistration<Note>(localAdapter: local, remoteAdapter: remote)],
      );
      final manager = Datum.manager<Note>();

      await manager.push(item: Note(id: 'n1', userId: 'u1', title: 'A'), userId: 'u1');
      final pending = await manager.getPendingOperations('u1');
      expect(pending, isNotEmpty);
      expect(pending.first.entityTable, 'Note'); // #16

      // #32: the system user is excluded from sync.
      final skipped = await manager.synchronize('system');
      expect(skipped.wasSkipped, isTrue);
    });
  });

  group('Remote deletion detection (#41)', () {
    test('local-only entity removed when opted in and resolver honors deletion', () async {
      final local = InMemoryLocalAdapter<Note>(fromMap: Note.fromMap);
      final remote = MockRemoteAdapter<Note>(fromJson: Note.fromMap);
      await Datum.initialize(
        config: DatumConfig<DatumEntityInterface>(
          enableLogging: false,
          detectRemoteDeletions: true,
          defaultSyncDirection: SyncDirection.pullOnly,
          defaultConflictResolver: DeletionHonoringResolver<DatumEntityInterface>(),
        ),
        connectivityChecker: _connectivity(),
        registrations: [DatumRegistration<Note>(localAdapter: local, remoteAdapter: remote)],
      );
      final manager = Datum.manager<Note>();

      await local.create(Note(id: 'n1', userId: 'u1', title: 'keep'));
      await local.create(Note(id: 'n2', userId: 'u1', title: 'gone-remotely'));
      remote.addRemoteItem('u1', Note(id: 'n1', userId: 'u1', title: 'keep'));

      await manager.synchronize('u1');

      expect(await manager.read('n1', userId: 'u1'), isNotNull);
      expect(await manager.read('n2', userId: 'u1'), isNull); // remote deletion applied
    });
  });

  group('Adapter-aware raw query (#11)', () {
    test('projection and count via a RawQueryCapable adapter', () async {
      await Datum.initialize(
        config: const DatumConfig<DatumEntityInterface>(enableLogging: false),
        connectivityChecker: _connectivity(),
        registrations: [DatumRegistration<Note>(localAdapter: RawNoteAdapter(), remoteAdapter: MockRemoteAdapter<Note>(fromJson: Note.fromMap))],
      );
      final manager = Datum.manager<Note>();
      await manager.push(item: Note(id: 'n1', userId: 'u1', title: 'A'), userId: 'u1');
      await manager.push(item: Note(id: 'n2', userId: 'u1', title: 'B'), userId: 'u1');

      final rows = await manager.rawQuery(const DatumRawQuery(select: 'id,title'), source: DataSource.local, userId: 'u1');
      expect(rows, hasLength(2));
      expect(rows.first.keys.toSet(), {'id', 'title'});

      final count = await manager.rawQuery(const DatumRawQuery(count: true), source: DataSource.local, userId: 'u1');
      expect(count.single['total'], 2);
    });
  });

  group('Query-cache opt-out & negative-read cache correctness (#37, #39)', () {
    test('local queries return fresh data by default; late-arriving data is visible', () async {
      final local = InMemoryLocalAdapter<Note>(fromMap: Note.fromMap);
      await Datum.initialize(
        config: const DatumConfig<DatumEntityInterface>(enableLogging: false),
        connectivityChecker: _connectivity(),
        registrations: [DatumRegistration<Note>(localAdapter: local, remoteAdapter: MockRemoteAdapter<Note>(fromJson: Note.fromMap))],
      );
      final manager = Datum.manager<Note>();

      // #39: a negative read must not be cached.
      expect(await manager.read('n1', userId: 'u1'), isNull);
      await local.create(Note(id: 'n1', userId: 'u1', title: 'arrived'));
      expect((await manager.read('n1', userId: 'u1'))?.title, 'arrived');

      // #37: query cache is off by default -> new rows are seen immediately.
      final first = await manager.query(const DatumQuery(), source: DataSource.local, userId: 'u1');
      expect(first, hasLength(1));
      await local.create(Note(id: 'n2', userId: 'u1', title: 'second'));
      final second = await manager.query(const DatumQuery(), source: DataSource.local, userId: 'u1');
      expect(second, hasLength(2));
    });
  });
}
