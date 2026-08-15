import 'package:datum/datum.dart';

import 'manager_cache_coordinator.dart';

// Internal class representing a step in the cascade delete plan.
enum CascadeStepType { delete, update }

// Internal class representing a step in the cascade delete plan.
class CascadeDeleteStep {
  final DatumEntityInterface entity;
  final dynamic manager;
  final String? relationName;
  final CascadeStepType type;
  final Map<String, dynamic>? updateData;

  const CascadeDeleteStep({
    required this.entity,
    required this.manager,
    this.relationName,
    this.type = CascadeStepType.delete,
    this.updateData,
  });
}

/// Internal class representing the complete cascade delete plan.
class CascadeDeletePlan<T extends DatumEntityInterface> {
  final T mainEntity;
  final List<CascadeDeleteStep> steps;
  final bool canDelete;
  final Map<String, List<DatumEntityInterface>> restrictedRelations;

  const CascadeDeletePlan({
    required this.mainEntity,
    required this.steps,
    required this.canDelete,
    required this.restrictedRelations,
  });
}

/// Internal collaborator of [DatumManager] that plans and executes cascade
/// delete operations.
///
/// This class is an implementation detail of the manager and is NOT exported
/// from the package barrel. The public entry points (`cascadeDelete`,
/// `executeCascadeDeleteWithOptions`, `getDeletePlan`, `deleteCascade`) stay
/// on [DatumManager] and delegate here.
class CascadeDeleteCoordinator<T extends DatumEntityInterface> {
  CascadeDeleteCoordinator({
    required this.manager,
    required DatumLogger logger,
    required this.cacheCoordinator,
    required this.executeSetNullOperations,
  }) : _logger = logger;

  /// The owning manager. Needed for read/delete/query and as the manager of
  /// the main entity in the delete plan.
  final DatumManager<T> manager;

  final DatumLogger _logger;

  /// Relationship-query caching lives on the manager's cache coordinator.
  final ManagerCacheCoordinator<T> cacheCoordinator;

  /// Executes setNull operations for BelongsTo relationships.
  ///
  /// Provided by [DatumManager] as a callback: the implementation enqueues
  /// sync operations on *other* managers via library-private members
  /// (`_createOperation`, `_queueManager`, `_isolateHelper`), so it must live
  /// in the manager's library.
  final Future<void> Function(
    T entity,
    String userId,
    DataSource source,
    bool forceRemoteSync,
    List<String> errors,
  ) executeSetNullOperations;

  /// Builds a cascade delete plan for the given entity.
  Future<CascadeDeletePlan<T>> buildCascadeDeletePlan(
    T entity,
    String userId,
    CascadeAnalyticsBuilder analyticsBuilder,
  ) async {
    // The relationship cache cannot observe writes made through *other*
    // managers (its keys don't reference child ids), so a plan must start
    // from a fresh view. Entries added below still dedupe lookups within
    // this single plan build.
    cacheCoordinator.relationshipQueryCache.clear();

    final restrictedRelations = <String, List<DatumEntityInterface>>{};
    final deleteOrder = <CascadeDeleteStep>[];
    final visitedEntities = <String>{};

    // Start with the main entity
    final mainStep = CascadeDeleteStep(
      entity: entity,
      manager: manager,
      relationName: null,
    );

    await _buildDeletePlanRecursive(
      mainStep,
      userId,
      deleteOrder,
      restrictedRelations,
      visitedEntities,
    );

    // Reverse the order so dependencies are deleted first
    final reversedOrder = deleteOrder.reversed.toList();
    deleteOrder.clear();
    deleteOrder.addAll(reversedOrder);

    return CascadeDeletePlan(
      mainEntity: entity,
      steps: deleteOrder,
      canDelete: restrictedRelations.isEmpty,
      restrictedRelations: restrictedRelations,
    );
  }

