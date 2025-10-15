import 'dart:async';

import 'package:datum/source/core/health/datum_health.dart';
import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/engine/conflict_detector.dart';
import 'package:datum/source/core/engine/isolate_helper.dart';
import 'package:datum/source/core/engine/queue_manager.dart';
import 'package:datum/source/core/events/conflict_detected_event.dart';
import 'package:datum/source/core/events/user_switched_event.dart';
import 'package:datum/source/core/events/conflict_resolved_event.dart';
import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/models/datum_exception.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/models/datum_sync_options.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:datum/source/core/models/datum_sync_scope.dart';
import 'package:datum/source/core/models/datum_sync_status_snapshot.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/utils/connectivity_checker.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:datum/source/core/engine/datum_observer.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:rxdart/rxdart.dart';

/// The core engine that orchestrates the synchronization process.
class DatumSyncEngine<T extends DatumEntity> {
  final LocalAdapter<T> localAdapter;
  final RemoteAdapter<T> remoteAdapter;
  final DatumConflictResolver<T> conflictResolver;
  final QueueManager<T> queueManager;
  final DatumConflictDetector<T> conflictDetector;
  final DatumLogger logger;
  final DatumConfig config;
  final ConnectivityChecker connectivityChecker;
  final StreamController<DatumSyncEvent<T>> eventController;
  final BehaviorSubject<DatumSyncStatusSnapshot> statusSubject;
  final BehaviorSubject<DatumSyncMetadata> metadataSubject;
  final IsolateHelper isolateHelper;
  final List<DatumObserver<T>> localObservers;
  final List<GlobalDatumObserver> globalObservers;

  String? _lastActiveUserId;

  String? get lastActiveUserId => _lastActiveUserId;

  String get entityName => T.toString();

  DatumSyncEngine({
    required this.localAdapter,
    required this.remoteAdapter,
    required this.conflictResolver,
    required this.queueManager,
    required this.conflictDetector,
    required this.logger,
    required this.config,
    required this.connectivityChecker,
    required this.eventController,
    required this.statusSubject,
    required this.metadataSubject,
    required this.isolateHelper,
    this.localObservers = const [],
    this.globalObservers = const [],
  });

  /// Checks if the active user has changed and emits an event if so.
  Future<void> checkForUserSwitch(String newUserId) async {
    if (_lastActiveUserId != null && _lastActiveUserId != newUserId) {
      logger.info('User switched from $_lastActiveUserId to $newUserId.');
      final oldUserOps = await queueManager.getPending(_lastActiveUserId!);
      final hadUnsyncedData = oldUserOps.isNotEmpty;

      if (!eventController.isClosed) {
        eventController.add(
          UserSwitchedEvent<T>(
            previousUserId: _lastActiveUserId!,
            newUserId: newUserId,
            hadUnsyncedData: hadUnsyncedData,
          ),
        );
      }
    }
    _lastActiveUserId = newUserId;
  }

