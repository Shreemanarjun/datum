# Cascading Delete Guide

Cascading delete is a powerful feature in Datum that allows you to safely delete entities and all their related data in a controlled manner. This guide covers the comprehensive cascading delete functionality including dry-run mode, progress callbacks, cancellation support, timeout protection, and improved error handling.

## Overview

Cascading delete ensures data integrity by automatically handling related entities when deleting a parent entity. It supports different deletion behaviors and provides extensive control over the deletion process.

## Cascade Delete Behaviors

Datum supports three cascade delete behaviors that determine how related entities are handled:

### Cascade
```dart no-verify
// Fragment of an entity's relations map — see the full example below.
'posts': HasMany<Post>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
```
Deletes all related entities along with the parent entity.

### Restrict
```dart no-verify
'comments': HasMany<Comment>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.restrict),
```
Prevents deletion if any related entities exist, maintaining referential integrity.

### None (Default)
```dart no-verify
'author': BelongsTo<User>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
```
Leaves related entities untouched (traditional foreign key behavior).

## Basic Usage

### Simple Cascade Delete

```dart
// Delete an entity and all related entities
final result = await manager.cascadeDelete(id: 'task-123', userId: userId);

if (result.success) {
  print('Successfully deleted ${result.totalDeleted} entities');
} else {
  print('Deletion failed: ${result.errors.join(', ')}');
}
```

### Fluent API Builder

```dart
// Use the fluent API for more control
final result = await manager
    .deleteCascade('task-123')
    .forUser(userId)
    .execute();
```

## Advanced Features

### Dry-Run Mode

Preview what would be deleted without actually performing the deletion:

```dart
// Preview the deletion
final preview = await manager
    .deleteCascade('task-123')
    .forUser(userId)
    .dryRun()
    .execute();

if (preview.success) {
  print('Would delete ${preview.totalDeleted} entities:');
  final success = preview as CascadeSuccess<Task>;
  success.deletedEntities.forEach((type, entities) {
    print('- ${entities.length} ${type.toString()} entities');
  });

  success.restrictedRelations.forEach((relation, entities) {
    print('${entities.length} entities would prevent deletion in relation: $relation');
  });
}
```

### Progress Callbacks

Monitor deletion progress in real-time:

```dart
final result = await manager
    .deleteCascade('task-123')
    .forUser(userId)
    .withProgress((progress) {
      print('Progress: ${progress.progressPercentage.toStringAsFixed(1)}% '
            '(${progress.completed}/${progress.total}) - ${progress.currentEntityType}');
    })
    .execute();
```

### Cancellation Support

Cancel long-running deletions:

```dart
final token = CancellationToken();

final future = manager
    .deleteCascade('task-123')
    .forUser(userId)
    .withCancellation(token)
    .execute();

// Cancel after 5 seconds if still running
Future.delayed(Duration(seconds: 5), () {
  token.cancel();
});

final result = await future;
if (result.success) {
  print('Deletion completed');
} else if (result.errors.any((e) => e.contains('cancelled'))) {
  print('Deletion was cancelled');
}
```

### Timeout Protection

Prevent hanging operations with timeouts:

```dart
final result = await manager
    .deleteCascade('task-123')
    .forUser(userId)
    .withTimeout(Duration(seconds: 30))
    .execute();
```

### Partial Deletes

Allow partial success when some deletions fail:

```dart
final result = await manager
    .deleteCascade('task-123')
    .forUser(userId)
    .allowPartialDeletes()
    .execute();

// Check what was actually deleted
if (result is CascadeSuccess<Task>) {
  print('Successfully deleted ${result.totalDeleted} entities');
  result.deletedEntities.forEach((type, entities) {
    print('- ${entities.length} ${type.toString()}');
  });
}
```

## Entity Relationships Example

Here's a complete example showing how cascade delete works with complex relationships:

```dart
class User extends RelationalDatumEntity with MemoizedRelations {
  User({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id;

  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, Relation> buildRelations() => {
        // Cascade: Delete all posts when user is deleted
        'posts': HasMany<Post>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        // Cascade: Delete profile when user is deleted
        'profile': HasOne<Profile>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        // Restrict: Prevent deletion if user has comments
        'comments': HasMany<Comment>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.restrict),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant User oldVersion) =>
      name == oldVersion.name ? null : {'name': name};

  @override
  User copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => User(
        id: id,
        name: name,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}

class Post extends RelationalDatumEntity with MemoizedRelations {
  Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String title;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, Relation> buildRelations() => {
        // None: Don't delete author when post is deleted
        'author': BelongsTo<User>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
        // Cascade: Delete all comments when post is deleted
        'comments': HasMany<Comment>(this, 'postId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

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
  Map<String, dynamic>? diff(covariant Post oldVersion) =>
      title == oldVersion.title ? null : {'title': title};

  @override
  Post copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Post(
        id: id,
        userId: userId,
        title: title,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}

class Comment extends RelationalDatumEntity with MemoizedRelations {
  Comment({
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
  final String id;
  @override
  final String userId;
  final String postId;
  final String content;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, Relation> buildRelations() => {
        // None: Don't delete related entities
        'post': BelongsTo<Post>(this, 'postId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'postId': postId,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant Comment oldVersion) =>
      content == oldVersion.content ? null : {'content': content};

  @override
  Comment copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Comment(
        id: id,
        userId: userId,
        postId: postId,
        content: content,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}

class Profile extends RelationalDatumEntity {
  Profile({
    required this.id,
    required this.userId,
    required this.bio,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String bio;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'bio': bio,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant Profile oldVersion) =>
      bio == oldVersion.bio ? null : {'bio': bio};

  @override
  Profile copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Profile(
        id: id,
        userId: userId,
        bio: bio,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}
```

