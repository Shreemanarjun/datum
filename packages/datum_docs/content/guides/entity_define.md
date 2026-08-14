---
title: Entity Define
---




First, you need to define your data models by extending either `DatumEntity` or `RelationalDatumEntity`. These classes provide the core structure for your entities, including properties like `id`, `userId`, `createdAt`, `modifiedAt`, `isDeleted`, and `version`.

## Entity Types

### DatumEntity (Non-Relational)

Use `DatumEntity` for entities that don't need relationships with other entities. This is the base class for simple data models.

### RelationalDatumEntity (Relational)

Use `RelationalDatumEntity` for entities that have relationships with other entities. This extends `DatumEntity` and adds support for defining and managing relationships.

## Entity Definition Approaches

Datum provides multiple ways to define your entities. Choose the approach that best fits your needs:

<Tabs defaultValue="inheritance">
  <TabItem label="Inheritance (Classes)" value="inheritance">
    <b>Use when:</b> You want full Datum integration with built-in relationship support.

  ### DatumEntity (Non-Relational)

  Use `DatumEntity` for entities that don't need relationships:

 ```dart
    class Task extends DatumEntity {
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
      final bool isDeleted;
      @override
      final int version;

      const Task({
        required this.id,
        required this.userId,
        required this.title,
        this.description,
        this.isCompleted = false,
        required this.createdAt,
        required this.modifiedAt,
        this.isDeleted = false,
        this.version = 1,
      });

      @override
      Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
            'id': id,
            'userId': userId,
            'title': title,
            'description': description,
            'isCompleted': isCompleted,
            'createdAt': createdAt.toIso8601String(),
            'modifiedAt': modifiedAt.toIso8601String(),
            'isDeleted': isDeleted,
            'version': version,
          };

      @override
      Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
        if (oldVersion is! Task) return toDatumMap();
        final delta = <String, dynamic>{};
        if (title != oldVersion.title) delta['title'] = title;
        if (description != oldVersion.description) delta['description'] = description;
        if (isCompleted != oldVersion.isCompleted) delta['isCompleted'] = isCompleted;
        return delta.isEmpty ? null : delta;
      }

      factory Task.fromMap(Map<String, dynamic> map) => Task(
            id: map['id'] as String,
            userId: map['userId'] as String,
            title: map['title'] as String,
            description: map['description'] as String?,
            isCompleted: map['isCompleted'] as bool? ?? false,
            createdAt: DateTime.parse(map['createdAt'] as String),
            modifiedAt: DateTime.parse(map['modifiedAt'] as String),
            isDeleted: map['isDeleted'] as bool? ?? false,
            version: map['version'] as int? ?? 1,
          );
    }
  ```

  ### RelationalDatumEntity (Relational)

  Use `RelationalDatumEntity` for entities with relationships:

  ```dart no-verify
    class User extends RelationalDatumEntity {
      @override
      Map<String, Relation> get relations => {
        'posts': HasMany<Post>(this, 'userId'),
        'profile': HasOne<Profile>(this, 'userId'),
      };

      // Implementation... (see the complete relational example
      // at the bottom of this page)
    }
  ```

  **Benefits:**
    - Full Datum integration
    - Built-in relationship support
    - Type safety
    - Automatic serialization

  **Complexity:** Medium-High
  </TabItem>

  <TabItem label="Mixins (Composition)" value="mixins">
  <b>Use when:</b> You need to add Datum functionality to existing classes or prefer composition over inheritance.

  ### DatumEntityMixin

  Basic mixin with change tracking and serialization. The mixin declares the
  core sync fields (`id`, `userId`, `createdAt`, `modifiedAt`, `version`,
  `isDeleted`) as abstract getters — your class provides them as final fields:

  ```dart
    class Task with DatumEntityMixin {
      @override
      final String id;
      @override
      final String userId;
      final String title;
      final String description;
      final bool isCompleted;
      final DateTime? dueDate;
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
        this.description = '',
        this.isCompleted = false,
        this.dueDate,
        required this.createdAt,
        required this.modifiedAt,
        this.version = 1,
        this.isDeleted = false,
      });

      // From Equatable (which the mixin implements): enables a
      // readable toString() built from props.
      @override
      bool? get stringify => true;

      @override
      Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
        return {
          'id': id,
          'userId': userId,
          'title': title,
          'description': description,
          'isCompleted': isCompleted,
          'dueDate': dueDate?.toIso8601String(),
          'createdAt': createdAt.toIso8601String(),
          'modifiedAt': modifiedAt.toIso8601String(),
          'version': version,
          'isDeleted': isDeleted,
        };
      }

      @override
      Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
        if (oldVersion is! Task) return toDatumMap();
        final delta = <String, dynamic>{};
        if (title != oldVersion.title) delta['title'] = title;
        if (description != oldVersion.description) delta['description'] = description;
        if (isCompleted != oldVersion.isCompleted) delta['isCompleted'] = isCompleted;
        if (dueDate != oldVersion.dueDate) delta['dueDate'] = dueDate?.toIso8601String();
        return delta.isEmpty ? null : delta;
      }

      factory Task.fromMap(Map<String, dynamic> map) {
        return Task(
          id: map['id'] as String,
          userId: map['userId'] as String,
          title: map['title'] as String,
          description: (map['description'] ?? '') as String,
          isCompleted: (map['isCompleted'] ?? false) as bool,
          dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate'] as String) : null,
          createdAt: DateTime.parse(map['createdAt'] as String),
          modifiedAt: DateTime.parse(map['modifiedAt'] as String),
          version: (map['version'] ?? 1) as int,
          isDeleted: (map['isDeleted'] ?? false) as bool,
        );
      }
    }
  ```

  ### RelationalDatumEntityMixin

  Marks a composed entity as relational (`isRelational` becomes `true`) and
  gives it a default empty `relations` map. Note that the built-in `Relation`
  constructors (`HasMany`, `BelongsTo`, ...) require a `RelationalDatumEntity`
  parent, so to declare typed relations extend `RelationalDatumEntity`
  (previous tab) or use the [generator annotations](code_generation_relationships):

  ```dart
    class Project with RelationalDatumEntityMixin {
      @override
      final String id;
      @override
      final String userId;
      final String name;
      final String description;
      @override
      final DateTime createdAt;
      @override
      final DateTime modifiedAt;
      @override
      final int version;
      @override
      final bool isDeleted;

      const Project({
        required this.id,
        required this.userId,
        required this.name,
        this.description = '',
        required this.createdAt,
        required this.modifiedAt,
        this.version = 1,
        this.isDeleted = false,
      });

      // From Equatable (which the mixin implements).
      @override
      bool? get stringify => true;

      @override
      Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
            'id': id,
            'userId': userId,
            'name': name,
            'description': description,
            'createdAt': createdAt.toIso8601String(),
            'modifiedAt': modifiedAt.toIso8601String(),
            'version': version,
            'isDeleted': isDeleted,
          };

      @override
      Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
        if (oldVersion is! Project) return toDatumMap();
        final delta = <String, dynamic>{};
        if (name != oldVersion.name) delta['name'] = name;
        if (description != oldVersion.description) delta['description'] = description;
        return delta.isEmpty ? null : delta;
      }
    }
  ```

  **Benefits:**
  - Flexible composition
  - Add Datum features to existing classes
  - Less coupling than inheritance
  - Compose Datum into existing class hierarchies

  **Complexity:** Low-Medium
