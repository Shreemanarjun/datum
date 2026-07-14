import 'package:meta/meta_meta.dart';

/// Annotation for classes that should have Datum code generated.
@Target({TargetKind.classType})
class DatumSerializable {
  /// The table name for this entity. If not provided, the class name will be used (converted to snake_case).
  final String? tableName;

  /// Whether to generate a mixin with all required method implementations.
  ///
  /// When true, generates a `_$EntityNameMixin` that you can use with:
  /// ```dart
  /// class MyEntity extends DatumEntity with _$MyEntityMixin {
  ///   // Just define fields and constructor!
  /// }
  /// ```
  ///
  /// When false, you must manually implement the required methods
  /// (`toDatumMap`, `diff`, `fromMap`, `copyWith`, …).
  ///
  /// Defaults to **true** (mixin-by-default): applying `with _$EntityNameMixin`
  /// removes all serialization boilerplate. The generated mixin is emitted with
  /// an `// ignore: unused_element` so it is harmless if you do not apply it.
  final bool generateMixin;

  /// Whether generated `fromMap` should NOT substitute default values for
  /// non-nullable primitive fields (`String`/`int`/`double`/`bool`).
  ///
  /// Defaults to **false** (backward compatible): a missing/`null` value is
  /// coerced to `''`/`0`/`0.0`/`false`. When **true**, the generator emits a
  /// plain cast (e.g. `map['name'] as String`), so a `null` surfaces as a clear
  /// runtime error instead of being silently masked (#29) — matching the
  /// behavior of `json_serializable`/`freezed`. Nullable fields are unaffected.
  final bool strictNullChecks;

  const DatumSerializable({
    this.tableName,
    this.generateMixin = true,
    this.strictNullChecks = false,
  });
}

/// Annotation for fields that should be excluded from Datum serialization or metadata methods.
@Target({TargetKind.field})
class DatumIgnore {
  /// Whether to exclude this field from copyWith and copyWithAll methods.
  final bool copyWith;

  /// Whether to exclude this field from operator == and hashCode.
  final bool equality;

  /// Whether to exclude this field when deserializing from a map.
  final bool fromMap;

  /// Whether to exclude this field when serializing to a map.
  final bool toMap;

  const DatumIgnore({
    this.copyWith = false,
    this.equality = false,
    this.fromMap = true,
    this.toMap = true,
  });
}

/// Annotation to specify a custom name for a field in the Datum map.
@Target({TargetKind.field})
class DatumField {
  /// The name to use for this field in the Datum map.
  final String? name;

  /// Custom Dart code to transform the field value from the map.
  /// Use %DATA_PROPERTY% as a placeholder for the map value access.
  /// Example: "PhoneMeta.fromJson(%DATA_PROPERTY% as Map<String, dynamic>)"
  final String? fromGenerator;

  /// Custom Dart code to transform the field value to the map.
  /// Use %DATA_PROPERTY% as a placeholder for the field value.
  /// Example: "%DATA_PROPERTY%.toJson()"
  final String? toGenerator;

  const DatumField({this.name, this.fromGenerator, this.toGenerator});
}

/// Annotation to define a BelongsTo relationship.
///
/// Use this when the current entity has a foreign key pointing to another entity.
///
/// Example:
/// ```dart
/// @BelongsToRelation<User>('userId')
/// final String? _author = null;  // Placeholder field
/// ```
@Target({TargetKind.field})
class BelongsToRelation<T> {
  /// The foreign key field name in this entity
  final String foreignKey;

  /// The local key field name in the related entity (defaults to 'id')
  final String localKey;

  /// Cascade delete behavior
  final String cascadeDelete;

  const BelongsToRelation(
    this.foreignKey, {
    this.localKey = 'id',
    this.cascadeDelete = 'none',
  });
}

/// Annotation to define a HasMany relationship.
///
/// Use this when another entity has a foreign key pointing to this entity.
///
/// Example:
/// ```dart
/// @HasManyRelation<Post>('userId')
/// final List<Post>? _posts = null;  // Placeholder field
/// ```
@Target({TargetKind.field})
class HasManyRelation<T> {
  /// The foreign key field name in the related entity
  final String foreignKey;

  /// The local key field name in this entity (defaults to 'id')
  final String localKey;

  /// Cascade delete behavior: 'none', 'cascade', 'restrict', 'setNull'
  final String cascadeDelete;

  const HasManyRelation(
    this.foreignKey, {
    this.localKey = 'id',
    this.cascadeDelete = 'none',
  });
}

/// Annotation to define a HasOne relationship.
///
/// Use this when another entity has a foreign key pointing to this entity (one-to-one).
///
/// Example:
/// ```dart
/// @HasOneRelation<Profile>('userId')
/// final Profile? _profile = null;  // Placeholder field
/// ```
@Target({TargetKind.field})
class HasOneRelation<T> {
  /// The foreign key field name in the related entity
  final String foreignKey;

  /// The local key field name in this entity (defaults to 'id')
  final String localKey;

  /// Cascade delete behavior
  final String cascadeDelete;

  const HasOneRelation(
    this.foreignKey, {
    this.localKey = 'id',
    this.cascadeDelete = 'none',
  });
}

/// Annotation to define a ManyToMany relationship.
///
/// Use this for many-to-many relationships through a pivot entity.
///
/// Example:
/// ```dart
/// @ManyToManyRelation<Tag, PostTag>(
///   pivotEntity: PostTag,
///   thisForeignKey: 'postId',
///   otherForeignKey: 'tagId',
/// )
/// final List<Tag>? _tags = null;  // Placeholder field
/// ```
@Target({TargetKind.field})
class ManyToManyRelation<T, P> {
  /// The pivot entity type
  final Type pivotEntity;

  /// The foreign key in the pivot entity pointing to this entity
  final String thisForeignKey;

  /// The foreign key in the pivot entity pointing to the related entity
  final String otherForeignKey;

  /// The local key in this entity (defaults to 'id')
  final String thisLocalKey;

  /// The local key in the related entity (defaults to 'id')
  final String otherLocalKey;

  /// Cascade delete behavior
  final String cascadeDelete;

  const ManyToManyRelation({
    required this.pivotEntity,
    required this.thisForeignKey,
    required this.otherForeignKey,
    this.thisLocalKey = 'id',
    this.otherLocalKey = 'id',
    this.cascadeDelete = 'none',
  });
}
