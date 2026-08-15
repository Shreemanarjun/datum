/// Typed relation descriptors — the no-codegen way to declare, load, and
/// fetch relations without stringly-typed names, foreign keys, or casts.
///
/// A [DatumRelationSpec] binds together, at the type level, everything a
/// relation needs: the owning entity [E], the related entity [R], the
/// relation name, and the foreign key **as a [DatumFieldSpec]** — so the
/// same declaration that powers queries and auto-migration also anchors the
/// relation graph, and a typo in any of them fails at compile time.
library;

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:datum/source/core/schema/datum_field_spec.dart';

/// The shape of a typed relation.
enum DatumRelationKind { belongsTo, hasOne, hasMany, manyToMany }

/// A typed, declare-once relation between entities [E] and [R].
///
/// ```dart
/// class Project extends RelationalDatumEntity with MemoizedRelations {
///   static final authorRel = DatumRelationSpec<Project, Author>.belongsTo(
///       'author', foreignKey: authorIdField);
///   static final ticketsRel = DatumRelationSpec<Project, Ticket>.hasMany(
///       'tickets', foreignKey: Ticket.projectIdField,
///       cascadeDelete: CascadeDeleteBehavior.cascade);
///
///   @override
///   Map<String, Relation> buildRelations() => datumRelationsFor(this, [authorRel, ticketsRel]);
/// }
///
/// // Eager load with typed names, read back with bound name + type:
/// final p = await projects.read('p1', userId: uid, withRelated: [Project.ticketsRel].names);
/// final tickets = Project.ticketsRel.listOf(p!) ?? const [];
///
/// // Or fetch lazily — resolved through Datum.manager<R>() on any adapter:
/// final author = await Project.authorRel.fetchOneFor(p);
/// ```
class DatumRelationSpec<E extends RelationalDatumEntity, R extends DatumEntityInterface> {
  /// A to-many relation: rows of [R] whose [foreignKey] equals this entity's
  /// [localKey]. [foreignKey] is the **child's** field spec
  /// (e.g. `Ticket.projectIdField`), keeping one vocabulary for queries,
  /// migration, and relations.
  DatumRelationSpec.hasMany(
    this.name, {
    required DatumFieldSpec<R, String> foreignKey,
    this.localKey = 'id',
    this.cascadeDelete = CascadeDeleteBehavior.none,
  })  : kind = DatumRelationKind.hasMany,
        foreignKeyName = foreignKey.name,
        pivotType = null,
        pivotOtherKeyName = null,
        otherLocalKey = 'id';

  /// A to-one child relation, same key semantics as [DatumRelationSpec.hasMany].
  DatumRelationSpec.hasOne(
    this.name, {
    required DatumFieldSpec<R, String> foreignKey,
    this.localKey = 'id',
    this.cascadeDelete = CascadeDeleteBehavior.none,
  })  : kind = DatumRelationKind.hasOne,
        foreignKeyName = foreignKey.name,
        pivotType = null,
        pivotOtherKeyName = null,
        otherLocalKey = 'id';

  /// A to-one parent relation: the [R] whose [localKey] equals this entity's
  /// [foreignKey] — the **owning entity's own** field spec
  /// (e.g. `Ticket.projectIdField` on `Ticket`).
  DatumRelationSpec.belongsTo(
    this.name, {
    required DatumFieldSpec<E, String> foreignKey,
    this.localKey = 'id',
    this.cascadeDelete = CascadeDeleteBehavior.none,
  })  : kind = DatumRelationKind.belongsTo,
        foreignKeyName = foreignKey.name,
        pivotType = null,
        pivotOtherKeyName = null,
        otherLocalKey = 'id';

  DatumRelationSpec._manyToMany(
    this.name, {
    required this.pivotType,
    required String pivotSelfKey,
    required String pivotOtherKey,
    this.localKey = 'id',
    this.otherLocalKey = 'id',
    this.cascadeDelete = CascadeDeleteBehavior.none,
  })  : kind = DatumRelationKind.manyToMany,
        foreignKeyName = pivotSelfKey,
        pivotOtherKeyName = pivotOtherKey;

  /// A many-to-many relation through a registered pivot entity [P]:
  /// pivot rows whose [pivotSelfKey] equals this entity's id select the [R]
  /// rows referenced by their [pivotOtherKey]. Both keys are the **pivot's**
  /// typed field specs, so the whole join is spelled in one vocabulary:
  ///
  /// ```dart
  /// static final tagsRel = DatumRelationSpec.manyToMany<Ticket, Tag, TicketTag>(
  ///   'tags',
  ///   pivotSelfKey: TicketTag.ticketIdField,
  ///   pivotOtherKey: TicketTag.tagIdField,
  /// );
  /// ```
  static DatumRelationSpec<E, R> manyToMany<E extends RelationalDatumEntity, R extends DatumEntityInterface, P extends DatumEntityInterface>(
    String name, {
    required DatumFieldSpec<P, String> pivotSelfKey,
    required DatumFieldSpec<P, String> pivotOtherKey,
    String localKey = 'id',
    String otherLocalKey = 'id',
    CascadeDeleteBehavior cascadeDelete = CascadeDeleteBehavior.none,
  }) =>
      DatumRelationSpec<E, R>._manyToMany(
        name,
        pivotType: P,
        pivotSelfKey: pivotSelfKey.name,
        pivotOtherKey: pivotOtherKey.name,
        localKey: localKey,
        otherLocalKey: otherLocalKey,
        cascadeDelete: cascadeDelete,
      );