</TabItem>
</Tabs>

## Detailed Comparison & Best Practices


|Feature | DatumEntity | RelationalDatumEntity | DatumEntityMixin | RelationalDatumEntityMixin |
|---------|-------------|----------------------|------------------|--------------------------|
| **Use Case** | Simple entities | Complex relationships | Simple with utilities | Utilities + relationships |
| **Complexity** | 🟢 Low | 🔴 High | 🟢 Low | 🟡 Medium |
| **Relationships** | ❌ None | ✅ Built-in | ❌ None | 🔧 Manual |
| **Inheritance** | ✅ Required | ✅ Required | ❌ Not required | ❌ Not required |
| **Flexibility** | ⚪ Low | 🟡 Medium | 🟢 High | 🟢 High |
| **Performance** | 🟢 Good | 🟢 Good | 🟢 Good | 🟢 Good |
| **Setup Time** | 🟢 Fast | 🟡 Medium | 🟢 Fast | 🟡 Medium |



### 🏗️ Inheritance Approaches

**Best For:**
- New projects from scratch
- Full Datum ecosystem integration
- Built-in relationship management
- Type-safe entity hierarchies

**When to Choose:**
- You want comprehensive Datum features
- Relationships are central to your domain
- You prefer declarative relationship definitions

### 🔧 Mixin Approaches

