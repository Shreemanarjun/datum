import 'package:datum/datum.dart';

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
    userId ??= entities.first.userId;

    // Support nested relations via dot notation, e.g. 'posts.comments'. Group
    // paths by their top-level segment so each relation is fetched once, then
    // recurse into the remaining sub-paths on the fetched related entities (#22).
    final nested = <String, List<String>>{};
    for (final path in relations) {
      final dot = path.indexOf('.');
      final head = dot == -1 ? path : path.substring(0, dot);
      final tail = dot == -1 ? null : path.substring(dot + 1);
      final subPaths = nested.putIfAbsent(head, () => <String>[]);
      if (tail != null && tail.isNotEmpty) subPaths.add(tail);
    }

    for (final entry in nested.entries) {
      final relationName = entry.key;
      final subPaths = entry.value;
      final firstEntity = entities.first as RelationalDatumEntity;
      final relation = firstEntity.relations[relationName];

      if (relation == null) {
        _logger.warn('Relation "$relationName" not found on entity ${T.toString()}');
        continue;
      }

      final relatedManager = relation.getRelatedManager();
      var fetchedRelated = const <DatumEntityInterface>[];

      if (relation is BelongsTo) {
        final foreignKeyName = relation.foreignKey;
        final foreignKeyValues = entities.map((e) => (e as RelationalDatumEntity).toDatumMap()[foreignKeyName]).nonNulls.toSet().toList();

        if (foreignKeyValues.isNotEmpty) {
          final relatedEntities = await relatedManager.query(
            DatumQuery(filters: [Filter(relation.localKey, FilterOperator.isIn, foreignKeyValues)]),
            source: source,
            userId: userId,
          );
          final relatedEntitiesById = {for (final e in relatedEntities) e.id: e};

          for (final entity in entities) {
            final relationalEntity = entity as RelationalDatumEntity;
            final foreignKeyValue = relationalEntity.toDatumMap()[foreignKeyName];
            final relatedEntity = relatedEntitiesById[foreignKeyValue];
            relationalEntity.relations[relationName]?.setRaw(relatedEntity);
          }
          fetchedRelated = relatedEntities;
        }
      } else if (relation is HasMany) {
        final foreignKeyName = relation.foreignKey;
        final localKeyValues = entities.map((e) => e.id).toSet().toList();

        if (localKeyValues.isNotEmpty) {
          final relatedEntities = await relatedManager.query(
            DatumQuery(filters: [Filter(foreignKeyName, FilterOperator.isIn, localKeyValues)]),
            source: source,
            userId: userId,
          );

          final relatedEntitiesByParentId = <String, List<DatumEntityInterface>>{};
          for (final relatedEntity in relatedEntities) {
            // toDatumMap is on the base interface — related entities need not be relational.
            final parentId = relatedEntity.toDatumMap()[foreignKeyName];
            (relatedEntitiesByParentId[parentId] ??= []).add(relatedEntity);
          }

          for (final entity in entities) {
            final related = relatedEntitiesByParentId[entity.id] ?? [];
            (entity as RelationalDatumEntity).relations[relationName]?.setRaw(related);
          }
          fetchedRelated = relatedEntities;
        }
      } else if (relation is HasOne) {
        // 1:1 where the related entity holds the foreign key.
        final foreignKeyName = relation.foreignKey;
        final localKeyName = relation.localKey;
        final localKeyValues = entities.map((e) => e.toDatumMap()[localKeyName]).nonNulls.toSet().toList();

        if (localKeyValues.isNotEmpty) {
          final relatedEntities = await relatedManager.query(
            DatumQuery(filters: [Filter(foreignKeyName, FilterOperator.isIn, localKeyValues)]),
            source: source,
            userId: userId,
          );
          final byForeignKey = <Object?, DatumEntityInterface>{};
          for (final r in relatedEntities) {
            final fk = r.toDatumMap()[foreignKeyName];
            byForeignKey.putIfAbsent(fk, () => r); // first wins for a 1:1
          }
          for (final entity in entities) {
            final lk = entity.toDatumMap()[localKeyName];
            (entity as RelationalDatumEntity).relations[relationName]?.setRaw(byForeignKey[lk]);
          }
          fetchedRelated = relatedEntities;
        }
      } else if (relation is ManyToMany) {
        // Traverse the pivot entity to resolve the many-to-many targets.
        final pivotManager = Datum.managerByType(relation.pivotType);
        final thisLocalKeyName = relation.thisLocalKey;
        final localKeyValues = entities.map((e) => e.toDatumMap()[thisLocalKeyName]).nonNulls.toSet().toList();

        if (localKeyValues.isNotEmpty) {
          final pivotEntries = await pivotManager.query(
            DatumQuery(filters: [Filter(relation.thisForeignKey, FilterOperator.isIn, localKeyValues)]),
            source: source,
            userId: userId,
          );

          final otherIdsByParent = <Object?, List<Object?>>{};
          final allOtherIds = <Object?>{};
          for (final pe in pivotEntries) {
            final m = pe.toDatumMap();
            final thisFk = m[relation.thisForeignKey];
            final otherFk = m[relation.otherForeignKey];
            if (otherFk != null) {
              (otherIdsByParent[thisFk] ??= []).add(otherFk);
              allOtherIds.add(otherFk);
            }
          }

          var related = const <DatumEntityInterface>[];
          if (allOtherIds.isNotEmpty) {
            related = await relatedManager.query(
              DatumQuery(filters: [Filter(relation.otherLocalKey, FilterOperator.isIn, allOtherIds.toList())]),
              source: source,
              userId: userId,
            );
          }
          final relatedByOtherLocalKey = {for (final r in related) r.toDatumMap()[relation.otherLocalKey]: r};
          for (final entity in entities) {
            final lk = entity.toDatumMap()[thisLocalKeyName];
            final ids = otherIdsByParent[lk] ?? const [];
            (entity as RelationalDatumEntity).relations[relationName]?.setRaw(ids.map((id) => relatedByOtherLocalKey[id]).nonNulls.toList());
          }
          fetchedRelated = related;
        }
      }

      // Recurse into nested relations on the fetched related entities.
      if (subPaths.isNotEmpty && fetchedRelated.isNotEmpty) {
        await recurseIntoRelated(relatedManager, fetchedRelated, subPaths, source, userId);
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

    final relatedManager = Datum.manager<R>();

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

    final relatedManager = Datum.manager<R>();

    return manager.localAdapter.watchRelated(
      parent,
      relationName,
      relatedManager.localAdapter,
    );
  }
}
