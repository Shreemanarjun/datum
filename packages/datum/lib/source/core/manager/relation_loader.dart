import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/models/data_source.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/relation_schema.dart';
import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:datum/source/core/query/datum_query.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:datum/source/core/manager/manager_locator.dart';

/// Internal collaborator of [DatumManager] that loads and stitches related
/// entities: eager loading (`withRelated`), relation-schema registration, and
/// the internals of the deprecated `fetchRelated`/`watchRelated` APIs.
///
/// This class is an implementation detail of the manager and is NOT exported
/// from the package barrel. The public methods stay on [DatumManager] and
/// delegate here.
class RelationLoader<T extends DatumEntityInterface> {
  RelationLoader({
    required this.manager,
    required DatumLogger logger,
    required this.recurseIntoRelated,
  }) : _logger = logger;

  /// The owning manager (adapters are reached through it).
  final DatumManager<T> manager;

  final DatumLogger _logger;

  /// Recurses into nested relation paths on a *related* manager.
  ///
  /// Provided by [DatumManager] as a callback: the recursion goes through the
  /// related manager's library-private `_fetchAndStitchRelations` (which in
  /// turn delegates to that manager's own [RelationLoader]), so the call must
  /// originate from the manager's library.
  final Future<void> Function(
    DatumManager<DatumEntityInterface> relatedManager,
    List<DatumEntityInterface> entities,
    List<String> relations,
    DataSource source,
    String? userId,
  ) recurseIntoRelated;

  /// Registers a relational entity's schema in [DatumRelationSchema] the first
  /// time an instance is seen, enabling instance-free relation traversal (#21).
  void registerRelationSchema(DatumEntityInterface entity) {
    if (entity is RelationalDatumEntity && !DatumRelationSchema.isRegistered(entity.runtimeType)) {
      DatumRelationSchema.register(entity.runtimeType, entity.relationSchema);
    }
  }

  Future<void> fetchAndStitchRelations(List<T> entities, List<String> relations, DataSource source, String? userId) async {
    if (entities.isEmpty || entities.first is! RelationalDatumEntity) {
      return;
    }
    registerRelationSchema(entities.first);

    // A read without an explicit userId still concerns the parents' OWN data:
    // fall back to their userId so stitching never attaches other users' rows
    // whose foreign keys happen to collide.
    final ownerId = userId ?? entities.first.userId;
    Future<List<DatumEntityInterface>> queryIn(DatumManager<DatumEntityInterface> m, String field, List<Object?> values) => m.query(DatumQuery(filters: [Filter(field, FilterOperator.isIn, values)]), source: source, userId: ownerId);

    final firstEntity = entities.first as RelationalDatumEntity;
    for (final MapEntry(key: relationName, value: subPaths) in _groupRelationPaths(relations).entries) {
      final relation = firstEntity.relations[relationName];
      if (relation == null) {
        _logger.warn('Relation "$relationName" not found on entity ${T.toString()}');
        continue;
      }

      final relatedManager = relation.relatedManager;
      final fetchedRelated = await switch (relation) {
        BelongsTo() => _stitchBelongsTo(relation, entities, relationName, queryIn),
        HasMany() => _stitchHasMany(relation, entities, relationName, queryIn),
        HasOne() => _stitchHasOne(relation, entities, relationName, queryIn),
        ManyToMany() => _stitchManyToMany(relation, entities, relationName, queryIn),
      };

      // Recurse into nested relations on the fetched related entities.
      if (subPaths.isNotEmpty && fetchedRelated.isNotEmpty) {
        await recurseIntoRelated(relatedManager, fetchedRelated, subPaths, source, ownerId);
      }
    }
  }

  /// Fetches related entities for a given parent entity (the internals behind
  /// the deprecated `DatumManager.fetchRelated`).
  Future<List<R>> fetchRelated<R extends DatumEntityInterface>(
    T parent,
    String relationName, {
    DataSource source = DataSource.local,
  }) async {
    if (parent is RelationalDatumEntity) {
      final relation = parent.relations[relationName];
      if (relation == null) {
        throw ArgumentError(
          'Relation "$relationName" is not defined on entity type ${parent.runtimeType}.',
        );
      }
    } else {
      throw ArgumentError(
        'The parent entity must be a RelationalDatumEntity to fetch relations.',
      );
    }

    final relatedManager = ManagerLocator.of<R>();

    switch (source) {
      case DataSource.local:
        return manager.localAdapter.fetchRelated(
          parent,
          relationName,
          relatedManager.localAdapter,
        );
      case DataSource.remote:
        return manager.remoteAdapter.fetchRelated(
          parent,
          relationName,
          relatedManager.remoteAdapter,
        );
    }
  }

  /// Reactively watches related entities for a given parent entity (the
  /// internals behind the deprecated `DatumManager.watchRelated`).
  Stream<List<R>>? watchRelated<R extends DatumEntityInterface>(
    T parent,
    String relationName,
  ) {
    if (parent is RelationalDatumEntity) {
      final relation = parent.relations[relationName];
      if (relation == null) {
        throw ArgumentError(
          'Relation "$relationName" is not defined on entity type ${parent.runtimeType}.',
        );
      }
    } else {
      throw ArgumentError(
        'The parent entity must be a RelationalDatumEntity to watch relations.',
      );
    }

    final relatedManager = ManagerLocator.of<R>();

    return manager.localAdapter.watchRelated(
      parent,
      relationName,
      relatedManager.localAdapter,
    );
  }
}

