import 'package:datum/source/core/models/datum_entity.dart';

/// A sealed class representing the different types of relationships between entities.
sealed class Relation {
  const Relation();
}

/// Represents a one-to-one or one-to-many relationship.
///
/// The field on the current entity that holds the ID of the related entity.
/// For example, a `Post` entity might have a `BelongsTo('userId')` to link to a `User`.
class BelongsTo extends Relation {
  final String foreignKey;
  const BelongsTo(this.foreignKey);
}

/// Represents a one-to-many relationship from the "one" side.
///
/// [foreignKey]: The field on the *related* entity that holds the ID of this entity.
///
/// Example: A `User` entity might have a `HasMany('userId')` to link to all of
/// its `Post` entities, where each `Post` has a `userId` field.
class HasMany extends Relation {
  final String foreignKey;
  const HasMany(this.foreignKey);
}

/// Represents a many-to-many relationship.
///
/// [pivotEntity]: A const instance of the entity that acts as the join table.
/// [thisForeignKey]: The field in the pivot entity that references this entity's ID.
/// [otherForeignKey]: The field in the pivot entity that references the related entity's ID.
///
/// Example: A `Post` entity could have a `ManyToMany(PostTag.constInstance, 'postId', 'tagId')`
/// to link to `Tag` entities.
class ManyToMany extends Relation {
  final DatumEntity pivotEntity;
  final String thisForeignKey;
  final String otherForeignKey;
  const ManyToMany(this.pivotEntity, this.thisForeignKey, this.otherForeignKey);
}

/// An extension of [DatumEntity] that includes support for defining relationships.
///
/// Entities that have relationships with other syncable entities should extend this
/// class instead of [DatumEntity] directly.
abstract class RelationalDatumEntity extends DatumEntity {
  /// A map defining all relationships for this entity.
  ///
  /// The key is a descriptive name for the relation, and the value is an
  /// instance of a [Relation] subclass (`BelongsTo`, `HasMany`, `ManyToMany`).
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Map<String, Relation> get relations => {
  ///   'author': BelongsTo('userId'),
  /// };
  /// ```
  Map<String, Relation> get relations => {};
}
