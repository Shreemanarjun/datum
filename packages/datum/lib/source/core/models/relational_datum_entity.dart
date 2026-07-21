import 'package:datum/datum.dart';
import 'package:equatable/equatable.dart';

/// Defines the cascading behavior for delete operations on relationships.
enum CascadeDeleteBehavior {
  /// Do not cascade delete - this is the default behavior.
  /// The related entities will remain, potentially becoming orphaned.
  none,

  /// Cascade delete to related entities.
  /// When the parent is deleted, all related entities will also be deleted.
  cascade,

  /// Prevent deletion if related entities exist.
  /// The delete operation will fail if there are related entities.
  restrict,

  /// Set foreign keys to null instead of deleting.
  /// Only applicable to BelongsTo relationships.
  setNull,
}

// A sealed class representing the different types of relationships between entities.
sealed class Relation<T extends DatumEntityInterface> {
  final RelationalDatumEntity _parent;
  final CascadeDeleteBehavior cascadeDeleteBehavior;

  const Relation(
    this._parent, {
    this.cascadeDeleteBehavior = CascadeDeleteBehavior.none,
  });

  dynamic get value;

  DatumManager<T> getRelatedManager();

  /// Returns true if this relation should cascade delete operations.
  bool get shouldCascadeDelete => cascadeDeleteBehavior == CascadeDeleteBehavior.cascade;

  /// Returns true if this relation should restrict delete operations.
  bool get shouldRestrictDelete => cascadeDeleteBehavior == CascadeDeleteBehavior.restrict;

  /// Returns true if this relation should set foreign keys to null.
  bool get shouldSetNullOnDelete => cascadeDeleteBehavior == CascadeDeleteBehavior.setNull;

  /// Sets the value of the relation from a raw dynamic value (e.g. from generic query results).
  void setRaw(dynamic value);

  /// The related entity type for this relation.
  Type get targetType => T;

  /// Builds an instance-free [RelationDescriptor] for this relation under [name].
  RelationDescriptor describe(String name) {
    final self = this;
    return switch (self) {
      BelongsTo() => RelationDescriptor(name: name, kind: RelationKind.belongsTo, targetType: targetType, foreignKey: self.foreignKey, localKey: self.localKey),
      HasMany() => RelationDescriptor(name: name, kind: RelationKind.hasMany, targetType: targetType, foreignKey: self.foreignKey, localKey: self.localKey),
      HasOne() => RelationDescriptor(name: name, kind: RelationKind.hasOne, targetType: targetType, foreignKey: self.foreignKey, localKey: self.localKey),
      ManyToMany() => RelationDescriptor(
          name: name,
          kind: RelationKind.manyToMany,
          targetType: targetType,
          foreignKey: self.thisForeignKey,
          localKey: self.thisLocalKey,
          pivotType: self.pivotType,
          otherForeignKey: self.otherForeignKey,
          otherLocalKey: self.otherLocalKey,
        ),
    };
  }
}

class BelongsTo<T extends DatumEntityInterface> extends Relation<T> {
  final String foreignKey;
  final String localKey;
  T? _value;
  bool _isLoaded = false;

  BelongsTo(
    super.parent,
    this.foreignKey, {
    this.localKey = 'id',
    T? value,
    super.cascadeDeleteBehavior = CascadeDeleteBehavior.none,
  }) {
    _value = value;
    if (value != null) {
      _isLoaded = true;
    }
  }

  @override
  T? get value => _value;

  void set(T? value) {
    _value = value;
    _isLoaded = true;
  }

  @override
  void setRaw(dynamic value) {
    if (value == null) {
      set(null);
    } else {
      set(value as T);
    }
  }

  Future<T?> fetch() async {
    if (_isLoaded) {
      return _value;
    }
    final foreignKeyValue = _parent.toDatumMap()[foreignKey];
    if (foreignKeyValue == null) {
      return null;
    }
    final manager = getRelatedManager();
    final related = await manager.read(foreignKeyValue, userId: _parent.userId);
    _value = related;
    _isLoaded = true;
    return related;
  }

  @override
  DatumManager<T> getRelatedManager() {
    return Datum.manager<T>();
  }
}

