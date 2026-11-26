import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';

import 'package:test/test.dart';

part 'relationship_generation_test.g.dart';

// Test entities for relationship testing
@DatumSerializable(tableName: 'users')
class User extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId;

  final String name;
  final String email;

  // Relationship annotations
  @HasManyRelation<Post>('userId', cascadeDelete: 'cascade')
  final List<Post>? _posts = null;

  @HasOneRelation<Profile>('userId')
  final Profile? _profile = null;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  const User({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    return datumDiff(oldVersion);
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return datumToMap(target: target);
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return _$UserFromMap(map);
  }

  @override
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return copyWithAll(
      modifiedAt: modifiedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }

  @override
  Map<String, Relation> get relations => datumRelations;

  @override
  bool operator ==(Object other) => other is User && datumEquals(other);

  @override
  int get hashCode => datumHashCode;
}

@DatumSerializable(tableName: 'posts')
class Post extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId;

  final String title;
  final String content;

  // Relationship annotations
  @BelongsToRelation<User>('userId')
  final String? _author = null;

  @HasManyRelation<Comment>('postId', cascadeDelete: 'cascade')
  final List<Comment>? _comments = null;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  const Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    return datumDiff(oldVersion);
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return datumToMap(target: target);
  }

  factory Post.fromMap(Map<String, dynamic> map) {
    return _$PostFromMap(map);
  }

  @override
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return copyWithAll(
      modifiedAt: modifiedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }

  @override
  Map<String, Relation> get relations => datumRelations;

  @override
  bool operator ==(Object other) => other is Post && datumEquals(other);

  @override
  int get hashCode => datumHashCode;
}

@DatumSerializable(tableName: 'comments')
class Comment extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId;

  final String postId;
  final String content;

  // Relationship annotation
  @BelongsToRelation<Post>('postId', cascadeDelete: 'restrict')
  final String? _post = null;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  const Comment({
    required this.id,
    required this.userId,
    required this.postId,
    required this.content,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    return datumDiff(oldVersion);
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return datumToMap(target: target);
  }

  factory Comment.fromMap(Map<String, dynamic> map) {
    return _$CommentFromMap(map);
  }

  @override
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return copyWithAll(
      modifiedAt: modifiedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }

  @override
  Map<String, Relation> get relations => datumRelations;

  @override
  bool operator ==(Object other) => other is Comment && datumEquals(other);

  @override
  int get hashCode => datumHashCode;
}

@DatumSerializable(tableName: 'profiles')
class Profile extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId;

  final String bio;
  final String? avatarUrl;

  // Relationship annotation
  @BelongsToRelation<User>('userId')
  final String? _user = null;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  const Profile({
    required this.id,
    required this.userId,
    required this.bio,
    this.avatarUrl,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    return datumDiff(oldVersion);
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return datumToMap(target: target);
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return _$ProfileFromMap(map);
  }

  @override
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return copyWithAll(
      modifiedAt: modifiedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }

  @override
  Map<String, Relation> get relations => datumRelations;

  @override
  bool operator ==(Object other) => other is Profile && datumEquals(other);

  @override
  int get hashCode => datumHashCode;
}