  Future<(DatumSyncResult<T>, List<DatumSyncEvent<T>>)> synchronize(
    String userId, {
    bool force = false,
    DatumSyncOptions<T>? options,
    DatumSyncScope? scope,
  }) async {
    final generatedEvents = <DatumSyncEvent<T>>[];
    final snapshot = statusSubject.value;
    if (!await connectivityChecker.isConnected && !force) {
      logger.warn('Sync skipped for user $userId: No internet connection.');
      return (
        // No health change, just skipped.
        DatumSyncResult<T>.skipped(userId, snapshot.pendingOperations),
        <DatumSyncEvent<T>>[],
      );
    }

    if (snapshot.status == DatumSyncStatus.syncing) {
      logger.info('Sync already in progress for user $userId. Skipping.');
      return (
        DatumSyncResult<T>.skipped(userId, snapshot.pendingOperations),
        <DatumSyncEvent<T>>[],
      );
    }

    await checkForUserSwitch(userId);

    final stopwatch = Stopwatch()..start();

    // Reset the snapshot for the new sync cycle, preserving only the user ID.
    statusSubject.add(
      DatumSyncStatusSnapshot.initial(userId).copyWith(
        status: DatumSyncStatus.syncing,
        health: const DatumHealth(status: DatumSyncHealth.syncing),
        // Carry over pending operations count for the start event.
        pendingOperations: (await queueManager.getPending(userId)).length,
      ),
    );
    final startEvent = DatumSyncStartedEvent<T>(
      userId: userId,
      pendingOperations: snapshot.pendingOperations,
    );
    generatedEvents.add(startEvent);
    _notifyObservers(startEvent);

    try {
      final direction = options?.direction ?? config.defaultSyncDirection;

      switch (direction) {
        case SyncDirection.pushThenPull:
          await _pushChanges(userId, generatedEvents);
          await _pullChanges(userId, options, scope, generatedEvents);
        case SyncDirection.pullThenPush:
          await _pullChanges(userId, options, scope, generatedEvents);
          await _pushChanges(userId, generatedEvents);
        case SyncDirection.pushOnly:
          await _pushChanges(userId, generatedEvents);
        case SyncDirection.pullOnly:
          await _pullChanges(userId, options, scope, generatedEvents);
      }

      // After operations, check if the sync was cancelled by a dispose call.
      // The status subject would be closed in this case.
      if (statusSubject.isClosed) {
        return (
          DatumSyncResult<T>.cancelled(userId, statusSubject.value.syncedCount),
          generatedEvents,
        );
      }

      final finalPending = await queueManager.getPending(userId);
      final result = DatumSyncResult(
        userId: userId,
        duration: stopwatch.elapsed,
        syncedCount: statusSubject.value.syncedCount,
        failedCount: statusSubject.value.failedOperations,
        conflictsResolved: statusSubject.value.conflictsResolved,
        pendingOperations: finalPending,
      );

      // Check if controllers are closed before adding events, as the manager
      // might have been disposed during the sync operation.
      if (!statusSubject.isClosed) {
        statusSubject.add(
          statusSubject.value.copyWith(
            status: DatumSyncStatus.idle,
            health: const DatumHealth(status: DatumSyncHealth.healthy),
          ),
        );
      }
      if (!eventController.isClosed) {
        final completedEvent = DatumSyncCompletedEvent<T>(
          userId: userId,
          result: result,
        );
        generatedEvents.add(completedEvent);
        _notifyObservers(completedEvent);
      }
      return (result, generatedEvents);
    } catch (e, stack) {
      logger.error('Synchronization failed for user $userId: $e', stack);
      if (!statusSubject.isClosed && !eventController.isClosed) {
        statusSubject.add(
          statusSubject.value.copyWith(
            status: DatumSyncStatus.failed,
            health: const DatumHealth(status: DatumSyncHealth.error),
            errors: [e],
          ),
        );
        final errorEvent = DatumSyncErrorEvent<T>(
          userId: userId,
          error: e,
          stackTrace: stack,
        );
        generatedEvents.add(errorEvent);
        _notifyObservers(errorEvent);
      }
      // Instead of a simple `rethrow`, we wrap the error in a custom
      // exception. This allows us to transport the `generatedEvents`
      // (which now includes the crucial error event) back up to the
      // DatumManager, which can process them before the user-facing Future
      // completes with an error.
      throw SyncExceptionWithEvents(e, stack, generatedEvents);
    }
  }

  Future<void> _pushChanges(
    String userId,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    final operationsToProcess = await queueManager.getPending(userId);
    if (operationsToProcess.isEmpty) {
      logger.info('No pending changes to push for user $userId.');
      return;
    }

    logger.info(
      'Pushing ${operationsToProcess.length} changes for user $userId...',
    );

    // The main `synchronize` method has a try-catch that will handle any
    // exceptions thrown by the execution strategy.
    await config.syncExecutionStrategy.execute(
      operationsToProcess,
      (op) => _processPendingOperation(op, generatedEvents: generatedEvents),
      () => statusSubject.value.status != DatumSyncStatus.syncing,
      (completed, total) {
        if (!statusSubject.isClosed && !eventController.isClosed) {
          final progress = total > 0 ? completed / total : 1.0;
          statusSubject.add(statusSubject.value.copyWith(progress: progress));
          final progressEvent = DatumSyncProgressEvent<T>(
            userId: userId,
            completed: completed,
            total: total,
          );
          generatedEvents.add(progressEvent);
          _notifyObservers(progressEvent);
        }
      },
    );
  }