class HasMany<T extends DatumEntityInterface> extends Relation<T> {
  final String foreignKey;
  final String localKey;
  List<T>? _value;
  bool _isLoaded = false;

  HasMany(
    super.parent,
    this.foreignKey, {
    this.localKey = 'id',
    List<T>? value,
    super.cascadeDeleteBehavior = CascadeDeleteBehavior.none,
  }) {
    _value = value;
    if (value != null) {
      _isLoaded = true;
    }
  }

  @override
  List<T>? get value => _value;

  void set(List<T>? value) {
    _value = value;
    _isLoaded = true;
  }

  @override
  void setRaw(dynamic value) {
    if (value == null) {
      set(null);
    } else if (value is List) {
      set(value.cast<T>());
    }
  }

  Future<List<T>?> fetch() async {
    if (_isLoaded) {
      return _value;
    }
    final localKeyValue = _parent.toDatumMap()[localKey];
    if (localKeyValue == null) {
      return [];
    }
    final manager = getRelatedManager();
    final related = await manager.query(
      DatumQuery(filters: [Filter(foreignKey, FilterOperator.equals, localKeyValue)]),
      source: DataSource.local,
      userId: _parent.userId,
    );
    _value = related;
    _isLoaded = true;
    return related;
  }

  @override
  DatumManager<T> getRelatedManager() {
    return Datum.manager<T>();
  }
}

class HasOne<T extends DatumEntityInterface> extends Relation<T> {
  final String foreignKey;
  final String localKey;
  T? _value;
  bool _isLoaded = false;

  HasOne(
    super.parent,
    this.foreignKey, {
    this.localKey = 'id',
    T? value,
    super.cascadeDeleteBehavior = CascadeDeleteBehavior.none,
  }) {
    _value = value;
    if (value != null) {
      _isLoaded = true;
    }
  }

  @override
  T? get value => _value;

  void set(T? value) {
    _value = value;
    _isLoaded = true;
  }

  @override
  void setRaw(dynamic value) {
    if (value == null) {
      set(null);
    } else {
      set(value as T);
    }
  }

  Future<T?> fetch() async {
    if (_isLoaded) {
      return _value;
    }
    final localKeyValue = _parent.toDatumMap()[localKey];
    if (localKeyValue == null) {
      return null;
    }
    final manager = getRelatedManager();
    // The related (child) entity holds the foreign key — query for it, exactly
    // like HasMany and the eager-loading stitcher do. The previous
    // implementation called `manager.read(localKeyValue)`, i.e. looked the
    // child up by PRIMARY id equal to the parent's key, which only returned
    // the right entity when the child's id coincidentally equalled it.
    final related = await manager.query(
      DatumQuery(filters: [Filter(foreignKey, FilterOperator.equals, localKeyValue)]),
      source: DataSource.local,
      userId: _parent.userId,
    );
    final result = related.isEmpty ? null : related.first;
    _value = result;
    _isLoaded = true;
    return result;
  }

  @override
  DatumManager<T> getRelatedManager() {
    return Datum.manager<T>();
  }
}

class ManyToMany<T extends DatumEntityInterface> extends Relation<T> {
  final Type pivotType;

  final String thisForeignKey;

  final String otherForeignKey;

  final String thisLocalKey;

  final String otherLocalKey;

  List<T>? _value;

  bool _isLoaded = false;

  ManyToMany(
    super.parent,
    this.pivotType,
    this.thisForeignKey,
    this.otherForeignKey, {
    this.thisLocalKey = 'id',
    this.otherLocalKey = 'id',
    List<T>? value,
    super.cascadeDeleteBehavior = CascadeDeleteBehavior.none,
  }) {
    _value = value;
    if (value != null) {
      _isLoaded = true;
    }
  }

  @override
  List<T>? get value => _value;

  void set(List<T>? value) {
    _value = value;

    _isLoaded = true;
  }

  @override
  void setRaw(dynamic value) {
    if (value == null) {
      set(null);
    } else if (value is List) {
      set(value.cast<T>());
    }
  }

