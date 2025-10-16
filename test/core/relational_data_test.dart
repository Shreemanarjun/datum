import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

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
  Map<String, Relation> get relations => {
    'posts': HasMany('userId'), // A user has many posts.
    'profile': HasOne('userId'), // A user has one profile.
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
  @override
  Map<String, Relation> get relations => {'author': BelongsTo('userId')};

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
  @override
  Map<String, Relation> get relations => {'user': BelongsTo('userId')};

  @override
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local}) => {
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

/// A local adapter that intentionally does not implement fetchRelated.
class _UnimplementedLocalAdapter<T extends DatumEntity>
    extends LocalAdapter<T> {
  @override
  Future<List<R>> fetchRelated<R extends DatumEntity>(
    RelationalDatumEntity parent,
    String relationName,
    LocalAdapter<R> relatedAdapter,
  ) {
    // By inheriting from LocalAdapter directly and not implementing this,
    // calling super will hit the base implementation that throws.
    return super.fetchRelated(parent, relationName, relatedAdapter);
  }

  @override
  Stream<List<R>>? watchRelated<R extends DatumEntity>(
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
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async =>
      [];
  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(
    String userId,
  ) async => [];
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
  }) => throw UnimplementedError();
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
  }) async => PaginatedResult<T>.empty();
  @override
  Future<Map<String, T>> readByIds(
    List<String> ids, {
    required String userId,
  }) async => {};
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
}

void main() {
  group('Relational Data: fetchRelated', () {
    late DatumManager<User> userManager;
    late DatumManager<Post> postManager;
    late DatumManager<Profile> profileManager;

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
          DatumRegistration<Profile>(
            localAdapter: MockLocalAdapter<Profile>(),
            remoteAdapter: MockRemoteAdapter<Profile>(),
          ),
        ],
      );
      userManager = Datum.manager<User>();
      postManager = Datum.manager<Post>();
      profileManager = Datum.manager<Profile>();
    });

    test('fetches a "belongsTo" related entity successfully', () async {
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

    test('fetches "hasMany" related entities successfully', () async {
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

    test('fetches a "hasOne" related entity successfully', () async {
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

    test('returns an empty list if related entity does not exist', () async {
      // Arrange: Add only the post, but not the user it belongs to.
      await postManager.push(item: testPost, userId: testUser.id);

      // Act: Fetch the 'author' for the post.
      final authors = await postManager.fetchRelated<User>(testPost, 'author');

      // Assert
      expect(authors, isEmpty);
    });

    test('throws an exception for an invalid relation name', () async {
      // Arrange
      await postManager.push(item: testPost, userId: testUser.id);

      // Act & Assert
      expect(
        () => postManager.fetchRelated<User>(testPost, 'invalid_relation'),
        throwsA(
          isA<Exception>().having(
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
        // Arrange: Create a manager for a non-relational entity type.
        await Datum.instance.register(
          registration: DatumRegistration<TestEntity>(
            localAdapter: MockLocalAdapter<TestEntity>(),
            remoteAdapter: MockRemoteAdapter<TestEntity>(),
          ),
        );

        // Act & Assert
        expect(
          () => Datum.manager<TestEntity>().fetchRelated<User>(
            TestEntity.create('id', 'uid', 'name'),
            'author',
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'throws UnimplementedError if local adapter does not implement fetchRelated',
      () async {
        // Arrange: Register a manager with an adapter that lacks the implementation.
        await Datum.instance.register(
          registration: DatumRegistration<Post>(
            localAdapter: _UnimplementedLocalAdapter<Post>(),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
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
        // Arrange: Register a manager with an adapter that lacks the implementation.
        await Datum.instance.register(
          registration: DatumRegistration<Post>(
            localAdapter: _UnimplementedLocalAdapter<Post>(),
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
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
}