  /// Recursively builds the delete plan for cascading deletes.
  Future<void> _buildDeletePlanRecursive(
    CascadeDeleteStep currentStep,
    String userId,
    List<CascadeDeleteStep> deleteOrder,
    Map<String, List<DatumEntityInterface>> restrictedRelations,
    Set<String> visitedEntities,
  ) async {
    final entity = currentStep.entity;
    final entityKey = '${entity.runtimeType}:${entity.id}';

    // Prevent infinite loops from circular references
    if (visitedEntities.contains(entityKey)) {
      return;
    }
    visitedEntities.add(entityKey);

    // Add current entity to delete order
    deleteOrder.add(currentStep);

    // If this is not a relational entity, we're done
    if (!entity.isRelational) {
      return;
    }

    final relationalEntity = entity;

    // Process each relationship
    final relations = (relationalEntity as dynamic).relations as Map<String, Relation>;
    for (final entry in relations.entries) {
      final relationName = entry.key;
      final relation = entry.value;

      if (relation.shouldRestrictDelete) {
        // Check if related entities exist
        final relatedEntities = await getRelatedEntities(relationalEntity, relation, userId);
        if (relatedEntities.isNotEmpty) {
          restrictedRelations[relationName] = relatedEntities;
        }
      } else if (relation.shouldCascadeDelete) {
        // Add related entities to delete plan
        final relatedEntities = await getRelatedEntities(relationalEntity, relation, userId);
        for (final relatedEntity in relatedEntities) {
          final relatedStep = CascadeDeleteStep(
            entity: relatedEntity,
            manager: relation.getRelatedManager(),
            relationName: relationName,
          );

          await _buildDeletePlanRecursive(
            relatedStep,
            userId,
            deleteOrder,
            restrictedRelations,
            visitedEntities,
          );
        }
      } else if (relation.shouldSetNullOnDelete) {
        if (relation is HasMany || relation is HasOne) {
          final relatedEntities = await getRelatedEntities(relationalEntity, relation, userId);
          String? foreignKeyName;
          if (relation is HasMany) {
            foreignKeyName = relation.foreignKey;
          } else if (relation is HasOne) {
            foreignKeyName = relation.foreignKey;
          }

          if (foreignKeyName != null) {
            for (final relatedEntity in relatedEntities) {
              final relatedStep = CascadeDeleteStep(
                entity: relatedEntity,
                manager: relation.getRelatedManager(),
                relationName: relationName,
                type: CascadeStepType.update,
                updateData: {foreignKeyName: null},
              );
              deleteOrder.add(relatedStep);
            }
          }
        }
        // For BelongsTo, the foreign key is on current entity being deleted, so no action needed.
      }
      // For none behavior, do nothing during planning
    }
  }

  /// Gets related entities for a given relation.
  Future<List<DatumEntityInterface>> getRelatedEntities(
    DatumEntityInterface parent,
    Relation relation,
    String userId,
  ) async {
    // Create a cache key for this relationship query
    final cacheKey = '${parent.runtimeType}:${parent.id}:${relation.runtimeType}:$userId';

    // Check cache first
    final cached = cacheCoordinator.getCachedRelationshipQuery(cacheKey);
    if (cached != null) {
      return cached;
    }

    final List<DatumEntityInterface> results;

    // Relation is sealed; the switch is exhaustive by construction.
    switch (relation) {
      // HasMany and HasOne resolve identically here: children whose foreign
      // key points at this parent's local key.
      case HasMany(:final localKey, :final foreignKey) || HasOne(:final localKey, :final foreignKey):
        final localKeyValue = parent.toDatumMap()[localKey];
        if (localKeyValue == null) return [];

        results = await relation.getRelatedManager().query(
              DatumQuery(filters: [Filter(foreignKey, FilterOperator.equals, localKeyValue)]),
              source: DataSource.local,
              // For cascade delete, don't filter by userId to find all related entities
            );
      case ManyToMany():
        final thisLocalKeyValue = parent.toDatumMap()[relation.thisLocalKey];
        if (thisLocalKeyValue == null) return [];

        // Get the manager for the pivot entity
        final pivotManager = Datum.managerByType(relation.pivotType);

        // Query the pivot entity to find related pivot entities
        final pivotEntities = await pivotManager.query(
          DatumQuery(filters: [Filter(relation.thisForeignKey, FilterOperator.equals, thisLocalKeyValue)]),
          source: DataSource.local,
          // For cascade delete, don't filter by userId to find all related entities
        );

        // Extract the foreign keys of the related entities from the pivot entities
        final otherForeignKeys = pivotEntities.map((e) => e.toDatumMap()[relation.otherForeignKey]).nonNulls.toSet().toList();

        if (otherForeignKeys.isEmpty) return [];

        // Get the manager for the target entity type
        final relatedManager = relation.getRelatedManager();

        // Query the target entity manager to get the related entities
        results = await relatedManager.query(
          DatumQuery(filters: [Filter('id', FilterOperator.isIn, otherForeignKeys)]),
          source: DataSource.local,
          // For cascade delete, don't filter by userId to find all related entities
        );
      case BelongsTo():
        final foreignKeyValue = parent.toDatumMap()[relation.foreignKey];
        if (foreignKeyValue == null) return [];

        final manager = relation.getRelatedManager();
        final entity = await manager.read(foreignKeyValue); // Don't filter by userId for cascade delete
        results = entity != null ? [entity] : [];
    }

    // Cache the results
    cacheCoordinator.cacheRelationshipQuery(cacheKey, results);
    return results;
  }

