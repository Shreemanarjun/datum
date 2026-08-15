import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../mocks/mock_adapters.dart';
import '../../mocks/mock_connectivity_checker.dart';

final _epoch = DateTime.utc(2026, 1, 1);

class Blog extends RelationalDatumEntity with MemoizedRelations {
  Blog({required this.id, required this.title});

  @override
  final String id;
  @override
  String get userId => 'u1';
  final String title;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final titleField = DatumFieldSpec<Blog, String>('title', getter: (b) => b.title);

  static final postsRel = DatumRelationSpec<Blog, Post>.hasMany(
    'posts',
    foreignKey: Post.blogIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );
  static final pinnedRel = DatumRelationSpec<Blog, Post>.hasOne('pinned', foreignKey: Post.blogIdField);

  factory Blog.fromMap(Map<String, dynamic> map) => Blog(id: map['id'] as String, title: map['title'] as String? ?? '');

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Blog copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Blog(id: id, title: title);

  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [postsRel, pinnedRel]);
}

class Post extends RelationalDatumEntity with MemoizedRelations {
  Post({required this.id, required this.blogId, required this.body});

  @override
  final String id;
  @override
  String get userId => 'u1';
  final String blogId;
  final String body;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final blogIdField = DatumFieldSpec<Post, String>('blogId', getter: (p) => p.blogId);
  static final blogRel = DatumRelationSpec<Post, Blog>.belongsTo('blog', foreignKey: blogIdField);
  static final tagsRel = DatumRelationSpec.manyToMany<Post, Tag, PostTag>(
    'tags',
    pivotSelfKey: PostTag.postIdField,
    pivotOtherKey: PostTag.tagIdField,
  );

  factory Post.fromMap(Map<String, dynamic> map) => Post(id: map['id'] as String, blogId: map['blogId'] as String? ?? '', body: map['body'] as String? ?? '');

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'blogId': blogId,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Post copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Post(id: id, blogId: blogId, body: body);

  @override
  Map<String, Relation> buildRelations() => datumRelationsFor(this, [blogRel, tagsRel]);
}

class Tag extends RelationalDatumEntity with MemoizedRelations {
  Tag({required this.id, required this.label});

  @override
  final String id;
  @override
  String get userId => 'u1';
  final String label;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(id: map['id'] as String, label: map['label'] as String? ?? '');

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  Tag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Tag(id: id, label: label);

  @override
  Map<String, Relation> buildRelations() => const {};
}

class PostTag extends RelationalDatumEntity with MemoizedRelations {
  PostTag({required this.id, required this.postId, required this.tagId});

  @override
  final String id;
  @override
  String get userId => 'u1';
  final String postId;
  final String tagId;
  @override
  DateTime get createdAt => _epoch;
  @override
  DateTime get modifiedAt => _epoch;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final postIdField = DatumFieldSpec<PostTag, String>('postId', getter: (l) => l.postId);
  static final tagIdField = DatumFieldSpec<PostTag, String>('tagId', getter: (l) => l.tagId);

  factory PostTag.fromMap(Map<String, dynamic> map) => PostTag(id: map['id'] as String, postId: map['postId'] as String? ?? '', tagId: map['tagId'] as String? ?? '');

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'postId': postId,
        'tagId': tagId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  PostTag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => PostTag(id: id, postId: postId, tagId: tagId);

  @override
  Map<String, Relation> buildRelations() => const {};
}

