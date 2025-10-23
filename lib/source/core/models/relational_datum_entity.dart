import 'package:datum/source/core/models/datum_entity.dart';

/// A sealed class representing the different types of relationships between entities.
sealed class Relation {
  const Relation();
}

/// Represents a one-to-one or one-to-many relationship.
///
/// [foreignKey]: The field on the current entity that holds the ID of the related entity.
/// [localKey]: The field on the *related* entity that the `foreignKey` points to.
/// Defaults to 'id'.
///
/// For example, a `Post` entity might have a `BelongsTo('userId')` to link to a `User`.
class BelongsTo extends Relation {
  final String foreignKey;
  final String localKey;
  const BelongsTo(this.foreignKey, {this.localKey = 'id'});
}

/// Represents a one-to-many relationship from the "one" side.
///
/// [foreignKey]: The field on the *related* entity that holds the ID of this entity.
/// [localKey]: The field on *this* entity that the `foreignKey` on the related
/// entity points to. Defaults to 'id'.
///
/// Example: A `User` entity might have a `HasMany('userId')` to link to all of
/// its `Post` entities, where each `Post` has a `userId` field.
class HasMany extends Relation {
  final String foreignKey;
  final String localKey;
  const HasMany(this.foreignKey, {this.localKey = 'id'});
}

/// Represents a one-to-one relationship from the "one" side.
///
/// This is the inverse of a `BelongsTo` relationship.
///
/// [foreignKey]: The field on the *related* entity that holds the ID of this entity.
/// [localKey]: The field on *this* entity that the `foreignKey` on the related
/// entity points to. Defaults to 'id'.
///
/// Example: A `User` entity might have a `HasOne('userId')` to link to a single
/// `Profile` entity, where the `Profile` has a unique `userId` field.
class HasOne extends Relation {
  final String foreignKey;
  final String localKey;
  const HasOne(this.foreignKey, {this.localKey = 'id'});
}

/// Represents a many-to-many relationship.
///
/// [pivotEntity]: A const instance of the entity that acts as the join table.
/// [thisForeignKey]: The field in the pivot entity that references this entity's ID.
/// [thisLocalKey]: The field on *this* entity that `thisForeignKey` points to.
/// Defaults to 'id'.
/// [otherForeignKey]: The field in the pivot entity that references the related entity's ID.
/// [otherLocalKey]: The field on the *related* entity that `otherForeignKey`
/// points to. Defaults to 'id'.
///
/// Example: A `Post` entity could have a `ManyToMany(PostTag.constInstance, 'postId', 'tagId')`
/// to link to `Tag` entities.
class ManyToMany extends Relation {
  final DatumEntityBase pivotEntity;
  final String thisForeignKey;
  final String otherForeignKey;
  final String thisLocalKey;
  final String otherLocalKey;
  const ManyToMany(
    this.pivotEntity,
    this.thisForeignKey,
    this.otherForeignKey, {
    this.thisLocalKey = 'id',
    this.otherLocalKey = 'id',
  });
}

/// An extension of [DatumEntity] that includes support for defining relationships.
///
/// ### Understanding Relationships
///
/// The key difference between `BelongsTo`, `HasOne`, and `HasMany` lies in
/// **which entity holds the foreign key**.
///
/// | Aspect                | `BelongsTo`                                     | `HasOne` / `HasMany`                                |
/// | :-------------------- | :---------------------------------------------- | :-------------------------------------------------- |
/// | **Who has the key?**  | **This entity** has the foreign key.            | The **other entity** has the foreign key.           |
/// | **Relationship Role** | The "child" or "dependent" side.                | The "parent" or "owner" side.                       |
/// | **Example**           | A `Post` **belongs to** a `User`.               | A `User` **has one** `Profile` or **has many** `Posts`. |
/// | **Code (`Post`)**     | `relations => {'author': BelongsTo('userId')}`  | (Defined in the `User` class)                       |
/// | **Code (`User`)**     | (Defined in the `Post` class)                   | `relations => {'profile': HasOne('userId')}`        |
///
/// #### `BelongsTo`
/// Use this when the current entity's table contains the foreign key that
/// points to the parent.
///
/// ```dart
/// // In a Post entity:
/// class Post extends RelationalDatumEntity {
///   final String userId; // Foreign key
///   @override
///   Map<String, Relation> get relations => {'author': BelongsTo('userId')};
/// }
/// ```
///
/// #### `HasOne` / `HasMany`
/// Use these when the *other* entity's table contains the foreign key that
/// points back to this one.
///
/// ```dart
/// // In a User entity:
/// class User extends RelationalDatumEntity {
///   @override
///   Map<String, Relation> get relations => {
///     'profile': HasOne('userId'), // A Profile has a `userId` field
///     'posts': HasMany('userId'),   // A Post has a `userId` field
///   };
/// }
/// ```
///
/// ---
// ///
// /// Entities that have relationships with other syncable entities should extend this
// /// class instead of [DatumEntity] directly.
// abstract class RelationalDatumEntity extends DatumEntity {
//   /// Creates a `const` [RelationalDatumEntity].
//   const RelationalDatumEntity();

//   /// Indicates whether this entity supports relationships. Always `true` for this class.
//   @override
//   bool get isRelational => true;

//   /// A map defining all relationships for this entity.
//   ///
//   /// The key is a descriptive name for the relation, and the value is an
//   /// instance of a [Relation] subclass (`BelongsTo`, `HasMany`, `ManyToMany`).
//   ///
//   /// Example:
//   /// ```dart
//   /// @override
//   /// Map<String, Relation> get relations => {
//   ///   'author': BelongsTo('userId'),
//   /// };
//   /// ```
//   Map<String, Relation> get relations => {};
// }