  Future<List<T>?> fetch() async {
    if (_isLoaded) {
      return _value;
    }

    final thisLocalKeyValue = _parent.toDatumMap()[thisLocalKey];
    if (thisLocalKeyValue == null) {
      return [];
    }

    // Get the manager for the pivot entity
    final pivotManager = Datum.managerByType(pivotType);

    // Query the pivot entity to find related pivot entities
    final pivotEntities = await pivotManager.query(
      DatumQuery(filters: [Filter(thisForeignKey, FilterOperator.equals, thisLocalKeyValue)]),
      source: DataSource.local,
      userId: _parent.userId,
    );

    // Extract the foreign keys of the related entities from the pivot entities
    final otherForeignKeys = pivotEntities.map((e) => e.toDatumMap()[otherForeignKey]).nonNulls.toList();

    if (otherForeignKeys.isEmpty) {
      _value = [];
      _isLoaded = true;
      return _value;
    }

    // Get the manager for the target entity type
    final relatedManager = getRelatedManager();

    // Query the target entity manager to get the related entities
    final related = await relatedManager.query(
      DatumQuery(filters: [Filter('id', FilterOperator.isIn, otherForeignKeys)]),
      source: DataSource.local,
      userId: _parent.userId,
    );

    _value = related;
    _isLoaded = true;
    return related;
  }

  @override
  DatumManager<T> getRelatedManager() {
    return Datum.manager<T>();
  }
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
///   Map<String, Relation> get relations => {'author': BelongsTo<User>(this, 'userId')};
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
///     'profile': HasOne<Profile>(this, 'userId'), // A Profile has a `userId` field
///     'posts': HasMany<Post>(this, 'userId'),   // A Post has a `userId` field
///   };
/// }
/// ```
///
/// ---
///
/// Entities that have relationships with other syncable entities should extend this
/// class instead of [DatumEntity] directly.
abstract class RelationalDatumEntity extends DatumEntity with RelationalDatumEntityMixin {
  /// Creates a `const` [RelationalDatumEntity].
  const RelationalDatumEntity();

  /// Indicates whether this entity supports relationships. Always `true` for this class.
  @override
  bool get isRelational => true;

  /// A map defining all relationships for this entity.
  ///
  /// The key is a descriptive name for the relation, and the value is an
  /// instance of a [Relation] subclass (`BelongsTo`, `HasMany`, `ManyToMany`).
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Map<String, Relation> get relations => {
  ///   'author': BelongsTo<User>(this, 'userId'),
  /// };
  /// ```
  @override
  Map<String, Relation> get relations => {};

  /// An instance-free description of this entity's relations (#21).
  ///
  /// Registered globally via [DatumRelationSchema] the first time the engine
  /// sees an instance, so adapters can traverse relation chains by type alone.
  Map<String, RelationDescriptor> get relationSchema => {
        for (final e in relations.entries) e.key: e.value.describe(e.key),
      };

  /// Copies all currently-loaded in-memory relation values from [source] onto
  /// this entity, so a rebuilt (`copyWith`) instance keeps its relation
  /// references instead of losing them (#34).
  ///
  /// Datum entities are immutable, so updating a field produces a new instance
  /// whose relations start empty. Rather than re-fetching or re-linking, carry
  /// the already-loaded relations across with a cascade:
  ///
  /// ```dart
  /// final updated = user.copyWith(name: 'New')..preserveRelationsFrom(user);
  /// // updated.relations['posts'].value is the same list as user's — no refetch.
  /// ```
  ///
  /// Only relations that are already loaded on [source] are copied.
  void preserveRelationsFrom(RelationalDatumEntity source) {
    for (final entry in source.relations.entries) {
      final loaded = entry.value.value;
      if (loaded != null) {
        relations[entry.key]?.setRaw(loaded);
      }
    }
  }

  /// Returns the loaded value of a to-many relation ([HasMany] / [ManyToMany])
  /// as a typed `List<R>`, or `null` if the relation is absent or not loaded.
  ///
  /// Ergonomic replacement for `(entity.relations['posts'] as HasMany).value`:
  ///
  /// ```dart
  /// final posts = blog.relatedList<Post>('posts') ?? const [];
  /// ```
  List<R>? relatedList<R extends DatumEntityInterface>(String name) {
    final value = relations[name]?.value;
    return value is List ? value.cast<R>() : null;
  }

  /// Returns the loaded value of a to-one relation ([BelongsTo] / [HasOne]) as
  /// a typed `R`, or `null` if the relation is absent or not loaded.
  ///
  /// ```dart
  /// final author = post.relatedOne<User>('author');
  /// ```
  R? relatedOne<R extends DatumEntityInterface>(String name) {
    final value = relations[name]?.value;
    return value is R ? value : null;
  }

  /// Converts the entity to a `Map<String, dynamic>` for persistence.
  ///
  /// The optional [target] parameter dictates which set of fields to include,
  /// e.g., excluding heavy local-only fields for remote sync.
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local});

