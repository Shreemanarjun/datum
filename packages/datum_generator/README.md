<p align="center">
  <img src="https://zmozkivkhopoeutpnnum.supabase.co/storage/v1/object/public/images/datum_banner.svg" alt="Datum Banner">
</p>

# Datum Generator

A powerful code generation package for the [Datum](https://pub.dev/packages/datum) framework. It automates the generation of boilerplate code for your `DatumEntity` and `RelationalDatumEntity` classes, including serialization, diff tracking, recursive relationships, and more.

## Features

- **🚀 Zero Boilerplate**: Use `generateMixin: true` to automatically implement all required `DatumEntity` methods.
- **🔗 Automated Relationships**: Define relationships using annotations (`@HasManyRelation`, `@BelongsToRelation`, etc.).
- **🔄 Smart Serialization**: Generates optimized `toDatumMap()` and type-safe `fromMap()` implementations.
- **📈 Diff Tracking**: Automatic `diff()` generation for efficient partial updates during synchronization.
- **💎 Type-Safe Queries**: Generates a type-safe query builder for every entity.
- **✨ Metadata Management**: Handles automatic version incrementing and metadata updates in `copyWith`.
- **🎨 Platform Ready**: Built-in support for Flutter-specific types like `Color` and `Offset`.

## Installation

Add `datum_generator` to your `pubspec.yaml`:

```yaml
dependencies:
  datum: ^1.1.0
  # Required for annotations
  datum_generator: ^1.1.0

dev_dependencies:
  build_runner: ^2.4.0
  # Required for the code generator
  datum_generator: ^1.1.0
```

## Basic Usage

### The Modern Way (Recommended)

Use `generateMixin: true` to let the generator handle all the heavy lifting.

```dart
import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';

part 'user.g.dart';

@DatumSerializable(generateMixin: true)
class User extends DatumEntity with _$UserMixin {
  @override
  final String id;
  @override
  final String userId;

  final String name;
  final String? email;

  // Metadata properties are handled by the mixin
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  User({
    required this.id,
    required this.userId,
    required this.name,
    this.email,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  // That's it! Everything else is implemented in the mixin.
}
```

## Relationships

Datum Generator makes defining relationships incredibly simple.

### Automated Relations

```dart
@DatumSerializable(generateMixin: true)
class Post extends RelationalDatumEntity with _$PostMixin {
  @override
  final String id;

  final String title;

  // Define relationship with a placeholder field and annotation
  @HasManyRelation<Comment>('postId', cascadeDelete: 'cascade')
  final List<Comment>? _comments = null;

  @BelongsToRelation<User>('authorId')
  final User? _author = null;

  // ... constructor and metadata
}
```

Supported annotations:
- `@BelongsToRelation<T>(foreignKey)`
- `@HasManyRelation<T>(foreignKey)`
- `@HasOneRelation<T>(foreignKey)`
- `@ManyToManyRelation<T, P>(pivotEntity, thisForeignKey, otherForeignKey)`

## Advanced Configuration

### Custom Field Mapping

```dart
class Product extends DatumEntity with _$ProductMixin {
  @DatumField('product_sku')
  final String sku;

  @DatumIgnore()
  final String cachedToken;
}
```

### Type-Safe Querying

The generator creates a static `Query` builder for your class:

```dart
final queriedData = await Datum.instance.query<TestEntity>(
  mediumPriorityIncompleteQuery,
  source: DataSource.local,
  userId: 'test-user',
);
```

## Running the Generator

Run the following command to generate the `.g.dart` files:

```bash
# Build once
flutter pub run build_runner build --delete-conflicting-outputs

# Watch for changes
flutter pub run build_runner watch
```

## Best Practices

1. **Use Mixins**: Always prefer `generateMixin: true` to keep your entity files clean and maintainable.
2. **Private Placeholders**: For relationship fields, use a private field (e.g., `_comments`) with a `null` default value. The generator will create public getters and setters in the mixin.
3. **Common Metadata**: Ensure your constructor includes all metadata fields (`id`, `userId`, `createdAt`, `modifiedAt`, `version`, `isDeleted`) as they are required for the offline-first sync engine.

# Documentation

[📚 Full Documentation](https://datum.shreeman.dev/)

Complete guides, API reference, and examples for building offline-first applications with Datum.

---

Built with ❤️ by [Shreeman Arjun](https://www.shreeman.dev)
