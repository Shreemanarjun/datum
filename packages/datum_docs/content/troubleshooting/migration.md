---
title: 🔄 Migration Troubleshooting
description: Debug and resolve Datum migration issues.
---


Handle schema changes, data transformations, and version upgrades in Datum.

Datum's migration system is built from a few pieces:

- **`Migration`** — one step from `fromVersion` to `toVersion`, with a per-row
  `migrate(Map) → Map` transform.
- **`SchemaMigration`** — a `Migration` described declaratively as a list of
  **`ColumnOperation`**s (`add`, `rename`, `remove`, `transform`, `row`).
- **`MigrationPlan`** — resolves and validates the chain of migrations before
  any data is touched.
- **`MigrationExecutor`** / **`SqlMigrationExecutor`** — run the plan,
  snapshotting the store first and restoring it on failure.

## Schema Migration Failures

### Issue: Migration execution errors

**Symptoms:** App crashes during startup with migration errors

**Common Causes:**
- Invalid data transformation logic
- Missing null checks in migration code
- A broken migration chain (gaps, duplicate starting versions, backward steps)

**Debugging Steps:**
```dart
// Enable detailed migration logging
final config = DatumConfig<Task>(
  enableLogging: true,
  logLevel: LogLevel.debug,
);

// Check the schema version currently stored by the local adapter
final currentVersion = await localAdapter.getStoredSchemaVersion();
print('Current schema version: $currentVersion');

// Verify a migration is needed
const targetVersion = 3; // Your target version
if (currentVersion < targetVersion) {
  print('Migration needed from v$currentVersion to v$targetVersion');
}
```

**Migration Implementation:**

A migration declares its version step and a per-row transform. There is no
per-migration `rollback` to write — the executor snapshots the store before
running and restores it automatically if any step throws.

```dart
class Migration1To2 extends Migration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    // Work on a copy to avoid mutating the executor's snapshot
    final migratedData = Map<String, dynamic>.of(oldData);

    // Safe field transformations
    if (migratedData.containsKey('oldFieldName')) {
      migratedData['newFieldName'] = migratedData.remove('oldFieldName');
    }

    // Add default values for new required fields
    migratedData['newRequiredField'] ??= 'defaultValue';

    return migratedData;
  }
}
```

The same change can be written declaratively with `SchemaMigration` — no
hand-written map surgery, and rows are copied for you:

```dart
final migration = SchemaMigration(
  fromVersion: 1,
  toVersion: 2,
  operations: [
    ColumnOperation.rename('oldFieldName', to: 'newFieldName'),
    ColumnOperation.add('newRequiredField', defaultValue: 'defaultValue'),
  ],
);
```

### Issue: Data loss during migration

**Symptoms:** Data disappears after migration

**Prevention Strategies:**

The `MigrationExecutor` snapshots the adapter's raw data and stored schema
version *before* running, validates the whole chain up front with
`MigrationPlan`, and restores the snapshot if anything fails — so a failed
migration never leaves the store half-migrated:

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
    // The store was restored to its pre-migration state
    print('Migration failed and was rolled back: ${result.migrationError}');
  }
}
```

In a normal app you rarely construct the executor yourself — the manager runs
it during `initialize()` whenever `DatumConfig.schemaVersion` is higher than
the version stored by the adapter.

## Version Compatibility Issues

### Issue: Local and remote schema mismatch

**Symptoms:** Sync fails with schema incompatibility errors

**Resolution Steps:**
```dart
// The stored schema version lives in the local adapter
final localVersion = await localAdapter.getStoredSchemaVersion();
print('Local schema version: $localVersion');

