import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

import 'non_relational_test_entity.dart';

// Helper function to create a properly stubbed MockConnectivityChecker
MockConnectivityChecker createMockConnectivityChecker() {
  final checker = MockConnectivityChecker();
  when(() => checker.isConnected).thenAnswer((_) async => true);
  when(() => checker.onStatusChange).thenAnswer((_) => Stream.value(true));
  return checker;
}

class MockDatumManager<T extends DatumEntityInterface> extends Mock implements DatumManager<T> {}

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

  @override
  List<Object?> get props => [
        ...super.props,
        name,
      ];

  User({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id; // For users, userId is often the same as id

  late final Map<String, Relation> _relations = {
    'posts': HasMany<Post>(this, 'userId'), // A user has many posts.
    'profile': HasOne<Profile>(this, 'userId'), // A user has one profile.
  };

  @override
  Map<String, Relation> get relations => _relations;

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
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

/// A Post entity that "belongs to" a User.
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

  @override
  List<Object?> get props => [
        ...super.props,
        title,
      ];

  Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  factory Post.fromMap(Map<String, dynamic> map) {
    return Post(
      id: map['id'] as String,
      userId: map['userId'] as String,
      title: map['title'] as String,
      modifiedAt: DateTime.parse(map['modifiedAt'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
      version: map['version'] as int? ?? 1,
      isDeleted: map['isDeleted'] as bool? ?? false,
    );
  }

  // Define the relationship
  late final Map<String, Relation> _relations = {
    'author': BelongsTo<User>(this, 'userId'),
  };
  
  @override
  Map<String, Relation> get relations => _relations;

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
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! Post) return toDatumMap();

    final diff = <String, dynamic>{};

    if (title != oldVersion.title) {
      diff['title'] = title;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
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

  @override
  List<Object?> get props => [
        ...super.props,
        bio,
      ];

  Profile({
    required this.id,
    required this.userId,
    required this.bio,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  // Define the relationship
  late final Map<String, Relation> _relations = {
    'user': BelongsTo<User>(this, 'userId')
  };

  @override
  Map<String, Relation> get relations => _relations;

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
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! Profile) return toDatumMap();

    final diff = <String, dynamic>{};

    if (bio != oldVersion.bio) {
      diff['bio'] = bio;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// A pivot entity for ManyToMany relationships.
class PostTag extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String postId;
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
  List<Object?> get props => [
        ...super.props,
        postId,
        tagId,
      ];

  const PostTag({
    required this.id,
    required this.userId,
    required this.postId,
    required this.tagId,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {}; // Pivot entities typically don't have relations

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'postId': postId,
        'tagId': tagId,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  PostTag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    return PostTag(
      id: id,
      userId: userId,
      postId: postId,
      tagId: tagId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

/// A Tag entity for ManyToMany relationships.
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

  @override
  List<Object?> get props => [
        ...super.props,
        name,
      ];

  Tag({
    required this.id,
    required this.userId,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  late final Map<String, Relation> _relations = {
    'posts': ManyToMany(this, PostTag, 'tagId', 'postId'), // ManyToMany with posts through PostTag
  };

  @override
  Map<String, Relation> get relations => _relations;

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
  Tag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    return Tag(
      id: id,
      userId: userId,
      name: name,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

/// A local adapter that intentionally does not implement fetchRelated.
class _UnimplementedLocalAdapter<T extends DatumEntityInterface> extends LocalAdapter<T> {
  @override
  Future<List<R>> fetchRelated<R extends DatumEntityInterface>(
    RelationalDatumEntity parent,
    String relationName,
    LocalAdapter<R> relatedAdapter,
  ) {
    // By inheriting from LocalAdapter directly and not implementing this,
    // calling super will hit the base implementation that throws.
    return super.fetchRelated(parent, relationName, relatedAdapter);
  }

  @override
  Stream<List<R>>? watchRelated<R extends DatumEntityInterface>(
    RelationalDatumEntity parent,
    String relationName,
    LocalAdapter<R> relatedAdapter,
  ) {
    // By inheriting from LocalAdapter directly and not implementing this,
    // calling super will hit the base implementation that throws.
    return super.watchRelated(parent, relationName, relatedAdapter);
  }

  // --- Stub implementations for all other abstract methods ---
  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<T> operation,
  ) async {}
  @override
  Stream<DatumChangeDetail<T>>? changeStream() => null;
  @override
  Future<void> clear() async {}
  @override
  Future<void> clearUserData(String userId) async {}
  @override
  Future<void> create(T entity) async {}
  @override
  Future<bool> delete(String id, {String? userId}) async => true;
  @override
  Future<void> dispose() async {}
  @override
  Future<List<String>> getAllUserIds() async => [];
  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async => [];
  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(
    String userId,
  ) async =>
      [];
  @override
  Future<int> getStoredSchemaVersion() async => 0;
  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) async {}
  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) =>
      throw UnimplementedError();
  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async => [];
  @override
  Future<T?> read(String id, {String? userId}) async => null;
  @override
  Future<List<T>> readAll({String? userId}) async => [];
  @override
  Future<PaginatedResult<T>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) async =>
      PaginatedResult<T>.empty();
  @override
  Future<Map<String, T>> readByIds(
    List<String> ids, {
    required String userId,
  }) async =>
      {};
  @override
  Future<void> removePendingOperation(String operationId) async {}
  @override
  Future<void> setStoredSchemaVersion(int version) async {}
  @override
  Future<R> transaction<R>(Future<R> Function() action) => action();
  @override
  Future<void> update(T entity) async {}
  @override
  Future<void> updateSyncMetadata(
    DatumSyncMetadata metadata,
    String userId,
  ) async {}

  @override
  Future<int> getStorageSize({String? userId}) {
    throw UnimplementedError();
  }

  @override
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) {
    throw UnimplementedError();
  }

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<T> result) {
    throw UnimplementedError();
  }
}

void main() {
  group('Relational Data: fetchRelated', () {
    late DatumManager<User> userManager;
    late DatumManager<Post> postManager;

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

    setUpAll(() {
      registerFallbackValue(
        User(
          id: 'fb',
          name: 'fb',
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
        ),
      );
      registerFallbackValue(
        Post(
          id: 'fb',
          userId: 'fb',
          title: 'fb',
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
        ),
      );
      registerFallbackValue(
        Profile(
          id: 'fb',
          userId: 'fb',
          bio: 'fb',
          modifiedAt: DateTime(0),
          createdAt: DateTime(0),
        ),
      );
    });

    setUp(() async {
      // Initialization will be handled by each test individually.
      Datum.resetForTesting();
    });

    test(
      'isRelational property returns true for RelationalDatumEntity and false for DatumEntity',
      () async {
        final relationalEntity = User(
          id: 'relational-1',
          name: 'Relational User',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        final nonRelationalEntity = NonRelationalTestEntity(
          id: 'non-relational-1',
          userId: 'user-1',
          name: 'Some data',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );

        expect(relationalEntity.isRelational, isTrue);
        expect(nonRelationalEntity.isRelational, isFalse);
      },
    );

    test('fetches "belongsTo" related entities successfully', () async {
      // Initialize Datum for this test
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: createMockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: MockLocalAdapter<User>()..addLocalItem(testUser.id, testUser),
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: MockLocalAdapter<Post>()..addLocalItem(testUser.id, testPost),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
        ],
      );
      userManager = Datum.manager<User>();
      postManager = Datum.manager<Post>();

      // Act: Fetch the 'author' for the post.
      final authors = await postManager.fetchRelated<User>(testPost, 'author');

      // Assert
      expect(authors, isNotEmpty);
      expect(authors.length, 1);
      expect(authors.first.id, testUser.id);
      expect(authors.first.name, 'John Doe');
    });

    test('fetches "hasMany" related entities successfully', () async {
      // Arrange: Create one user and two posts belonging to that user.
      final post2 = Post(
        id: 'post-2',
        userId: 'user-1',
        title: 'My Second Post',
        modifiedAt: DateTime(2023, 2),
        createdAt: DateTime(2023, 2),
      );

      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: createMockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: MockLocalAdapter<User>()..addLocalItem(testUser.id, testUser),
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: MockLocalAdapter<Post>()
              ..addLocalItem(testUser.id, testPost)
              ..addLocalItem(testUser.id, post2),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
        ],
      );

      userManager = Datum.manager<User>();
      postManager = Datum.manager<Post>();

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

    test('fetches a "hasOne" related entity successfully', () async {
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: createMockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: MockLocalAdapter<User>()..addLocalItem(testUser.id, testUser),
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Profile>(
            localAdapter: MockLocalAdapter<Profile>()..addLocalItem(testUser.id, testProfile),
            remoteAdapter: MockRemoteAdapter<Profile>(),
          ),
        ],
      );

      userManager = Datum.manager<User>();

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

    test('returns an empty list if related entity does not exist', () async {
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: createMockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: MockLocalAdapter<User>(), // Empty user adapter
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: MockLocalAdapter<Post>()..addLocalItem(testUser.id, testPost),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
        ],
      );

      postManager = Datum.manager<Post>();

      // Act: Fetch the 'author' for the post.
      final authors = await postManager.fetchRelated<User>(testPost, 'author');

      // Assert
      expect(authors, isEmpty);
    });

    test('throws an exception for an invalid relation name', () async {
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: createMockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: MockLocalAdapter<User>(), // Not needed for this test
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: MockLocalAdapter<Post>()..addLocalItem(testUser.id, testPost),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
        ],
      );

      postManager = Datum.manager<Post>();

      // Act & Assert
      expect(
        () => postManager.fetchRelated<User>(testPost, 'invalid_relation'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            contains('is not defined on entity type Post'),
          ),
        ),
      );
    });

    test(
      'throws an ArgumentError if parent is not a RelationalDatumEntity',
      () async {
        // Arrange: Initialize Datum before using it.
        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: createMockConnectivityChecker(),
        );
        // Arrange: Initialize with a non-relational entity type.
        await Datum.instance.register(
          registration: DatumRegistration<NonRelationalTestEntity>(
            localAdapter: MockLocalAdapter<NonRelationalTestEntity>(),
            remoteAdapter: MockRemoteAdapter<NonRelationalTestEntity>(),
          ),
        );

        // Act & Assert
        expect(
          () => Datum.manager<NonRelationalTestEntity>().fetchRelated<User>(
            NonRelationalTestEntity.create('id', 'uid', 'name'),
            'posts',
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'throws UnimplementedError if local adapter does not implement fetchRelated',
      () async {
        // Arrange: Initialize a fresh Datum instance with the special adapter.
        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: createMockConnectivityChecker(),
          registrations: [
            DatumRegistration<Post>(
              localAdapter: _UnimplementedLocalAdapter<Post>(),
              remoteAdapter: MockRemoteAdapter<Post>(),
            ),
            DatumRegistration<User>(
              localAdapter: MockLocalAdapter<User>(),
              remoteAdapter: MockRemoteAdapter<User>(),
            ),
          ],
        );
        final postManagerWithUnimplementedAdapter = Datum.manager<Post>();

        // Act & Assert
        expect(
          () => postManagerWithUnimplementedAdapter.fetchRelated<User>(
            testPost,
            'author',
            source: DataSource.local,
          ),
          throwsA(isA<UnimplementedError>()),
        );
      },
      // This test needs to run after the main setup has completed.
    );

    test(
      'throws UnimplementedError if local adapter does not implement watchRelated',
      () async {
        // Arrange: Initialize a fresh Datum instance with the special adapter.
        await Datum.initialize(
          config: const DatumConfig(enableLogging: false),
          connectivityChecker: createMockConnectivityChecker(),
          registrations: [
            DatumRegistration<Post>(
              localAdapter: _UnimplementedLocalAdapter<Post>(),
              remoteAdapter: MockRemoteAdapter<Post>(),
            ),
            DatumRegistration<User>(
              localAdapter: MockLocalAdapter<User>(),
              remoteAdapter: MockRemoteAdapter<User>(),
            ),
          ],
        );
        final postManagerWithUnimplementedAdapter = Datum.manager<Post>();

        // Act & Assert
        expect(
          () => postManagerWithUnimplementedAdapter.watchRelated<User>(
            testPost,
            'author',
          ),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );
  });

  group('Relational Data: query', () {
    late User testUser;
    late Post testPost;
    late DatumManager<User> userManager;
    late DatumManager<Post> postManager;

    setUp(() {
      Datum.resetForTesting();

      testUser = User(
        id: 'user-1',
        name: 'Kiddo V',
        modifiedAt: DateTime(2026, 3, 31),
        createdAt: DateTime(2026, 3, 31),
      );

      testPost = Post(
        id: 'post-1',
        userId: 'user-1',
        title: 'My First Post',
        modifiedAt: DateTime(2026, 3, 31),
        createdAt: DateTime(2026, 3, 31),
      );
    });

    tearDown(() {
      Datum.resetForTesting();
    });
    test('query supports nested relation field (author.name)', () async {
      // Arrange
      await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: createMockConnectivityChecker(),
        registrations: [
          DatumRegistration<User>(
            localAdapter: MockLocalAdapter<User>()..addLocalItem(testUser.id, testUser),
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: MockLocalAdapter<Post>()..addLocalItem(testUser.id, testPost),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
        ],
      );

      userManager = Datum.manager<User>();
      postManager = Datum.manager<Post>();

      // Test 1: make sure data exists
      final users = await userManager.readAll(userId: testUser.userId);
      final posts = await postManager.readAll(userId: testUser.userId);
      expect(users, isNotEmpty, reason: 'Users should exist in local adapter');
      expect(posts, isNotEmpty, reason: 'Posts should exist in local adapter');

      // Test 2: query with nested relation
      final usersWithPosts = await userManager.query(
        const DatumQuery(
          withRelated: ['posts', 'posts.author'],
        ),
        source: DataSource.local,
        userId: testUser.id,
      );
      final postsWithAuthors = usersWithPosts.first.relations['posts']?.value as List<Post>?;
      final author = postsWithAuthors?.first.relations['author']?.value;
      expect(postsWithAuthors?.length, 1, reason: 'Should find 1 post');
      expect(author, isNotNull, reason: 'Post author should exist');
    });
  });
}