  Future<void> _processPendingOperation(
    DatumSyncOperation<T> operation, {
    required List<DatumSyncEvent<T>> generatedEvents,
  }) async {
    _notifyPreOperationObservers(operation);
    logger.debug(
      'Processing operation: ${operation.type.name} for entity ${operation.entityId}',
    );
    try {
      switch (operation.type) {
        case DatumOperationType.create:
          if (operation.data == null) {
            throw ArgumentError('Create op needs data');
          }
          logger.debug('Creating entity ${operation.entityId} on remote.');
          await remoteAdapter.create(operation.data!);
        case DatumOperationType.update:
          if (operation.data == null) {
            throw ArgumentError('Update op needs data');
          }
          if (operation.delta != null && operation.delta!.isNotEmpty) {
            logger.debug(
              'Patching entity ${operation.entityId} with delta: ${operation.delta}',
            );
            await remoteAdapter.patch(
              id: operation.entityId,
              delta: operation.delta!,
              userId: operation.userId,
            );
          } else {
            logger.debug(
              'Updating full entity ${operation.entityId} on remote.',
            );
            await remoteAdapter.update(operation.data!);
          }
        case DatumOperationType.delete:
          logger.debug('Deleting entity ${operation.entityId} on remote.');
          await remoteAdapter.delete(
            operation.entityId,
            userId: operation.userId,
          );
      }

      await queueManager.dequeue(operation.id);
      if (!statusSubject.isClosed) {
        statusSubject.add(
          statusSubject.value.copyWith(
            syncedCount: statusSubject.value.syncedCount + 1,
          ),
        );
        _notifyPostOperationObservers(operation, success: true);
      }
    } on EntityNotFoundException catch (e, stackTrace) {
      // If a patch fails because the entity doesn't exist on the remote,
      // convert the operation to a full 'create' and re-process it immediately.
      if (operation.type == DatumOperationType.update &&
          operation.data != null) {
        logger.warn(
          'Patch for ${operation.entityId} failed because it was not found on remote. Retrying as a create operation. Error: $e',
        );
        final createOperation = operation.copyWith(
          type: DatumOperationType.create,
        );
        // Re-call the same method with the converted operation.
        return _processPendingOperation(
          createOperation,
          generatedEvents: generatedEvents,
        );
      }
      _notifyPostOperationObservers(operation, success: false);
      logger.error('Operation ${operation.id} failed: $e', stackTrace);
      // If the operation was not an update that could be retried as a create,
      // we must rethrow the exception to let the sync process know that this
      // operation has failed.
      rethrow;
    } on Object catch (e, stackTrace) {
      final isRetryable =
          e is NetworkException &&
          e.isRetryable &&
          operation.retryCount < config.maxRetries;

      if (isRetryable) {
        final updatedOp = operation.copyWith(
          retryCount: operation.retryCount + 1,
        );
        await queueManager.update(updatedOp);
        logger.warn(
          'Operation ${operation.id} failed. Will retry on next sync.',
        );
        return;
      }

      // For non-retryable errors, mark the operation as failed and remove it
      // from the queue to prevent it from blocking subsequent syncs.
      // A more advanced implementation might move it to a separate "dead-letter queue".
      if (!statusSubject.isClosed) {
        // Generate the error event here, before re-throwing, to ensure it's
        // captured by listeners even if the sync process terminates early.
        if (!eventController.isClosed) {
          generatedEvents.add(
            DatumSyncErrorEvent<T>(
              userId: operation.userId,
              error: e,
              stackTrace: stackTrace,
            ),
          );
        }
        _notifyPostOperationObservers(operation, success: false);
        statusSubject.add(
          statusSubject.value.copyWith(
            failedOperations: statusSubject.value.failedOperations + 1,
            errors: [...statusSubject.value.errors, e],
          ),
        );
      }
      logger.error(
        'Operation ${operation.id} failed permanently: $e',
        stackTrace,
      );
      // Dequeue the operation to prevent it from blocking future syncs.
      // A more advanced implementation could move it to a dead-letter queue.
      await queueManager.dequeue(operation.id);

      // Re-throw the exception. This is crucial for allowing execution
      // strategies (like `ParallelStrategy` with `failFast: true`) to
      // stop processing and immediately propagate the failure up to the
      // main `synchronize` method's `try...catch` block.
      rethrow;
    }
  }