  /// Creates a **new instance** of the entity with updated values.
  ///
  /// This method is primarily used to update the sync-related fields
  /// like [modifiedAt], [version], and [isDeleted] during a sync operation.
  ///
  /// **Subclasses must override** this method to include their own fields
  /// in the copy process.
  RelationalDatumEntity copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  });

  /// Computes the **difference** between the current entity state and an
  /// [oldVersion] of the entity.
  ///
  /// Returns a **`Map<String, dynamic>`** containing only the fields that have
  /// changed, with their new values.
  /// Returns `null` if the entities are identical (no changes detected).
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion);
}

/// A mixin that provides relational functionality for Datum entities.
///
/// Use this mixin when you want to compose Datum's relational capabilities
/// into your own base classes, allowing for a clean and maintainable architecture
/// without extending [RelationalDatumEntity].
///
/// **Important:** Use either [DatumEntityMixin] OR [RelationalDatumEntityMixin],
/// not both. [RelationalDatumEntityMixin] provides all the functionality of
/// [DatumEntityMixin] plus relational capabilities.
///
/// ```dart
/// class MyEntity with RelationalDatumEntityMixin {
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
///   Map<String, Relation> get relations => {
///     'author': BelongsTo<User>(this, 'userId'),
///   };
///
///   @override
///   Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
///     // Implementation...
///   }
///
///   @override
///   DatumEntityInterface copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
///     // Implementation...
///   }
///
///   @override
///   Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
///     // Implementation...
///   }
/// }
/// ```
mixin RelationalDatumEntityMixin implements Equatable, DatumEntityInterface {
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

  /// Computes the **difference** between the current entity state and an
  /// [oldVersion] of the entity.
  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion);

  /// Merges this entity with [other].
  @override
  DatumEntityInterface merge(covariant DatumEntityInterface other) => other;

  /// Indicates whether this entity supports relationships. Always `true` for this mixin.
  @override
  bool get isRelational => true;

  /// A map defining all relationships for this entity.
  ///
  /// The key is a descriptive name for the relation, and the value is an
  /// instance of a [Relation] subclass (`BelongsTo`, `HasMany`, `ManyToMany`).
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Map<String, Relation> get relations => {
  ///   'author': BelongsTo<User>(this, 'userId'),
  /// };
  /// ```
  Map<String, Relation> get relations => {};

  /// Provides the list of properties to be used by the [Equatable] mixin
  /// for value equality checks.
  @override
  List<Object?> get props => [id, userId, modifiedAt, createdAt, version, isDeleted, vectorClock];
}

/// Memoizes an entity's relations so eager loading (`withRelated`) works
/// reliably for **hand-written** entities.
///
/// Eager loading mutates `Relation` objects in place (via `setRaw`). If your
/// `relations` getter builds a fresh map on every call, those mutations are
/// silently lost and `relatedList(...)` always returns `null`. Mix this in and
/// define [buildRelations] instead of overriding `relations` — the map is built
/// once, lazily, and reused, so loaded relations persist:
///
/// ```dart
/// class Blog extends RelationalDatumEntity with MemoizedRelations {
///   @override
///   Map<String, Relation> buildRelations() => {
///         'posts': HasMany<Post>(this, 'blogId'),
///       };
/// }
/// ```
///
/// (Generated entities already memoize via their generated relations map, so
/// this is only needed when hand-writing relational entities.)
mixin MemoizedRelations on RelationalDatumEntity {
  /// Builds this entity's relation map. Called once, lazily, then cached.
  Map<String, Relation> buildRelations();

  // `late final` (like the generated `_cachedRelations`) memoizes on first
  // access and stays compatible with the entity's `@immutable` contract.
  @override
  late final Map<String, Relation> relations = buildRelations();
}