/// Queries [manager] for rows whose [field] is in [values].
typedef _InQuery = Future<List<DatumEntityInterface>> Function(
  DatumManager<DatumEntityInterface> manager,
  String field,
  List<Object?> values,
);

/// Groups dot-notation relation paths (e.g. 'posts.comments') by their
/// top-level segment so each relation is fetched once; the values are the
/// remaining sub-paths to recurse into (#22).
Map<String, List<String>> _groupRelationPaths(List<String> relations) {
  final nested = <String, List<String>>{};
  for (final path in relations) {
    final dot = path.indexOf('.');
    final subPaths = nested.putIfAbsent(dot == -1 ? path : path.substring(0, dot), () => <String>[]);
    if (dot != -1 && dot + 1 < path.length) subPaths.add(path.substring(dot + 1));
  }
  return nested;
}

void _setRelation(DatumEntityInterface entity, String relationName, Object? value) => (entity as RelationalDatumEntity).relations[relationName]?.setRaw(value);

List<Object?> _distinctValues(List<DatumEntityInterface> entities, String key) => entities.map((e) => e.toDatumMap()[key]).nonNulls.toSet().toList();

Future<List<DatumEntityInterface>> _stitchBelongsTo(
  BelongsTo relation,
  List<DatumEntityInterface> entities,
  String relationName,
  _InQuery queryIn,
) async {
  final foreignKeyName = relation.foreignKey;
  final foreignKeyValues = _distinctValues(entities, foreignKeyName);
  if (foreignKeyValues.isEmpty) return const [];

  final related = await queryIn(relation.relatedManager, relation.localKey, foreignKeyValues);
  final relatedById = {for (final e in related) e.id: e};
  for (final entity in entities) {
    _setRelation(entity, relationName, relatedById[entity.toDatumMap()[foreignKeyName]]);
  }
  return related;
}

Future<List<DatumEntityInterface>> _stitchHasMany(
  HasMany relation,
  List<DatumEntityInterface> entities,
  String relationName,
  _InQuery queryIn,
) async {
  final foreignKeyName = relation.foreignKey;
  final localKeyValues = entities.map((e) => e.id).toSet().toList();
  if (localKeyValues.isEmpty) return const [];

  final related = await queryIn(relation.relatedManager, foreignKeyName, localKeyValues);
  final relatedByParentId = <String, List<DatumEntityInterface>>{};
  for (final r in related) {
    // toDatumMap is on the base interface — related entities need not be relational.
    (relatedByParentId[r.toDatumMap()[foreignKeyName]] ??= []).add(r);
  }
  for (final entity in entities) {
    _setRelation(entity, relationName, relatedByParentId[entity.id] ?? <DatumEntityInterface>[]);
  }
  return related;
}

/// 1:1 where the related entity holds the foreign key.
Future<List<DatumEntityInterface>> _stitchHasOne(
  HasOne relation,
  List<DatumEntityInterface> entities,
  String relationName,
  _InQuery queryIn,
) async {
  final foreignKeyName = relation.foreignKey;
  final localKeyName = relation.localKey;
  final localKeyValues = _distinctValues(entities, localKeyName);
  if (localKeyValues.isEmpty) return const [];

  final related = await queryIn(relation.relatedManager, foreignKeyName, localKeyValues);
  final byForeignKey = <Object?, DatumEntityInterface>{};
  for (final r in related) {
    byForeignKey.putIfAbsent(r.toDatumMap()[foreignKeyName], () => r); // first wins for a 1:1
  }
  for (final entity in entities) {
    _setRelation(entity, relationName, byForeignKey[entity.toDatumMap()[localKeyName]]);
  }
  return related;
}

/// Traverses the pivot entity to resolve the many-to-many targets.
Future<List<DatumEntityInterface>> _stitchManyToMany(
  ManyToMany relation,
  List<DatumEntityInterface> entities,
  String relationName,
  _InQuery queryIn,
) async {
  final thisLocalKeyName = relation.thisLocalKey;
  final localKeyValues = _distinctValues(entities, thisLocalKeyName);
  if (localKeyValues.isEmpty) return const [];

  final pivotEntries = await queryIn(ManagerLocator.byType(relation.pivotType), relation.thisForeignKey, localKeyValues);
  final otherIdsByParent = <Object?, List<Object?>>{};
  final allOtherIds = <Object?>{};
  for (final pe in pivotEntries) {
    final m = pe.toDatumMap();
    final otherFk = m[relation.otherForeignKey];
    if (otherFk == null) continue;
    (otherIdsByParent[m[relation.thisForeignKey]] ??= []).add(otherFk);
    allOtherIds.add(otherFk);
  }

  final related = allOtherIds.isEmpty ? const <DatumEntityInterface>[] : await queryIn(relation.relatedManager, relation.otherLocalKey, allOtherIds.toList());
  final relatedByOtherLocalKey = {for (final r in related) r.toDatumMap()[relation.otherLocalKey]: r};
  for (final entity in entities) {
    final ids = otherIdsByParent[entity.toDatumMap()[thisLocalKeyName]] ?? const [];
    _setRelation(entity, relationName, ids.map((id) => relatedByOtherLocalKey[id]).nonNulls.toList());
  }
  return related;
}