void main() {
  group('spec construction', () {
    test('carries name, kind, typed foreign key, and cascade behavior', () {
      expect(Blog.postsRel.name, 'posts');
      expect(Blog.postsRel.kind, DatumRelationKind.hasMany);
      expect(Blog.postsRel.foreignKeyName, 'blogId');
      expect(Blog.postsRel.cascadeDelete, CascadeDeleteBehavior.cascade);
      expect(Post.blogRel.kind, DatumRelationKind.belongsTo);
      expect(Blog.pinnedRel.kind, DatumRelationKind.hasOne);
      expect(Post.tagsRel.kind, DatumRelationKind.manyToMany);
      expect(Post.tagsRel.pivotType, PostTag);
      expect(Post.tagsRel.foreignKeyName, 'postId');
      expect(Post.tagsRel.pivotOtherKeyName, 'tagId');
    });

    test('datumRelationsFor builds the runtime relations with the same semantics', () {
      final blog = Blog(id: 'b1', title: 'datum');
      final posts = blog.relations['posts']! as HasMany<Post>;
      expect(posts.foreignKey, 'blogId');
      expect(posts.cascadeDeleteBehavior, CascadeDeleteBehavior.cascade);
      expect(blog.relations['pinned'], isA<HasOne<Post>>());
      final post = Post(id: 'p', blogId: 'b1', body: '');
      expect(post.relations['blog'], isA<BelongsTo<Blog>>());
      final m2m = post.relations['tags']! as ManyToMany<Tag>;
      expect(m2m.pivotType, PostTag);
      expect(m2m.thisForeignKey, 'postId');
      expect(m2m.otherForeignKey, 'tagId');
    });

    test('.names feeds withRelated', () {
      expect([Blog.postsRel, Blog.pinnedRel].names, ['posts', 'pinned']);
    });
  });

  group('loading and fetching through the engine', () {
    late DatumManager<Blog> blogs;
    late DatumManager<Post> posts;

    setUp(() async {
      final connectivity = MockConnectivityChecker();
      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivity,
        registrations: [
          DatumRegistration<Blog>(
            localAdapter: MockLocalAdapter<Blog>(fromJson: Blog.fromMap),
            remoteAdapter: MockRemoteAdapter<Blog>(fromJson: Blog.fromMap),
          ),
          DatumRegistration<Post>(
            localAdapter: MockLocalAdapter<Post>(fromJson: Post.fromMap),
            remoteAdapter: MockRemoteAdapter<Post>(fromJson: Post.fromMap),
          ),
          DatumRegistration<Tag>(
            localAdapter: MockLocalAdapter<Tag>(fromJson: Tag.fromMap),
            remoteAdapter: MockRemoteAdapter<Tag>(fromJson: Tag.fromMap),
          ),
          DatumRegistration<PostTag>(
            localAdapter: MockLocalAdapter<PostTag>(fromJson: PostTag.fromMap),
            remoteAdapter: MockRemoteAdapter<PostTag>(fromJson: PostTag.fromMap),
          ),
        ],
      );
      expect(result.isSuccess(), isTrue, reason: '${result.errorOrNull}');
      blogs = Datum.manager<Blog>();
      posts = Datum.manager<Post>();

      await blogs.push(item: Blog(id: 'b1', title: 'datum'), userId: 'u1');
      await posts.saveMany(items: [
        Post(id: 'p1', blogId: 'b1', body: 'one'),
        Post(id: 'p2', blogId: 'b1', body: 'two'),
      ], userId: 'u1');
      await Datum.manager<Tag>().saveMany(items: [
        Tag(id: 'g1', label: 'dart'),
        Tag(id: 'g2', label: 'sync'),
      ], userId: 'u1');
      await Datum.manager<PostTag>().saveMany(items: [
        PostTag(id: 'l1', postId: 'p1', tagId: 'g1'),
        PostTag(id: 'l2', postId: 'p1', tagId: 'g2'),
        PostTag(id: 'l3', postId: 'p2', tagId: 'g2'),
      ], userId: 'u1');
    });

    tearDown(() => Datum.instance.dispose());

    test('eager loading with typed names, typed access with bound name + type', () async {
      final blog = (await blogs.read('b1', userId: 'u1', withRelated: [Blog.postsRel].names))!;
      final loaded = Blog.postsRel.listOf(blog);
      expect(loaded?.map((p) => p.id).toSet(), {'p1', 'p2'});

      final post = (await posts.read('p1', userId: 'u1', withRelated: [Post.blogRel].names))!;
      expect(Post.blogRel.oneOf(post)?.title, 'datum');
    });

    test('lazy typed fetching resolves through registered managers', () async {
      final blog = (await blogs.read('b1', userId: 'u1'))!;
      expect(Blog.postsRel.listOf(blog), isNull, reason: 'nothing eager-loaded');
      final fetched = await Blog.postsRel.fetchListFor(blog);
      expect(fetched.map((p) => p.id).toSet(), {'p1', 'p2'});
      expect(Blog.postsRel.listOf(blog)?.length, 2, reason: 'fetch caches onto the relation');

      final post = (await posts.read('p2', userId: 'u1'))!;
      final parent = await Post.blogRel.fetchOneFor(post);
      expect(parent?.title, 'datum');
    });

    test('many-to-many loads eagerly and fetches lazily through the pivot', () async {
      final tagged = (await posts.read('p1', userId: 'u1', withRelated: [Post.tagsRel].names))!;
      expect(Post.tagsRel.listOf(tagged)?.map((t) => t.label).toSet(), {'dart', 'sync'});

      final lazy = (await posts.read('p2', userId: 'u1'))!;
      expect(Post.tagsRel.listOf(lazy), isNull);
      final tags = await Post.tagsRel.fetchListFor(lazy);
      expect(tags.map((t) => t.label).toList(), ['sync']);
    });

    test('a spec used against the wrong relation fails with guidance', () async {
      final post = (await posts.read('p1', userId: 'u1'))!;
      final wrongName = DatumRelationSpec<Post, Blog>.hasMany('ghosts', foreignKey: Blog.titleField);
      await expectLater(
        wrongName.fetchListFor(post),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('"ghosts"'))),
      );
      await expectLater(
        DatumRelationSpec<Post, Blog>.hasOne('ghosts', foreignKey: Blog.titleField).fetchOneFor(post),
        throwsA(isA<StateError>()),
      );
    });
  });
}
