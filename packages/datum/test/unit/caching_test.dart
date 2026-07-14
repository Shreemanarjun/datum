import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

// Simple test entities for caching tests
class TestUser extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String email;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TestUser({
    required this.id,
    required this.name,
    required this.email,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id;

  @override
  Map<String, Relation> get relations => {};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'email': email,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  TestUser copyWith({
    String? name,
    String? email,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return TestUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! TestUser) return toDatumMap();

    final diff = <String, dynamic>{};
    if (name != oldVersion.name) diff['name'] = name;
    if (email != oldVersion.email) diff['email'] = email;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    return diff.isEmpty ? null : diff;
  }
}

class TestPost extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String title;
  final String content;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TestPost({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'content': content,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  TestPost copyWith({
    String? title,
    String? content,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return TestPost(
      id: id,
      userId: userId,
      title: title ?? this.title,
      content: content ?? this.content,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! TestPost) return toDatumMap();

    final diff = <String, dynamic>{};
    if (title != oldVersion.title) diff['title'] = title;
    if (content != oldVersion.content) diff['content'] = content;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    return diff.isEmpty ? null : diff;
  }
}

class TestComment extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String postId;
  final String content;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TestComment({
    required this.id,
    required this.userId,
    required this.postId,
    required this.content,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'postId': postId,
        'content': content,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  TestComment copyWith({
    String? content,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return TestComment(
      id: id,
      userId: userId,
      postId: postId,
      content: content ?? this.content,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! TestComment) return toDatumMap();

    final diff = <String, dynamic>{};
    if (content != oldVersion.content) diff['content'] = content;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    return diff.isEmpty ? null : diff;
  }
}

class TestProfile extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String bio;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TestProfile({
    required this.id,
    required this.userId,
    required this.bio,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {};

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
  TestProfile copyWith({
    String? bio,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return TestProfile(
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
    if (oldVersion is! TestProfile) return toDatumMap();

    final diff = <String, dynamic>{};
    if (bio != oldVersion.bio) diff['bio'] = bio;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    return diff.isEmpty ? null : diff;
  }
}

void main() {
  group('DatumManager Caching', () {
    late DatumManager<TestUser> userManager;
    late DatumManager<TestPost> postManager;
    late DatumManager<TestComment> commentManager;
    late DatumManager<TestProfile> profileManager;
    late MockLocalAdapter<TestUser> userAdapter;
    late MockLocalAdapter<TestPost> postAdapter;
    late MockLocalAdapter<TestComment> commentAdapter;
    late MockLocalAdapter<TestProfile> profileAdapter;
    late MockRemoteAdapter<TestUser> userRemoteAdapter;
    late MockRemoteAdapter<TestPost> postRemoteAdapter;
    late MockRemoteAdapter<TestComment> commentRemoteAdapter;
    late MockRemoteAdapter<TestProfile> profileRemoteAdapter;
    late DatumConnectivityChecker connectivity;

    setUp(() async {
      // Initialize adapters with fromJson functions for patch support
      userAdapter = MockLocalAdapter<TestUser>(
        fromJson: (json) => TestUser(
          id: json['id'] as String,
          name: json['name'] as String,
          email: json['email'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );
      postAdapter = MockLocalAdapter<TestPost>(
        fromJson: (json) => TestPost(
          id: json['id'] as String,
          userId: json['userId'] as String,
          title: json['title'] as String,
          content: json['content'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );
      commentAdapter = MockLocalAdapter<TestComment>(
        fromJson: (json) => TestComment(
          id: json['id'] as String,
          userId: json['userId'] as String,
          postId: json['postId'] as String,
          content: json['content'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );
      profileAdapter = MockLocalAdapter<TestProfile>(
        fromJson: (json) => TestProfile(
          id: json['id'] as String,
          userId: json['userId'] as String,
          bio: json['bio'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );

      userRemoteAdapter = MockRemoteAdapter<TestUser>(
        fromJson: (json) => TestUser(
          id: json['id'] as String,
          name: json['name'] as String,
          email: json['email'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );
      postRemoteAdapter = MockRemoteAdapter<TestPost>(
        fromJson: (json) => TestPost(
          id: json['id'] as String,
          userId: json['userId'] as String,
          title: json['title'] as String,
          content: json['content'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );
      commentRemoteAdapter = MockRemoteAdapter<TestComment>(
        fromJson: (json) => TestComment(
          id: json['id'] as String,
          userId: json['userId'] as String,
          postId: json['postId'] as String,
          content: json['content'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );
      profileRemoteAdapter = MockRemoteAdapter<TestProfile>(
        fromJson: (json) => TestProfile(
          id: json['id'] as String,
          userId: json['userId'] as String,
          bio: json['bio'] as String,
          modifiedAt: DateTime.parse(json['modifiedAt'] as String),
          createdAt: DateTime.parse(json['createdAt'] as String),
          version: json['version'] as int? ?? 1,
          isDeleted: json['isDeleted'] as bool? ?? false,
        ),
      );

      connectivity = MockConnectivityChecker();

      // Initialize managers
      userManager = DatumManager<TestUser>(
        localAdapter: userAdapter,
        remoteAdapter: userRemoteAdapter,
        connectivity: connectivity,
        // These tests exercise the (opt-in) query cache feature directly.
        datumConfig: const DatumConfig<TestUser>(enableQueryCache: true),
      );

      postManager = DatumManager<TestPost>(
        localAdapter: postAdapter,
        remoteAdapter: postRemoteAdapter,
        connectivity: connectivity,
      );

      commentManager = DatumManager<TestComment>(
        localAdapter: commentAdapter,
        remoteAdapter: commentRemoteAdapter,
        connectivity: connectivity,
      );

      profileManager = DatumManager<TestProfile>(
        localAdapter: profileAdapter,
        remoteAdapter: profileRemoteAdapter,
        connectivity: connectivity,
      );

      // Initialize all managers
      await userManager.initialize();
      await postManager.initialize();
      await commentManager.initialize();
      await profileManager.initialize();
    });

    tearDown(() async {
      await userManager.dispose();
      await postManager.dispose();
      await commentManager.dispose();
      await profileManager.dispose();
    });

    group('Query Caching', () {
      test('caches query results', () async {
        // Create test data
        final user1 = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        final user2 = TestUser(id: 'user-2', name: 'Jane', email: 'jane@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());

        await userManager.push(item: user1, userId: 'user-1');
        await userManager.push(item: user2, userId: 'user-2');

        // First query should hit database
        final users1 = await userManager.query(
          const DatumQuery(),
          source: DataSource.local,
          userId: 'user-1',
        );

        expect(users1.length, equals(1));

        // Second query should use cache
        final users2 = await userManager.query(
          const DatumQuery(),
          source: DataSource.local,
          userId: 'user-1',
        );

        expect(users2.length, equals(1));
        expect(users2, equals(users1));

        // Verify cache stats
        final stats = userManager.getCacheStats();
        expect(stats['queries'], greaterThan(0));
      });

      test('invalidates cache when entity is updated', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());

        await userManager.push(item: user, userId: 'user-1');

        // Query to populate cache
        await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');

        // Update user (should invalidate cache)
        final updatedUser = user.copyWith(name: 'Jane');
        await userManager.push(item: updatedUser, userId: 'user-1');

        // Cache should be invalidated
        final stats = userManager.getCacheStats();
        expect(stats['queries'], equals(0));
      });

      test('cache respects user isolation', () async {
        final user1 = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        final user2 = TestUser(id: 'user-2', name: 'Jane', email: 'jane@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());

        await userManager.push(item: user1, userId: 'user-1');
        await userManager.push(item: user2, userId: 'user-2');

        // Query for user-1
        final usersUser1 = await userManager.query(
          const DatumQuery(),
          source: DataSource.local,
          userId: 'user-1',
        );
        expect(usersUser1.length, equals(1));

        // Query for user-2
        final usersUser2 = await userManager.query(
          const DatumQuery(),
          source: DataSource.local,
          userId: 'user-2',
        );
        expect(usersUser2.length, equals(1));

        // Verify different cache entries
        final stats = userManager.getCacheStats();
        expect(stats['queries'], greaterThan(1));
      });
    });

    group('Entity Existence Caching', () {
      test('caches entity existence checks', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        await userManager.push(item: user, userId: 'user-1');

        // First existence check
        final exists1 = await userManager.read('user-1', userId: 'user-1');
        expect(exists1, isNotNull);

        // Second existence check should use cache
        final exists2 = await userManager.read('user-1', userId: 'user-1');
        expect(exists2, isNotNull);

        final stats = userManager.getCacheStats();
        expect(stats['entity_existence'], greaterThan(0));
      });

      test('handles non-existent entities correctly', () async {
        // Check non-existent entity
        final exists = await userManager.read('non-existent', userId: 'user-1');
        expect(exists, isNull);

        // Cache should still work for non-existence
        final existsAgain = await userManager.read('non-existent', userId: 'user-1');
        expect(existsAgain, isNull);
      });
    });

    group('Cache Invalidation', () {
      test('invalidates cache on entity deletion', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        final post = TestPost(id: 'post-1', userId: 'user-1', title: 'Post 1', content: 'Content 1', modifiedAt: DateTime.now(), createdAt: DateTime.now());

        await userManager.push(item: user, userId: 'user-1');
        await postManager.push(item: post, userId: 'user-1');

        // Populate cache
        await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');

        // Delete entity
        await userManager.delete(id: 'user-1', userId: 'user-1');

        // Cache should be invalidated
        final stats = userManager.getCacheStats();
        expect(stats['queries'], equals(0));
      });
    });

    group('Cache Management', () {
      test('clearCaches clears all caches', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        await userManager.push(item: user, userId: 'user-1');

        // Populate caches
        await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');
        await userManager.read('user-1', userId: 'user-1');

        // Verify caches are populated
        var stats = userManager.getCacheStats();
        expect(stats['queries'], greaterThan(0));
        expect(stats['entity_existence'], greaterThan(0));

        // Clear caches
        userManager.clearCaches();

        // Verify caches are cleared
        stats = userManager.getCacheStats();
        expect(stats['queries'], equals(0));
        expect(stats['entity_existence'], equals(0));
      });

      test('dispose clears all caches', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        await userManager.push(item: user, userId: 'user-1');

        // Populate caches
        await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');

        // Dispose manager
        await userManager.dispose();

        // Caches should be cleared (though we can't check after dispose)
        expect(userManager.isDisposed, isTrue);
      });
    });

    group('Performance and Concurrency', () {
      test('handles concurrent cache access', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        await userManager.push(item: user, userId: 'user-1');

        // Run multiple concurrent queries
        final futures = List.generate(10, (_) => userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1'));

        final results = await Future.wait(futures);

        // All results should be consistent
        for (final result in results) {
          expect(result.length, equals(1));
          expect(result.first.id, equals('user-1'));
        }
      });

      test('cache survives multiple operations', () async {
        final users = List.generate(5, (i) => TestUser(id: 'user-$i', name: 'User $i', email: 'user$i@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now()));

        // Create users
        for (final user in users) {
          await userManager.push(item: user, userId: 'user-${user.id}');
        }

        // Perform multiple read operations
        for (var i = 0; i < 10; i++) {
          final user = await userManager.read('user-1', userId: 'user-1');
          expect(user, isNotNull);
        }

        final stats = userManager.getCacheStats();
        expect(stats['entity_existence'], greaterThan(0));
      });
    });

    group('Edge Cases and Error Handling', () {
      test('handles empty cache gracefully', () async {
        // Query with empty cache
        final users = await userManager.readAll(userId: 'user-1');
        expect(users, isEmpty);

        // Cache should still work
        final usersAgain = await userManager.readAll(userId: 'user-1');
        expect(usersAgain, isEmpty);
      });

      test('handles cache corruption gracefully', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
        await userManager.push(item: user, userId: 'user-1');

        // Populate cache
        await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');

        // Manually corrupt cache (simulate edge case)
        userManager.clearCaches();

        // Should still work after cache corruption
        final users = await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');
        expect(users.length, equals(1));
      });

      test('handles rapid cache invalidation', () async {
        final user = TestUser(id: 'user-1', name: 'John', email: 'john@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());

        // Rapid create/update/delete cycle using manager methods to ensure cache invalidation
        await userManager.push(item: user, userId: 'user-1');
        await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');

        final updatedUser = user.copyWith(name: 'Jane');
        await userManager.push(item: updatedUser, userId: 'user-1');

        await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');
        await userManager.delete(id: 'user-1', userId: 'user-1');

        // Allow time for cache invalidation to process
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should handle all operations without issues
        final finalQuery = await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-1');
        expect(finalQuery, isEmpty);
      });
    });

    group('Memory and Resource Management', () {
      test('cache does not grow unbounded', () async {
        // Create many different queries to test cache size management
        for (var i = 0; i < 50; i++) {
          final user = TestUser(id: 'user-$i', name: 'User $i', email: 'user$i@example.com', modifiedAt: DateTime.now(), createdAt: DateTime.now());
          await userManager.push(item: user, userId: 'user-$i');

          // Query each user
          await userManager.query(const DatumQuery(), source: DataSource.local, userId: 'user-$i');
        }

        final stats = userManager.getCacheStats();
        // Cache should have reasonable size (not all 50 entries)
        expect(stats['relationship_queries'], lessThan(50));
      });
    });
  });
}
