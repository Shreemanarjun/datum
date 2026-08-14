---
title: Migration Module
---

The Migration module handles database schema and data migrations when upgrading between different versions of your Datum entities.

## Overview

Migrations are essential when you need to modify your entity structure, add new fields, or transform existing data. Datum provides a robust migration system: a **declarative API** (`SchemaMigration` + `ColumnOperation`) for the common cases, a low-level `Migration` base class for arbitrary transformations, and a **SQL executor** that runs the same declarative migrations natively on SQL stores.

## Key Components

### Migration

Abstract base class representing a single migration step from one schema version to another.

**Required Members:**
- `fromVersion`: The schema version this migration starts from (integer)
- `toVersion`: The schema version this migration migrates to (integer)
- `migrate(Map<String, dynamic> oldData)`: Transforms a single raw entity map

### SchemaMigration (Recommended)

A `Migration` described as a list of `ColumnOperation`s instead of hand-written map surgery.

**Constructor Parameters:**
- `fromVersion` / `toVersion`: The version step (toVersion must be greater)
- `operations`: The `ColumnOperation`s applied, in order, to every matching row
- `entityType`: Optional — only rows whose `__typename` matches are migrated
- `where`: Optional predicate scoping which rows are migrated
- `sqlWhere`: Optional SQL `WHERE` clause counterpart of `where` for the SQL path

### ColumnOperation

Declarative row transformations with factory shorthands:

- `ColumnOperation.add(name, {defaultValue, compute, overwrite, sqlType, sqlExpression})`
- `ColumnOperation.rename(from, to: ...)`
- `ColumnOperation.remove(name)`
- `ColumnOperation.transform(name, (value, row) => ..., {applyIfAbsent, sqlExpression})`
- `ColumnOperation.row((row) => ..., {sql})` — whole-row rewrite

### MigrationExecutor

Orchestrates the execution of schema migrations against a local adapter.

**Constructor Parameters:**
- `localAdapter`: The `LocalAdapter` whose data is migrated
- `migrations`: The available `Migration`s
- `targetVersion`: The version to migrate up to
- `logger`: A `DatumLogger`

**Key Methods:**
- `needsMigration()`: Whether the stored schema version is behind `targetVersion`
- `execute()`: Resolves the chain with `MigrationPlan`, snapshots the store, runs the migrations inside a transaction, and returns a `MigrationResult`

### MigrationResult

A record describing the outcome of a migration run:

```dart no-verify
typedef MigrationResult = ({
  bool success,
  Object? migrationError,
  StackTrace? migrationStack,
});
```

### MigrationPlan

Resolves and validates the chain of migrations from one version to another **before any data is touched**. It throws a `MigrationException` describing every problem found — duplicate starting versions, steps that don't move forward, gaps in the chain, or steps that overshoot the target.

## Creating Migrations

### Declarative Migrations (Recommended)

Most migrations are column additions, renames, removals, or value transformations — express them with `SchemaMigration`:

```dart
final addPriority = SchemaMigration(
  fromVersion: 1,
  toVersion: 2,
  operations: [
    // Add priority field with a default value
    ColumnOperation.add('priority', defaultValue: 3),
  ],
);

final renameDescription = SchemaMigration(
  fromVersion: 2,
  toVersion: 3,
  operations: [
    // Rename "description" to "content"; rows without the field pass through
    ColumnOperation.rename('description', to: 'content'),
  ],
);

final convertStatus = SchemaMigration(
  fromVersion: 3,
  toVersion: 4,
  operations: [
    // Convert string status to integer enum values
    ColumnOperation.transform('status', (value, row) {
      switch (value) {
        case 'pending':
          return 0;
        case 'in_progress':
          return 1;
        case 'completed':
          return 2;
        default:
          return value;
      }
    }),
  ],
);
```

Computed columns and whole-row rewrites are also supported:

```dart
final computed = SchemaMigration(
  fromVersion: 4,
  toVersion: 5,
  operations: [
    // Compute a value from the rest of the row
    ColumnOperation.add(
      'slug',
      compute: (row) => (row['title'] as String? ?? '').toLowerCase(),
    ),
    // Arbitrary whole-row rewrite — spread the input to keep untouched columns
    ColumnOperation.row(
      (row) => {...row, 'fullName': '${row['firstName']} ${row['lastName']}'},
    ),
  ],
);
```

### Custom Migration Classes

For logic that doesn't fit the declarative operations, extend `Migration` directly:

```dart
class AddPriorityToTasksMigration extends Migration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    // Add priority field with default value
    return {
      ...oldData,
      'priority': oldData['priority'] ?? 3, // Default medium priority
    };
  }
}
```

