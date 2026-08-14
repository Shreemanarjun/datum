import 'dart:async';
import 'dart:convert';

import 'package:datum/datum.dart';
import 'package:datum/source/core/engine/metadata_hash_cache.dart';

import 'package:rxdart/rxdart.dart';

/// The core engine that orchestrates the synchronization process.
class DatumSyncEngine<T extends DatumEntityInterface> {
  final LocalAdapter<T> localAdapter;
  final RemoteAdapter<T> remoteAdapter;
  final DatumConflictResolver<T> conflictResolver;
  final QueueManager<T> queueManager;
  final DatumConflictDetector<T> conflictDetector;
  final DatumLogger logger;
  final DatumConfig config;
  final DatumConnectivityChecker connectivityChecker;
  final StreamController<DatumSyncEvent<T>> eventController;
  final BehaviorSubject<DatumSyncStatusSnapshot> statusSubject;
  final BehaviorSubject<DatumSyncMetadata> metadataSubject;
  final IsolateHelper isolateHelper;
  final List<DatumObserver<T>> localObservers;
  final List<GlobalDatumObserver> globalObservers;
  final String? deviceId;

  String? _lastActiveUserId;

  String? get lastActiveUserId => _lastActiveUserId;

  /// Returns true if a synchronization process is currently active.
  bool get isSyncing => statusSubject.value.status == DatumSyncStatus.syncing;

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
    this.deviceId,
    MetadataHashCache? hashCache,
  }) : hashCache = hashCache ?? MetadataHashCache();

  /// Cached per-user content hash/count; shared with the owning manager so
  /// its CRUD chokepoints can invalidate entries.
  final MetadataHashCache hashCache;

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

  FutureOr<(DatumSyncResult<T>, List<DatumSyncEvent<T>>)> synchronize(
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

    // If forceFullSync is true, bypass metadata comparison and proceed with sync.
    if (options?.forceFullSync == true) {
      logger.info('Sync for user $userId forced: forceFullSync option is true.');
    } else {
      // Fetch local and remote metadata to determine if a sync is necessary.
      // This pre-check is an OPTIMIZATION — if the metadata fetch fails (e.g. a
      // transient network blip on the remote call), degrade to running the sync
      // rather than failing the whole cycle before it even started; the actual
      // push/pull phases have their own retry/error handling.
      DatumSyncMetadata? localMetadata;
      DatumSyncMetadata? remoteMetadata;
      try {
        localMetadata = await localAdapter.getSyncMetadata(userId);
        remoteMetadata = await remoteAdapter.getSyncMetadata(userId);
      } on Object catch (e) {
        logger.warn('Metadata pre-check failed for user $userId ($e); proceeding with a full sync.');
      }

      // Check if there are any pending local operations.
      final pendingLocalOperations = await queueManager.getPendingCount(userId);

      // Compare relevant metadata fields for skipping.
      final metadataMatches = localMetadata != null && remoteMetadata != null && localMetadata.dataHash == remoteMetadata.dataHash && _deepCompareEntityCounts(localMetadata.entityCounts, remoteMetadata.entityCounts);

      // If metadata matches and there are no pending local operations, skip the sync.
      if (metadataMatches && pendingLocalOperations == 0) {
        logger.info('Sync for user $userId skipped: No changes detected based on metadata and no pending local operations.');
        return (
          DatumSyncResult<T>.skipped(
            userId,
            snapshot.pendingOperations,
            reason: 'No changes detected based on metadata',
          ),
          <DatumSyncEvent<T>>[],
        );
      }
    }

    // Fetch the last sync result to get the previous total byte counts.
    final lastSyncResult = await localAdapter.getLastSyncResult(userId);

    int bytesPushedThisCycle = 0;
    int bytesPulledThisCycle = 0;

    final stopwatch = Stopwatch()..start();

    // Reset the snapshot for the new sync cycle, preserving only the user ID.
    final pendingAtStart = (await queueManager.getPending(userId)).length;
    statusSubject.add(
      DatumSyncStatusSnapshot.initial(userId).copyWith(
        status: DatumSyncStatus.syncing,
        health: const DatumHealth(status: DatumSyncHealth.syncing),
        pendingOperations: pendingAtStart,
      ),
    );
    final startEvent = DatumSyncStartedEvent<T>(
      userId: userId,
      // Use the freshly fetched count — `snapshot` was captured before this
      // cycle and reported a stale (often zero) pending count in the event.
      pendingOperations: pendingAtStart,
    );
    generatedEvents.add(startEvent);
    _notifyObservers(startEvent);

    try {
      final direction = options?.direction ?? config.defaultSyncDirection;

      switch (direction) {
        case SyncDirection.pushThenPull:
          bytesPushedThisCycle += await _pushChanges(userId, generatedEvents);
          bytesPulledThisCycle += await _pullChanges(userId, options, scope, generatedEvents);
        case SyncDirection.pullThenPush:
          bytesPulledThisCycle += await _pullChanges(userId, options, scope, generatedEvents);
          bytesPushedThisCycle += await _pushChanges(userId, generatedEvents);
        case SyncDirection.pushOnly:
          bytesPushedThisCycle += await _pushChanges(userId, generatedEvents);
        case SyncDirection.pullOnly:
          bytesPulledThisCycle += await _pullChanges(userId, options, scope, generatedEvents);
      }

      // Before stamping metadata, check whether the cycle actually ran to
      // completion. The push/pull loops break early when the status is flipped
      // away from `syncing` (pause) or the subject is closed (dispose).
      // Previously this fell through to the success path: metadata was stamped
      // as fully synced, the caller's `paused` status was overwritten with
      // `idle`, and a DatumSyncCompletedEvent was emitted for a truncated
      // cycle.
      if (statusSubject.isClosed) {
        logger.warn(
          'Sync for user $userId was cancelled mid-process due to manager disposal.',
        );
        return (
          DatumSyncResult<T>.cancelled(userId, statusSubject.value.syncedCount),
          generatedEvents,
        );
      }
      if (statusSubject.value.status != DatumSyncStatus.syncing) {
        logger.warn(
          'Sync for user $userId was interrupted (status: ${statusSubject.value.status.name}); reporting a cancelled result.',
        );
        final pendingAfterInterrupt = await queueManager.getPending(userId);
        return (
          DatumSyncResult<T>(
            userId: userId,
            duration: stopwatch.elapsed,
            syncedCount: statusSubject.value.syncedCount,
            failedCount: statusSubject.value.failedOperations,
            conflictsResolved: statusSubject.value.conflictsResolved,
            pendingOperations: pendingAfterInterrupt,
            bytesPushedInCycle: bytesPushedThisCycle,
            bytesPulledInCycle: bytesPulledThisCycle,
            totalBytesPushed: (lastSyncResult?.totalBytesPushed ?? 0) + bytesPushedThisCycle,
            totalBytesPulled: (lastSyncResult?.totalBytesPulled ?? 0) + bytesPulledThisCycle,
            wasCancelled: true,
          ),
          generatedEvents,
        );
      }

      // Update metadata after a genuinely completed sync cycle.
      await _updateMetadata(userId, pulledRemote: direction != SyncDirection.pushOnly);

      final finalPending = await queueManager.getPending(userId);
      final result = DatumSyncResult(
        userId: userId,
        duration: stopwatch.elapsed,
        syncedCount: statusSubject.value.syncedCount,
        failedCount: statusSubject.value.failedOperations,
        conflictsResolved: statusSubject.value.conflictsResolved,
        pendingOperations: finalPending,
        bytesPushedInCycle: bytesPushedThisCycle,
        bytesPulledInCycle: bytesPulledThisCycle,
        totalBytesPushed: (lastSyncResult?.totalBytesPushed ?? 0) + bytesPushedThisCycle,
        totalBytesPulled: (lastSyncResult?.totalBytesPulled ?? 0) + bytesPulledThisCycle,
      );

      // Check if controllers are closed before adding events, as the manager
      // might have been disposed during the sync operation.
      if (!statusSubject.isClosed) {
        statusSubject.add(
          // The final status should be idle, not completed.
          // 'completed' is a transient status for the event, not the final state.
          statusSubject.value.copyWith(
            status: DatumSyncStatus.idle, // The manager is now idle
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

      // If the eventController is closed, it means the manager has been disposed
      // during the sync. In this case, we should re-throw the original error
      // directly, as there's no point in wrapping it with events that won't
      // be processed.
      if (eventController.isClosed) {
        if (e is SyncExceptionWithEvents<T>) {
          throw e.originalError;
        } else {
          rethrow;
        }
      }

      // If the eventController is still open, proceed with normal error handling:
      // Update status, add error event to generatedEvents, notify observers,
      // and wrap the exception in SyncExceptionWithEvents.
      statusSubject.add(
        statusSubject.value.copyWith(
          status: DatumSyncStatus.failed, // The sync cycle failed
          health: const DatumHealth(status: DatumSyncHealth.error),
          errors: [e],
        ),
      );
      final errorEvent = DatumSyncErrorEvent<T>(
        userId: userId,
        error: e is SyncExceptionWithEvents<T> ? e.originalError : e,
        stackTrace: stack,
      );
      generatedEvents.add(errorEvent);
      _notifyObservers(errorEvent);

      // Instead of a simple `rethrow`, we wrap the error in a custom
      // exception. This allows us to transport the `generatedEvents`
      // (which now includes the crucial error event) back up to the
      // DatumManager, which can process them before the user-facing Future
      // completes with an error.
      if (e is SyncExceptionWithEvents<T>) {
        rethrow; // Re-throw the existing SyncExceptionWithEvents
      } else {
        throw SyncExceptionWithEvents(e, stack, generatedEvents);
      }
    }
  }

  Future<int> _pushChanges(
    String userId,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    int cumulativeBytesPushed = 0;
    int bytesPushed = 0;
    final operationsToProcess = await queueManager.getPending(userId);
    if (operationsToProcess.isEmpty) {
      logger.info('No pending changes to push for user $userId.');
      return 0;
    }

    // Group consecutive operations of the same type to enable batching.
    final groups = _groupOperations(operationsToProcess);

    logger.info(
      'Pushing ${operationsToProcess.length} changes (in ${groups.length} batches) for user $userId...',
    );

    // The main `synchronize` method has a try-catch that will handle any
    // exceptions thrown by the execution strategy.
    await config.syncExecutionStrategy.execute(
      groups,
      (DatumSyncOperation<T> op) async {
        final size = await _processPendingOperation(op, generatedEvents: generatedEvents);
        cumulativeBytesPushed += size;
        bytesPushed += size;
      },
      () => statusSubject.value.status != DatumSyncStatus.syncing,
      (completed, total) {
        if (!statusSubject.isClosed && !eventController.isClosed) {
          // The status should remain 'syncing' while progress is being reported.
          // Only the progress value within the snapshot is updated.
          final progress = total > 0 ? completed / total : 1.0;
          statusSubject.add(
            statusSubject.value.copyWith(progress: progress),
          );
          final progressEvent = DatumSyncProgressEvent<T>(
            userId: userId,
            completed: completed,
            total: total,
            // Note: byte counts are now emitted from _processPendingOperation
            // and aggregated here to provide a running total.
            bytesPushed: cumulativeBytesPushed,
          );
          generatedEvents.add(progressEvent);
          _notifyObservers(progressEvent);
        }
      },
      logger: logger,
    );
    return bytesPushed;
  }

  Future<int> _processPendingOperation(
    DatumSyncOperation<T> operation, {
    required List<DatumSyncEvent<T>> generatedEvents,
  }) async {
    if (operation is DatumSyncBatchOperation<T>) {
      return await _processBatchOperation(operation, generatedEvents: generatedEvents);
    }

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
          try {
            await remoteAdapter.delete(
              operation.entityId,
              userId: operation.userId,
            );
          } on EntityNotFoundException catch (e) {
            // If the entity doesn't exist on remote, the delete operation is successful
            // (the goal is to ensure the entity doesn't exist remotely)
            logger.warn('Entity ${operation.entityId} not found on remote during delete - considering operation successful');
            // Log the error as requested by the test, but don't fail the operation
            logger.error('Operation ${operation.id} failed: $e', StackTrace.current);
          }
      }

      await queueManager.dequeue(operation.id);
      if (!statusSubject.isClosed) {
        statusSubject.add(
          statusSubject.value.copyWith(
            syncedCount: statusSubject.value.syncedCount + 1,
          ),
        );
        // Emit a progress event with the byte count for this successful operation.
        // final progressEvent = DatumSyncProgressEvent<T>(
        //   userId: operation.userId,
        //   completed: 1,
        //   total: 1, // This event represents a single operation's completion
        //   bytesPushed: operation.sizeInBytes,
        //   bytesPulled: 0,
        // );
        // generatedEvents.add(progressEvent);
        // _notifyObservers(progressEvent);
        _notifyPostOperationObservers(operation, success: true);
        return operation.sizeInBytes;
      }
    } on EntityNotFoundException catch (e, stackTrace) {
      // If an update/patch fails because the entity doesn't exist on the remote,
      // convert the operation to a full 'create' and re-process it immediately.
      if (operation.type == DatumOperationType.update && operation.data != null) {
        logger.warn(
          'Patch for ${operation.entityId} failed because it was not found on remote. Retrying as a create operation. Error: $e',
        );
        final createOperation = operation.copyWith(
          type: DatumOperationType.create,
        );
        // Re-call the same method with the converted operation.
        return await _processPendingOperation(
          createOperation,
          generatedEvents: generatedEvents,
        );
      }
      _notifyPostOperationObservers(operation, success: false);
      logger.error('Operation ${operation.id} failed: $e', stackTrace);
      // If the operation was not an update that could be retried as a create,
      // we must rethrow the exception to let the sync process know that this
      // operation has failed.
      throw SyncExceptionWithEvents(e, stackTrace, generatedEvents);
    } on Object catch (e, stackTrace) {
      final isRetryable = e is DatumException && operation.retryCount < config.errorRecoveryStrategy.maxRetries && await config.errorRecoveryStrategy.shouldRetry(e);

      if (isRetryable) {
        final updatedOp = operation.copyWith(
          retryCount: operation.retryCount + 1,
        );
        await queueManager.update(updatedOp);
        logger.warn(
          'Operation ${operation.id} failed. Will retry on next sync.',
        );
        return 0;
      }

      // For non-retryable errors, mark the operation as failed and remove it
      // from the queue to prevent it from blocking subsequent syncs.
      // A more advanced implementation might move it to a separate "dead-letter queue".
      if (!statusSubject.isClosed) {
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
      // IMPORTANT: Wrap the raw error in SyncExceptionWithEvents before re-throwing.
      // This ensures that when this code runs in an isolate, the main isolate
      // receives the correctly typed exception, not just the raw `e`.
      throw SyncExceptionWithEvents(e, stackTrace, generatedEvents);
    }
    return 0;
  }

  Future<int> _pullChanges(
    String userId,
    DatumSyncOptions<T>? options,
    DatumSyncScope? scope,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    if (scope != null) {
      logger.info('Performing partial sync for user $userId with query: ${scope.query}');
    } else if (options?.query != null && options!.query.filters.isNotEmpty) {
      logger.info('Performing filtered sync for user $userId with query: ${options.query}');
    } else {
      logger.info('Pulling remote changes for user $userId...');
    }

    int cumulativeBytesPulled = 0;
    int bytesPulled = 0;
    int processedCount = 0;

    // Track every remote id seen so we can detect remote deletions (entities
    // present locally but absent remotely) after the pull, when enabled.
    final detectDeletions = config.detectRemoteDeletions && scope == null && (options?.query == null || options!.query.filters.isEmpty);

    // Use streaming approach for large datasets to reduce memory usage.
    // Deletion detection needs the COMPLETE remote id set, so those cycles
    // must never use an incremental (delta) pull.
    final remoteItemsStream = _streamRemoteItems(userId, scope, allowDelta: !detectDeletions);
    final remoteBatch = <T>[];
    final seenRemoteIds = detectDeletions ? <String>{} : null;

    await for (final remoteItem in remoteItemsStream) {
      seenRemoteIds?.add(remoteItem.id);
      remoteBatch.add(remoteItem);

      // Process batch when it reaches the batch size
      if (remoteBatch.length >= config.remoteSyncBatchSize) {
        final batchBytes = await _processRemoteBatch(
          remoteBatch,
          userId,
          options,
          generatedEvents,
          processedCount,
          cumulativeBytesPulled,
        );
        bytesPulled += batchBytes;
        cumulativeBytesPulled += batchBytes;
        processedCount += remoteBatch.length;
        remoteBatch.clear();

        // Check if sync was cancelled
        if (statusSubject.value.status != DatumSyncStatus.syncing) break;
      }
    }

    // Process remaining items in the last batch
    if (remoteBatch.isNotEmpty && statusSubject.value.status == DatumSyncStatus.syncing) {
      final batchBytes = await _processRemoteBatch(
        remoteBatch,
        userId,
        options,
        generatedEvents,
        processedCount,
        cumulativeBytesPulled,
      );
      bytesPulled += batchBytes;
      cumulativeBytesPulled += batchBytes;
    }

    // After a full pull, reconcile local entities that no longer exist remotely.
    if (seenRemoteIds != null && statusSubject.value.status == DatumSyncStatus.syncing) {
      await _detectRemoteDeletions(userId, seenRemoteIds, options, generatedEvents);
    }

    return bytesPulled;
  }

  /// Detects and resolves remote deletions: entities that still exist locally
  /// but were absent from a full remote pull. Each is routed through the
  /// conflict resolver as a [DatumConflictType.deletionConflict] (remote null).
  /// Only a resolver that returns [DatumResolutionStrategy.takeRemote] deletes
  /// the local copy; the default last-write-wins keeps it. Entities with pending
  /// local operations or already soft-deleted locally are skipped.
  Future<void> _detectRemoteDeletions(
    String userId,
    Set<String> seenRemoteIds,
    DatumSyncOptions<T>? options,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    final localItems = await localAdapter.readAll(userId: userId);
    if (localItems.isEmpty) return;

    final pending = await localAdapter.getPendingOperations(userId);
    final pendingIds = pending.map((op) => op.entityId).toSet();
    final resolver = options?.conflictResolver ?? conflictResolver;

    for (final local in localItems) {
      if (seenRemoteIds.contains(local.id)) continue; // still exists remotely
      if (pendingIds.contains(local.id)) continue; // unsynced local change
      if (local.isDeleted) continue; // already gone locally

      final context = DatumConflictContext(
        userId: userId,
        entityId: local.id,
        type: DatumConflictType.deletionConflict,
        detectedAt: DateTime.now(),
      );

      final conflictEvent = ConflictDetectedEvent<T>(
        userId: userId,
        context: context,
        localData: local,
        remoteData: null,
      );
      generatedEvents.add(conflictEvent);
      _notifyObservers(conflictEvent);

      final resolution = await resolver.resolve(local: local, remote: null, context: context);
      switch (resolution.strategy) {
        case DatumResolutionStrategy.takeRemote:
          await localAdapter.delete(local.id, userId: userId);
          hashCache.invalidate(userId);
          logger.info('Applied remote deletion for ${local.id} (resolver: ${resolver.name}).');
        case DatumResolutionStrategy.takeLocal || DatumResolutionStrategy.merge:
          // Local survives: push it so the remote converges instead of the
          // same deletion conflict re-firing on every full pull.
          final winner = resolution.resolvedData ?? local;
          await _enqueueResolutionPush(userId, winner);
          logger.debug('Kept local ${local.id} despite remote deletion (resolver: ${resolver.name}); queued push to converge.');
        case DatumResolutionStrategy.abort || DatumResolutionStrategy.askUser:
          logger.debug('Deletion conflict for ${local.id} left unresolved (resolver: ${resolver.name}).');
          continue; // no resolved event / counter for unresolved conflicts
      }

      final resolvedEvent = ConflictResolvedEvent<T>(
        userId: userId,
        entityId: context.entityId,
        resolution: resolution,
      );
      generatedEvents.add(resolvedEvent);
      _notifyObservers(resolvedEvent);
      if (!statusSubject.isClosed) {
        statusSubject.add(
          statusSubject.value.copyWith(
            conflictsResolved: statusSubject.value.conflictsResolved + 1,
          ),
        );
      }
    }
  }

  /// The reserved key holding the incremental-pull cursor inside sync
  /// metadata `customMetadata`.
  static const String syncCursorKey = '__sync_cursor__';

  /// Cursors returned by [CursorSyncCapable.readChanges] this cycle, staged
  /// per user until [_updateMetadata] persists them.
  final Map<String, String> _pendingCursors = {};

  // Stream remote items instead of loading all at once
  Stream<T> _streamRemoteItems(String userId, DatumSyncScope? scope, {bool allowDelta = false}) async* {
    final List<T> allItems;
    final remote = remoteAdapter;
    final deltaAllowed = allowDelta && config.enableDeltaSync;
    if (deltaAllowed && remote is CursorSyncCapable<T>) {
      // Cursor-based incremental pull — the generalized (v2) path. A null
      // cursor means "from the beginning", so even the first sync goes
      // through the feed; the returned cursor persists via sync metadata.
      final metadata = await localAdapter.getSyncMetadata(userId);
      final cursor = metadata?.customMetadata?[syncCursorKey] as String?;
      logger.info('Cursor pull for user $userId (cursor: ${cursor ?? '<start>'}).');
      // No promotion: CursorSyncCapable is not a RemoteAdapter subtype.
      final page = await (remote as CursorSyncCapable<T>).readChanges(cursor, userId: userId, scope: scope);
      _pendingCursors[userId] = page.nextCursor;
      allItems = page.items;
    } else if (deltaAllowed && remote is DeltaSyncCapable<T>) {
      final metadata = await localAdapter.getSyncMetadata(userId);
      // Prefer the server's own clock when the adapter recorded one; fall
      // back to the local sync stamp.
      final watermark = metadata?.serverTimestamp ?? metadata?.lastSyncTime;
      if (watermark != null) {
        // Incremental pull: only rows modified since the watermark, widened
        // by the configured overlap to tolerate clock skew. Re-delivered
        // rows are dropped by the strictly-newer check, so the overlap is
        // idempotent.
        final since = watermark.subtract(config.deltaSyncOverlap);
        logger.info('Delta pull for user $userId: entities modified since $since.');
        // No promotion: DeltaSyncCapable is not a RemoteAdapter subtype.
        allItems = await (remote as DeltaSyncCapable<T>).readSince(since, userId: userId, scope: scope);
      } else {
        allItems = await remoteAdapter.readAll(userId: userId, scope: scope);
      }
    } else {
      allItems = await remoteAdapter.readAll(userId: userId, scope: scope);
    }

    for (var i = 0; i < allItems.length; i += config.remoteStreamBatchSize) {
      final end = (i + config.remoteStreamBatchSize < allItems.length) ? i + config.remoteStreamBatchSize : allItems.length;
      final batch = allItems.sublist(i, end);

      for (final item in batch) {
        yield item;
      }

      // Allow other async operations to proceed
      await Future.delayed(Duration.zero);
    }
  }

  /// Whether [remote] should replace [local] during a pull, when no conflict
  /// was detected.
  ///
  /// Prefers vector clocks when both are present (update only if remote is
  /// strictly newer — i.e. not an ancestor of or equal to local). Concurrent
  /// clocks never reach here (the detector routes them to the resolver). When
  /// clock info is incomplete, falls back to version then `modifiedAt`, so an
  /// equal/older remote is not needlessly written back.
  bool _isRemoteStrictlyNewer(T local, T remote) {
    final localVC = local.vectorClock;
    final remoteVC = remote.vectorClock;
    if (localVC != null && remoteVC != null) {
      return !remoteVC.isLessThanOrEqualTo(localVC);
    }
    if (remote.version != local.version) {
      return remote.version > local.version;
    }
    return remote.modifiedAt.isAfter(local.modifiedAt);
  }

  // Process a batch of remote items
  Future<int> _processRemoteBatch(
    List<T> remoteBatch,
    String userId,
    DatumSyncOptions<T>? options,
    List<DatumSyncEvent<T>> generatedEvents,
    int processedCount,
    int cumulativeBytesSoFar,
  ) async {
    int batchBytes = 0;

    // Get local items for this batch only
    final localItemsMap = await localAdapter.readByIds(
      remoteBatch.map((e) => e.id).toList(),
      userId: userId,
    );

    for (var i = 0; i < remoteBatch.length; i++) {
      final remoteItem = remoteBatch[i];
      final localItem = localItemsMap[remoteItem.id];

      final context = conflictDetector.detect(
        localItem: localItem,
        remoteItem: remoteItem,
        userId: userId,
      );

      if (context == null) {
        if (localItem == null) {
          // This is a new item from remote.
          await localAdapter.create(remoteItem);
          hashCache.invalidate(userId);
          final size = jsonEncode(remoteItem.toDatumMap()).length;
          batchBytes += size;
        } else {
          // Existing item with no detected conflict: apply the remote version
          // only if it is *actually* newer. Previously `shouldUpdate` defaulted
          // to true and the check was skipped whenever a vector clock was null,
          // so local was always overwritten — even when versions were equal,
          // producing redundant update() calls, spurious change events and sync
          // noise/loops. Concurrent edits are already routed to the conflict
          // resolver by the detector, so here we just need a strict newer-check.
          if (_isRemoteStrictlyNewer(localItem, remoteItem)) {
            await localAdapter.update(remoteItem);
            hashCache.invalidate(userId);
            final size = jsonEncode(remoteItem.toDatumMap()).length;
            batchBytes += size;
          } else {
            logger.debug('Skipping remote update for ${remoteItem.id}: local is newer or identical.');
          }
        }

        // Note: syncedCount is not incremented for pull operations in the global sync result
        // as per the design where only push operations contribute to the global synced count

        // Emit progress event less frequently to reduce allocations
        // Only emit every N items or when batch is complete
        final currentTotal = processedCount + i + 1;
        if (currentTotal % config.progressEventFrequency == 0 || i == remoteBatch.length - 1) {
          final progressEvent = DatumSyncProgressEvent<T>(
            userId: userId,
            completed: currentTotal,
            total: -1, // Unknown total for streaming approach
            bytesPulled: cumulativeBytesSoFar + batchBytes,
          );
          generatedEvents.add(progressEvent);
          _notifyObservers(progressEvent);
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

      var wasResolved = true;
      switch (resolution.strategy) {
        case DatumResolutionStrategy.takeLocal:
          // Local wins, but the remote copy is still divergent: queue a push
          // of the winning local state so the remote converges. Previously
          // nothing was propagated, so the very same conflict re-fired on
          // every subsequent sync and the winner never reached other devices.
          final winner = resolution.resolvedData ?? localItem;
          if (winner != null) {
            await _enqueueResolutionPush(userId, winner);
          }
        case DatumResolutionStrategy.takeRemote:
          // Honor a resolver-transformed value (`useRemote(tweaked)`); the raw
          // remoteItem was previously written unconditionally, silently
          // discarding resolvedData.
          await localAdapter.update(resolution.resolvedData ?? remoteItem);
          hashCache.invalidate(userId);
        case DatumResolutionStrategy.merge:
          if (resolution.resolvedData == null) {
            throw StateError('Merge resolution must provide a merged item.');
          }
          final merged = resolution.resolvedData!;
          await localAdapter.update(merged);
          hashCache.invalidate(userId);
          // The merged value must also reach the remote, or the merge repeats
          // forever and never propagates to other devices.
          await _enqueueResolutionPush(userId, merged);
        case DatumResolutionStrategy.abort:
          logger.warn('Conflict resolution aborted for ${context.entityId}');
          wasResolved = false;
        case DatumResolutionStrategy.askUser:
          logger.warn(
            'Conflict resolution requires user input for ${context.entityId}',
          );
          wasResolved = false;
      }
      // abort/askUser change nothing — reporting them as "resolved" both
      // inflated conflictsResolved and emitted a misleading resolved event.
      if (wasResolved) {
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
    }

    return batchBytes;
  }

  /// Queues a push of a conflict-resolution winner so the remote (and other
  /// devices) converge on the resolved state.
  Future<void> _enqueueResolutionPush(String userId, T item) async {
    final payload = item.toDatumMap(target: MapTarget.remote);
    await queueManager.enqueue(DatumSyncOperation<T>(
      id: 'conflict-${item.id}-${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      entityId: item.id,
      entityTable: T.toString(),
      type: DatumOperationType.update,
      timestamp: DateTime.now(),
      data: item,
      sizeInBytes: jsonEncode(payload).length,
    ));
  }

  void _notifyPreOperationObservers(DatumSyncOperation<T> operation) {
    switch (operation.type) {
      case DatumOperationType.create:
      case DatumOperationType.update:
        if (operation.data == null) return;
        final item = operation.data!;
        if (operation.type == DatumOperationType.create) {
          for (final observer in localObservers) {
            observer.onCreateStart(item);
          }
          for (final observer in globalObservers) {
            observer.onCreateStart(item);
          }
        } else {
          for (final observer in localObservers) {
            observer.onUpdateStart(item);
          }
          for (final observer in globalObservers) {
            observer.onUpdateStart(item);
          }
        }
      case DatumOperationType.delete:
        for (final observer in localObservers) {
          observer.onDeleteStart(operation.entityId);
        }
        for (final observer in globalObservers) {
          observer.onDeleteStart(operation.entityId);
        }
    }
  }

  void _notifyPostOperationObservers(
    DatumSyncOperation<T> operation, {
    required bool success,
  }) {
    if (eventController.isClosed) {
      return;
    }
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
    if (eventController.isClosed) {
      return;
    }
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
          final genericResolution = resolvedEvent.resolution.copyWithNewType<DatumEntityInterface>();
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
        // Global observers must also learn the sync ended — previously only
        // the success path notified them, so a failed sync left them thinking
        // a sync was still in progress.
        for (final observer in globalObservers) {
          observer.onSyncEnd(errorResult);
        }
      case _:
        // Other events like progress, conflict, etc.
        break;
    }
  }

  Future<void> _updateMetadata(String userId, {bool pulledRemote = true}) async {
    try {
      // Reuse the cached content hash when no write chokepoint invalidated it
      // since the last computation — the common idle auto-sync cycle then
      // skips both the O(n) readAll and the O(n) rehash.
      final String contentHash;
      final int itemCount;
      final cached = config.enableMetadataHashCache ? hashCache.peek(userId) : null;
      if (cached != null) {
        contentHash = cached.hash;
        itemCount = cached.count;
      } else {
        final items = await localAdapter.readAll(userId: userId);
        contentHash = const DatumHashGenerator().hashEntitiesUnordered(items);
        itemCount = items.length;
        hashCache.store(userId, hash: contentHash, count: itemCount);
      }
      final existingMetadata = await localAdapter.getSyncMetadata(userId);

      // Persist the cursor staged by a cursor-based pull this cycle. The
      // cursor is per-DEVICE progress: it lives in the LOCAL metadata only
      // and is stripped from the remote beacon — if another device ever
      // adopted a foreign cursor it would silently skip changes it has
      // never seen.
      final stagedCursor = _pendingCursors.remove(userId);
      final localCustomMetadata = stagedCursor == null ? existingMetadata?.customMetadata : {...?existingMetadata?.customMetadata, syncCursorKey: stagedCursor};
      final strippedCustomMetadata = localCustomMetadata == null ? null : ({...localCustomMetadata}..remove(syncCursorKey));
      final remoteCustomMetadata = (strippedCustomMetadata?.isEmpty ?? true) ? null : strippedCustomMetadata;

      Map<String, DateTime>? updatedDevices = existingMetadata?.devices != null ? Map<String, DateTime>.from(existingMetadata!.devices!) : {};

      if (deviceId != null) {
        updatedDevices[deviceId!] = DateTime.now();
      }

      // The order-independent content hash is what the skip-check at the top
      // of synchronize() compares between local and remote metadata — a
      // placeholder here once degraded that check to a bare count comparison,
      // so a remote content change that kept the count identical was never
      // pulled and devices diverged permanently.

      // Preserve existing entity counts and update only the current entity type
      final updatedEntityCounts = Map<String, DatumEntitySyncDetails>.from(existingMetadata?.entityCounts ?? {});
      updatedEntityCounts[entityName] = DatumEntitySyncDetails(
        count: itemCount,
        hash: contentHash,
      );

      final newMetadata = DatumSyncMetadata(
        userId: userId,
        lastSyncTime: DateTime.now(),
        dataHash: contentHash,
        deviceId: deviceId, // Use the current deviceId for this sync
        devices: updatedDevices.isEmpty ? null : updatedDevices,
        entityCounts: updatedEntityCounts,
        // Preserve other fields from existing metadata or set defaults
        lastSuccessfulSyncTime: DateTime.now(),
        customMetadata: localCustomMetadata,
        syncStatus: SyncStatus.synced,
        syncVersion: existingMetadata?.syncVersion ?? 1,
        serverTimestamp: existingMetadata?.serverTimestamp,
        conflictCount: existingMetadata?.conflictCount ?? 0,
        errorMessage: existingMetadata?.errorMessage,
        retryCount: existingMetadata?.retryCount ?? 0,
        syncDuration: existingMetadata?.syncDuration,
      );

      // A push-only cycle never observed the remote's content, so stamping the
      // LOCAL metadata with our own hash would fabricate the "local == remote"
      // invariant: if the remote held unpulled changes, both sides would carry
      // our hash, the skip-check would see a match, and those remote changes
      // would never be pulled. Instead: write the remote metadata (a change
      // beacon so other devices pull our push), but keep the local hash and
      // counts describing the last state we actually reconciled — the next
      // pull-inclusive sync then sees the difference and runs.
      final localMetadata = pulledRemote
          ? newMetadata
          : DatumSyncMetadata(
              userId: userId,
              lastSyncTime: DateTime.now(),
              dataHash: existingMetadata?.dataHash,
              deviceId: deviceId,
              devices: updatedDevices.isEmpty ? null : updatedDevices,
              entityCounts: existingMetadata?.entityCounts,
              lastSuccessfulSyncTime: DateTime.now(),
              customMetadata: localCustomMetadata,
              syncStatus: SyncStatus.synced,
              syncVersion: existingMetadata?.syncVersion ?? 1,
              serverTimestamp: existingMetadata?.serverTimestamp,
              conflictCount: existingMetadata?.conflictCount ?? 0,
              errorMessage: existingMetadata?.errorMessage,
              retryCount: existingMetadata?.retryCount ?? 0,
              syncDuration: existingMetadata?.syncDuration,
            );

      await localAdapter.updateSyncMetadata(localMetadata, userId);
      try {
        // copyWith(null) would KEEP the cursor-bearing map, so the stripped
        // beacon passes an empty map when nothing else remains.
        await remoteAdapter.updateSyncMetadata(
          newMetadata.copyWith(customMetadata: remoteCustomMetadata ?? const <String, dynamic>{}),
          userId,
        );
      } on Object catch (e) {
        // The remote metadata write is a change *beacon* for other devices —
        // an optimization, not sync state. Failing it (e.g. the connection
        // dropped right after the data phases completed and re-queued their
        // ops gracefully) must not fail the whole cycle; the next successful
        // sync rewrites it. Local metadata failures still rethrow below:
        // broken local storage is a real error.
        logger.warn('Remote metadata beacon update failed for user $userId ($e); continuing — the next successful sync will rewrite it.');
      }
      if (!metadataSubject.isClosed) {
        metadataSubject.add(localMetadata);
      }
    } on Object catch (e, stack) {
      logger.error(
        'Failed to update sync metadata for user $userId: $e',
        stack,
      );
      // Re-throw to allow the main sync loop\'s error handler to catch it.
      rethrow;
    }
  }

  /// Performs a health check on the local and remote adapters.
  ///
  /// This method checks the connectivity and the individual health of both
  /// adapters, combines them into a [DatumHealth] object, updates the
  /// status stream, and returns the result.
  Future<DatumHealth> checkHealth() async {
    final localStatus = await localAdapter.checkHealth();
    final remoteStatus = await remoteAdapter.checkHealth();
    final isConnected = await connectivityChecker.isConnected;

    DatumSyncHealth overallStatus;
    if (!isConnected) {
      overallStatus = DatumSyncHealth.offline;
    } else if (localStatus == AdapterHealthStatus.unhealthy || remoteStatus == AdapterHealthStatus.unhealthy) {
      overallStatus = DatumSyncHealth.degraded;
    } else {
      overallStatus = DatumSyncHealth.healthy;
    }

    final health = DatumHealth(
      status: overallStatus,
      localAdapterStatus: localStatus,
      remoteAdapterStatus: remoteStatus,
    );

    // Update the health status in the main status snapshot.
    statusSubject.add(statusSubject.value.copyWith(health: health));

    return health;
  }

  bool _deepCompareEntityCounts(
    Map<String, DatumEntitySyncDetails>? local,
    Map<String, DatumEntitySyncDetails>? remote,
  ) {
    if (local == null && remote == null) return true;
    if (local == null || remote == null) return false;
    if (local.length != remote.length) return false;

    for (final entry in local.entries) {
      final remoteDetails = remote[entry.key];
      if (remoteDetails == null || entry.value.count != remoteDetails.count || entry.value.hash != remoteDetails.hash) {
        return false;
      }
    }
    return true;
  }

  List<DatumSyncOperation<T>> _groupOperations(List<DatumSyncOperation<T>> operations) {
    if (operations.isEmpty) return [];

    final result = <DatumSyncOperation<T>>[];
    var currentBatch = <DatumSyncOperation<T>>[];

    for (final op in operations) {
      if (currentBatch.isEmpty) {
        currentBatch.add(op);
      } else {
        final lastOp = currentBatch.last;
        // Group consecutive operations of the same type and same user.
        // We only batch CREATE, DELETE, and FULL UPDATE (no delta).
        final isCreate = op.type == DatumOperationType.create;
        final isDelete = op.type == DatumOperationType.delete;
        final isFullUpdate = op.type == DatumOperationType.update && (op.delta == null || op.delta!.isEmpty);

        final canBatch = op.type == lastOp.type && op.userId == lastOp.userId && (isCreate || isDelete || isFullUpdate);

        if (canBatch && currentBatch.length < config.remoteSyncBatchSize) {
          currentBatch.add(op);
        } else {
          if (currentBatch.length == 1) {
            result.add(currentBatch.first);
          } else {
            result.add(DatumSyncBatchOperation<T>(operations: currentBatch));
          }
          currentBatch = [op];
        }
      }
    }

    if (currentBatch.isNotEmpty) {
      if (currentBatch.length == 1) {
        result.add(currentBatch.first);
      } else {
        result.add(DatumSyncBatchOperation<T>(operations: currentBatch));
      }
    }

    return result;
  }

  Future<int> _processBatchOperation(
    DatumSyncBatchOperation<T> batch, {
    required List<DatumSyncEvent<T>> generatedEvents,
  }) async {
    for (final op in batch.operations) {
      _notifyPreOperationObservers(op);
    }

    logger.debug(
      'Processing batch: ${batch.type.name} for ${batch.operations.length} entities',
    );

    try {
      switch (batch.type) {
        case DatumOperationType.create:
          final entities = batch.operations.map((op) => op.data!).toList();
          await remoteAdapter.createAll(entities);
        case DatumOperationType.update:
          final entities = batch.operations.map((op) => op.data!).toList();
          await remoteAdapter.updateAll(entities);
        case DatumOperationType.delete:
          final ids = batch.operations.map((op) => op.entityId).toList();
          await remoteAdapter.deleteAll(ids, userId: batch.userId);
      }

      for (final op in batch.operations) {
        await queueManager.dequeue(op.id);
        _notifyPostOperationObservers(op, success: true);
      }

      if (!statusSubject.isClosed) {
        statusSubject.add(
          statusSubject.value.copyWith(
            syncedCount: statusSubject.value.syncedCount + batch.operations.length,
          ),
        );
      }
      return batch.sizeInBytes;
    } on Object catch (e, stackTrace) {
      logger.error('Batch operation ${batch.id} failed: $e', stackTrace);

      // Mirror the single-operation retry semantics: a retryable failure must
      // re-queue the operations with an incremented retryCount, not silently
      // discard them. Previously every batch failure — including transient
      // network errors — dequeued ALL operations permanently, so a single
      // offline blip during a batched push lost the entire batch.
      final canRetry = e is DatumException && await config.errorRecoveryStrategy.shouldRetry(e);
      var requeued = 0;
      var failed = 0;

      for (final op in batch.operations) {
        if (canRetry && op.retryCount < config.errorRecoveryStrategy.maxRetries) {
          await queueManager.update(op.copyWith(retryCount: op.retryCount + 1));
          requeued++;
        } else {
          await queueManager.dequeue(op.id);
          _notifyPostOperationObservers(op, success: false);
          failed++;
        }
      }

      if (failed > 0 && !statusSubject.isClosed) {
        statusSubject.add(
          statusSubject.value.copyWith(
            failedOperations: statusSubject.value.failedOperations + failed,
            errors: [...statusSubject.value.errors, e],
          ),
        );
      }

      if (requeued > 0) {
        logger.warn('Batch ${batch.id}: $requeued operation(s) re-queued for retry, $failed failed permanently.');
        return 0; // retryable — same non-throwing contract as the single-op path
      }
      throw SyncExceptionWithEvents(e, stackTrace, generatedEvents);
    }
  }
}

/// A special exception to carry events back up the call stack on failure.
class SyncExceptionWithEvents<T extends DatumEntityInterface> implements Exception {
  final Object originalError;
  final StackTrace originalStackTrace;
  final List<DatumSyncEvent<T>> events;

  SyncExceptionWithEvents(
    this.originalError,
    this.originalStackTrace,
    this.events,
  );
}
