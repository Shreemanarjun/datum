---
title: Code Generation
---

# Code Generation with datum_generator

Datum provides a powerful code generator that automatically creates boilerplate code for your entities, significantly reducing development time and eliminating common errors.

## Why Use Code Generation?

Writing manual serialization, deserialization, diff tracking, and copy methods for every entity is:

- **Time-consuming**: Repetitive boilerplate code for every field
- **Error-prone**: Easy to miss fields or make type conversion mistakes
- **Hard to maintain**: Changes to your entity require updating multiple methods
- **Inconsistent**: Different developers may implement methods differently

The `datum_generator` package solves these problems by automatically generating:

- ✅ `toDatumMap()` - Serialization with automatic snake_case conversion
- ✅ `fromMap()` - Type-safe deserialization with proper null handling
- ✅ `diff()` - Change tracking between entity versions
- ✅ `copyWith()` and `copyWithAll()` - Immutable updates with automatic version incrementing
- ✅ `operator ==` and `hashCode` - Proper equality comparisons
- ✅ Helper methods for date parsing and list equality

Add `datum_generator` as a dependency (for annotations) and a dev dependency (for the builder) in your `pubspec.yaml`:

```yaml
dependencies:
  datum: ^1.1.0
  datum_generator: ^1.1.0

dev_dependencies:
  build_runner: ^2.4.0
  datum_generator: ^1.1.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

### 1. Annotate Your Entity

Add the `@DatumSerializable` annotation, set `generateMixin: true`, and include the part directive:

```dart
import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';

part 'task.g.dart';

@DatumSerializable(tableName: 'tasks', generateMixin: true)
class Task extends DatumEntity with _$TaskMixin {
  @override
  final String id;

  @override
  final String userId;

  final String title;
  final String? description;
  final bool isCompleted;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  const Task({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });
}
```

By using the generated mixin (`with _$TaskMixin`), you no longer need to manually override `toDatumMap`, `diff`, `copyWith`, `operator ==`, or `hashCode`. The generator handles everything!

### 2. Run the Generator

Execute the build runner to generate the code:

```bash
dart run build_runner build
```

For continuous generation during development:

```bash
dart run build_runner watch
```

This creates a `task.g.dart` file with all the boilerplate code!

### 3. Use the Generated Code

The generated file includes:

```dart no-verify
// task.g.dart (generated)
extension $TaskDatum on Task {
  static const String tableName = 'tasks';

  Map<String, dynamic> datumToMap({MapTarget target = MapTarget.local}) {
    // Automatic serialization with snake_case conversion
  }

  Map<String, dynamic>? datumDiff(DatumEntityInterface oldVersion) {
    // Automatic change tracking
  }

  Task copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    // Metadata-only copy
  }

  Task copyWithAll({/* all fields */}) {
    // Full copy with version incrementing
  }

  bool datumEquals(Task other) {
    // Field-by-field equality
  }

  int get datumHashCode {
    // Proper hash code generation
  }
}

Task _$TaskFromMap(Map<String, dynamic> map) {
  // Type-safe deserialization
}
```

## Available Annotations

### @DatumSerializable

Marks a class for code generation.

```dart
import 'package:datum_generator/datum_generator.dart';

@DatumSerializable(tableName: 'custom_table_name')
class MyEntity extends DatumEntity {
  // ...
}
```

**Parameters:**
- `tableName` (optional): Custom table name. Defaults to snake_case of class name.
- `generateMixin` (optional, default: `true`): Generates a `_$EntityNameMixin` that implements all required `DatumEntity` methods. Set it to `false` if you prefer to write those methods yourself and only want the extension helpers.
- `strictNullChecks` (optional, default: `false`): When `true`, the generated `fromMap` uses plain casts instead of substituting default values for missing non-nullable primitives.

### @DatumIgnore

Excludes a field from serialization (but still includes it in `copyWith` and equality checks).

```dart
import 'package:datum_generator/datum_generator.dart';

class User extends DatumEntity {
  final String email;

  @DatumIgnore()
  final String? temporaryToken;  // Won't be serialized to database

  // ...
}
```

**Use cases:**
- Computed properties
- Temporary runtime data
- Sensitive information that shouldn't be persisted
- UI state that doesn't belong in the database

### @DatumField

Specifies a custom database field name.

```dart
import 'package:datum_generator/datum_generator.dart';

class Product extends DatumEntity {
  @DatumField(name: 'product_name')
  final String name;

  @DatumField(name: 'unit_price')
  final double price;

  // ...
}
```

**Use cases:**
- Matching existing database schemas
- Following specific naming conventions
- Avoiding reserved keywords

## Supported Types

The generator automatically handles these types:

### Primitives
- `String`, `int`, `double`, `bool`
- Nullable variants: `String?`, `int?`, etc.

### Dates
- `DateTime` - Automatically converts between:
  - Milliseconds (local storage)
  - ISO8601 strings (remote storage)

### Flutter Types
- `Color` - Serialized as ARGB integer
- `Offset` - Serialized as `{x: double, y: double}`
- `List<Offset>` - Serialized as array of offset maps

### Collections
- `List<T>` - With proper equality checking
- `Map<String, dynamic>` - Nested data structures

### Example with Complex Types

```dart
import 'dart:ui';
import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';