```dart
class NormalizeDatesMigration extends Migration {
  @override
  int get fromVersion => 2;

  @override
  int get toVersion => 3;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    final result = Map<String, dynamic>.from(oldData);

    // Normalize createdAt to UTC ISO-8601
    final createdAt = result['createdAt'];
    if (createdAt is String) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) {
        result['createdAt'] = parsed.toUtc().toIso8601String();
      }
    }

    return result;
  }
}
```

## Configuring Migrations

### In DatumConfig

```dart
final config = DatumConfig(
  schemaVersion: 4, // Current schema version
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [ColumnOperation.add('priority', defaultValue: 3)],
    ),
    SchemaMigration(
      fromVersion: 2,
      toVersion: 3,
      operations: [ColumnOperation.rename('description', to: 'content')],
    ),
    SchemaMigration(
      fromVersion: 3,
      toVersion: 4,
      operations: [ColumnOperation.remove('legacyField')],
    ),
  ],
);
```

### Migration Execution Order

Migrations are executed in version order automatically. Before touching data, `MigrationPlan.resolve` validates the whole chain:

1. Reads the current stored schema version from the local adapter
2. Builds the ordered chain of migrations to reach the target version
3. Fails fast (throwing `MigrationException`) on gaps, duplicates, backwards steps, or overshooting steps
4. Executes migrations in ascending version order and updates the stored version after each step

## Migration Lifecycle

### Automatic Execution

Migrations run automatically during Datum initialization if the stored schema version is lower than the configured version.

```dart
class MyConnectivityChecker implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
```

```dart continue
// Migrations run automatically during initialization
await Datum.initialize(
  config: DatumConfig(
    schemaVersion: 4,
    migrations: [/* migration list */],
  ),
  connectivityChecker: MyConnectivityChecker(),
);
```

### Manual Execution

You can also execute migrations manually with `MigrationExecutor`:

```dart
final executor = MigrationExecutor<Task>(
  localAdapter: localAdapter,
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [ColumnOperation.add('priority', defaultValue: 0)],
    ),
  ],
  targetVersion: 2,
  logger: logger,
);

if (await executor.needsMigration()) {
  final result = await executor.execute();
  if (result.success) {
    print('Migration completed');
  } else {
    print('Migration failed: ${result.migrationError}');
  }
}
```

## SQL Migrations

For SQL-backed adapters (like `SqliteLocalAdapter` from `datum_sqlite`), the map-based executor's serialize-rewrite-overwrite cycle can't add or drop real table columns. `SqlMigrationExecutor` runs the *same* `SchemaMigration`s natively as `ALTER TABLE`/`UPDATE` statements through the adapter's `RawQueryCapable.rawQuery`:

```dart
final executor = SqlMigrationExecutor<Task>(
  localAdapter: localAdapter, // must mix in RawQueryCapable
  table: 'tasks',
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [
        // sqlType overrides the column type inferred from defaultValue
        ColumnOperation.add('priority', defaultValue: 0, sqlType: 'INTEGER'),
        // sqlExpression is the SQL counterpart of the Dart transform closure
        ColumnOperation.transform(
          'title',
          (value, row) => (value as String).trim(),
          sqlExpression: 'TRIM(title)',
        ),
      ],
    ),
  ],
  targetVersion: 2,
  logger: logger,
);

final result = await executor.execute();
print(result.success ? 'Migrated' : 'Failed: ${result.migrationError}');
```

Every statement for the whole chain is generated (and therefore validated) up front, and execution runs inside the adapter's transaction, so an invalid or partially-expressible chain never touches the database.

`SqlMigrationGenerator` can be used directly to inspect the generated statements:

```dart
final generator = SqlMigrationGenerator(dialect: SqlDialect.sqlite);
final statements = generator.statementsFor(
  SchemaMigration(
    fromVersion: 1,
    toVersion: 2,
    operations: [ColumnOperation.add('priority', defaultValue: 0, sqlType: 'INTEGER')],
  ),
  table: 'tasks',
);
statements.forEach(print);
```

Custom `ColumnOperation` implementations can participate in the SQL path by implementing `SqlConvertibleOperation` and its `toSqlStatements(table, dialect)` method.

## Error Handling

### Migration Failures

`MigrationExecutor.execute()` never leaves the store in a partially-migrated state: it snapshots the adapter's raw data and stored version before running, executes inside a transaction where possible, and restores the snapshot on failure. Errors are reported through the returned `MigrationResult` rather than thrown:

```dart
final executor = MigrationExecutor<Task>(
  localAdapter: localAdapter,
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [ColumnOperation.add('priority', defaultValue: 0)],
    ),
  ],
  targetVersion: 2,
  logger: logger,
);

final result = await executor.execute();
if (!result.success) {
  print('Migration failed: ${result.migrationError}');
  print(result.migrationStack);
  // The store was restored to its pre-migration state
}
```