// A local/remote schema mismatch surfaces as a DatumException with
// code `schemaMismatch` — detect it with the typed result API:
final result = await manager.trySynchronize(userId);
if (result case Failure(value: final error)) {
  final cause = error.cause;
  if (cause is DatumException &&
      cause.code == DatumExceptionCode.schemaMismatch) {
    print('Schema mismatch — bump DatumConfig.schemaVersion and '
        'register migrations for it: $cause');
  }
}
```

### Issue: Breaking changes in entity definitions

**Symptoms:** Serialization/deserialization errors after entity changes

**Entity Evolution Strategies:**
```dart
class BackwardCompatibleTask extends DatumEntity {
  const BackwardCompatibleTask({
    required this.id,
    required this.userId,
    this.nickname,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  /// Handles both the old and the new field name when deserializing.
  factory BackwardCompatibleTask.fromMap(Map<String, dynamic> map) {
    return BackwardCompatibleTask(
      id: map['id'] as String,
      userId: map['userId'] as String,
      // Read the new name first, fall back to the legacy one.
      nickname: (map['nickname'] ?? map['displayName']) as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      modifiedAt: DateTime.parse(map['modifiedAt'] as String),
      version: map['version'] as int? ?? 1,
      isDeleted: map['isDeleted'] as bool? ?? false,
    );
  }

  @override
  final String id;
  @override
  final String userId;

  /// New field name; replaces the legacy `displayName`.
  final String? nickname;

  /// Keep the old accessor for callers that haven't migrated yet.
  @Deprecated('Use nickname instead')
  String? get displayName => nickname;

  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = <String, dynamic>{
      'id': id,
      'userId': userId,
      'nickname': nickname,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
    };
    // Keep writing the legacy name remotely until every client migrated.
    if (target == MapTarget.remote) {
      map['displayName'] = nickname;
    }
    return map;
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      toDatumMap(target: MapTarget.remote);
}
```

## Data Transformation Issues

### Issue: Complex data restructuring

**Symptoms:** Migration logic becomes too complex

**Advanced Migration Patterns:**
```dart
class ComplexMigration2To3 extends Migration {
  @override
  int get fromVersion => 2;

  @override
  int get toVersion => 3;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    final migratedData = Map<String, dynamic>.of(oldData);

    // Handle nested object restructuring
    if (migratedData['nestedObject'] is Map) {
      final nested =
          (migratedData['nestedObject'] as Map).cast<String, dynamic>();

      // Flatten nested structure
      migratedData['flattenedField'] = nested['deepField'];
      migratedData.remove('nestedObject');
    }

    // Handle array transformations
    if (migratedData['tags'] is List) {
      final tags = migratedData['tags'] as List;
      migratedData['tagObjects'] = tags
          .map((tag) => {
                'name': tag,
                'created': DateTime.now().toIso8601String(),
              })
          .toList();
    }

    return migratedData;
  }
}
```

### Issue: Large dataset migration performance

**Symptoms:** Migration takes too long for large datasets

**Performance Optimization:**

`migrate` runs once per row — keep it cheap and allocation-light. For SQL
adapters, give each operation its SQL counterpart so `SqlMigrationExecutor`
can run the whole migration as `ALTER TABLE` / `UPDATE` statements inside the
database instead of round-tripping every row through Dart:

```dart
final sqlFriendly = SchemaMigration(
  fromVersion: 2,
  toVersion: 3,
  operations: [
    ColumnOperation.add(
      'slug',
      compute: (row) => (row['title'] as String? ?? '').toLowerCase(),
      sqlType: 'TEXT',
      sqlExpression: 'lower(title)', // SQL counterpart of `compute`
    ),
    ColumnOperation.transform(
      'createdAt',
      (value, row) => value ?? DateTime(2000).toIso8601String(),
      sqlExpression: "COALESCE(createdAt, '2000-01-01T00:00:00.000')",
    ),
  ],
);
```

## Cross-Platform Migration Issues

### Issue: Platform-specific data incompatibility

**Symptoms:** Data works on one platform but fails on another

**Cross-Platform Solutions:**
```dart
import 'dart:io';

class CrossPlatformMigration extends Migration {
  @override
  int get fromVersion => 3;

  @override
  int get toVersion => 4;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    final migratedData = Map<String, dynamic>.of(oldData);

    // Normalize platform-specific data
    migratedData['platform'] = detectCurrentPlatform();

    // Handle file path differences
    final filePath = migratedData['filePath'];
    if (filePath is String) {
      migratedData['filePath'] = normalizeFilePath(filePath);
    }

    // Standardize date formats
    final createdAt = migratedData['createdAt'];
    if (createdAt is String) {
      migratedData['createdAt'] = standardizeDateFormat(createdAt);
    }

