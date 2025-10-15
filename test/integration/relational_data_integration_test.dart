import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

/// A simple User entity for testing relationships.
class User extends RelationalDatumEntity {
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

  User({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id; // For users, userId is often the same as id

  @override
  Map<String, Relation> get relations => {'posts': HasMany('userId')}; // A user has many posts.

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'userId': userId,
    'name': name,
    'modifiedAt': modifiedAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'isDeleted': isDeleted,
  };

  @override
  User copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    return User(
      id: id,
      name: name,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}

/// A Post entity that "belongs to" a User and has a many-to-many with Tag.
class Post extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId; // This is the foreign key to the User entity
  final String title;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  // Define the relationships
  @override
  Map<String, Relation> get relations => {
    'author': BelongsTo('userId'),
    'tags': ManyToMany(PostTag.constInstance, 'postId', 'tagId'),
  };

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'userId': userId,
    'title': title,
    'modifiedAt': modifiedAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'isDeleted': isDeleted,
  };

  @override
  Post copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    return Post(
      id: id,
      userId: userId,
      title: title,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}

/// A Tag entity for the many-to-many relationship.
class Tag extends RelationalDatumEntity {
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

  Tag({
    required this.id,
    required this.userId,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
    'posts': ManyToMany(PostTag.constInstance, 'tagId', 'postId'),
  };

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'userId': userId,
    'name': name,
    'modifiedAt': modifiedAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'isDeleted': isDeleted,
  };

  @override
  Tag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}

/// The pivot entity for the Post-Tag many-to-many relationship.
class PostTag extends RelationalDatumEntity {
  final String postId;
  final String tagId;

  @override
  final String id;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;

  PostTag({
    required this.id,
    required this.postId,
    required this.tagId,
    required this.modifiedAt,
    required this.createdAt,
  });

  @override
  String get userId => 'pivot_user';
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  static final constInstance = PostTag(
    id: '',
    postId: '',
    tagId: '',
    modifiedAt: DateTime.fromMicrosecondsSinceEpoch(0),
    createdAt: DateTime.fromMicrosecondsSinceEpoch(0),
  );

  @override
  Map<String, Relation> get relations => {};

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'postId': postId,
    'tagId': tagId,
  };

  @override
  PostTag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      this;

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}