  Future<void> _pullChanges(
    String userId,
    DatumSyncOptions<T>? options,
    DatumSyncScope? scope,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    logger.info('Pulling remote changes for user $userId...');

    final remoteItems = await remoteAdapter.readAll(
      userId: userId,
      scope: scope,
    );
    final localItemsMap = await localAdapter.readByIds(
      remoteItems.map((e) => e.id).toList(),
      userId: userId,
    );

    for (final remoteItem in remoteItems) {
      if (statusSubject.value.status != DatumSyncStatus.syncing) break;

      final localItem = localItemsMap[remoteItem.id];
      final context = conflictDetector.detect(
        localItem: localItem,
        remoteItem: remoteItem,
        userId: userId,
      );

      if (context == null) {
        if (localItem == null) {
          await localAdapter.create(remoteItem);
        } else {
          await localAdapter.update(remoteItem);
        }
        continue;
      }

      final conflictEvent = ConflictDetectedEvent<T>(
        userId: userId,
        context: context,
        localData: localItem,
        remoteData: remoteItem,
      );
      generatedEvents.add(conflictEvent);
      _notifyObservers(conflictEvent);

      final resolver = options?.conflictResolver ?? conflictResolver;
      final resolution = await resolver.resolve(
        local: localItem,
        remote: remoteItem,
        context: context,
      );

      switch (resolution.strategy) {
        case DatumResolutionStrategy.takeLocal:
          break;
        case DatumResolutionStrategy.takeRemote:
          await localAdapter.update(remoteItem);
        case DatumResolutionStrategy.merge:
          if (resolution.resolvedData == null) {
            throw StateError('Merge resolution must provide a merged item.');
          }
          await localAdapter.update(resolution.resolvedData!);
        case DatumResolutionStrategy.abort:
          logger.warn('Conflict resolution aborted for ${context.entityId}');
        case DatumResolutionStrategy.askUser:
          logger.warn(
            'Conflict resolution requires user input for ${context.entityId}',
          );
      }
      final resolvedEvent = ConflictResolvedEvent<T>(
        userId: userId,
        entityId: context.entityId,
        resolution: resolution,
      );
      generatedEvents.add(resolvedEvent);
      _notifyObservers(resolvedEvent);
      statusSubject.add(
        statusSubject.value.copyWith(
          conflictsResolved: statusSubject.value.conflictsResolved + 1,
        ),
      );
    }

    await _updateMetadata(userId);
  }

  void _notifyPreOperationObservers(DatumSyncOperation<T> operation) {
    if (operation.data == null) return;
    final item = operation.data!;
    switch (operation.type) {
      case DatumOperationType.create:
        for (final observer in localObservers) {
          observer.onCreateStart(item);
        }
        for (final observer in globalObservers) {
          observer.onCreateStart(item);
        }
      case DatumOperationType.update:
        for (final observer in localObservers) {
          observer.onUpdateStart(item);
        }
        for (final observer in globalObservers) {
          observer.onUpdateStart(item);
        }
      case DatumOperationType.delete:
        for (final observer in localObservers) {
          observer.onDeleteStart(item.id);
        }
        for (final observer in globalObservers) {
          observer.onDeleteStart(item.id);
        }
    }
  }