  /// Executes the cascade delete plan.
  Future<CascadeDeleteResult<T>> executeCascadeDeletePlan(
    CascadeDeletePlan<T> plan,
    String userId,
    DataSource source,
    bool forceRemoteSync,
  ) async {
    final deletedEntities = <Type, List<DatumEntityInterface>>{};
    final errors = <String>[];

    // First, handle setNull operations for BelongsTo relationships
    await executeSetNullOperations(plan.mainEntity, userId, source, forceRemoteSync, errors);

    // Execute the plan in order: setNull steps patch the foreign key,
    // delete steps remove the row (same semantics as the progress variant).
    for (final step in plan.steps) {
      try {
        if (step.type == CascadeStepType.update && step.updateData != null) {
          await step.manager.localAdapter.patch(
            id: step.entity.id,
            delta: step.updateData!,
            userId: userId,
          );
          step.manager.invalidateMetadataHash(userId);
          continue;
        }

        final success = await step.manager.performDeleteWithoutEvents(
          id: step.entity.id,
          userId: userId,
          source: source,
          forceRemoteSync: forceRemoteSync,
        );

        if (success) {
          deletedEntities.putIfAbsent(step.entity.runtimeType, () => []).add(step.entity);
        } else {
          errors.add('Failed to delete ${step.entity.runtimeType}:${step.entity.id}');
        }
      } catch (e) {
        errors.add('Error deleting ${step.entity.runtimeType}:${step.entity.id}: $e');
      }
    }

    return CascadeDeleteResult<T>(
      success: errors.isEmpty,
      entity: plan.mainEntity,
      deletedEntities: deletedEntities,
      restrictedRelations: plan.restrictedRelations,
      errors: errors,
    );
  }

  /// Executes cascade delete plan with progress tracking and cancellation support.
  Future<CascadeDeleteResult<T>> executeCascadeDeletePlanWithProgress(
    CascadeDeletePlan<T> plan,
    String userId,
    DataSource source,
    bool forceRemoteSync,
    CascadeOptions options,
    CascadeAnalyticsBuilder analyticsBuilder,
  ) async {
    final deletedEntities = <Type, List<DatumEntityInterface>>{};
    final errors = <String>[];
    var completed = 0;

    // Execute deletes in the planned order
    for (final step in plan.steps) {
      // Check for cancellation
      if (options.cancellationToken?.isCancelled ?? false) {
        analyticsBuilder.recordError();
        errors.add('Operation cancelled');
        break;
      }

      // Check for timeout
      final startTime = DateTime.now();
      if (startTime.difference(DateTime.now()) > options.timeout) {
        analyticsBuilder.recordError();
        errors.add('Operation timed out');
        break;
      }

      try {
        analyticsBuilder.recordQueryExecuted();

        bool success = true;
        if (step.type == CascadeStepType.delete) {
          success = await step.manager.performDeleteWithoutEvents(
            id: step.entity.id,
            userId: userId,
            source: source,
            forceRemoteSync: forceRemoteSync,
          );
        } else if (step.type == CascadeStepType.update && step.updateData != null) {
          try {
            await step.manager.localAdapter.patch(
              id: step.entity.id,
              delta: step.updateData!,
              userId: userId,
            );
            step.manager.invalidateMetadataHash(userId);
            analyticsBuilder.recordSetNullOperation();
            // Manually emit update event? Or assume localAdapter emits it?
            // performDeleteWithoutEvents suggests we manipulate events manually.
            // localAdapter.patch likely emits change event if implemented properly.
            // For consistency with cascade delete which suppresses events during execution
            // and emits them later (maybe?), we should check.
            // But existing delete implementation emits main entity delete event at the end.
            // Cascade steps might not emit events?
            // Actually currently step.manager.performDeleteWithoutEvents is used.
            // So we probably want update without events, but we don't have that method easily.
            // For now using patch is atomic-ish on adapter level.
            success = true;
          } catch (e) {
            success = false;
            // Log error?
            _logger.error('Failed to set null for ${step.entity.id}: $e');
          }
        }

        if (success) {
          if (step.type == CascadeStepType.delete) {
            analyticsBuilder.recordEntityDeleted(step.entity.runtimeType);
            deletedEntities.putIfAbsent(step.entity.runtimeType, () => []).add(step.entity);
          }
        } else {
          analyticsBuilder.recordError();
          errors.add('Failed to ${step.type == CascadeStepType.delete ? 'delete' : 'update'} ${step.entity.runtimeType}:${step.entity.id}');
          if (!options.allowPartialDeletes) {
            break; // Stop on first failure if partial deletes not allowed
          }
        }
      } catch (e) {
        analyticsBuilder.recordError();
        errors.add('Error deleting ${step.entity.runtimeType}:${step.entity.id}: $e');
        if (!options.allowPartialDeletes) {
          break; // Stop on first error if partial deletes not allowed
        }
      }

      completed++;
      options.onProgress?.call(CascadeProgress(
        completed: completed,
        total: plan.steps.length,
        currentEntityType: step.entity.runtimeType.toString(),
        currentEntityId: step.entity.id,
        message: step.type == CascadeStepType.delete ? 'Deleting ${step.entity.runtimeType.toString()}' : 'Updating ${step.entity.runtimeType.toString()}',
      ));
    }

    return CascadeDeleteResult<T>(
      success: errors.isEmpty,
      entity: plan.mainEntity,
      deletedEntities: deletedEntities,
      restrictedRelations: plan.restrictedRelations,
      errors: errors,
    );
  }
}