**Best For:**
- Adding Datum to existing classes
- Composition over inheritance preference
- Library/framework development
- Gradual migration scenarios

**When to Choose:**
- You have existing class hierarchies
- You need more control over relationships
- You're building reusable components

### 🔄 Migration Between Approaches

**From Mixin to Inheritance:**
```dart no-verify
// Before (Mixin)
class Task with DatumEntityMixin {
  // Fields, toDatumMap, diff, fromMap...
}

// After (Inheritance)
class Task extends DatumEntity {
  // The class body stays the same — DatumEntity already mixes in
  // DatumEntityMixin, so only the declaration line changes.
}
```

**From Inheritance to Mixin:**
```dart no-verify
// Before (Inheritance)
class Task extends DatumEntity {
  // Implementation
}

// After (Mixin)
class Task with DatumEntityMixin {
  // Remove the extends clause. Keep the same final fields
  // (id, userId, createdAt, modifiedAt, version, isDeleted)
  // and method overrides — the mixin declares them as abstract members.
}
```

> **💡 Pro Tip:** Start with inheritance approaches for new projects, and use mixins when you need to integrate Datum into existing codebases or prefer more flexible composition patterns.

## Implementation Best Practices

### Core Requirements

1. **Always implement `toDatumMap()` and `fromMap()`**
   ```dart no-verify
   @override
   Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
     // Required for serialization
   }

   factory EntityName.fromMap(Map<String, dynamic> map) {
     // Required for deserialization
   }
   ```

2. **Use meaningful relationship names**
   ```dart no-verify
   // Good
   'author': BelongsTo<User>(this, 'userId'),
   'comments': HasMany<Comment>(this, 'postId'),

   // Avoid
   'rel1': BelongsTo<User>(this, 'userId'),
   'rel2': HasMany<Comment>(this, 'postId'),
   ```

### Advanced Patterns

3. **Preview cascading deletes before running them**
   ```dart
   final plan = await manager.getDeletePlan(task.id, userId: userId);
   if (plan != null && plan.canDelete) {
     await manager.cascadeDelete(id: task.id, userId: userId);
   }
   ```

4. **Declare cascade behavior on the relation itself**
   ```dart no-verify
   @override
   Map<String, Relation> get relations => {
     // Deleting this entity also deletes its comments
     'comments': HasMany<Comment>(
       this,
       'postId',
       cascadeDeleteBehavior: CascadeDeleteBehavior.cascade,
     ),
   };
   ```

5. **Use lazy loading for performance**
   ```dart
   // Load relationships on demand instead of embedding them eagerly.
   // Works on any RelationalDatumEntity with a declared relation.
   final subtasks = await manager.fetchRelated<Task>(task, 'subtasks');
   ```

### Performance Considerations

- **Inheritance approaches** have slightly better performance due to direct method calls
- **Mixin approaches** have minimal performance overhead but offer more flexibility
- **Relationship-heavy entities** benefit from built-in relationship management
- **Large datasets** should use lazy loading to avoid memory issues

### Testing Recommendations

```dart
import 'package:test/test.dart';

void main() {
  group('Entity Tests', () {
    test('should serialize correctly', () {
      final entity = Task(
        id: '1',
        userId: 'user1',
        title: 'Test Task',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      final map = entity.toDatumMap();
      expect(map['title'], equals('Test Task'));
    });

    test('should deserialize correctly', () {
      final map = {
        'id': '1',
        'title': 'Test',
        'userId': 'user1',
        'createdAt': DateTime.now().toIso8601String(),
        'modifiedAt': DateTime.now().toIso8601String(),
      };
      final entity = Task.fromMap(map);
      expect(entity.title, equals('Test'));
    });

    test('should report changes through diff', () {
      final task = Task(
        id: '1',
        userId: 'user1',
        title: 'Before',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      final updated = Task.fromMap({...task.toDatumMap(), 'title': 'After'});
      expect(updated.diff(task), containsPair('title', 'After'));
    });
  });
}
```


