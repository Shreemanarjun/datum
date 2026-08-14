---
title: Querying Data
---

This guide covers how to query and filter data in Datum using the powerful query API.

## Overview

Datum provides a comprehensive query system that allows you to filter, sort, and paginate data from both local and remote sources.

## Basic Queries

### Simple Filtering

```dart
// Find all completed tasks
final completedTasks = await Datum.manager<Task>().query(
  DatumQuery(
    filters: [Filter('isCompleted', FilterOperator.equals, true)],
  ),
  source: DataSource.local,
  userId: 'user-123',
);

// Find tasks created in the last week
final recentTasks = await Datum.manager<Task>().query(
  DatumQuery(
    filters: [Filter('createdAt', FilterOperator.greaterThan, DateTime.now().subtract(Duration(days: 7)))],
  ),
  source: DataSource.local,
  userId: 'user-123',
);
```

### Sorting

```dart
// Sort by creation date (newest first)
final sortedTasks = await Datum.manager<Task>().query(
  DatumQuery(
    sorting: [SortDescriptor('createdAt', descending: true)],
  ),
  source: DataSource.local,
  userId: 'user-123',
);

// Multiple sort criteria
final sortedByPriority = await Datum.manager<Task>().query(
  DatumQuery(
    sorting: [
      SortDescriptor('priority', descending: true), // High priority first
      SortDescriptor('createdAt', descending: true), // Then by date
    ],
  ),
  source: DataSource.local,
  userId: 'user-123',
);
```

### Pagination

```dart
// Get first 20 items
final firstPage = await Datum.manager<Task>().query(
  DatumQuery(
    limit: 20,
    offset: 0,
  ),
  source: DataSource.local,
  userId: 'user-123',
);

// Get next page
final secondPage = await Datum.manager<Task>().query(
  DatumQuery(
    limit: 20,
    offset: 20,
  ),
  source: DataSource.local,
  userId: 'user-123',
);
```

## Filter Operators

Datum supports various filter operators:

### Equality Operators
```dart
// Exact match
final isActive = Filter('status', FilterOperator.equals, 'active');

// Not equal
final notDeleted = Filter('status', FilterOperator.notEquals, 'deleted');
```

### Comparison Operators
```dart
// Numeric/date comparisons
final highPriority = Filter('priority', FilterOperator.greaterThan, 5);
final createdInPast = Filter('createdAt', FilterOperator.lessThan, DateTime.now());
final goodScore = Filter('score', FilterOperator.greaterThanOrEqual, 80);
final notRetired = Filter('age', FilterOperator.lessThanOrEqual, 65);
```

### String Operators
```dart
// String matching
final urgentTitle = Filter('title', FilterOperator.contains, 'urgent');
final adminEmail = Filter('email', FilterOperator.startsWith, 'admin');
final pdfFile = Filter('filename', FilterOperator.endsWith, '.pdf');
```

### Set Operators
```dart
// Check if value is in a list
final knownCategory = Filter('category', FilterOperator.isIn, ['work', 'personal', 'urgent']);

// Check if value is not in a list
final visible = Filter('status', FilterOperator.isNotIn, ['deleted', 'archived']);
```

### Null Checks
```dart
// Check for null values
final noDescription = Filter('description', FilterOperator.isNull, null);

// Check for non-null values
final assigned = Filter('assignedTo', FilterOperator.isNotNull, null);
```

### Array Operators
```dart
// Check if array contains a value
final important = Filter('tags', FilterOperator.arrayContains, 'important');
```

## Complex Queries

### Multiple Filters

```dart
// AND logic (default)
final complexQuery = DatumQuery(
  filters: [
    Filter('isCompleted', FilterOperator.equals, false),
    Filter('priority', FilterOperator.greaterThan, 3),
    Filter('createdAt', FilterOperator.greaterThan, DateTime.now().subtract(Duration(days: 7))),
  ],
  // logicalOperator: LogicalOperator.and, // Default
);

// OR logic
final orQuery = DatumQuery(
  filters: [
    Filter('status', FilterOperator.equals, 'urgent'),
    Filter('assignedTo', FilterOperator.equals, 'me'),
  ],
  logicalOperator: LogicalOperator.or,
);
```

### Combining with Sorting and Pagination

```dart
final complexQuery = await Datum.manager<Task>().query(
  DatumQuery(
    filters: [
      Filter('isCompleted', FilterOperator.equals, false),
      Filter('priority', FilterOperator.greaterThanOrEqual, 4),
    ],
    sorting: [
      SortDescriptor('priority', descending: true),
      SortDescriptor('createdAt'), // ascending by default
    ],
    limit: 50,
    offset: 0,
  ),
  source: DataSource.local,
  userId: 'user-123',
);
```

## Query Builder

For more complex queries, use the fluent `DatumQueryBuilder` API:

```dart
final query = DatumQueryBuilder<Task>()
    .where('isCompleted', isEqualTo: false)
    .where('priority', isGreaterThan: 3)
    .where('createdAt', isGreaterThan: DateTime.now().subtract(Duration(days: 7)))
    .orderBy('priority', descending: true)
    .orderBy('createdAt', descending: false)
    .limit(50)
    .offset(0)
    .build();

// Execute the query
final results = await Datum.manager<Task>().query(query, source: DataSource.local, userId: 'user-123');
```

For compile-time safety, declare `DatumQueryField` descriptors (or use the
`<Entity>Query` extension generated by `datum_generator`) and query with
`whereField` / `orderByField`:

```dart
abstract class TaskFields {
  static const title = DatumQueryField<Task, String>('title');
  static const priority = DatumQueryField<Task, int>('priority');
}
```

