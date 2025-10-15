import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import 'relational_data_integration_test.dart';

void main() {
  group('Reactive Relational Data Integration Tests', () {
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
      userId: 'user-1',
      title: 'My First Post',
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

      // Wire up manager events to mock adapter streams for reactive queries
      (userManager.localAdapter as MockLocalAdapter).externalChangeStream =
          userManager.onDataChange;
      (postManager.localAdapter as MockLocalAdapter).externalChangeStream =
          postManager.onDataChange;
      (tagManager.localAdapter as MockLocalAdapter).externalChangeStream =
          tagManager.onDataChange;
      (postTagManager.localAdapter as MockLocalAdapter).externalChangeStream =
          postTagManager.onDataChange;
    });

    tearDown(() {
      Datum.resetForTesting();
    });

    test('watchRelated for "hasMany" reacts to new related entities', () async {
      // Arrange
      await userManager.push(item: testUser, userId: testUser.id);
      final postStream = userManager.watchRelated<Post>(testUser, 'posts');

      // Assert: Expect initial empty list, then a list with one post.
      expect(
        postStream,
        emitsInOrder([
          isEmpty, // Initial state
          (List<Post> posts) => posts.length == 1 && posts.first.id == 'post-1',
        ]),
      );

      // Act: Add a post that belongs to the user.
      await postManager.push(item: testPost, userId: testUser.id);
    });

    test(
      'watchRelated for "belongsTo" reacts to related entity deletion (constraint failure)',
      () async {
        // Arrange
        await userManager.push(item: testUser, userId: testUser.id);
        await postManager.push(item: testPost, userId: testUser.id);

        final authorStream = postManager.watchRelated<User>(testPost, 'author');

        // Assert: Expect initial author, then an empty list after deletion.
        expect(
          authorStream,
          emitsInOrder([
            (List<User> users) =>
                users.length == 1 && users.first.id == 'user-1',
            isEmpty, // After user is deleted
          ]),
        );

        // Act: Delete the user the post belongs to.
        await userManager.delete(id: testUser.id, userId: testUser.id);
      },
    );

    test(
      'watchRelated for "manyToMany" reacts to new pivot table entries',
      () async {
        // Arrange
        final tag = Tag(
          id: 'tag-1',
          userId: 'user-1',
          name: 'Flutter',
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
        );
        final postTag = PostTag(
          id: 'pt-1',
          postId: 'post-1',
          tagId: 'tag-1',
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
        );

        await postManager.push(item: testPost, userId: testUser.id);
        await tagManager.push(item: tag, userId: testUser.id);

        final tagStream = postManager.watchRelated<Tag>(testPost, 'tags');

        // Assert
        expect(
          tagStream,
          emitsInOrder([
            isEmpty,
            (List<Tag> tags) => tags.length == 1 && tags.first.id == 'tag-1',
          ]),
        );

        // Act: Create the link in the pivot table.
        await postTagManager.push(item: postTag, userId: postTag.userId);
      },
    );
  });
}
