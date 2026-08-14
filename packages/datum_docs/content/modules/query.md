---




title: Query Module
---

The Query module provides powerful tools for filtering, sorting, and paginating data across Datum entities.

## Key Components

### DatumQuery

The main query class that defines filtering, sorting, and pagination parameters.

**Properties:**
- `filters`: List of `FilterCondition`s to apply (`Filter` or `CompositeFilter`)
- `sorting`: List of `SortDescriptor` for ordering results
- `limit`: Maximum number of results to return
- `offset`: Number of results to skip (for pagination)
- `logicalOperator`: `LogicalOperator.and` or `LogicalOperator.or` for combining root filters
- `withRelated`: List of relationship names to eagerly load

### Filter

Represents a single filtering condition, created with positional arguments: `Filter(field, operator, value)`.

**Properties:**
- `field`: The field name to filter on (dot notation supported for nested fields)
- `operator`: The `FilterOperator` to apply
- `value`: The value to compare against

`CompositeFilter(conditions, operator)` groups conditions with explicit AND/OR logic.

### FilterOperator

Supported filtering operations:

**Equality:**
- `equals`: Exact match
- `notEquals`: Not equal to value

**Comparison:**
- `greaterThan`: Greater than value
- `lessThan`: Less than value
- `greaterThanOrEqual`: Greater than or equal to value
- `lessThanOrEqual`: Less than or equal to value
- `between`: Between two values (inclusive)

**String Matching:**
- `contains`: String contains substring (case-sensitive)
- `containsIgnoreCase`: String contains substring (case-insensitive)
- `startsWith`: String starts with value
- `endsWith`: String ends with value
- `matches`: Matches a regular expression pattern

**Set Operations:**
- `isIn`: Value is in the provided list
- `isNotIn`: Value is not in the provided list

**Null Checks:**
- `isNull`: Field is null
- `isNotNull`: Field is not null

**Array Operations:**
- `arrayContains`: Array field contains the value
- `arrayContainsAny`: Array field contains any of the values

**Geo:**
- `withinDistance`: Within a distance of a geographical point

### SortDescriptor

Defines sorting criteria for query results: `SortDescriptor(field, {descending, nullSortOrder})`.

**Properties:**
- `field`: Field name to sort by (dot notation supported)
- `descending`: Whether to sort in descending order (default: `false`)
- `nullSortOrder`: `NullSortOrder.first` or `NullSortOrder.last` (default) for null handling

### DatumQueryBuilder

Fluent API for building complex queries programmatically. Operators are expressed as named parameters of `where`.

**Key Methods:**
- `where(field, {isEqualTo, isNotEqualTo, isGreaterThan, isGreaterThanOrEqualTo, isLessThan, isLessThanOrEqualTo, contains, startsWith, endsWith, isIn, isNotIn, arrayContains, matches, between, ...})`: Add filter conditions
- `whereNull(field)` / `whereNotNull(field)`: Null checks
- `or(conditions)` / `and(conditions)`: Grouped conditions with OR/AND logic
- `orderBy(field, {descending, nullSortOrder})`: Add sorting criteria
- `limit(count)`: Set maximum results
- `offset(count)`: Set results to skip
- `withRelated(relations)`: Specify relationships to eager load
- `whereField(field, ...)` / `orderByField(field, ...)`: Type-safe variants using `DatumQueryField` descriptors
- `build()`: Create the final `DatumQuery`

**Example:**
```dart
final query = DatumQueryBuilder<Task>()
    .where('isCompleted', isEqualTo: false)
    .where('priority', isGreaterThan: 3)
    .orderBy('createdAt', descending: true)
    .limit(50)
    .withRelated(['assignee'])
    .build();
```

**Grouped conditions:**
```dart
final query = DatumQueryBuilder<Task>()
    .or([
      Filter('priority', FilterOperator.greaterThan, 5),
      Filter('title', FilterOperator.contains, 'urgent'),
    ])
    .build();
```

### DatumQueryField (Type-Safe Fields)

`DatumQueryField<E, V>` describes a field of entity `E` with value type `V`, giving compile-time checking of both the field and the compared value. The `datum_generator` package emits one descriptor per serializable field:

```dart
abstract class TaskFields {
  static const title = DatumQueryField<Task, String>('title');
  static const priority = DatumQueryField<Task, int>('priority');
}
```

```dart continue
final query = DatumQueryBuilder<Task>()
    .whereField(TaskFields.priority, isGreaterThan: 2)
    .orderByField(TaskFields.title)
    .build();

// Descriptors can also build Filters directly:
final filter = TaskFields.priority.greaterThan(4);
```

### LogicalOperator

Controls how multiple filters are combined:

- `and`: All filters must be true (default)
- `or`: At least one filter must be true

Set it via the builder's `logicalOperator` field or `DatumQuery(logicalOperator: ...)`.

## Usage Examples

### Basic Filtering

```dart
// Find incomplete tasks
final openTasks = await Datum.manager<Task>().query(
  DatumQuery(
    filters: [Filter('isCompleted', FilterOperator.equals, false)],
  ),
  source: DataSource.local,
  userId: 'user-123',
);
```

### Complex Queries