During `Datum.initialize`, migration failures are routed to `DatumConfig.onMigrationError` if provided — otherwise they are rethrown so the app never runs against a corrupted database:

```dart
final config = DatumConfig(
  schemaVersion: 2,
  migrations: [/* ... */],
  onMigrationError: (error, stackTrace) async {
    // Custom recovery strategy, e.g. report and clear local data
    print('Migration failed: $error');
  },
);
```

### Invalid Migration Chains

`MigrationPlan.resolve` validates a chain without executing it:

```dart
try {
  final plan = MigrationPlan.resolve(
    [
      SchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        operations: [ColumnOperation.add('priority', defaultValue: 0)],
      ),
      // Gap: nothing starts at version 2
      SchemaMigration(
        fromVersion: 3,
        toVersion: 4,
        operations: [ColumnOperation.remove('legacyField')],
      ),
    ],
    fromVersion: 1,
    toVersion: 4,
  );
  print('${plan.steps.length} steps to run');
} on MigrationException catch (e) {
  print('Invalid migration configuration: ${e.message}');
}
```

## Best Practices

### Migration Design

1. **Make migrations idempotent**: They should be safe to run multiple times
2. **Test migrations thoroughly**: Test on sample data before production
3. **Keep migrations small**: One migration per logical change
4. **Prefer declarative operations**: `SchemaMigration` is validated, SQL-convertible, and never mutates its input rows
5. **Rely on the automatic snapshot**: The executor restores the pre-migration state on failure — you don't write rollback code

### Data Safety

1. **Backup data first**: Always backup before running migrations
2. **Validate data**: Check data integrity after migration
3. **Handle edge cases**: Account for unexpected data formats
4. **Use transactions**: The executor wraps the run in `LocalAdapter.transaction` when the adapter supports it

### Version Management

1. **Increment versions sequentially**: Each step's `toVersion` must chain to the next step's `fromVersion`
2. **Never skip versions**: `MigrationPlan` rejects chains with gaps
3. **Document version changes**: Keep a changelog of what each version changes
4. **Test version upgrades**: Test upgrades from multiple previous versions

### Performance Considerations

1. **Batch operations**: Process data in batches for large datasets
2. **Prefer the SQL executor for SQL stores**: `ALTER TABLE`/`UPDATE` beats a full serialize-rewrite cycle
3. **Memory management**: Be mindful of memory usage with large datasets
4. **Timeout handling**: Implement timeouts for long-running migrations

## Migration Examples

### Adding a New Field

```dart
final addCreatedBy = SchemaMigration(
  fromVersion: 4,
  toVersion: 5,
  operations: [
    // Default the new field from another column on the same row
    ColumnOperation.add('createdBy', compute: (row) => row['userId']),
  ],
);
```

### Splitting Fields

```dart
final splitName = SchemaMigration(
  fromVersion: 5,
  toVersion: 6,
  operations: [
    ColumnOperation.row((row) {
      final fullName = row['fullName'];
      if (fullName is! String) return row;
      row.remove('fullName');
      final parts = fullName.split(' ');
      return {
        ...row,
        'firstName': parts.isNotEmpty ? parts.first : '',
        'lastName': parts.length > 1 ? parts.sublist(1).join(' ') : '',
      };
    }),
  ],
);
```

### Scoped Cleanup

A migration cannot drop rows, but it can scope itself to the rows that need fixing and flag them:

```dart
final flagInvalid = SchemaMigration(
  fromVersion: 6,
  toVersion: 7,
  // Only rows matching the predicate are migrated; others pass through
  where: (row) => row['status'] == 'invalid',
  operations: [
    ColumnOperation.add('isDeleted', defaultValue: true, overwrite: true),
  ],
);
```

## Troubleshooting

### Common Issues

1. **Migration fails mid-execution**: The executor restores its pre-migration snapshot automatically; inspect `MigrationResult.migrationError`
2. **Data corruption**: Always backup before migrating
3. **Performance issues**: Optimize migrations for large datasets
4. **Version conflicts**: `MigrationPlan` rejects duplicate or non-sequential version steps up front

### Debugging Migrations

```dart
// Enable detailed logging
final config = DatumConfig(
  enableLogging: true,
  logLevel: LogLevel.debug,
);

// Test a migration on sample data
final migration = SchemaMigration(
  fromVersion: 1,
  toVersion: 2,
  operations: [ColumnOperation.add('priority', defaultValue: 3)],
);

final migrated = migration.migrate({'id': '1', 'title': 'Test'});
print('Migration result: $migrated');
// {id: 1, title: Test, priority: 3}
```