```dart continue
final typeSafeQuery = (DatumQueryBuilder<Task>()
      ..whereField(TaskFields.priority, isGreaterThanOrEqualTo: 2) // int-checked
      ..whereField(TaskFields.title, contains: 'urgent')
      ..orderByField(TaskFields.priority, descending: true))
    .build();
```

### Advanced Query Builder

Use `or([...])` / `and([...])` to add explicitly grouped composite conditions:

```dart
final complexQuery = DatumQueryBuilder<Task>()
    // Grouped OR condition: urgent title OR high priority
    .or([
      Filter('title', FilterOperator.contains, 'urgent'),
      Filter('priority', FilterOperator.greaterThan, 3),
    ])
    .where('createdAt', isGreaterThan: DateTime.now().subtract(Duration(days: 30)))
    .where('tags', arrayContains: 'featured')
    .orderBy('createdAt', descending: true)
    .withRelated(['author', 'comments'])
    .limit(20)
    .build();
```

## Reactive Queries

Watch queries reactively for real-time updates:

```dart
// Watch a dynamic query
final urgentTasksStream = Datum.manager<Task>().watchQuery(
  DatumQuery(
    filters: [Filter('priority', FilterOperator.greaterThan, 4)],
    sorting: [SortDescriptor('createdAt', descending: true)],
  ),
  userId: 'user-123',
);

// Listen for changes
urgentTasksStream.listen((tasks) {
  print('Urgent tasks updated: ${tasks.length} tasks');
  // Update UI
});
```

## Relationship Queries

Query with related data using `withRelated`. Given a relational `Post` that
belongs to an `Author` (see the [Relationships guide](/guides/relationships)):

```dart
class Author extends RelationalDatumEntity {
  Author({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

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
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      toDatumMap();

  @override
  Author copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Author(
        id: id,
        userId: userId,
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
    required this.authorId,
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
  final String authorId;
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
        'author': BelongsTo<Author>(this, 'authorId'),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'authorId': authorId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      toDatumMap();

  @override
  Post copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Post(
        id: id,
        userId: userId,
        title: title,
        authorId: authorId,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}
```

```dart continue
// Load posts with their authors
final postsWithAuthors = await Datum.manager<Post>().query(
  DatumQuery(
    withRelated: ['author'],
    sorting: [SortDescriptor('createdAt', descending: true)],
    limit: 20,
  ),
  source: DataSource.local,
  userId: 'user-123',
);

// Access related data with the typed accessor
for (final post in postsWithAuthors) {
  final author = post.relatedOne<Author>('author');
  print('Post: ${post.title} by ${author?.name}');
}
```

### Nested Relationships

```dart continue
// Load posts with authors, and comments with their authors (dot paths)
final postsWithNestedRelations = await Datum.manager<Post>().query(
  DatumQuery(
    withRelated: ['author', 'comments.author'],
    filters: [Filter('createdAt', FilterOperator.greaterThan, DateTime.now().subtract(Duration(days: 7)))],
  ),
  source: DataSource.remote,
  userId: 'user-123',
);
```

## Data Sources

Queries can be executed against different data sources:

```dart
final query = DatumQueryBuilder<Task>().where('isCompleted', isEqualTo: false).build();

// Query local data only
final localResults = await Datum.manager<Task>().query(
  query,
  source: DataSource.local,
  userId: 'user-123',
);

// Query remote data only
final remoteResults = await Datum.manager<Task>().query(
  query,
  source: DataSource.remote,
  userId: 'user-123',
);

// Note: Some operations like relationships may not be available for remote-only queries
```

## Performance Considerations

### Indexing
For optimal query performance, ensure your local adapter supports indexing on frequently queried fields.

### Query Optimization
- Use specific filters rather than broad ones
- Limit result sets with pagination
- Use `withRelated` strategically to avoid N+1 queries
- Consider the cost of sorting large datasets

### Memory Usage
- Large result sets can consume significant memory
- Use pagination for large datasets
- Consider using `watchQuery` for reactive updates instead of polling

## Error Handling

Handle query errors appropriately:

```dart
final query = DatumQueryBuilder<Task>().where('priority', isGreaterThan: 3).build();

try {
  final results = await Datum.manager<Task>().query(query, source: DataSource.local, userId: 'user-123');
  print('Found ${results.length} tasks');
} on DatumException catch (e) {
  switch (e.code) {
    case DatumExceptionCode.badRequest:
      print('Invalid query');
      break;
    case DatumExceptionCode.adapterError:
      print('Filter operator not supported by adapter');
      break;
    case DatumExceptionCode.networkError:
      print('Failed to query remote data');
      break;
    default:
      print('Query failed: ${e.message}');
  }
}
```

Prefer the result-returning `tryQuery` when you don't want try/catch:

```dart
final result = await manager.tryQuery(
  DatumQueryBuilder<Task>().where('priority', isGreaterThan: 3).build(),
  source: DataSource.local,
  userId: userId,
);
switch (result) {
  case Success(value: final tasks):
    print('Found ${tasks.length} tasks');
  case Failure(value: final DatumError error):
    print('Query failed: $error');
}
```

## Best Practices

1. **Use appropriate data sources**: Query local for fast access, remote for fresh data
2. **Leverage pagination**: Always paginate large result sets
3. **Index frequently queried fields**: Ensure your adapters support indexing
4. **Use eager loading**: Use `withRelated` to avoid N+1 query problems
5. **Handle errors gracefully**: Implement proper error handling for all queries
6. **Consider performance**: Profile your queries and optimize as needed
7. **Use reactive queries**: Prefer `watchQuery` for dynamic, real-time data