```dart
// Find high-priority tasks from last week
final urgentTasks = await Datum.manager<Task>().query(
  DatumQuery(
    filters: [
      Filter('priority', FilterOperator.greaterThan, 4),
      Filter('createdAt', FilterOperator.greaterThan, DateTime.now().subtract(Duration(days: 7))),
    ],
    sorting: [SortDescriptor('createdAt', descending: true)],
    limit: 20,
  ),
  source: DataSource.local,
  userId: 'user-123',
);
```

### Relationship Queries

```dart
// Load tasks with their assignees eagerly loaded
final tasksWithAssignees = await Datum.manager<Task>().query(
  DatumQuery(
    withRelated: ['assignee'],
    sorting: [SortDescriptor('createdAt', descending: true)],
  ),
  source: DataSource.local,
  userId: 'user-123',
);
```

### Reactive Queries

```dart
// Watch for changes to a query
final urgentTasksStream = Datum.manager<Task>().watchQuery(
  DatumQuery(
    filters: [Filter('priority', FilterOperator.greaterThan, 4)],
  ),
  userId: 'user-123',
);
```

## SQL Conversion

For SQL-backed adapters, any `DatumQuery` can be converted into a parameterized SQL statement with the `toSql` extension. It returns a `DatumSqlQueryResult` record with the SQL string and its parameters:

```dart
final query = DatumQueryBuilder<Task>()
    .where('isCompleted', isEqualTo: false)
    .orderBy('createdAt', descending: true)
    .limit(20)
    .build();

final DatumSqlQueryResult result = query.toSql('tasks', dialect: SqlDialect.sqlite);
print(result.sql);    // SELECT * FROM tasks WHERE isCompleted = ? ORDER BY ...
print(result.params); // [false]
```

`SqlDialect.sqlite` uses `?` placeholders, `SqlDialect.postgresql` uses `$1, $2, ...`, and `SqlDialect.custom` takes a `placeholderBuilder`. A `customBuilder` callback can translate app-specific operators (e.g. geo queries) into dialect-specific SQL.

## In-Memory Matching

`DatumQueryMatcher` is the reference implementation used by non-SQL adapters (Hive, in-memory). It applies a query's filters, sorting, offset, and limit to a list of entities or raw maps:

```dart
final tasks = await manager.readAll(userId: userId);

final query = DatumQueryBuilder<Task>()
    .where('priority', isGreaterThan: 3)
    .orderBy('createdAt', descending: true)
    .build();

// Filter + sort + paginate entity instances
final filtered = DatumQueryMatcher.apply(tasks, query);

// Or match raw maps (e.g. rows an adapter stores directly)
final matches = DatumQueryMatcher.matchesMap({'priority': 5}, query);
```

Adapters backed by SQL should instead translate the query with `toSql` and let the database do the work.

## Raw Queries

`DatumRawQuery` bypasses entity hydration for projections, aggregations, and joins — it returns raw rows (`List<DatumRawRow>`, i.e. `List<Map<String, dynamic>>`). The adapter must mix in `RawQueryCapable`:

```dart
// Local SQL adapter (e.g. datum_sqlite):
final rows = await manager.rawQuery(
  const DatumRawQuery(
    sql: 'SELECT id, title FROM tasks WHERE priority > ?',
    args: [3],
  ),
  source: DataSource.local,
);

// Remote adapter (structured fields instead of SQL):
final remoteRows = await manager.rawQuery(
  const DatumRawQuery(
    table: 'tasks',
    select: 'id, title',
    filters: {'priority': {'gt': 3}},
  ),
  source: DataSource.remote,
);
```

**DatumRawQuery fields:** `sql` + `args` for local SQL adapters; `table`, `select`, `filters` for remote adapters; `count` for count aggregations; `metadata` for adapter-specific extras. `rawQuery` throws `UnsupportedError` when the selected adapter does not mix in `RawQueryCapable`.

## Performance Considerations

### Indexing
Ensure your local adapters support indexing on frequently queried fields for optimal performance.

### Query Optimization
- Use specific filters to reduce result sets
- Leverage pagination to limit memory usage
- Use `withRelated` strategically to avoid N+1 queries
- Consider the performance impact of sorting large datasets

### Memory Management
- Large result sets consume memory; use pagination
- Prefer reactive queries (`watchQuery`) over polling
- Clean up streams when no longer needed

## Error Handling

Handle query-related errors appropriately. Datum errors carry a `DatumExceptionCode`:

```dart
final query = DatumQueryBuilder<Task>()
    .where('priority', isGreaterThan: 3)
    .build();

try {
  final results = await manager.query(query, source: DataSource.local, userId: userId);
  print('${results.length} matches');
} on DatumException catch (e) {
  switch (e.code) {
    case DatumExceptionCode.validationError:
      // Invalid query for this adapter
      break;
    case DatumExceptionCode.adapterError:
      // The underlying store failed to execute the query
      break;
    default:
      // Other Datum errors
      break;
  }
}
```

## Best Practices

1. **Use appropriate data sources**: Query local data for speed, remote data for freshness
2. **Implement pagination**: Always paginate large result sets
3. **Index queried fields**: Ensure adapters support indexing on filtered fields
4. **Use eager loading**: Leverage `withRelated` to prevent N+1 query issues
5. **Prefer type-safe fields**: Use `DatumQueryField` descriptors (via `datum_generator`) to catch typos at compile time
6. **Handle errors gracefully**: Implement comprehensive error handling
7. **Prefer reactive queries**: Use `watchQuery` for real-time data updates