## Next Steps

Now that you've defined your entities, you can:

1. **[Set up adapters](guides/local_adapter_implement)**: Implement local and remote adapters for your entities
2. **[Initialize Datum](guides/initialization)**: Configure and initialize the Datum system
3. **[Work with relationships](guides/relationships)**: Learn about defining and using entity relationships (if using `RelationalDatumEntity`)
4. **[Query data](guides/querying)**: Learn how to query and filter your data

## Example: Non-Relational Entity

Below is an example of a `Task` entity using `DatumEntity` (non-relational). Your entities will likely have more specific fields relevant to your application.

```dart
import 'package:datum/datum.dart';
import 'dart:convert'; // For json.encode and json.decode
import 'dart:math'; // For Random
import 'package:supabase_flutter/supabase_flutter.dart'; // Example for userId

class Task extends DatumEntity {
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
  final bool isDeleted;

  @override
  final int version;
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  Task copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isDeleted,
    int? version,
  }) {
    // Determine if any field is being changed.
    final bool hasChanges = id != null ||
        userId != null ||
        title != null ||
        description != null ||
        isCompleted != null ||
        createdAt != null ||
        modifiedAt != null ||
        isDeleted != null;

    return Task(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      // Always update modifiedAt if there are changes.
      modifiedAt: (modifiedAt ?? this.modifiedAt),
      isDeleted: isDeleted ?? this.isDeleted,
      // If a version is explicitly passed, use it. Otherwise, increment if there are changes.
      version: version ?? (hasChanges ? this.version + 1 : this.version),
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) {
    if (oldVersion is! Task) return toDatumMap();

    final diff = <String, dynamic>{};

    if (title != oldVersion.title) {
      diff['title'] = title;
    }
    if (description != oldVersion.description) {
      diff['description'] = description;
    }
    if (isCompleted != oldVersion.isCompleted) {
      diff['isCompleted'] = isCompleted;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    // Only include modification details if there are other changes
    if (diff.isNotEmpty) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
      diff['version'] = version;
    }

    return diff.isEmpty ? null : diff;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = {
      'id': id,
      'userId': userId,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'isDeleted': isDeleted,
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

  static DateTime _parseDate(dynamic dateValue) {
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    if (dateValue is String) {
      return DateTime.tryParse(dateValue) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Task create({required String title, String? description}) {
    final now = DateTime.now();
    // This is an example using Supabase for user ID. Adjust as per your auth solution.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Cannot create task: user is not logged in.');
    }
    return Task(
      id: '${now.millisecondsSinceEpoch}${Random().nextInt(9999)}',
      userId: userId,
      title: title,
      description: description,
      isCompleted: false,
      createdAt: now,
      modifiedAt: now,
    );
  }

  String toJson() => json.encode(toDatumMap());

  factory Task.fromJson(String source) =>
      Task.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Task(id: $id, userId: $userId, title: $title, description: $description, isCompleted: $isCompleted, createdAt: $createdAt, modifiedAt: $modifiedAt, isDeleted: $isDeleted, version: $version)';
  }

  @override
  bool operator ==(covariant Task other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.userId == userId &&
        other.title == title &&
        other.isCompleted == isCompleted &&
        other.description == description &&
        other.createdAt == createdAt &&
        other.modifiedAt == modifiedAt &&
        other.isDeleted == isDeleted &&
        other.version == version;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        title.hashCode ^
        isCompleted.hashCode ^
        description.hashCode ^
        createdAt.hashCode ^
        modifiedAt.hashCode ^
        isDeleted.hashCode ^
        version.hashCode;
  }
}
```

## Example: Relational Entity

Below is an example of entities using `RelationalDatumEntity` to demonstrate relationships between `User`, `Post`, and `Comment` entities.