void main() {
  group('Relational Data Integration Tests', () {
    late DatumManager<User> userManager;
    late DatumManager<Post> postManager;
    late DatumManager<Tag> tagManager;
    late DatumManager<PostTag> postTagManager;

    final testUser = User(
      id: 'user-1',
      name: 'John Doe',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testPost = Post(
      id: 'post-1',
      userId: 'user-1', // Foreign key linking to testUser
      title: 'My First Post',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final tag1 = Tag(
      id: 'tag-1',
      userId: 'user-1',
      name: 'Flutter',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );
    final tag2 = Tag(
      id: 'tag-2',
      userId: 'user-1',
      name: 'Dart',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final postTag1 = PostTag(
      id: 'pt-1',
      postId: 'post-1',
      tagId: 'tag-1',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );
    final postTag2 = PostTag(
      id: 'pt-2',
      postId: 'post-1',
      tagId: 'tag-2',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    setUp(() async {
      Datum.resetForTesting();
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: MockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: MockLocalAdapter<User>(),
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: MockLocalAdapter<Post>(),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
          DatumRegistration<Tag>(
            localAdapter: MockLocalAdapter<Tag>(),
            remoteAdapter: MockRemoteAdapter<Tag>(),
          ),
          DatumRegistration<PostTag>(
            localAdapter: MockLocalAdapter<PostTag>(),
            remoteAdapter: MockRemoteAdapter<PostTag>(),
          ),
        ],
      );
      userManager = Datum.manager<User>();
      postManager = Datum.manager<Post>();
      tagManager = Datum.manager<Tag>();
      postTagManager = Datum.manager<PostTag>();
    });

    tearDown(() {
      Datum.resetForTesting();
    });

    test('fetches "belongsTo" related entity successfully from local', () async {
      // Arrange: Add both the user and the post to the local store.
      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost, userId: testUser.id);

      // Act: Fetch the 'author' for the post.
      final authors = await postManager.fetchRelated<User>(testPost, 'author');

      // Assert
      expect(authors, isNotEmpty);
      expect(authors.length, 1);
      expect(authors.first.id, testUser.id);
      expect(authors.first.name, 'John Doe');
    });

    test('fetches "belongsTo" related entity successfully from remote',
        () async {
      // Arrange: Add the user and post to the remote mock adapters.
      (userManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
        testUser.id,
        testUser,
      );
      (postManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
        testUser.id,
        testPost,
      );

      // Act: Fetch the 'author' for the post from the remote source.
      final authors =
          await postManager.fetchRelated<User>(testPost, 'author', source: DataSource.remote);

      // Assert
      expect(authors, isNotEmpty);
      expect(authors.length, 1);
      expect(authors.first.id, testUser.id);
    });

    test(
      'fetches "manyToMany" related entities successfully from local',
      () async {
        // Arrange: Add the post, tags, and pivot entries to the local store.
        await postManager.push(item: testPost, userId: testUser.id);
        await tagManager.push(item: tag1, userId: testUser.id);
        await tagManager.push(item: tag2, userId: testUser.id);
        await postTagManager.push(item: postTag1, userId: testUser.id);
        await postTagManager.push(item: postTag2, userId: testUser.id);

        // Act: Fetch the 'tags' for the post.
        final tags = await postManager.fetchRelated<Tag>(testPost, 'tags');

        // Assert
        expect(tags, isNotEmpty);
        expect(tags.length, 2);
        expect(tags.map((t) => t.id), containsAll(['tag-1', 'tag-2']));
        expect(tags.map((t) => t.name), containsAll(['Flutter', 'Dart']));
      },
    );

    test('fetches "hasMany" related entities successfully from local', () async {
      // Arrange: Create one user and two posts belonging to that user.
      final post2 = Post(
        id: 'post-2',
        userId: 'user-1',
        title: 'My Second Post',
        modifiedAt: DateTime(2023, 2),
        createdAt: DateTime(2023, 2),
      );
      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost, userId: testUser.id);
      await postManager.push(item: post2, userId: testUser.id);

      // Act: Fetch the 'posts' for the user.
      final posts = await userManager.fetchRelated<Post>(testUser, 'posts');

      // Assert
      expect(posts, isNotEmpty);
      expect(posts.length, 2);
      expect(posts.map((p) => p.id), containsAll(['post-1', 'post-2']));
      expect(
        posts.map((p) => p.title),
        containsAll(['My First Post', 'My Second Post']),
      );
    });

    test(
      'fetches "hasMany" related entities successfully from remote',
      () async {
        // Arrange: Create one user and two posts belonging to that user.
        final post2 = Post(
          id: 'post-2',
          userId: 'user-1',
          title: 'My Second Post',
          modifiedAt: DateTime(2023, 2),
          createdAt: DateTime(2023, 2),
        );
        // Push data to the remote adapter directly for the test setup.
        (userManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
          testUser.id,
          testUser,
        );
        (postManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
          testUser.id,
          testPost,
        );
        (postManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
          testUser.id,
          post2,
        );

        // Act: Fetch the 'posts' for the user from the remote source.
        final posts = await userManager.fetchRelated<Post>(
          testUser,
          'posts',
          source: DataSource.remote,
        );

        // Assert
        expect(posts, isNotEmpty);
        expect(posts.length, 2);
        expect(posts.map((p) => p.id), containsAll(['post-1', 'post-2']));
      },
    );

    test(
      'fetches "manyToMany" related entities successfully from remote',
      () async {
        // Arrange: Add the post, tags, and pivot entries to the remote store.
        (postManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
          testUser.id,
          testPost,
        );
        (tagManager.remoteAdapter as MockRemoteAdapter)
          ..addRemoteItem(testUser.id, tag1)
          ..addRemoteItem(testUser.id, tag2);
        (postTagManager.remoteAdapter as MockRemoteAdapter)
          ..addRemoteItem(testUser.id, postTag1)
          ..addRemoteItem(testUser.id, postTag2);

        // Act: Fetch the 'tags' for the post from the remote source.
        final tags = await postManager.fetchRelated<Tag>(
          testPost,
          'tags',
          source: DataSource.remote,
        );

        // Assert
        expect(tags, isNotEmpty);
        expect(tags.length, 2);
        expect(tags.map((t) => t.id), containsAll(['tag-1', 'tag-2']));
        expect(
          tags.map((t) => t.name),
          containsAll(['Flutter', 'Dart']),
          reason: 'Should fetch both tags related to the post.',
        );
      },
    );
  });
}
