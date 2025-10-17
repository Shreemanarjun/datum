import 'package:test/test.dart';
import 'package:datum/datum.dart';
import '../mocks/test_entity.dart';

void main() {
  group('Conflict Resolvers', () {
    final context = DatumConflictContext(
      type: DatumConflictType.bothModified,
      entityId: 'test-id',
      userId: 'test-user',
      detectedAt: DateTime.now(),
    );
    final baseTime = DateTime(2023);
    final localOlder = TestEntity(
      id: 'e1',
      userId: 'u1',
      name: 'Local',
      value: 1,
      modifiedAt: baseTime,
      createdAt: baseTime,
      version: 1,
    );
    final remoteNewer = localOlder.copyWith(
      name: 'Remote',
      value: 2,
      modifiedAt: baseTime.add(const Duration(minutes: 1)),
      version: 2,
    );

    group('MergeResolver', () {
      test('should have correct name property', () {
        final resolver =
            MergeResolver<TestEntity>(onMerge: (_, __, ___) async => null);
        expect(resolver.name, 'Merge');
      });

      test('should abort when both local and remote items are null', () async {
        // Arrange
        final resolver = MergeResolver<TestEntity>(
          onMerge: (local, remote, context) async {
            // This won't be called, but is required.
            return local.copyWith(name: remote.name);
          },
        );

        // Act
        final resolution = await resolver.resolve(
          local: null,
          remote: null,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message, 'No entities supplied to merge resolver.');
      });

      test(
        'should return a merged entity when both items are provided',
        () async {
          // Arrange
          final resolver = MergeResolver<TestEntity>(
            onMerge: (local, remote, context) async {
              // Simple merge logic for testing: prefer local, but take remote's name.
              return local.copyWith(name: remote.name);
            },
          );

          // Act
          final resolution = await resolver.resolve(
            local: localOlder,
            remote: remoteNewer,
            context: context,
          );

          // Assert
          expect(resolution.strategy, DatumResolutionStrategy.merge);
          expect(resolution.resolvedData!.name, 'Remote'); // from remote
          expect(resolution.resolvedData!.value, 1); // from local
        },
      );

      test('should abort when only local is null', () async {
        // Arrange
        final resolver = MergeResolver<TestEntity>(
          onMerge: (local, remote, context) async => local,
        );

        // Act
        final resolution = await resolver.resolve(
          local: null,
          remote: remoteNewer,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message,
            'Merge requires both local and remote data to be available.');
      });

      test('should abort when only remote is null', () async {
        // Arrange
        final resolver = MergeResolver<TestEntity>(
          onMerge: (local, remote, context) async => local,
        );

        // Act
        final resolution = await resolver.resolve(
          local: localOlder,
          remote: null,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message,
            'Merge requires both local and remote data to be available.');
      });

      test('should abort when onMerge returns null', () async {
        // Arrange
        final resolver = MergeResolver<TestEntity>(
          onMerge: (local, remote, context) async => null,
        );

        // Act
        final resolution = await resolver.resolve(
          local: localOlder,
          remote: remoteNewer,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message, 'User cancelled merge operation.');
      });
    });

    group('LocalPriorityResolver', () {
      test('should have correct name property', () {
        final resolver = LocalPriorityResolver<TestEntity>();
        expect(resolver.name, 'LocalPriority');
      });

      test('should abort when both local and remote items are null', () async {
        // Arrange
        final resolver = LocalPriorityResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: null,
          remote: null,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message, 'No data available to resolve conflict.');
      });

      test('should always choose local when it exists', () async {
        // Arrange
        final resolver = LocalPriorityResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: localOlder,
          remote: remoteNewer,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeLocal);
        expect(resolution.resolvedData, localOlder);
      });

      test('should choose remote when only local is null', () async {
        // Arrange
        final resolver = LocalPriorityResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: null,
          remote: remoteNewer,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeRemote);
        expect(resolution.resolvedData, remoteNewer);
      });
    });

    group('RemotePriorityResolver', () {
      test('should have correct name property', () {
        final resolver = RemotePriorityResolver<TestEntity>();
        expect(resolver.name, 'RemotePriority');
      });

      test('should abort when both local and remote items are null', () async {
        // Arrange
        final resolver = RemotePriorityResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: null,
          remote: null,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message, 'No data available to resolve conflict.');
      });

      test('should always choose remote when it exists', () async {
        // Arrange
        final resolver = RemotePriorityResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: localOlder,
          remote: remoteNewer,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeRemote);
        expect(resolution.resolvedData, remoteNewer);
      });

      test('should choose local when only remote is null', () async {
        // Arrange
        final resolver = RemotePriorityResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: localOlder,
          remote: null,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeLocal);
        expect(resolution.resolvedData, localOlder);
      });
    });

    group('LastWriteWinsResolver', () {
      test('should have correct name property', () {
        final resolver = LastWriteWinsResolver<TestEntity>();
        expect(resolver.name, 'LastWriteWins');
      });

      test('should abort when both local and remote items are null', () async {
        final resolver = LastWriteWinsResolver<TestEntity>();
        final resolution = await resolver.resolve(
          local: null,
          remote: null,
          context: context,
        );
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message, 'No data available for resolution.');
      });

      test('should choose remote when its version is higher', () async {
        final resolver = LastWriteWinsResolver<TestEntity>();
        final resolution = await resolver.resolve(
          local: localOlder,
          remote: remoteNewer,
          context: context,
        );
        expect(resolution.strategy, DatumResolutionStrategy.takeRemote);
        expect(resolution.resolvedData, remoteNewer);
      });

      test('should choose local when its version is higher', () async {
        final resolver = LastWriteWinsResolver<TestEntity>();
        final resolution = await resolver.resolve(
          local: remoteNewer, // local is now the "newer" one
          remote: localOlder,
          context: context,
        );
        expect(resolution.strategy, DatumResolutionStrategy.takeLocal);
        expect(resolution.resolvedData, remoteNewer);
      });

      test(
        'should choose remote when versions are same and its modifiedAt is later',
        () async {
          final resolver = LastWriteWinsResolver<TestEntity>();
          final sameVersionRemote = remoteNewer.copyWith(version: 1);
          final resolution = await resolver.resolve(
            local: localOlder,
            remote: sameVersionRemote,
            context: context,
          );
          expect(resolution.strategy, DatumResolutionStrategy.takeRemote);
          expect(resolution.resolvedData, sameVersionRemote);
        },
      );

      test(
        'should choose local when versions and modifiedAt are same',
        () async {
          // Arrange
          final resolver = LastWriteWinsResolver<TestEntity>();
          final identicalTwin = localOlder.copyWith(); // Exact copy

          // Act
          final resolution = await resolver.resolve(
            local: localOlder,
            remote: identicalTwin,
            context: context,
          );
          // Assert: Local wins as a tie-breaker
          expect(resolution.strategy, DatumResolutionStrategy.takeLocal);
        },
      );

      test('should choose remote when only remote exists', () async {
        // Arrange
        final resolver = LastWriteWinsResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: null,
          remote: remoteNewer,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeRemote);
        expect(resolution.resolvedData, remoteNewer);
      });

      test('should choose local when only local exists', () async {
        // Arrange
        final resolver = LastWriteWinsResolver<TestEntity>();

        // Act
        final resolution = await resolver.resolve(
          local: localOlder,
          remote: null,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeLocal);
        expect(resolution.resolvedData, localOlder);
      });
    });

    group('UserPromptResolver', () {
      test('should have correct name property', () {
        final resolver = UserPromptResolver<TestEntity>(
            onPrompt: (_, __, ___) async => DatumResolutionStrategy.abort);
        expect(resolver.name, 'UserPrompt');
      });

      late TestEntity localItem;
      late TestEntity remoteItem;
      late DatumConflictContext context;

      setUp(() {
        localItem = TestEntity(
          id: 'entity1',
          userId: 'user1',
          name: 'Local',
          value: 42,
          modifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          version: 1,
        );
        remoteItem = TestEntity(
          id: 'entity1',
          userId: 'user1',
          name: 'Remote',
          value: 100,
          modifiedAt: DateTime.now().add(const Duration(seconds: 10)),
          createdAt: DateTime.now(),
          version: 2,
        );
        context = DatumConflictContext(
          type: DatumConflictType.bothModified,
          entityId: 'entity1',
          userId: 'user1',
          detectedAt: DateTime.now(),
        );
      });

      test('should use local when user chooses useLocal', () async {
        // Arrange
        final resolver = UserPromptResolver<TestEntity>(
          onPrompt: (ctx, local, remote) async =>
              DatumResolutionStrategy.takeLocal,
        );

        // Act
        final resolution = await resolver.resolve(
          local: localItem,
          remote: remoteItem,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeLocal);
        expect(resolution.resolvedData, localItem);
      });

      test(
        'should abort when user chooses useLocal but local is null',
        () async {
          // Arrange
          final resolver = UserPromptResolver<TestEntity>(
            onPrompt: (ctx, local, remote) async =>
                DatumResolutionStrategy.takeLocal,
          );

          // Act
          final resolution = await resolver.resolve(
            local: null,
            remote: remoteItem,
            context: context,
          );

          // Assert
          expect(resolution.strategy, DatumResolutionStrategy.abort);
          expect(
            resolution.message,
            'Local data unavailable for chosen strategy.',
          );
        },
      );

      test('should use remote when user chooses useRemote', () async {
        // Arrange
        final resolver = UserPromptResolver<TestEntity>(
          onPrompt: (ctx, local, remote) async =>
              DatumResolutionStrategy.takeRemote,
        );

        // Act
        final resolution = await resolver.resolve(
          local: localItem,
          remote: remoteItem,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.takeRemote);
        expect(resolution.resolvedData, remoteItem);
      });

      test(
        'should abort when user chooses useRemote but remote is null',
        () async {
          // Arrange
          final resolver = UserPromptResolver<TestEntity>(
            onPrompt: (ctx, local, remote) async =>
                DatumResolutionStrategy.takeRemote,
          );

          // Act
          final resolution = await resolver.resolve(
            local: localItem,
            remote: null,
            context: context,
          );

          // Assert
          expect(resolution.strategy, DatumResolutionStrategy.abort);
          expect(
            resolution.message,
            'Remote data unavailable for chosen strategy.',
          );
        },
      );

      test(
        'should merge when user chooses merge and onMerge is provided',
        () async {
          // Arrange
          final resolver = UserPromptResolver<TestEntity>(
            onPrompt: (ctx, local, remote) async =>
                DatumResolutionStrategy.merge,
            onMerge: (local, remote, context) async =>
                local.copyWith(name: remote.name),
          );

          // Act
          final resolution = await resolver.resolve(
            local: localItem,
            remote: remoteItem,
            context: context,
          );

          // Assert
          expect(resolution.strategy, DatumResolutionStrategy.merge);
          expect(resolution.resolvedData!.name, remoteItem.name);
          expect(resolution.resolvedData!.value, localItem.value);
        },
      );

      test('should abort when onMerge returns null', () async {
        // Arrange
        final resolver = UserPromptResolver<TestEntity>(
          onPrompt: (ctx, local, remote) async => DatumResolutionStrategy.merge,
          onMerge: (local, remote, context) async {
            // Simulate the user cancelling the merge UI.
            return null;
          },
        );

        // Act
        final resolution = await resolver.resolve(
          local: localItem,
          remote: remoteItem,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message, 'User cancelled merge operation.');
      });

      test(
        'should abort when user chooses merge but onMerge is not provided',
        () async {
          // Arrange
          final resolver = UserPromptResolver<TestEntity>(
            onPrompt: (ctx, local, remote) async =>
                DatumResolutionStrategy.merge,
            // onMerge is intentionally omitted (null)
          );

          // Act
          final resolution = await resolver.resolve(
            local: localItem,
            remote: remoteItem,
            context: context,
          );

          // Assert
          expect(resolution.strategy, DatumResolutionStrategy.abort);
          expect(
            resolution.message,
            'Merge strategy chosen, but no `onMerge` function was provided.',
          );
        },
      );

      test('should abort when user chooses merge but data is missing',
          () async {
        // Arrange
        final resolver = UserPromptResolver<TestEntity>(
          onPrompt: (ctx, local, remote) async => DatumResolutionStrategy.merge,
          onMerge: (local, remote, context) async => local, // Dummy onMerge
        );

        // Act
        final resolution = await resolver.resolve(
          local: null, // Missing local data
          remote: remoteItem,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message,
            'Merge requires both local and remote data to be available.');
      });

      test('should abort when user chooses abort', () async {
        // Arrange
        final resolver = UserPromptResolver<TestEntity>(
          onPrompt: (ctx, local, remote) async => DatumResolutionStrategy.abort,
        );

        // Act
        final resolution = await resolver.resolve(
          local: localItem,
          remote: remoteItem,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.abort);
        expect(resolution.message, 'User cancelled resolution.');
      });

      test('should require user input when user chooses askUser', () async {
        // Arrange
        final resolver = UserPromptResolver<TestEntity>(
          onPrompt: (ctx, local, remote) async =>
              DatumResolutionStrategy.askUser,
        );

        // Act
        final resolution = await resolver.resolve(
          local: localItem,
          remote: remoteItem,
          context: context,
        );

        // Assert
        expect(resolution.strategy, DatumResolutionStrategy.askUser);
        expect(resolution.requiresUserInput, isTrue);
      });
    });
  });
}
