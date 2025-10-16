import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import 'relational_data_integration_test.dart';

void main() {
  group('Reactive Relational Data Integration Tests', () {
    late DatumManager<User> userManager;
    late DatumManager<Post> postManager;
    late DatumManager<Tag> tagManager;
    late DatumManager<Profile> profileManager;
    // Declare adapters here to make them accessible in setUp and tests.
    late MockLocalAdapter<User> userAdapter;
    late MockLocalAdapter<Post> postAdapter;
    late MockLocalAdapter<Tag> tagAdapter;
    late MockLocalAdapter<Profile> profileAdapter;
    late MockLocalAdapter<PostTag> postTagAdapter;
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

    final testProfile = Profile(
      id: 'profile-1',
      userId: 'user-1', // Foreign key linking to testUser
      bio: 'Loves Dart and Flutter.',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    setUp(() async {
      // Create all mock adapters first.
      userAdapter = MockLocalAdapter<User>();
      tagAdapter = MockLocalAdapter<Tag>();
      profileAdapter = MockLocalAdapter<Profile>();
      postTagAdapter = MockLocalAdapter<PostTag>();
      postAdapter = MockLocalAdapter<Post>(
        relatedAdapters: {PostTag: postTagAdapter},
      );

      Datum.resetForTesting();
      await Datum.initialize(
        config: const DatumConfig(
          enableLogging: false,
          autoStartSync:
              false, // Disable auto-sync to prevent timers in fakeAsync.
        ),
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

      // Wire up manager events to mock adapter streams for reactive queries
      userAdapter.externalChangeStream = userManager.onDataChange;
      postAdapter.externalChangeStream = postManager.onDataChange;
      tagAdapter.externalChangeStream = tagManager.onDataChange;
      profileAdapter.externalChangeStream = profileManager.onDataChange;
      postTagAdapter.externalChangeStream = postTagManager.onDataChange;

      // CRITICAL: Set all mock adapters to silent mode. This prevents them
      // from firing their own internal change events. The reactive queries in
      // this test are driven by the manager's `onDataChange` stream, so we
      // must prevent any adapter from also firing events to avoid duplicates
      // and race conditions.
      userAdapter.silent = true;
      postAdapter.silent = true;
      tagAdapter.silent = true;
      profileAdapter.silent = true;
      postTagAdapter.silent = true;

      // Since the Post adapter has a ManyToMany, its mock needs the pivot adapter.
      // We also need to wire up the pivot manager's events to its adapter.
      final mockPostTagAdapter =
          postAdapter.relatedAdapters![PostTag]! as MockLocalAdapter<PostTag>;
      mockPostTagAdapter.externalChangeStream = postTagManager.onDataChange;
    });

    tearDown(() async {
      // It's good practice to make tearDown async and await the disposal.
      await userManager.dispose();
      await postManager.dispose();
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

    test('watchRelated for "hasOne" reacts to changes in the related entity', () {
      fakeAsync((async) async {
        // Arrange
        await userManager.push(item: testUser, userId: testUser.id);
        final profileStream = userManager.watchRelated<Profile>(
          testUser,
          'profile',
        );

        final updatedProfile = testProfile.copyWith(
          bio: 'Expert in reactive programming.',
        );

        // Assert: Expect initial empty list, then the profile, then the
        // updated profile, and finally an empty list after deletion.
        expect(
          profileStream,
          emitsInOrder([
            isEmpty, // Initial state
            (List<Profile> profiles) {
              // ignore: avoid_print
              print(
                'watchRelated emitted [create]: ${profiles.map((e) => e.toMap()).toList()}',
              );
              return profiles.length == 1 &&
                  profiles.first.id == testProfile.id;
            },
            (List<Profile> profiles) {
              // ignore: avoid_print
              print(
                'watchRelated emitted [update]: ${profiles.map((e) => e.toMap()).toList()}',
              );
              return profiles.length == 1 &&
                  profiles.first.bio == 'Expert in reactive programming.';
            },
            isEmpty, // After profile is deleted
          ]),
        );

        // Act:
        profileManager.push(item: testProfile, userId: testUser.id);
        async.flushMicrotasks(); // Process the create event.
        profileManager.push(item: updatedProfile, userId: testUser.id);
        async.flushMicrotasks(); // Process the update event.
        profileManager.delete(id: testProfile.id, userId: testUser.id);
        async.flushMicrotasks(); // Process the delete event.
      });
    });
  });
}
