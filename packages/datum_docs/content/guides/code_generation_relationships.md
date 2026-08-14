---
title: Code Generation - Relationships
---

# Automated Relationship Generation

The `datum_generator` can automatically create the `relations` getter for `RelationalDatumEntity` classes, eliminating the need to manually define relationships.

## Overview

Instead of manually writing the `relations` getter, you can use relationship annotations on placeholder fields. The generator will automatically create the complete `relations` map for you.

**Important:**
- If your field name starts with an underscore (e.g., `_posts`), the generator will strip the underscore for the relation name in the `datumRelations` map (e.g., `'posts'`).
- When `generateMixin: true` is used, the generator also adds public getters and setters for these private fields (e.g., `get posts` and `set posts`) to make them easily accessible from outside the entity while keeping the storage private.

## Available Relationship Annotations

### 1. @BelongsToRelation<T>

Use when **this entity** has a foreign key pointing to another entity.

```dart no-verify
@BelongsToRelation<User>('userId', cascadeDelete: 'none')
final String? _author = null;
```

**Parameters:**
- `foreignKey` (required): The foreign key field name in this entity
- `localKey` (optional, default: 'id'): The local key in the related entity
- `cascadeDelete` (optional, default: 'none'): Cascade behavior ('none', 'cascade', 'restrict', 'setNull')

### 2. @HasManyRelation<T>

Use when **another entity** has a foreign key pointing to this entity (one-to-many).

```dart no-verify
@HasManyRelation<Post>('userId', cascadeDelete: 'cascade')
final List<Post>? _posts = null;
```

**Parameters:**
- `foreignKey` (required): The foreign key field name in the related entity
- `localKey` (optional, default: 'id'): The local key in this entity
- `cascadeDelete` (optional, default: 'none'): Cascade behavior

### 3. @HasOneRelation<T>

Use when **another entity** has a foreign key pointing to this entity (one-to-one).

```dart no-verify
@HasOneRelation<Profile>('userId')
final Profile? _profile = null;
```

**Parameters:**
- `foreignKey` (required): The foreign key field name in the related entity
- `localKey` (optional, default: 'id'): The local key in this entity
- `cascadeDelete` (optional, default: 'none'): Cascade behavior

### 4. @ManyToManyRelation<T, P>

Use for many-to-many relationships through a pivot entity.

```dart no-verify
@ManyToManyRelation<Tag, PostTag>(
  pivotEntity: PostTag,
  thisForeignKey: 'postId',
  otherForeignKey: 'tagId',
  cascadeDelete: 'cascade',
)
final List<Tag>? _tags = null;
```

**Parameters:**
- `pivotEntity` (required): The pivot entity type
- `thisForeignKey` (required): Foreign key in pivot pointing to this entity
- `otherForeignKey` (required): Foreign key in pivot pointing to related entity
- `thisLocalKey` (optional, default: 'id'): Local key in this entity
- `otherLocalKey` (optional, default: 'id'): Local key in related entity
- `cascadeDelete` (optional, default: 'none'): Cascade behavior

## Complete Example

### Before (Manual)

```dart
import 'package:datum_generator/datum_generator.dart';

@DatumSerializable(tableName: 'users')
class User extends RelationalDatumEntity {
  @override
  final String id;

  final String name;
  final String email;

  // ... other fields

  // Manual relationship definition
  @override
  Map<String, Relation> get relations => {
    'posts': HasMany<Post>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
    'profile': HasOne<Profile>(this, 'userId'),
    'groups': ManyToMany<Group>(
      this,
      UserGroup, // the pivot entity type
      'userId',
      'groupId',
    ),
  };
}
```

### After (Automated with Mixin)

```dart
import 'package:datum_generator/datum_generator.dart';

part 'user.g.dart';

@DatumSerializable(tableName: 'users', generateMixin: true)
class User extends RelationalDatumEntity with _$UserMixin {
  @override
  final String id;

  final String name;
  final String email;

  // Define relationships with annotations on private fields
  @HasManyRelation<Post>('userId', cascadeDelete: 'cascade')
  final List<Post>? _posts = null;

  @HasOneRelation<Profile>('userId')
  final Profile? _profile = null;

  @ManyToManyRelation<Group, UserGroup>(
    pivotEntity: UserGroup,
    thisForeignKey: 'userId',
    otherForeignKey: 'groupId',
  )
  final List<Group>? _groups = null;

  // ... other fields

  // Use generated relations
  @override
  Map<String, Relation> get relations => datumRelations;

  factory User.fromMap(Map<String, dynamic> map) {
    return _$UserFromMap(map);
  }
}
```

**Note:** In the example above, the mixin will automatically provide public `posts`, `profile`, and `groups` getters/setters that proxy to the private `_posts`, `_profile`, and `_groups` fields while ensuring the `datumRelations` map remains synchronized.