```dart
import 'package:datum/datum.dart';

// User entity with relationships
class User extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId;

  final String name;
  final String email;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final bool isDeleted;

  @override
  final int version;

  const User({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  @override
  Map<String, Relation> get relations => {
    'posts': HasMany<Post>(this, 'userId'),
    'profile': HasOne<Profile>(this, 'userId'),
  };

  @override
  User copyWith({
    String? id,
    String? userId,
    String? name,
    String? email,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isDeleted,
    int? version,
  }) {
    final bool hasChanges = id != null || userId != null || name != null ||
        email != null || createdAt != null || modifiedAt != null ||
        isDeleted != null;

    return User(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: hasChanges ? DateTime.now() : (modifiedAt ?? this.modifiedAt),
      isDeleted: isDeleted ?? this.isDeleted,
      version: version ?? (hasChanges ? this.version + 1 : this.version),
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! User) return toDatumMap();

    final diff = <String, dynamic>{};
    if (name != oldVersion.name) diff['name'] = name;
    if (email != oldVersion.email) diff['email'] = email;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    if (diff.isNotEmpty) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
      diff['version'] = version;
    }
    return diff.isEmpty ? null : diff;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = {
      'id': id,
      'userId': userId,
      'name': name,
      'email': email,
      'isDeleted': isDeleted,
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

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String,
      userId: map['userId'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']),
      modifiedAt: _parseDate(map['modifiedAt'] ?? map['modified_at']),
      isDeleted: (map['isDeleted'] ?? false) as bool,
      version: (map['version'] ?? 1) as int,
    );
  }

  static DateTime _parseDate(dynamic dateValue) {
    if (dateValue is int) return DateTime.fromMillisecondsSinceEpoch(dateValue);
    if (dateValue is String) return DateTime.tryParse(dateValue) ?? DateTime.now();
    return DateTime.now();
  }
}

// Post entity with BelongsTo relationship
class Post extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId; // Foreign key to User

  final String title;
  final String content;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final bool isDeleted;

  @override
  final int version;

  const Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  @override
  Map<String, Relation> get relations => {
    'author': BelongsTo<User>(this, 'userId'),
    'comments': HasMany<Comment>(this, 'postId'),
  };

  @override
  Post copyWith({
    String? id,
    String? userId,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isDeleted,
    int? version,
  }) {
    final bool hasChanges = id != null || userId != null || title != null ||
        content != null || createdAt != null || modifiedAt != null ||
        isDeleted != null;

    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: hasChanges ? DateTime.now() : (modifiedAt ?? this.modifiedAt),
      isDeleted: isDeleted ?? this.isDeleted,
      version: version ?? (hasChanges ? this.version + 1 : this.version),
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! Post) return toDatumMap();

    final diff = <String, dynamic>{};
    if (title != oldVersion.title) diff['title'] = title;
    if (content != oldVersion.content) diff['content'] = content;
    if (userId != oldVersion.userId) diff['userId'] = userId;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    if (diff.isNotEmpty) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
      diff['version'] = version;
    }
    return diff.isEmpty ? null : diff;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = {
      'id': id,
      'userId': userId,
      'title': title,
      'content': content,
      'isDeleted': isDeleted,
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

  factory Post.fromMap(Map<String, dynamic> map) {
    return Post(
      id: map['id'] as String,
      userId: map['userId'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']),
      modifiedAt: _parseDate(map['modifiedAt'] ?? map['modified_at']),
      isDeleted: (map['isDeleted'] ?? false) as bool,
      version: (map['version'] ?? 1) as int,
    );
  }

  static DateTime _parseDate(dynamic dateValue) {
    if (dateValue is int) return DateTime.fromMillisecondsSinceEpoch(dateValue);
    if (dateValue is String) return DateTime.tryParse(dateValue) ?? DateTime.now();
    return DateTime.now();
  }
}

// Comment entity with BelongsTo relationship
class Comment extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId;

  final String postId; // Foreign key to Post
  final String content;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final bool isDeleted;

  @override
  final int version;

  const Comment({
    required this.id,
    required this.userId,
    required this.postId,
    required this.content,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  @override
  Map<String, Relation> get relations => {
    'author': BelongsTo<User>(this, 'userId'),
    'post': BelongsTo<Post>(this, 'postId'),
  };

  @override
  Comment copyWith({
    String? id,
    String? userId,
    String? postId,
    String? content,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isDeleted,
    int? version,
  }) {
    final bool hasChanges = id != null || userId != null || postId != null ||
        content != null || createdAt != null || modifiedAt != null ||
        isDeleted != null;

    return Comment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      postId: postId ?? this.postId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: hasChanges ? DateTime.now() : (modifiedAt ?? this.modifiedAt),
      isDeleted: isDeleted ?? this.isDeleted,
      version: version ?? (hasChanges ? this.version + 1 : this.version),
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! Comment) return toDatumMap();

    final diff = <String, dynamic>{};
    if (content != oldVersion.content) diff['content'] = content;
    if (postId != oldVersion.postId) diff['postId'] = postId;
    if (userId != oldVersion.userId) diff['userId'] = userId;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    if (diff.isNotEmpty) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
      diff['version'] = version;
    }
    return diff.isEmpty ? null : diff;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = {
      'id': id,
      'userId': userId,
      'postId': postId,
      'content': content,
      'isDeleted': isDeleted,
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

  factory Comment.fromMap(Map<String, dynamic> map) {
    return Comment(
      id: map['id'] as String,
      userId: map['userId'] as String,
      postId: map['postId'] as String,
      content: map['content'] as String,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']),
      modifiedAt: _parseDate(map['modifiedAt'] ?? map['modified_at']),
      isDeleted: (map['isDeleted'] ?? false) as bool,
      version: (map['version'] ?? 1) as int,
    );
  }

  static DateTime _parseDate(dynamic dateValue) {
    if (dateValue is int) return DateTime.fromMillisecondsSinceEpoch(dateValue);
    if (dateValue is String) return DateTime.tryParse(dateValue) ?? DateTime.now();
    return DateTime.now();
  }
}

// Profile entity for HasOne relationship
class Profile extends RelationalDatumEntity {
  @override
  final String id;

  @override
  final String userId; // Foreign key to User

  final String bio;
  final String avatarUrl;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final bool isDeleted;

  @override
  final int version;

  const Profile({
    required this.id,
    required this.userId,
    required this.bio,
    required this.avatarUrl,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  @override
  Map<String, Relation> get relations => {
    'user': BelongsTo<User>(this, 'userId'),
  };

  @override
  Profile copyWith({
    String? id,
    String? userId,
    String? bio,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isDeleted,
    int? version,
  }) {
    final bool hasChanges = id != null || userId != null || bio != null ||
        avatarUrl != null || createdAt != null || modifiedAt != null ||
        isDeleted != null;

    return Profile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: hasChanges ? DateTime.now() : (modifiedAt ?? this.modifiedAt),
      isDeleted: isDeleted ?? this.isDeleted,
      version: version ?? (hasChanges ? this.version + 1 : this.version),
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! Profile) return toDatumMap();

    final diff = <String, dynamic>{};
    if (bio != oldVersion.bio) diff['bio'] = bio;
    if (avatarUrl != oldVersion.avatarUrl) diff['avatarUrl'] = avatarUrl;
    if (userId != oldVersion.userId) diff['userId'] = userId;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;

    if (diff.isNotEmpty) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
      diff['version'] = version;
    }
    return diff.isEmpty ? null : diff;
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    final map = {
      'id': id,
      'userId': userId,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'isDeleted': isDeleted,
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

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      userId: map['userId'] as String,
      bio: map['bio'] as String,
      avatarUrl: map['avatarUrl'] as String,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']),
      modifiedAt: _parseDate(map['modifiedAt'] ?? map['modified_at']),
      isDeleted: (map['isDeleted'] ?? false) as bool,
      version: (map['version'] ?? 1) as int,
    );
  }

  static DateTime _parseDate(dynamic dateValue) {
    if (dateValue is int) return DateTime.fromMillisecondsSinceEpoch(dateValue);
    if (dateValue is String) return DateTime.tryParse(dateValue) ?? DateTime.now();
    return DateTime.now();
  }
}
```
