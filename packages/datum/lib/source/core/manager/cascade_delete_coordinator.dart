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
      (order: deleteOrder, restricted: restrictedRelations, visited: visitedEntities),
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
    _PlanState state,
  ) async {
    final entity = currentStep.entity;

    // Prevent infinite loops from circular references
    if (!state.visited.add('${entity.runtimeType}:${entity.id}')) {
      return;
    }

    // Add current entity to delete order
    state.order.add(currentStep);

    // If this is not a relational entity, we're done
    if (!entity.isRelational) {
      return;
    }

    final relations = (entity as dynamic).relations as Map<String, Relation>;
    for (final entry in relations.entries) {
      await _planRelation(entity, entry, userId, state);
    }
  }

  /// Adds the plan contribution of one relationship of [entity] to [state].
  Future<void> _planRelation(
    DatumEntityInterface entity,
    MapEntry<String, Relation> entry,
    String userId,
    _PlanState state,
  ) async {
    final MapEntry(key: relationName, value: relation) = entry;

    if (relation.shouldRestrictDelete) {
      final relatedEntities = await getRelatedEntities(entity, relation, userId);
      if (relatedEntities.isNotEmpty) {
        state.restricted[relationName] = relatedEntities;
      }
      return;
    }

    if (relation.shouldCascadeDelete) {
      for (final relatedEntity in await getRelatedEntities(entity, relation, userId)) {
        final relatedStep = CascadeDeleteStep(
          entity: relatedEntity,
          manager: relation.getRelatedManager(),
          relationName: relationName,
        );
        await _buildDeletePlanRecursive(relatedStep, userId, state);
      }
      return;
    }

    // For none behavior, do nothing during planning. For BelongsTo setNull the
    // foreign key is on the entity being deleted, so no action is needed.
    if (!relation.shouldSetNullOnDelete) return;
    final foreignKeyName = switch (relation) {
      HasMany(:final foreignKey) || HasOne(:final foreignKey) => foreignKey,
      BelongsTo() || ManyToMany() => null,
    };
    if (foreignKeyName == null) return;

    for (final relatedEntity in await getRelatedEntities(entity, relation, userId)) {
      state.order.add(CascadeDeleteStep(
        entity: relatedEntity,
        manager: relation.getRelatedManager(),
        relationName: relationName,
        type: CascadeStepType.update,
        updateData: {foreignKeyName: null},
      ));
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
              // Scope to the requesting user: another user's rows can share
              // foreign-key VALUES (their own graph reuses the same ids), and
              // the executor deletes with this userId anyway — unscoped
              // planning produced spurious failures and cross-user restricts.
              userId: userId,
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
          userId: userId,
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
          userId: userId,
        );
      case BelongsTo():
        final foreignKeyValue = parent.toDatumMap()[relation.foreignKey];
        if (foreignKeyValue == null) return [];

        final manager = relation.getRelatedManager();
        final entity = await manager.read(foreignKeyValue, userId: userId);
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
    final startTime = DateTime.now();

    Future<bool> performDelete(CascadeDeleteStep step) async => await step.manager.performDeleteWithoutEvents(
          id: step.entity.id,
          userId: userId,
          source: source,
          forceRemoteSync: forceRemoteSync,
        );

    // Execute deletes in the planned order
    for (final step in plan.steps) {
      final abortReason = _abortReason(options, startTime);
      if (abortReason != null) {
        analyticsBuilder.recordError();
        errors.add(abortReason);
        break;
      }

      final failure = await _runProgressStep(step, userId, performDelete, analyticsBuilder);
      if (failure == null && step.type == CascadeStepType.delete) {
        deletedEntities.putIfAbsent(step.entity.runtimeType, () => []).add(step.entity);
      }

      if (failure != null) {
        analyticsBuilder.recordError();
        errors.add(failure);
        // Stop on first failure if partial deletes not allowed
        if (!options.allowPartialDeletes) break;
      }

      completed++;
      options.onProgress?.call(_progressFor(step, completed, plan.steps.length));
    }

    return CascadeDeleteResult<T>(
      success: errors.isEmpty,
      entity: plan.mainEntity,
      deletedEntities: deletedEntities,
      restrictedRelations: plan.restrictedRelations,
      errors: errors,
    );
  }

  /// Runs one cascade step, returning the failure message (null on success).
  Future<String?> _runProgressStep(
    CascadeDeleteStep step,
    String userId,
    Future<bool> Function(CascadeDeleteStep step) performDelete,
    CascadeAnalyticsBuilder analyticsBuilder,
  ) async {
    try {
      analyticsBuilder.recordQueryExecuted();
      final updateData = step.updateData;
      final success = switch (step.type) {
        CascadeStepType.delete => await performDelete(step),
        CascadeStepType.update => updateData == null || await _applySetNull(step, updateData, userId, analyticsBuilder),
      };
      if (!success) {
        return 'Failed to ${step.type == CascadeStepType.delete ? 'delete' : 'update'} ${step.entity.runtimeType}:${step.entity.id}';
      }
      if (step.type == CascadeStepType.delete) {
        analyticsBuilder.recordEntityDeleted(step.entity.runtimeType);
      }
      return null;
    } catch (e) {
      return 'Error deleting ${step.entity.runtimeType}:${step.entity.id}: $e';
    }
  }

  /// Patches [updateData] (a nulled foreign key) onto the step's entity.
  /// Cascade steps run without events, so this uses the adapter patch
  /// directly. Returns false (after logging) when the patch fails.
  Future<bool> _applySetNull(
    CascadeDeleteStep step,
    Map<String, dynamic> updateData,
    String userId,
    CascadeAnalyticsBuilder analyticsBuilder,
  ) async {
    try {
      await step.manager.localAdapter.patch(id: step.entity.id, delta: updateData, userId: userId);
      step.manager.invalidateMetadataHash(userId);
      analyticsBuilder.recordSetNullOperation();
      return true;
    } catch (e) {
      _logger.error('Failed to set null for ${step.entity.id}: $e');
      return false;
    }
  }
}

/// Accumulators threaded through the recursive delete-plan build.
typedef _PlanState = ({
  List<CascadeDeleteStep> order,
  Map<String, List<DatumEntityInterface>> restricted,
  Set<String> visited,
});

/// Why a progress-tracked cascade must stop before the next step, if at all.
String? _abortReason(CascadeOptions options, DateTime startTime) {
  if (options.cancellationToken?.isCancelled ?? false) return 'Operation cancelled';
  if (DateTime.now().difference(startTime) > options.timeout) return 'Operation timed out';
  return null;
}

CascadeProgress _progressFor(CascadeDeleteStep step, int completed, int total) {
  final typeName = step.entity.runtimeType.toString();
  return CascadeProgress(
    completed: completed,
    total: total,
    currentEntityType: typeName,
    currentEntityId: step.entity.id,
    message: step.type == CascadeStepType.delete ? 'Deleting $typeName' : 'Updating $typeName',
  );
}