```dart no-verify
// user.g.dart (generated)
extension $UserDatum on User {
  // ... other generated methods

  Map<String, Relation> get datumRelations => {
    'posts': HasMany<Post>(
      this,
      'userId',
      localKey: 'id',
      cascadeDeleteBehavior: CascadeDeleteBehavior.cascade,
    )..setRaw(_posts),
    'profile': HasOne<Profile>(
      this,
      'userId',
      localKey: 'id',
      cascadeDeleteBehavior: CascadeDeleteBehavior.none,
    )..setRaw(_profile),
    'groups': ManyToMany<Group>(
      this,
      UserGroup,
      'userId',
      'groupId',
      thisLocalKey: 'id',
      otherLocalKey: 'id',
      cascadeDeleteBehavior: CascadeDeleteBehavior.none,
    )..setRaw(_groups),
  };
}

mixin _$UserMixin on RelationalDatumEntity {
  // ... method overrides (toDatumMap, diff, etc.)

  // Generated proxies for private relationship fields
  List<Post>? get posts => (this as User)._posts;
  set posts(List<Post>? value) {
    if (this is User) {
       (this as User).datumRelations['posts']?.setRaw(value);
    }
  }

  // ... profile and groups proxies
}
```

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
  final String? description;
  final int strokeCount;

  // Define relationship using annotation on private field
  @HasManyRelation<PaintStroke>('canvasId', cascadeDelete: 'cascade')
  final List<PaintStroke>? _strokes = null;

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
    this.description,
    this.strokeCount = 0,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  // Use generated relations
  @override
  Map<String, Relation> get relations => datumRelations;

  factory PaintCanvas.fromMap(Map<String, dynamic> map) {
    return _$PaintCanvasFromMap(map);
  }
}
```

## Benefits

1. **Less Boilerplate**: No need to manually write the `relations` getter
2. **Type Safety**: Generic type parameters ensure compile-time type checking
3. **Consistency**: All relationships follow the same pattern
4. **Maintainability**: Changes to relationships only require updating annotations
5. **Discoverability**: Annotations make relationships explicit and easy to find
6. **Documentation**: Annotation parameters are self-documenting
7. **Refactoring**: Easier to rename or modify relationships

## Migration Guide

To migrate existing code from manual to automated relationships:

### Step 1: Add Placeholder Fields with Annotations

```dart no-verify
// Add annotated fields for each relationship
@HasManyRelation<Post>('userId', cascadeDelete: 'cascade')
final List<Post>? _posts = null;

@HasOneRelation<Profile>('userId')
final Profile? _profile = null;
```

### Step 2: Replace Manual Relations Getter

```dart no-verify
// Before
@override
Map<String, Relation> get relations => {
  'posts': HasMany<Post>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
  'profile': HasOne<Profile>(this, 'userId'),
};

// After
@override
Map<String, Relation> get relations => datumRelations;
```

### Step 3: Run the Generator

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Step 4: Verify Generated Code

Check the generated `.g.dart` file to ensure all relationships are correctly generated.

## Best Practices

1. **Use Descriptive Field Names**: Even though the field is a placeholder, use meaningful names like `_posts`, `_profile`, etc.

2. **Specify Cascade Behavior**: Always explicitly set `cascadeDelete` to make the behavior clear:
   ```dart no-verify
   @HasManyRelation<Comment>('postId', cascadeDelete: 'cascade')
   ```

3. **Document Complex Relationships**: Add comments for many-to-many relationships:
   ```dart no-verify
   // Tags associated with this post through the post_tags pivot table
   @ManyToManyRelation<Tag, PostTag>(
     pivotEntity: PostTag,
     thisForeignKey: 'postId',
     otherForeignKey: 'tagId',
   )
   final List<Tag>? _tags = null;
   ```

4. **Group Related Annotations**: Keep relationship fields together in your class definition for better readability.

## Troubleshooting

### Relationship Not Generated

**Problem:** The `datumRelations` getter doesn't include your relationship.

**Solutions:**
1. Ensure the field has a relationship annotation
2. Verify the class extends `RelationalDatumEntity`
3. Check that the field is not `static`
4. Run `dart run build_runner clean` and rebuild

### Type Mismatch Errors

**Problem:** Generated code has type errors for relationships.

**Solutions:**
1. Ensure generic types match your entity types
2. For `ManyToManyRelation`, verify both generic types are correct
3. Check that pivot entity is properly defined

### Cascade Delete Not Working

**Problem:** Cascade delete behavior isn't applied.

**Solutions:**
1. Verify `cascadeDelete` parameter is set correctly
2. Check spelling: 'cascade', 'restrict', 'setNull', or 'none'
3. Ensure you're using the generated `datumRelations` getter

## Next Steps

- **[Code Generation Guide](/guides/code_generation)**: Learn about other code generation features
- **[Relationships Guide](/guides/relationships)**: Understand Datum's relationship system
- **[Cascading Deletes](/guides/cascading_delete)**: Deep dive into cascade behaviors