part 'drawing.g.dart';

@DatumSerializable()
class Drawing extends DatumEntity {
  final Color backgroundColor;
  final List<Offset> points;
  final double strokeWidth;
  final Map<String, dynamic>? metadata;

  // ... constructor and other methods
}
```

Generated code handles:
- `Color` → `int` (ARGB format)
- `List<Offset>` → `List<Map<String, dynamic>>`
- Proper type conversions in both directions

## Advanced Usage

### Relational Entities

The generator works seamlessly with `RelationalDatumEntity`:

```dart
import 'package:datum_generator/datum_generator.dart';

part 'paint_canvas.g.dart';

@DatumSerializable(tableName: 'paint_canvases', generateMixin: true)
class PaintCanvas extends RelationalDatumEntity with _$PaintCanvasMixin {
  @override
  final String id;

  @override
  final String userId;

  final String title;
  final int strokeCount;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  const PaintCanvas({
    required this.id,
    required this.userId,
    required this.title,
    this.strokeCount = 0,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => datumRelations;

  @HasManyRelation<PaintStroke>('canvasId', cascadeDelete: 'cascade')
  final List<PaintStroke>? _strokes = null;

  factory PaintCanvas.fromMap(Map<String, dynamic> map) {
    return _$PaintCanvasFromMap(map);
  }
}
```

### Custom Serialization Logic

If you need custom logic for specific fields, you can still use the generator for most fields:

```dart
import 'package:datum_generator/datum_generator.dart';

@DatumSerializable()
class CustomEntity extends DatumEntity {
  final String normalField;

  @DatumIgnore()
  final ComplexType customField;

  // Override toDatumMap to add custom field
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = datumToMap(target: target);
    map['custom_field'] = customField.toJson();
    return map;
  }

  // Override fromMap to parse custom field
  factory CustomEntity.fromMap(Map<String, dynamic> map) {
    final entity = _$CustomEntityFromMap(map);
    return entity.copyWithAll(
      customField: ComplexType.fromJson(map['custom_field']),
    );
  }
}
```

## Generated Method Details

### datumToMap()

Converts the entity to a map with automatic field name conversion:

```dart no-verify
final task = Task(
  id: '1',
  userId: 'user1',
  title: 'Buy groceries',
  createdAt: DateTime.now(),
  modifiedAt: DateTime.now(),
);

// For local storage (milliseconds)
final localMap = task.datumToMap(target: MapTarget.local);
// {
//   'id': '1',
//   'user_id': 'user1',
//   'title': 'Buy groceries',
//   'createdAt': 1704729600000,
//   'modifiedAt': 1704729600000,
// }

// For remote storage (ISO8601)
final remoteMap = task.datumToMap(target: MapTarget.remote);
// {
//   'id': '1',
//   'user_id': 'user1',
//   'title': 'Buy groceries',
//   'createdAt': '2024-01-08T12:00:00.000Z',
//   'modifiedAt': '2024-01-08T12:00:00.000Z',
// }
```

### datumDiff()

Tracks changes between versions:

```dart no-verify
final oldTask = Task(
  id: '1',
  userId: 'user1',
  title: 'Buy groceries',
  isCompleted: false,
  createdAt: DateTime.now(),
  modifiedAt: DateTime.now(),
);

final newTask = oldTask.copyWithAll(
  title: 'Buy groceries and cook',
  isCompleted: true,
);

final changes = newTask.datumDiff(oldTask);
// {
//   'title': 'Buy groceries and cook',
//   'is_completed': true,
//   'modifiedAt': '2024-01-08T12:05:00.000Z',
//   'version': 2,
// }
```

### copyWithAll()

Creates a copy with automatic version incrementing:

```dart no-verify
final task = Task(
  id: '1',
  userId: 'user1',
  title: 'Original',
  version: 1,
  createdAt: DateTime.now(),
  modifiedAt: DateTime.now(),
);

final updated = task.copyWithAll(
  title: 'Updated',
  isCompleted: true,
);

print(updated.version);  // 2 (automatically incremented)
print(updated.title);    // 'Updated'
```

### datumEquals() and datumHashCode

Proper equality and hashing:

```dart no-verify
final task1 = Task(id: '1', userId: 'user1', title: 'Task', ...);
final task2 = Task(id: '1', userId: 'user1', title: 'Task', ...);
final task3 = Task(id: '1', userId: 'user1', title: 'Different', ...);

print(task1 == task2);  // true (all fields match)
print(task1 == task3);  // false (title differs)

final set = {task1, task2};
print(set.length);  // 1 (task2 is considered duplicate)
```

## Best Practices

### 1. Always Use Part Directive

```dart no-verify
// ✅ Correct
part 'my_entity.g.dart';

// ❌ Wrong - will cause build errors
// Missing part directive
```

### 2. Use Const Constructors

```dart no-verify
// ✅ Preferred
const Task({
  required this.id,
  required this.userId,
  // ...
});

// ⚠️ Works but less efficient
Task({
  required this.id,
  required this.userId,
  // ...
});
```

### 3. Implement Equality Using Generated Methods

```dart no-verify
// ✅ Correct
@override
bool operator ==(Object other) => other is Task && datumEquals(other);

@override
int get hashCode => datumHashCode;

// ❌ Wrong - manual implementation may miss fields
@override
bool operator ==(Object other) {
  return other is Task && other.id == id && other.title == title;
}
```

### 4. Run Generator After Schema Changes

```bash
# Clean build cache if you encounter issues
dart run build_runner clean

# Rebuild with conflict resolution
dart run build_runner build --delete-conflicting-outputs
```

### 5. Commit Generated Files

Always commit `.g.dart` files to version control for consistency across team members and CI/CD pipelines.

## Troubleshooting

### Generator Not Running

**Problem:** No `.g.dart` file is created.

**Solutions:**
1. Ensure you have the `part` directive: `part 'filename.g.dart';`
2. Verify the class is annotated: `@DatumSerializable()`
3. Check that `datum_generator` is in `dev_dependencies`
4. Run `flutter pub get` to install dependencies

### Build Errors

**Problem:** Build fails with errors.

**Solutions:**
```bash
# Clean and rebuild
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Type Errors in Generated Code

**Problem:** Generated code has type mismatches.

**Solutions:**
1. Ensure all fields have explicit types (avoid `var` or `dynamic`)
2. Use nullable types correctly (`String?` vs `String`)
3. Check that custom types are properly imported

### Missing Fields in Generated Methods

**Problem:** Some fields are not included in generated code.

**Solutions:**
1. Check if fields are marked with `@DatumIgnore()`
2. Verify fields are not `static` or `synthetic`
3. Ensure fields are instance variables, not getters

### Conflicts with Manual Implementation

**Problem:** Generated methods conflict with existing code.

**Solutions:**
1. Remove manual implementations of `toDatumMap`, `fromMap`, etc.
2. Use generated methods by calling `datumToMap()`, `_$EntityFromMap()`, etc.
3. For custom logic, override and call generated methods:

```dart no-verify
@override
Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
  final map = datumToMap(target: target);
  // Add custom logic
  map['computed_field'] = someComputation();
  return map;
}
```

## Performance Considerations

The code generator produces highly optimized code:

- **No reflection**: All code is generated at compile time
- **Type-safe**: No runtime type checking overhead
- **Efficient**: Direct field access without intermediate representations
- **Minimal overhead**: Generated code is as fast as hand-written code

## Comparison: Manual vs Generated

### Manual Implementation (Before)

```dart no-verify
class Task extends DatumEntity {
  // 50+ lines of boilerplate per entity

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = {
      'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'is_deleted': isDeleted,
      'version': version,
    };
    if (target == MapTarget.remote) {
      map['createdAt'] = createdAt.toIso8601String();
      map['modifiedAt'] = modifiedAt.toIso8601String();
    } else {
      map['createdAt'] = createdAt.millisecondsSinceEpoch;
      map['modifiedAt'] = modifiedAt.millisecondsSinceEpoch;
    }
    return map;
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: (map['id'] ?? '') as String,
      userId: (map['userId'] ?? map['user_id'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      description: map['description'] as String?,
      isCompleted: (map['isCompleted'] ?? map['is_completed'] ?? false) as bool,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']),
      modifiedAt: _parseDate(map['modifiedAt'] ?? map['modified_at']),
      isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? false) as bool,
      version: (map['version'] ?? 1) as int,
    );
  }

  // ... more boilerplate for diff, copyWith, equality, etc.
}
```

### Generated Implementation (After)

```dart
import 'package:datum_generator/datum_generator.dart';

part 'task.g.dart';

@DatumSerializable()
class Task extends DatumEntity {
  // Just 10 lines to use generated code

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return datumToMap(target: target);
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return _$TaskFromMap(map);
  }

  @override
  bool operator ==(Object other) => other is Task && datumEquals(other);

  @override
  int get hashCode => datumHashCode;
}
```

**Benefits:**
- ✅ 80% less code to write and maintain
- ✅ Zero chance of missing fields
- ✅ Consistent implementation across all entities
- ✅ Automatic updates when fields change

## Next Steps

- **[Define Entities](/guides/entity_define)**: Learn more about entity definition patterns
- **[Implement Adapters](/guides/local_adapter_implement)**: Set up local and remote adapters
- **[Work with Relationships](/guides/relationships)**: Use code generation with relational entities
- **[Query Data](/guides/querying)**: Learn how to query generated entities

## Additional Resources

- [datum_generator Package](https://pub.dev/packages/datum_generator)
- [Example Project](https://github.com/shreemanarjun/datum/tree/main/packages/datum/example)
- [API Documentation](https://pub.dev/documentation/datum_generator/latest/)