void main() {
  group('Relationship Generation - HasMany', () {
    test('should generate HasMany relation from annotation', () {
      final user = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(user.relations, isNotEmpty);
      expect(user.relations.containsKey('posts'), isTrue);

      final postsRelation = user.relations['posts'] as HasMany<Post>;
      expect(postsRelation, isA<HasMany<Post>>());
      expect(postsRelation.foreignKey, equals('user_id'));
      expect(postsRelation.localKey, equals('id'));
      expect(
        postsRelation.cascadeDeleteBehavior,
        equals(CascadeDeleteBehavior.cascade),
      );
    });

    test('should strip leading underscore from field name', () {
      final user = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      // Field is _posts, but relation name should be 'posts'
      expect(user.relations.containsKey('_posts'), isFalse);
      expect(user.relations.containsKey('posts'), isTrue);
    });
  });

  group('Relationship Generation - HasOne', () {
    test('should generate HasOne relation from annotation', () {
      final user = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(user.relations.containsKey('profile'), isTrue);

      final profileRelation = user.relations['profile'] as HasOne<Profile>;
      expect(profileRelation, isA<HasOne<Profile>>());
      expect(profileRelation.foreignKey, equals('user_id'));
      expect(profileRelation.localKey, equals('id'));
    });
  });

  group('Relationship Generation - BelongsTo', () {
    test('should generate BelongsTo relation from annotation', () {
      final post = Post(
        id: '1',
        userId: 'user1',
        title: 'Test Post',
        content: 'Content',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(post.relations.containsKey('author'), isTrue);

      final authorRelation = post.relations['author'] as BelongsTo<User>;
      expect(authorRelation, isA<BelongsTo<User>>());
      expect(authorRelation.foreignKey, equals('user_id'));
      expect(authorRelation.localKey, equals('id'));
    });

    test('should respect cascade delete behavior', () {
      final comment = Comment(
        id: '1',
        userId: 'user1',
        postId: 'post1',
        content: 'Great post!',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final postRelation = comment.relations['post'];
      expect(
        postRelation!.cascadeDeleteBehavior,
        equals(CascadeDeleteBehavior.restrict),
      );
    });
  });

  group('Relationship Generation - Multiple Relations', () {
    test('should generate multiple relations on same entity', () {
      final post = Post(
        id: '1',
        userId: 'user1',
        title: 'Test Post',
        content: 'Content',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(post.relations.length, equals(2));
      expect(post.relations.containsKey('author'), isTrue);
      expect(post.relations.containsKey('comments'), isTrue);
    });

    test('should have correct types for each relation', () {
      final post = Post(
        id: '1',
        userId: 'user1',
        title: 'Test Post',
        content: 'Content',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(post.relations['author'], isA<BelongsTo<User>>());
      expect(post.relations['comments'], isA<HasMany<Comment>>());
    });
  });

  group('Relationship Generation - Serialization', () {
    test('should not include relationship fields in serialization', () {
      final user = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = user.toDatumMap();

      // Relationship placeholder fields should not be in the map
      expect(map.containsKey('_posts'), isFalse);
      expect(map.containsKey('posts'), isFalse);
      expect(map.containsKey('_profile'), isFalse);
      expect(map.containsKey('profile'), isFalse);

      // Regular fields should be present
      expect(map['id'], equals('1'));
      expect(map['name'], equals('John Doe'));
      expect(map['email'], equals('john@example.com'));
    });

    test('should not include relationship fields in copyWithAll', () {
      final user = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      // copyWithAll should work without relationship fields
      final updated = user.copyWith(
        modifiedAt: DateTime(2024, 1, 2),
        version: 2,
      );

      expect(updated, isA<User>());
      expect(updated.version, equals(2));
    });

    test('should deserialize without relationship fields', () {
      final map = {
        'id': '1',
        'user_id': '1',
        'name': 'Jane Doe',
        'email': 'jane@example.com',
        'createdAt': DateTime(2024, 1, 1).millisecondsSinceEpoch,
        'modifiedAt': DateTime(2024, 1, 1).millisecondsSinceEpoch,
      };

      final user = User.fromMap(map);

      expect(user.id, equals('1'));
      expect(user.name, equals('Jane Doe'));
      expect(user.email, equals('jane@example.com'));

      // Relations should still be available
      expect(user.relations.isNotEmpty, isTrue);
    });
  });

  group('Relationship Generation - Equality', () {
    test('should not include relationship fields in equality check', () {
      final user1 = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final user2 = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(user1, equals(user2));
      expect(user1.hashCode, equals(user2.hashCode));
    });
  });

  group('Relationship Generation - Diff Tracking', () {
    test('should not include relationship fields in diff', () {
      final old = User(
        id: '1',
        userId: '1',
        name: 'John Doe',
        email: 'john@example.com',
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = old.toDatumMap();
      map['name'] = 'Jane Doe';
      map['modifiedAt'] = DateTime(2024, 1, 2).millisecondsSinceEpoch;
      final updated = User.fromMap(map);

      final diff = updated.diff(old);

      expect(diff, isNotNull);
      expect(diff!['name'], equals('Jane Doe'));

      // Relationship fields should not be in diff
      expect(diff.containsKey('_posts'), isFalse);
      expect(diff.containsKey('posts'), isFalse);
      expect(diff.containsKey('_profile'), isFalse);
      expect(diff.containsKey('profile'), isFalse);
    });
  });
}
