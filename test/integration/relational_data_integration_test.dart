// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:test/test.dart';

import 'package:datum/datum.dart';

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

  const User({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id; // For users, userId is often the same as id

  @override
  Map<String, Relation> get relations => {
        'posts': const HasMany('userId'), // A user has many posts.
        'profile': const HasOne('userId'), // A user has one profile.
      };

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

  @override
  bool operator ==(covariant User other) {
    if (identical(this, other)) return true;

    return other.id == id && other.userId == userId && other.name == name && other.modifiedAt == modifiedAt && other.createdAt == createdAt && other.version == version && other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ name.hashCode ^ modifiedAt.hashCode ^ createdAt.hashCode ^ version.hashCode ^ isDeleted.hashCode;
  }
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

  const Post({
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
        'author': const BelongsTo('userId'),
        'tags': ManyToMany(PostTag.constInstance, 'postId', 'tagId'),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;

  @override
  Post copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? modifiedAt,
    DateTime? createdAt,
    int? version,
    bool? isDeleted,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(covariant Post other) {
    if (identical(this, other)) return true;

    return other.id == id && other.userId == userId && other.title == title && other.modifiedAt == modifiedAt && other.createdAt == createdAt && other.version == version && other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ title.hashCode ^ modifiedAt.hashCode ^ createdAt.hashCode ^ version.hashCode ^ isDeleted.hashCode;
  }
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

  const Tag({
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
  Tag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;

  @override
  bool operator ==(covariant Tag other) {
    if (identical(this, other)) return true;

    return other.id == id && other.userId == userId && other.name == name && other.modifiedAt == modifiedAt && other.createdAt == createdAt && other.version == version && other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ name.hashCode ^ modifiedAt.hashCode ^ createdAt.hashCode ^ version.hashCode ^ isDeleted.hashCode;
  }
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

  const PostTag({
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
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'postId': postId,
        'tagId': tagId,
      };

  @override
  PostTag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}

/// A Profile entity that "belongs to" a User.
class Profile extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId; // This is the foreign key to the User entity
  final String bio;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Profile({
    required this.id,
    required this.userId,
    required this.bio,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  // Define the relationship
  @override
  Map<String, Relation> get relations => {'user': const BelongsTo('userId')};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'bio': bio,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Profile copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? bio,
  }) {
    return Profile(
      id: id,
      userId: userId,
      bio: bio ?? this.bio,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}

void main() {
  group('Relational Data Integration Tests', () {
    late DatumManager<User> userManager;
    late DatumManager<Post> postManager;
    late DatumManager<Tag> tagManager;
    late DatumManager<Profile> profileManager;
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

    final testProfile = Profile(
      id: 'profile-1',
      userId: 'user-1', // Foreign key linking to testUser
      bio: 'Loves Dart and Flutter.',
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
      // Create all mock adapters first, providing related adapters where needed.
      final userAdapter = MockLocalAdapter<User>();
      final profileAdapter = MockLocalAdapter<Profile>();
      final postTagAdapter = MockLocalAdapter<PostTag>();
      final postAdapter = MockLocalAdapter<Post>(
        relatedAdapters: {PostTag: postTagAdapter},
      );
      final tagAdapter = MockLocalAdapter<Tag>(
        relatedAdapters: {PostTag: postTagAdapter},
      );

      Datum.resetForTesting();
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: MockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: userAdapter,
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: postAdapter,
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
          DatumRegistration<Tag>(
            localAdapter: tagAdapter,
            remoteAdapter: MockRemoteAdapter<Tag>(),
          ),
          DatumRegistration<Profile>(
            localAdapter: profileAdapter,
            remoteAdapter: MockRemoteAdapter<Profile>(),
          ),
          DatumRegistration<PostTag>(
            localAdapter: postTagAdapter,
            remoteAdapter: MockRemoteAdapter<PostTag>(),
          ),
        ],
      );
      userManager = Datum.manager<User>();
      postManager = Datum.manager<Post>();
      tagManager = Datum.manager<Tag>();
      profileManager = Datum.manager<Profile>();
      postTagManager = Datum.manager<PostTag>();
    });

    tearDown(() {
      Datum.resetForTesting();
    });

    test(
      'fetches "belongsTo" related entity successfully from local',
      () async {
        // Arrange: Add both the user and the post to the local store.
        await userManager.push(item: testUser, userId: testUser.id);
        await postManager.push(item: testPost, userId: testUser.id);

        // Act: Fetch the 'author' for the post.
        final authors = await postManager.fetchRelated<User>(
          testPost,
          'author',
        );

        // Assert
        expect(authors, isNotEmpty);
        expect(authors.length, 1);
        expect(authors.first.id, testUser.id);
        expect(authors.first.name, 'John Doe');
      },
    );

    test(
      'fetches "belongsTo" related entity successfully from remote',
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
        final authors = await postManager.fetchRelated<User>(
          testPost,
          'author',
          source: DataSource.remote,
        );

        // Assert
        expect(authors, isNotEmpty);
        expect(authors.length, 1);
        expect(authors.first.id, testUser.id);
      },
    );

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

    test(
      'fetches "hasMany" related entities successfully from local',
      () async {
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
      },
    );

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

    test('fetches "hasOne" related entity successfully from local', () async {
      // Arrange: Add both the user and their profile to the local store.
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);

      // Act: Fetch the 'profile' for the user.
      final profiles = await userManager.fetchRelated<Profile>(
        testUser,
        'profile',
      );

      // Assert
      expect(profiles, isNotEmpty);
      expect(profiles.length, 1);
      expect(profiles.first.id, testProfile.id);
      expect(profiles.first.bio, 'Loves Dart and Flutter.');
    });

    test('fetches "hasOne" related entity successfully from remote', () async {
      // Arrange: Add the user and profile to the remote mock adapters.
      (userManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
        testUser.id,
        testUser,
      );
      (profileManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
        testUser.id,
        testProfile,
      );

      // Act: Fetch the 'profile' for the user from the remote source.
      final profiles = await userManager.fetchRelated<Profile>(
        testUser,
        'profile',
        source: DataSource.remote,
      );

      // Assert
      expect(profiles, isNotEmpty);
      expect(profiles.length, 1);
      expect(profiles.first.id, testProfile.id);
    });

    test(
      'returns an empty list for "hasMany" when no related entities exist',
      () async {
        // Arrange: Add a user but no posts.
        await userManager.push(item: testUser, userId: testUser.id);

        // Act: Fetch the 'posts' for the user.
        final posts = await userManager.fetchRelated<Post>(testUser, 'posts');

        // Assert
        expect(posts, isEmpty);
      },
    );

    test(
      'returns an empty list for "belongsTo" when foreign key is non-existent',
      () async {
        // Arrange: Add a post with a foreign key that doesn't match any user.
        final postWithOrphanFk = testPost.copyWith(userId: 'non-existent-user');
        await postManager.push(item: postWithOrphanFk, userId: testUser.id);

        // Act: Fetch the 'author' for the post.
        final authors = await postManager.fetchRelated<User>(
          postWithOrphanFk,
          'author',
        );

        // Assert
        expect(authors, isEmpty);
      },
    );

    test(
      'returns an empty list for "manyToMany" when no pivot entries exist',
      () async {
        // Arrange: Add a post and tags, but no PostTag entries to link them.
        await postManager.push(item: testPost, userId: testUser.id);
        await tagManager.push(item: tag1, userId: testUser.id);
        await tagManager.push(item: tag2, userId: testUser.id);

        // Act: Fetch the 'tags' for the post.
        final tags = await postManager.fetchRelated<Tag>(testPost, 'tags');

        // Assert
        expect(tags, isEmpty);
      },
    );

    test(
      'returns an empty list for "manyToMany" from remote when no pivot entries exist',
      () async {
        // Arrange: Add post and tags to remote, but no pivot entries.
        (postManager.remoteAdapter as MockRemoteAdapter).addRemoteItem(
          testUser.id,
          testPost,
        );
        (tagManager.remoteAdapter as MockRemoteAdapter)
          ..addRemoteItem(testUser.id, tag1)
          ..addRemoteItem(testUser.id, tag2);

        // Act: Fetch the 'tags' for the post from the remote source.
        final tags = await postManager.fetchRelated<Tag>(
          testPost,
          'tags',
          source: DataSource.remote,
        );

        // Assert
        expect(tags, isEmpty);
      },
    );

    test(
      'fetches "hasMany" correctly after a related entity is deleted',
      () async {
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

        // Act: Delete one of the posts.
        await postManager.delete(id: testPost.id, userId: testUser.id);

        // Assert: Fetch the 'posts' for the user again.
        final posts = await userManager.fetchRelated<Post>(testUser, 'posts');
        expect(posts, isNotEmpty);
        expect(posts.length, 1);
        expect(posts.first.id, 'post-2');
      },
    );

    test(
      'fetches "belongsTo" correctly after the parent entity is deleted',
      () async {
        // Arrange: Add both the user and the post to the local store.
        await userManager.push(item: testUser, userId: testUser.id);
        await postManager.push(item: testPost, userId: testUser.id);

        // Pre-Assert: Ensure the relationship exists before deletion.
        final initialAuthors = await postManager.fetchRelated<User>(testPost, 'author');
        expect(initialAuthors, isNotEmpty);

        // Act: Delete the user (the "parent" in the belongsTo relationship).
        await userManager.delete(id: testUser.id, userId: testUser.id);

        // Assert: Fetching the author for the post should now return an empty list.
        final authorsAfterDelete = await postManager.fetchRelated<User>(testPost, 'author');
        expect(authorsAfterDelete, isEmpty);
      },
    );

    test(
      'fetches "manyToMany" correctly after a pivot entry is deleted',
      () async {
        // Arrange: Add the post, tags, and pivot entries to the local store.
        await postManager.push(item: testPost, userId: testUser.id);
        await tagManager.push(item: tag1, userId: testUser.id);
        await tagManager.push(item: tag2, userId: testUser.id);
        await postTagManager.push(item: postTag1, userId: postTag1.userId);
        await postTagManager.push(item: postTag2, userId: postTag2.userId);

        // Pre-Assert: Ensure both tags are related initially.
        final initialTags = await postManager.fetchRelated<Tag>(testPost, 'tags');
        expect(initialTags, hasLength(2));

        // Act: Delete one of the pivot table entries (the link between post and tag).
        await postTagManager.delete(id: postTag1.id, userId: postTag1.userId);

        // Assert: Fetching the tags for the post should now only return one tag.
        final tagsAfterDelete = await postManager.fetchRelated<Tag>(testPost, 'tags');
        expect(tagsAfterDelete, hasLength(1));
        expect(tagsAfterDelete.first.id, 'tag-2');
      },
    );
  });
}