  /// The relation name (the `relations` map key / `withRelated` entry).
  final String name;

  /// The relation shape.
  final DatumRelationKind kind;

  /// The serialized foreign-key field name, taken from the typed field spec
  /// (for [DatumRelationKind.manyToMany]: the pivot's self-side key).
  final String foreignKeyName;

  /// The key on the referenced side (default `'id'`).
  final String localKey;

  /// Cascade-delete behavior carried onto the built relation.
  final CascadeDeleteBehavior cascadeDelete;

  /// The pivot entity type ([DatumRelationKind.manyToMany] only) — must be
  /// registered with `Datum` so `managerByType` can resolve it.
  final Type? pivotType;

  /// The pivot's other-side key name ([DatumRelationKind.manyToMany] only).
  final String? pivotOtherKeyName;

  /// The referenced-side key for the far end of a many-to-many.
  final String otherLocalKey;

  /// Builds the runtime [Relation] for [entity] — `buildRelations()` becomes
  /// a one-liner via [datumRelationsFor].
  Relation<R> buildFor(E entity) => switch (kind) {
        DatumRelationKind.hasMany => HasMany<R>(entity, foreignKeyName, localKey: localKey, cascadeDeleteBehavior: cascadeDelete),
        DatumRelationKind.hasOne => HasOne<R>(entity, foreignKeyName, localKey: localKey, cascadeDeleteBehavior: cascadeDelete),
        DatumRelationKind.belongsTo => BelongsTo<R>(entity, foreignKeyName, localKey: localKey, cascadeDeleteBehavior: cascadeDelete),
        DatumRelationKind.manyToMany => ManyToMany<R>(
            entity,
            pivotType!,
            foreignKeyName,
            pivotOtherKeyName!,
            thisLocalKey: localKey,
            otherLocalKey: otherLocalKey,
            cascadeDeleteBehavior: cascadeDelete,
          ),
      };

  /// The loaded values of this to-many relation on [entity], or null when
  /// not loaded (eager-load first with `withRelated: [spec].names`).
  List<R>? listOf(E entity) => entity.relatedList<R>(name);

  /// The loaded value of this to-one relation on [entity], or null when
  /// absent or not loaded.
  R? oneOf(E entity) => entity.relatedOne<R>(name);

  /// Lazily fetches this to-many relation for [entity], resolving through
  /// the registered `Datum.manager<R>()` — identical on every adapter.
  /// Returns the cached value when already loaded.
  Future<List<R>> fetchListFor(E entity) async {
    final relation = entity.relations[name];
    return switch (relation) {
      HasMany<R>() => await relation.fetch() ?? const [],
      ManyToMany<R>() => await relation.fetch() ?? const [],
      _ => throw StateError('Relation "$name" on $E is not a to-many relation of $R — '
          'was buildRelations() wired through datumRelationsFor with this spec?'),
    };
  }

  /// Lazily fetches this to-one relation for [entity] ([DatumRelationKind.belongsTo]
  /// or [DatumRelationKind.hasOne]), resolving through `Datum.manager<R>()`.
  Future<R?> fetchOneFor(E entity) async {
    final relation = entity.relations[name];
    return switch (relation) {
      BelongsTo<R>() => relation.fetch(),
      HasOne<R>() => relation.fetch(),
      _ => throw StateError('Relation "$name" on $E is not a to-one relation of $R — '
          'was buildRelations() wired through datumRelationsFor with this spec?'),
    };
  }
}

/// Builds an entity's `relations` map from typed specs:
///
/// ```dart
/// @override
/// Map<String, Relation> buildRelations() => datumRelationsFor(this, [authorRel, ticketsRel]);
/// ```
Map<String, Relation> datumRelationsFor<E extends RelationalDatumEntity>(
  E entity,
  List<DatumRelationSpec<E, DatumEntityInterface>> specs,
) =>
    {for (final spec in specs) spec.name: spec.buildFor(entity)};

/// `withRelated:` from typed specs: `withRelated: [Project.ticketsRel].names`.
extension DatumRelationSpecNames on Iterable<DatumRelationSpec<RelationalDatumEntity, DatumEntityInterface>> {
  /// The relation names, for `withRelated:` parameters.
  List<String> get names => [for (final spec in this) spec.name];
}