## Analytics and Monitoring

Get detailed analytics about the deletion process:

```dart continue
final result = await Datum.manager<User>()
    .deleteCascade('user-123')
    .forUser('user-123')
    .execute();

if (result is CascadeSuccess<User>) {
  final analytics = result.analytics;

  print('Deletion Analytics:');
  print('- Duration: ${analytics.totalDuration}');
  print('- Queries executed: ${analytics.queriesExecuted}');
  print('- Relationships traversed: ${analytics.relationshipsTraversed}');
  print('- Total entities processed: ${analytics.totalEntitiesProcessed}');
  print('- Total entities deleted: ${analytics.totalEntitiesDeleted}');
  print('- Success rate: ${analytics.successRate.toStringAsFixed(1)}%');

  analytics.entitiesProcessedByType.forEach((type, count) {
    print('- Processed $count ${type.toString()} entities');
  });
}
```

## Error Handling

Cascade delete provides detailed error information:

```dart continue
final result = await Datum.manager<User>()
    .cascadeDelete(id: 'user-123', userId: 'user-123');

if (!result.success) {
  print('Deletion failed with ${result.errors.length} errors:');
  result.errors.forEach((error) {
    print('- $error');
  });

  // Check for restrict violations
  result.restrictedRelations.forEach((relation, entities) {
    print('Restrict violation in $relation: ${entities.length} entities');
  });
}
```

### Common Error Types

- **ENTITY_NOT_FOUND**: The entity to delete doesn't exist
- **RESTRICT_VIOLATION**: Related entities prevent deletion
- **DELETE_FAILED**: Individual entity deletion failed
- **TIMEOUT**: Operation exceeded timeout duration
- **CANCELLED**: Operation was cancelled

## Best Practices

### 1. Use Dry-Run for Critical Operations

```dart
// Always preview critical deletions
final preview = await manager.deleteCascade(task.id).forUser(userId).dryRun().execute();
if (preview.totalDeleted > 100) {
  // Get user confirmation for large deletions before executing for real
  print('About to delete ${preview.totalDeleted} entities — confirm first.');
  return;
}
```

### 2. Handle Restrict Violations Gracefully

```dart
final result = await manager.deleteCascade(task.id).forUser(userId).execute();

if (result is CascadeFailure<Task> && result.error.code == 'RESTRICT_VIOLATION') {
  // Show the user which relation is preventing deletion
  print('Blocked by relation: ${result.error.relationName}');
  print('Restricted entity ids: ${result.error.details?['restrictedEntities']}');
}
```

### 3. Use Progress Callbacks for Long Operations

```dart
final result = await manager
    .deleteCascade(task.id)
    .forUser(userId)
    .withProgress((progress) {
      // Drive your UI's progress indicator from here
      if (progress.progressPercentage % 25 == 0) {
        print('Deletion ${progress.progressPercentage}% complete');
      }
    })
    .execute();
```

### 4. Set Appropriate Timeouts

```dart
// Adjust timeout based on expected data size
const expectedEntityCount = 1500;
final timeout = expectedEntityCount > 1000
    ? Duration(minutes: 5)
    : Duration(seconds: 30);

final result = await manager
    .deleteCascade(task.id)
    .forUser(userId)
    .withTimeout(timeout)
    .execute();
```

### 5. Use Cancellation for User-Initiated Operations

```dart
final token = CancellationToken();

// Wire this to your UI's cancel button
void onCancelPressed() => token.cancel();

final result = await manager
    .deleteCascade(task.id)
    .forUser(userId)
    .withCancellation(token)
    .execute();
```

## Production Considerations

### Performance Optimization

- Use batch processing for large datasets
- Monitor analytics for performance bottlenecks
- Consider using `allowPartialDeletes()` for resilient operations

### Data Safety

- Always use dry-run mode for critical data
- Implement proper backup strategies
- Log all cascade delete operations for audit trails

### Error Recovery

- Handle partial failures gracefully
- Provide clear error messages to users
- Implement retry logic for transient failures

## Integration with Sync

Cascade delete operations are automatically included in sync operations:

```dart
// Cascade delete with immediate sync
await manager.cascadeDelete(id: task.id, userId: userId, forceRemoteSync: true);
```

All deleted entities will be queued for remote synchronization, ensuring consistency across all data sources.

## Testing

Use the comprehensive test examples as reference for testing cascade delete functionality:

```dart
import 'package:test/test.dart';

// Test restrict violations
test('prevents deletion with restrict relationships', () async {
  // Create entity with restrict relationship
  await manager.cascadeDelete(id: entityId, userId: userId);
  // Verify deletion was blocked
});

// Test cascade behavior
test('deletes all related entities with cascade behavior', () async {
  // Create entity with cascade relationships
  final result = await manager.cascadeDelete(id: entityId, userId: userId);
  // Verify all related entities were deleted
});

// Test dry-run mode
test('dry-run shows what would be deleted', () async {
  final preview = await manager.deleteCascade(entityId).forUser(userId).dryRun().execute();
  // Verify preview shows correct entities without deleting them
});
```

This guide covers the comprehensive cascading delete functionality in Datum. For more advanced usage patterns, refer to the API documentation and test examples.
