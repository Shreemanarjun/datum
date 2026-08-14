import 'package:datum/source/core/models/vector_clock.dart';
import 'package:equatable/equatable.dart';

/// The **target for serialization**, allowing different fields to be included
/// or excluded based on whether the data is going to a **local** or **remote**
/// data source.
enum MapTarget {
  /// Used for serialization when saving the entity to the **local database**.
  /// May exclude fields only relevant for remote sync.
  local,

  /// Used for serialization when sending the entity to the **remote server**
  /// or data source. Typically includes all necessary sync metadata.
  remote,
}

/// Interface for all Datum entities, allowing both inheritance and mixin approaches.
abstract interface class DatumEntityInterface {
  /// A **unique identifier** for the entity.
  String get id;

  /// The ID of the user who owns or created this entity.
  String get userId;

  /// The **timestamp** of the last time this entity was modified.
  DateTime get modifiedAt;

  /// The **timestamp** of when this entity was first created.
  DateTime get createdAt;

  /// A **sequential integer** used for optimistic concurrency and tracking
  /// changes.
  int get version;

  /// A **vector clock** for tracking causality across multiple devices.
  /// If provided, this allows for more accurate conflict detection than
  /// simple version numbers.
  VectorClock? get vectorClock;

  /// A flag indicating if this entity has been locally marked for **deletion**.
  bool get isDeleted;

  /// Returns a new instance with the vector clock incremented for [replicaId].
  ///
  /// If this entity does not support vector clocks, it should return itself.
  DatumEntityInterface incrementClock(String replicaId);

  /// Converts the entity to a `Map<String, dynamic>` for persistence.
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local});

  /// Computes the **difference** between the current entity state and an
  /// [oldVersion] of the entity.
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion);

  /// Merges this entity with [other].
  ///
  /// This is used for conflict resolution, especially when using CRDT fields.
  DatumEntityInterface merge(covariant DatumEntityInterface other);

  /// Indicates whether this entity supports relationships.
  bool get isRelational;
}

/// The **base sealed class** for all entities managed by the Datum framework.
///
/// This class enforces the core sync and identification fields. It extends
/// [Equatable] for easy value comparison.
sealed class DatumEntityBase extends Equatable implements DatumEntityInterface {
  const DatumEntityBase();

  /// A **unique identifier** for the entity.
  @override
  String get id;

  /// The ID of the user who owns or created this entity.
  @override
  String get userId;

  /// The **timestamp** of the last time this entity was modified.
  @override
  DateTime get modifiedAt;

  /// The **timestamp** of when this entity was first created.
  @override
  DateTime get createdAt;

  /// A **sequential integer** used for optimistic concurrency and tracking
  /// changes.
  @override
  int get version;

  /// A **vector clock** for tracking causality across multiple devices.
  ///
  /// Declared, not defined: [DatumEntityMixin] always provides the
  /// implementation (mixin linearization wins), so a body here is dead code.
  @override
  VectorClock? get vectorClock;

  /// A flag indicating if this entity has been locally marked for **deletion**.
  @override
  bool get isDeleted;

  /// Returns a new instance with the vector clock incremented for [replicaId].
  @override
  DatumEntityInterface incrementClock(String replicaId);

  /// Converts the entity to a `Map<String, dynamic>` for persistence.
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local});

  /// Creates a **new instance** of the entity with updated values.
  // Note: copyWith is not included in the mixin to allow flexible return types

  /// Computes the **difference** between the current entity state and an
  /// [oldVersion] of the entity.
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion);

  /// Merges this entity with [other].
  @override
  DatumEntityInterface merge(covariant DatumEntityInterface other);

  /// Indicates whether this entity supports relationships.
  @override
  bool get isRelational;

  /// Provides the list of properties to be used by the [Equatable] mixin
  /// for value equality checks.
  @override
  List<Object?> get props;
}

/// The **base abstract class** for all entities managed by Datum **without**
/// built-in relationship handling.
///
/// Concrete entity classes should typically extend this class if they do
/// not manage relations to other Datum entities.
abstract class DatumEntity extends DatumEntityBase with DatumEntityMixin {
  const DatumEntity();
}

/// A mixin that provides the base functionality for Datum entities.
///
/// Use this mixin when you want to compose Datum's capabilities into your own
/// base classes, allowing for a clean and maintainable architecture without
/// extending [DatumEntity].
///
/// **Important:** Use either [DatumEntityMixin] OR [RelationalDatumEntityMixin],
/// not both. [DatumEntityMixin] provides basic entity functionality without
/// relationships. For entities that need relationships, use [RelationalDatumEntityMixin].
///
/// ```dart
/// class MyEntity with DatumEntityMixin {
///   @override
///   final String id;
///   @override
///   final String userId;
///   @override
///   final DateTime modifiedAt;
///   @override
///   final DateTime createdAt;
///   @override
///   final int version;
///   @override
///   final bool isDeleted;
///
///   // Your custom fields...
///
///   @override
///   Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
///     // Implementation...
///   }
///
///   @override
///   DatumEntityBase copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
///     // Implementation...
///   }
///
///   @override
///   Map<String, dynamic>? diff(covariant DatumEntityBase oldVersion) {
///     // Implementation...
///   }
/// }
/// ```
mixin DatumEntityMixin implements Equatable, DatumEntityInterface {
  /// A **unique identifier** for the entity.
  @override
  String get id;

  /// The ID of the user who owns or created this entity.
  @override
  String get userId;

  /// The **timestamp** of the last time this entity was modified.
  @override
  DateTime get modifiedAt;

  /// The **timestamp** of when this entity was first created.
  @override
  DateTime get createdAt;

  /// A **sequential integer** used for optimistic concurrency and tracking
  /// changes.
  @override
  int get version;

  /// A **vector clock** for tracking causality across multiple devices.
  @override
  VectorClock? get vectorClock => null;

  /// A flag indicating if this entity has been locally marked for **deletion**.
  @override
  bool get isDeleted;

  /// Returns a new instance with the vector clock incremented for [replicaId].
  @override
  DatumEntityInterface incrementClock(String replicaId) => this;

  /// Converts the entity to a `Map<String, dynamic>` for persistence.
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local});

  /// Creates a **new instance** of the entity with updated values.
  // copyWith is not defined in the mixin to allow flexible implementations

  /// Computes the **difference** between the current entity state and an
  /// [oldVersion] of the entity.
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion);

  /// Merges this entity with [other].
  @override
  DatumEntityInterface merge(covariant DatumEntityInterface other) => other;

  /// Indicates whether this entity supports relationships. Always `false` for this mixin.
  @override
  bool get isRelational => false;

  /// Provides the list of properties to be used by the [Equatable] mixin
  /// for value equality checks.
  @override
  List<Object?> get props => [id, userId, modifiedAt, createdAt, version, isDeleted, vectorClock];
}