  void _notifyPostOperationObservers(
    DatumSyncOperation<T> operation, {
    required bool success,
  }) {
    if (operation.data == null && operation.type != DatumOperationType.delete) {
      return;
    }
    final item = operation.data;
    switch (operation.type) {
      case DatumOperationType.create:
        if (item != null) {
          for (final observer in localObservers) {
            observer.onCreateEnd(item);
          }
          for (final observer in globalObservers) {
            observer.onCreateEnd(item);
          }
        }
      case DatumOperationType.update:
        if (item != null) {
          for (final observer in localObservers) {
            observer.onUpdateEnd(item);
          }
          for (final observer in globalObservers) {
            observer.onUpdateEnd(item);
          }
        }
      case DatumOperationType.delete:
        for (final observer in localObservers) {
          observer.onDeleteEnd(operation.entityId, success: success);
        }
        for (final observer in globalObservers) {
          observer.onDeleteEnd(operation.entityId, success: success);
        }
    }
  }

  void _notifyObservers(DatumSyncEvent<T> event) {
    switch (event) {
      case DatumSyncStartedEvent():
        for (final observer in localObservers) {
          observer.onSyncStart();
        }
        for (final observer in globalObservers) {
          observer.onSyncStart();
        }
      case DatumSyncCompletedEvent():
        for (final observer in localObservers) {
          observer.onSyncEnd(event.result);
        }
        for (final observer in globalObservers) {
          observer.onSyncEnd(event.result);
        }
      case ConflictDetectedEvent<T>():
        final conflictEvent = event;
        final local = conflictEvent.localData;
        final remote = conflictEvent.remoteData;
        if (local != null && remote != null) {
          for (final observer in localObservers) {
            observer.onConflictDetected(local, remote, conflictEvent.context);
          }
          for (final observer in globalObservers) {
            observer.onConflictDetected(local, remote, conflictEvent.context);
          }
        }
      case ConflictResolvedEvent<T>():
        final resolvedEvent = event;
        for (final observer in localObservers) {
          observer.onConflictResolved(resolvedEvent.resolution);
        }
        for (final observer in globalObservers) {
          // We need to cast the resolution to the generic DatumEntity type
          // that the GlobalDatumObserver expects.
          final genericResolution = resolvedEvent.resolution
              .copyWithNewType<DatumEntity>();
          observer.onConflictResolved(genericResolution);
        }
      case DatumSyncErrorEvent<T>():
        // Although there's no specific `onSyncError` in the observer,
        // we can treat it as a form of `onSyncEnd` to signal completion.
        final errorResult = DatumSyncResult<T>.fromError(
          event.userId,
          event.error,
        );
        for (final observer in localObservers) {
          observer.onSyncEnd(errorResult);
        }
      case _:
        // Other events like progress, conflict, etc.
        break;
    }
  }

  Future<void> _updateMetadata(String userId) async {
    try {
      final items = await localAdapter.readAll(userId: userId);
      final newMetadata = DatumSyncMetadata(
        userId: userId,
        lastSyncTime: DateTime.now(),
        dataHash: 'testhash',
        entityCounts: {
          entityName: DatumEntitySyncDetails(
            count: items.length,
            hash: 'testhash',
          ),
        },
      );
      await localAdapter.updateSyncMetadata(newMetadata, userId);
      await remoteAdapter.updateSyncMetadata(newMetadata, userId);
      if (!metadataSubject.isClosed) {
        metadataSubject.add(newMetadata);
      }
    } on Object catch (e, stack) {
      logger.error(
        'Failed to update sync metadata for user $userId: $e',
        stack,
      );
      // Re-throw to allow the main sync loop's error handler to catch it.
      rethrow;
    }
  }
}

/// A special exception to carry events back up the call stack on failure.
class SyncExceptionWithEvents<T extends DatumEntity> implements Exception {
  final Object originalError;
  final StackTrace originalStackTrace;
  final List<DatumSyncEvent<T>> events;

  SyncExceptionWithEvents(
    this.originalError,
    this.originalStackTrace,
    this.events,
  );
}
