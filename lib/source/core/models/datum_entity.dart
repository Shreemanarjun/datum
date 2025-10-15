/// The target for serialization, allowing different fields for local vs. remote.
enum MapTarget {
  /// For serialization to the local database.
  local,

  /// For serialization to the remote data source.
  remote,
}

/// Base class for all entities managed by Datum.
///
/// This abstract class defines the essential properties and methods that
/// any data model must implement to be compatible with the Datum synchronization
/// engine. It promotes immutability through the `copyWith` method and provides
/// mechanisms for serialization and change detection.
abstract class DatumEntity {
  /// A unique identifier for the entity. Typically a UUID.
  String get id;

  /// The ID of the user who owns this entity.
  String get userId;

  /// The last time the entity was modified. This is crucial for conflict
  /// resolution strategies like "last write wins".
  DateTime get modifiedAt;

  /// The time the entity was created.
  DateTime get createdAt;

  /// The version of the entity, used for optimistic locking and conflict detection.
  /// This number should be incremented on every modification.
  int get version;

  /// A flag indicating if the entity is soft-deleted. Instead of physically
  /// deleting records, they are marked as deleted to allow the deletion to be
  /// synced to other clients.
  bool get isDeleted;

  /// Serializes the entity to a map.
  ///
  /// The [target] parameter can be used to customize the output for different
  /// destinations (e.g., omitting certain fields for the remote API).
  Map<String, dynamic> toMap({MapTarget target = MapTarget.local});

  /// Creates a copy of the entity with updated fields.
  ///
  /// This method is crucial for immutability. Instead of modifying an entity
  /// directly, you create a new instance with the desired changes.
  DatumEntity copyWith({DateTime? modifiedAt, int? version, bool? isDeleted});

  /// Compares this entity with an older version and returns a map of the
  /// fields that have changed. Returns `null` if there are no differences.
  Map<String, dynamic>? diff(DatumEntity oldVersion);
}