    return migratedData;
  }

  String detectCurrentPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  String normalizeFilePath(String path) =>
      path.replaceAll(r'\', Platform.pathSeparator);

  String standardizeDateFormat(String raw) =>
      (DateTime.tryParse(raw) ?? DateTime(2000)).toUtc().toIso8601String();
}
```

## Testing Migration Changes

### Testing a single migration step

A `Migration` is a pure per-row function, so it can be tested directly:

```dart
Future<void> main() async {
  final migration = SchemaMigration(
    fromVersion: 1,
    toVersion: 2,
    operations: [
      ColumnOperation.rename('oldFieldName', to: 'newFieldName'),
    ],
  );

  // Forward migration transforms the row as expected
  final migrated = migration.migrate({'id': 'a', 'oldFieldName': 'x'});
  assert(migrated['newFieldName'] == 'x');
  assert(!migrated.containsKey('oldFieldName'));

  // Rows without the field pass through untouched
  final untouched = migration.migrate({'id': 'b'});
  assert(!untouched.containsKey('newFieldName'));
}
```

### Testing the whole migration pipeline

`package:datum_test` ships a conformance suite that exercises ordering,
rollback-on-failure, version stamping and more against a real adapter:

```dart
void main() {
  runMigrationConformanceTests(
    name: 'in-memory',
    createLocal: () async => InMemoryLocalAdapter<ConformanceEntity>(
      fromMap: ConformanceEntity.fromMap,
    ),
  );
}
```

## Rollback and Recovery

### Issue: Failed migration recovery

**Symptoms:** Migration fails and app is left in broken state

**Recovery Strategies:**

The executor already restores its pre-migration snapshot when a step fails.
For a last-resort recovery strategy on top of that, register
`onMigrationError` in your config:

```dart
final config = DatumConfig<Task>(
  schemaVersion: 2,
  migrations: [
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [ColumnOperation.add('priority', defaultValue: 0)],
    ),
  ],
  onMigrationError: (error, stackTrace) async {
    print('Migration failed: $error');
    // Emergency recovery: clear local data and let sync rebuild it.
    await localAdapter.clear();
  },
);
```

If `onMigrationError` is null, the error is rethrown so the app never runs
against a store it cannot understand.

## Best Practices

### 1. Test Migrations Thoroughly
```dart
Future<void> main() async {
  final migration = SchemaMigration(
    fromVersion: 1,
    toVersion: 2,
    operations: [ColumnOperation.add('priority', defaultValue: 0)],
  );

  final row = {'id': 't1', 'title': 'Test'};
  final migrated = migration.migrate(row);

  // Data integrity is preserved
  assert(migrated['id'] == 't1');
  assert(migrated['title'] == 'Test');
  assert(migrated['priority'] == 0);
}
```

### 2. Version Control Migrations

Keep one migration file per step in version control, and let
`MigrationPlan` validate the chain — duplicate starting versions, gaps,
backward steps, and overshoots all fail fast, before any data is touched:

```dart
final plan = MigrationPlan.resolve(
  [
    SchemaMigration(fromVersion: 1, toVersion: 2, operations: [
      ColumnOperation.add('priority', defaultValue: 0),
    ]),
    SchemaMigration(fromVersion: 2, toVersion: 3, operations: [
      ColumnOperation.rename('name', to: 'title'),
    ]),
  ],
  fromVersion: 1,
  toVersion: 3,
);
print('Steps to run: ${plan.steps.length}');
```

### 3. Monitor Migration Performance
```dart
class MigrationMonitor {
  /// Wraps a per-row migration with timing output.
  static Map<String, dynamic> monitorMigration(
    Migration migration,
    Map<String, dynamic> row,
  ) {
    final stopwatch = Stopwatch()..start();
    final result = migration.migrate(row);
    stopwatch.stop();

    print('${migration.runtimeType} '
        'v${migration.fromVersion} -> v${migration.toVersion}: '
        '${stopwatch.elapsedMicroseconds}us');
    return result;
  }
}
```

---


*For more migration patterns, check the [Migration Module](../../modules/migration) documentation.*
