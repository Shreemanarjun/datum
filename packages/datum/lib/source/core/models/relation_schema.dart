import 'package:datum/source/core/models/datum_entity.dart';

/// The kind of a relationship, independent of any entity instance.
enum RelationKind { belongsTo, hasMany, hasOne, manyToMany }

/// A **type-level, instance-free description** of a single relationship.
///
/// Lets adapters (e.g. a Drift/SQL adapter) traverse a relation chain such as
/// `debt.lenderGroup.members.person` to build joins, without needing a fetched
/// entity instance (whose `relation.value` may still be null). See issue #21.
class RelationDescriptor {
  const RelationDescriptor({
    required this.name,
    required this.kind,
    required this.targetType,
    required this.foreignKey,
    required this.localKey,
    this.pivotType,
    this.otherForeignKey,
    this.otherLocalKey,
  });

  /// The relation name (the key in the entity's `relations` map).
  final String name;

  /// Whether this is a belongsTo / hasMany / hasOne / manyToMany relation.
  final RelationKind kind;

  /// The related entity type.
  final Type targetType;

  /// The foreign key column (for many-to-many, the pivot's key on this side).
  final String foreignKey;

  /// The local key column (for many-to-many, this side's local key).
  final String localKey;

  /// The pivot entity type (many-to-many only).
  final Type? pivotType;

  /// The pivot's foreign key on the other side (many-to-many only).
  final String? otherForeignKey;

  /// The other side's local key (many-to-many only).
  final String? otherLocalKey;

  @override
  String toString() => 'RelationDescriptor($name: $kind -> $targetType, fk=$foreignKey, lk=$localKey)';
}

/// A global registry mapping an entity [Type] to its relation schema.
///
/// Populated automatically the first time the engine sees an instance of a
/// relational entity (e.g. on push/read), and/or explicitly via [register] /
/// [registerFromInstance]. Once registered, adapters can traverse relations by
/// type alone — no entity instance required (#21):
///
/// ```dart
/// final debtRels = DatumRelationSchema.of(Debt);           // {lenderGroup: ...}
/// final groupType = debtRels!['lenderGroup']!.targetType;  // Group
/// final memberType = DatumRelationSchema.descriptor(groupType, 'members')!.targetType;
/// ```
abstract final class DatumRelationSchema {
  static final Map<Type, Map<String, RelationDescriptor>> _schemas = {};

  /// Registers [schema] for [type], replacing any existing registration.
  static void register(Type type, Map<String, RelationDescriptor> schema) {
    _schemas[type] = Map.unmodifiable(schema);
  }

  /// The relation schema registered for [type], or `null` if none.
  static Map<String, RelationDescriptor>? of(Type type) => _schemas[type];

  /// The descriptor for relation [name] on [type], or `null`.
  static RelationDescriptor? descriptor(Type type, String name) => _schemas[type]?[name];

  /// Whether a schema is registered for [type].
  static bool isRegistered(Type type) => _schemas.containsKey(type);

  /// All registered entity types.
  static Iterable<Type> get registeredTypes => _schemas.keys;

  /// Clears the registry (primarily for tests).
  static void clear() => _schemas.clear();
}

/// Contract for objects that can describe their relation schema without needing
/// their relation values to be loaded. Implemented by `RelationalDatumEntity`.
abstract interface class RelationSchemaProvider {
  /// The relation schema for this entity, keyed by relation name.
  Map<String, RelationDescriptor> get relationSchema;
}

/// Marker used by the schema registry; kept here to avoid import cycles.
typedef DatumEntityType = DatumEntityInterface;
