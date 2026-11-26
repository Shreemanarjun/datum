import 'dart:async';
import 'dart:convert';

import 'package:datum/source/adapter/adapter_capabilities.dart';
import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/engine/conflict_detector.dart';
import 'package:datum/source/core/engine/datum_observer.dart';
import 'package:datum/source/core/engine/isolate_helper.dart';
import 'package:datum/source/core/engine/queue_manager.dart';
import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:datum/source/core/events/conflict_detected_event.dart';
import 'package:datum/source/core/events/conflict_resolved_event.dart';
import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/events/user_switched_event.dart';
import 'package:datum/source/core/health/datum_health.dart';
import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/models/datum_sync_options.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:datum/source/core/models/datum_sync_scope.dart';
import 'package:datum/source/core/models/datum_sync_status_snapshot.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/utils/hash_generator.dart';
import 'package:datum/source/utils/connectivity_checker.dart';
import 'package:datum/source/utils/datum_logger.dart';
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

    // Loaded once and reused by the pre-check and the start snapshot.
    final pendingAtStart = (await queueManager.getPending(userId)).length;
    final skipped = await _preflightSkip(userId, options, pendingAtStart, snapshot.pendingOperations);
    if (skipped != null) return (skipped, <DatumSyncEvent<T>>[]);

    // Fetch the last sync result to get the previous total byte counts.
    final lastSyncResult = await localAdapter.getLastSyncResult(userId);

    final stopwatch = Stopwatch()..start();

    // Reset the snapshot for the new sync cycle, preserving only the user ID.
    statusSubject.add(
      DatumSyncStatusSnapshot.initial(userId).copyWith(
        status: DatumSyncStatus.syncing,
        health: const DatumHealth(status: DatumSyncHealth.syncing),
        pendingOperations: pendingAtStart,
      ),
    );
    _record(
      generatedEvents,
      // Use the freshly fetched count — `snapshot` was captured before this
      // cycle and reported a stale (often zero) pending count in the event.
      DatumSyncStartedEvent<T>(userId: userId, pendingOperations: pendingAtStart, reason: options?.reason),
    );

    try {
      final (:pushed, :pulled) = await _runPhases(userId, options, scope, generatedEvents);
      final totals = (pushed: pushed, pulled: pulled, previous: lastSyncResult);

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
        _discardStagedPullState(userId);
        return (
          DatumSyncResult<T>.cancelled(userId, statusSubject.value.syncedCount),
          generatedEvents,
        );
      }
      if (statusSubject.value.status != DatumSyncStatus.syncing) {
        logger.warn(
          'Sync for user $userId was interrupted (status: ${statusSubject.value.status.name}); reporting a cancelled result.',
        );
        _discardStagedPullState(userId);
        return (await _cycleResult(userId, stopwatch, totals, wasCancelled: true), generatedEvents);
      }

      // Update metadata after a genuinely completed sync cycle.
      await _updateMetadata(userId, pulledRemote: _directionOf(options) != SyncDirection.pushOnly);

      final result = await _cycleResult(userId, stopwatch, totals);

      // The manager might have been disposed during the sync operation.
      // The final status is idle: 'completed' is a transient event, not a state.
      _emitStatus(
        (s) => s.copyWith(
          status: DatumSyncStatus.idle,
          health: const DatumHealth(status: DatumSyncHealth.healthy),
        ),
      );
      if (!eventController.isClosed) {
        _record(generatedEvents, DatumSyncCompletedEvent<T>(userId: userId, result: result));
      }
      return (result, generatedEvents);
    } catch (e, stack) {
      _failCycle(userId, e, stack, generatedEvents);
    }
  }

  SyncDirection _directionOf(DatumSyncOptions<T>? options) => options?.direction ?? config.defaultSyncDirection;

  /// Returns a skipped result when the cycle has nothing to do, else null.
  Future<DatumSyncResult<T>?> _preflightSkip(
    String userId,
    DatumSyncOptions<T>? options,
    int pendingAtStart,
    int snapshotPending,
  ) async {
    final forced = options?.forceFullSync == true;
    // A push-only cycle with an empty queue has nothing to do — skip before
    // the metadata round-trips and the end-of-cycle rehash/metadata write.
    // (Datum.synchronize runs a push-only pass over every manager.)
    if (_directionOf(options) == SyncDirection.pushOnly && pendingAtStart == 0 && !forced) {
      logger.debug('Push-only sync for user $userId skipped: no pending operations.');
      return DatumSyncResult<T>.skipped(userId, 0, reason: 'No pending operations to push');
    }

    // If forceFullSync is true, bypass metadata comparison and proceed with sync.
    if (forced) {
      logger.info('Sync for user $userId forced: forceFullSync option is true.');
      return null;
    }

    // Fetch local and remote metadata to determine if a sync is necessary.
    // This pre-check is an OPTIMIZATION — if the metadata fetch fails (e.g. a
    // transient network blip on the remote call), degrade to running the sync
    // rather than failing the whole cycle before it even started; the actual
    // push/pull phases have their own retry/error handling.
    DatumSyncMetadata? localMetadata;
    DatumSyncMetadata? remoteMetadata;
    try {
      [localMetadata, remoteMetadata] = await Future.wait([localAdapter.getSyncMetadata(userId), remoteAdapter.getSyncMetadata(userId)]);
    } on Object catch (e) {
      logger.warn('Metadata pre-check failed for user $userId ($e); proceeding with a full sync.');
    }

    // Compare relevant metadata fields for skipping.
    final metadataMatches = localMetadata != null && remoteMetadata != null && localMetadata.dataHash == remoteMetadata.dataHash && _deepCompareEntityCounts(localMetadata.entityCounts, remoteMetadata.entityCounts);

    // If metadata matches and there are no pending local operations, skip the sync.
    if (!metadataMatches || pendingAtStart != 0) return null;
    logger.info('Sync for user $userId skipped: No changes detected based on metadata and no pending local operations.');
    return DatumSyncResult<T>.skipped(
      userId,
      snapshotPending,
      reason: 'No changes detected based on metadata',
    );
  }

  /// Runs the push/pull phases in the configured order; returns bytes moved.
  Future<({int pushed, int pulled})> _runPhases(
    String userId,
    DatumSyncOptions<T>? options,
    DatumSyncScope? scope,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    Future<int> push() => _pushChanges(userId, options, generatedEvents);
    Future<int> pull() => _pullChanges(userId, options, scope, generatedEvents);
    return switch (_directionOf(options)) {
      SyncDirection.pushThenPull => (pushed: await push(), pulled: await pull()),
      SyncDirection.pullThenPush => (pulled: await pull(), pushed: await push()),
      SyncDirection.pushOnly => (pushed: await push(), pulled: 0),
      SyncDirection.pullOnly => (pushed: 0, pulled: await pull()),
    };
  }

  Future<DatumSyncResult<T>> _cycleResult(
    String userId,
    Stopwatch stopwatch,
    ({int pushed, int pulled, DatumSyncResult<T>? previous}) totals, {
    bool wasCancelled = false,
  }) async {
    final pending = await queueManager.getPending(userId);
    final status = statusSubject.value;
    return DatumSyncResult<T>(
      userId: userId,
      duration: stopwatch.elapsed,
      syncedCount: status.syncedCount,
      failedCount: status.failedOperations,
      conflictsResolved: status.conflictsResolved,
      pendingOperations: pending,
      bytesPushedInCycle: totals.pushed,
      bytesPulledInCycle: totals.pulled,
      totalBytesPushed: (totals.previous?.totalBytesPushed ?? 0) + totals.pushed,
      totalBytesPulled: (totals.previous?.totalBytesPulled ?? 0) + totals.pulled,
      wasCancelled: wasCancelled,
      retryAfter: _retryAfter,
    );
  }

  /// Reports a failed cycle and throws. When the manager was disposed
  /// mid-sync the original error propagates unwrapped (no one will process
  /// events); otherwise it is wrapped in [SyncExceptionWithEvents] so the
  /// generated events (including the error event) reach the DatumManager.
  Never _failCycle(
    String userId,
    Object e,
    StackTrace stack,
    List<DatumSyncEvent<T>> generatedEvents,
  ) {
    logger.error('Synchronization failed for user $userId: $e', stack);
    _discardStagedPullState(userId);
    final original = e is SyncExceptionWithEvents<T> ? e.originalError : e;

    if (eventController.isClosed) {
      if (e is SyncExceptionWithEvents<T>) throw original;
      Error.throwWithStackTrace(e, stack);
    }

    statusSubject.add(
      statusSubject.value.copyWith(
        status: DatumSyncStatus.failed, // The sync cycle failed
        health: const DatumHealth(status: DatumSyncHealth.error),
        errors: [e],
      ),
    );
    _record(
      generatedEvents,
      DatumSyncErrorEvent<T>(userId: userId, error: original, stackTrace: stack),
    );

    if (e is SyncExceptionWithEvents<T>) Error.throwWithStackTrace(e, stack);
    throw SyncExceptionWithEvents(e, stack, generatedEvents);
  }

  /// Appends [event] to [generatedEvents] and notifies observers.
  void _record(List<DatumSyncEvent<T>> generatedEvents, DatumSyncEvent<T> event) {
    generatedEvents.add(event);
    _notifyObservers(event);
  }

  /// Applies [update] to the status snapshot unless the subject is closed.
  void _emitStatus(DatumSyncStatusSnapshot Function(DatumSyncStatusSnapshot current) update) {
    if (!statusSubject.isClosed) statusSubject.add(update(statusSubject.value));
  }

  /// Entities whose op failed retryably THIS cycle. Later queued ops for the
  /// same entity must wait for the retry instead of overtaking it — otherwise
  /// the failed older op replays AFTER them next cycle, regressing the remote
  /// (lost updates) or resurrecting deleted entities.
  final Set<String> _blockedEntityIds = {};

  Future<int> _pushChanges(
    String userId,
    DatumSyncOptions<T>? options,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    int cumulativeBytesPushed = 0;
    int bytesPushed = 0;
    _blockedEntityIds.clear();
    _retryAfter = null;
    final pending = await queueManager.getPending(userId);
    // Parked ops stay queued, and nothing later for the same entity may
    // overtake them. Deletes held back by `includeDeletes: false` hold their
    // entity's later ops the same way.
    final holdDeletes = options?.includeDeletes == false;
    final held = {
      for (final op in pending)
        if (op.isParked || (holdDeletes && op.type == DatumOperationType.delete)) op.entityId
    };
    final operationsToProcess = [
      for (final op in pending)
        if (!held.contains(op.entityId)) op
    ];
    if (operationsToProcess.isEmpty) {
      logger.info('No pending changes to push for user $userId.');
      return 0;
    }

    // Group consecutive operations of the same type to enable batching.
    final groups = _groupOperations(operationsToProcess, _batchSize(options));

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
    // The manager was disposed mid-cycle: leave the rest queued.
    if (statusSubject.isClosed) return 0;
    if (operation is DatumSyncBatchOperation<T>) {
      return await _processBatchOperation(operation, generatedEvents: generatedEvents);
    }

    if (_blockedEntityIds.contains(operation.entityId)) {
      // An earlier op for this entity failed retryably this cycle. Leave
      // this one queued so replay order stays intact next cycle.
      logger.warn(
        'Operation ${operation.id} for entity ${operation.entityId} deferred: '
        'an earlier operation for the same entity is awaiting retry.',
      );
      return 0;
    }

    _notifyPreOperationObservers(operation);
    logger.debug(
      'Processing operation: ${operation.type.name} for entity ${operation.entityId}',
    );
    try {
      await _sendToRemote(operation);
      await queueManager.dequeue(operation.id);
      if (statusSubject.isClosed) return 0;
      statusSubject.add(
        statusSubject.value.copyWith(
          syncedCount: statusSubject.value.syncedCount + 1,
        ),
      );
      _notifyPostOperationObservers(operation, success: true);
      return operation.sizeInBytes;
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
      return _onOperationFailed(operation, e, stackTrace, generatedEvents);
    }
  }

  /// Handles a failed send: pause on an expired session, schedule a retry,
  /// or park. Returns 0 (bytes sent) or throws to stop the cycle.
  Future<int> _onOperationFailed(
    DatumSyncOperation<T> operation,
    Object e,
    StackTrace stackTrace,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    if (e is AuthenticationException && config.authErrorPolicy == AuthErrorPolicy.pauseSync) {
      // Session expired: the op stays queued untouched and the manager
      // pauses until the user signs in again.
      _notifyPostOperationObservers(operation, success: false);
      throw SyncExceptionWithEvents(e, stackTrace, generatedEvents);
    }
    final isRetryable = e is DatumException && operation.retryCount < config.errorRecoveryStrategy.maxRetries && await config.errorRecoveryStrategy.shouldRetry(e);

    if (isRetryable) {
      final updatedOp = operation.copyWith(
        retryCount: operation.retryCount + 1,
      );
      await queueManager.update(updatedOp);
      // Later ops for this entity must not overtake the failed one.
      _blockedEntityIds.add(operation.entityId);
      if (e is NetworkException) _retryAfter = _longer(_retryAfter, e.retryAfter);
      logger.warn(
        'Operation ${operation.id} failed. Will retry on next sync.',
      );
      return 0;
    }

    // Non-retryable (or out of retries): park it. It stays queued so the
    // user's edit is never lost, but stops blocking other entities.
    _emitStatus(
      (s) => s.copyWith(
        failedOperations: s.failedOperations + 1,
        errors: [...s.errors, e],
      ),
    );
    logger.error(
      'Operation ${operation.id} failed permanently: $e',
      stackTrace,
    );
    await queueManager.update(operation.copyWith(parkedError: e is DatumException ? e.message : '$e'));
    _blockedEntityIds.add(operation.entityId);

    // Re-throw the exception. This is crucial for allowing execution
    // strategies (like `ParallelStrategy` with `failFast: true`) to
    // stop processing and immediately propagate the failure up to the
    // main `synchronize` method's `try...catch` block.
    // IMPORTANT: Wrap the raw error in SyncExceptionWithEvents before re-throwing.
    // This ensures that when this code runs in an isolate, the main isolate
    // receives the correctly typed exception, not just the raw `e`.
    throw SyncExceptionWithEvents(e, stackTrace, generatedEvents);
  }

  /// The longest server-requested wait seen on this cycle's retryable failures.
  Duration? _retryAfter;

  static Duration? _longer(Duration? a, Duration? b) => a == null || (b != null && b > a) ? b : a;

  /// Sends a single (non-batched) operation to the remote adapter.
  Future<void> _sendToRemote(DatumSyncOperation<T> operation) async {
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
  }

  bool _isForced(DatumSyncOptions<T>? options) => options?.forceFullSync ?? false;

  /// Whether this pull compares the full remote id set against local rows.
  /// Needs an unscoped, unfiltered pull, and deletions being synced at all.
  bool _detectsDeletions(DatumSyncOptions<T>? options, DatumSyncScope? scope) {
    final isFiltered = options?.query.filters.isNotEmpty ?? false;
    return config.detectRemoteDeletions && scope == null && !isFiltered && (options?.includeDeletes ?? true);
  }

  /// This cycle's batch size: the per-sync override, else the configured one.
  int _batchSize(DatumSyncOptions<T>? options) => options?.overrideBatchSize ?? config.remoteSyncBatchSize;

  Future<int> _pullChanges(
    String userId,
    DatumSyncOptions<T>? options,
    DatumSyncScope? scope,
    List<DatumSyncEvent<T>> generatedEvents,
  ) async {
    final isFiltered = options?.query.filters.isNotEmpty ?? false;
    if (scope != null) {
      logger.info('Performing partial sync for user $userId with query: ${scope.query}');
    } else if (isFiltered) {
      logger.info('Performing filtered sync for user $userId with query: ${options!.query}');
    } else {
      logger.info('Pulling remote changes for user $userId...');
    }

    int cumulativeBytesPulled = 0;
    int bytesPulled = 0;
    int processedCount = 0;

    // Track every remote id seen so we can detect remote deletions (entities
    // present locally but absent remotely) after the pull, when enabled.
    final detectDeletions = _detectsDeletions(options, scope);

    // Use streaming approach for large datasets to reduce memory usage.
    // Deletion detection needs the COMPLETE remote id set, so those cycles
    // must never use an incremental (delta) pull.
    // A forced full sync re-reads everything too (its documented contract).
    final remoteItemsStream = _streamRemoteItems(userId, scope, allowDelta: !detectDeletions && !_isForced(options));
    final remoteBatch = <T>[];
    final seenRemoteIds = detectDeletions ? <String>{} : null;

    await for (final remoteItem in remoteItemsStream) {
      seenRemoteIds?.add(remoteItem.id);
      remoteBatch.add(remoteItem);

      // Process batch when it reaches the batch size
      if (remoteBatch.length >= _batchSize(options)) {
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

  /// When this cycle's pull request started (this device's clock), staged per
  /// user and persisted as [DatumSyncMetadata.serverTimestamp]. Taken BEFORE
  /// the read, so rows written during a long cycle are re-read next time;
  /// never from rows' `modifiedAt` — a writer whose clock runs ahead would push
  /// the watermark past rows written later. Device-vs-server skew is covered by
  /// `DatumConfig.deltaSyncOverlap` (servers should filter on received-at).
  final Map<String, DateTime> _pendingServerWatermarks = {};

  /// Drops pull state staged by an aborted cycle. A cursor or watermark whose
  /// items were never fully applied locally must not be persisted by a later
  /// cycle — the rows behind it would never be fetched again.
  void _discardStagedPullState(String userId) {
    _pendingCursors.remove(userId);
    _pendingServerWatermarks.remove(userId);
  }

  // Stream remote items instead of loading all at once
  Stream<T> _streamRemoteItems(String userId, DatumSyncScope? scope, {bool allowDelta = false}) async* {
    final pullStartedAt = DateTime.now();
    final allItems = await _fetchRemoteItems(userId, scope, allowDelta: allowDelta);
    // Max across multiple pulls in one cycle.
    _pendingServerWatermarks[userId] = _later(_pendingServerWatermarks[userId], pullStartedAt)!;

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

  /// Reads this cycle's remote items: a cursor feed or delta read when the
  /// adapter supports it and [allowDelta] holds, otherwise a full read.
  Future<List<T>> _fetchRemoteItems(String userId, DatumSyncScope? scope, {required bool allowDelta}) async {
    if (allowDelta && config.enableDeltaSync) {
      try {
        final incremental = await _fetchIncremental(userId, scope);
        if (incremental != null) return incremental;
      } on ResyncRequiredException catch (e) {
        // The server cannot serve changes from our position any more (a
        // compacted log, an expired cursor): read everything again.
        logger.warn('Remote requires a full resync for user $userId: ${e.message}');
        final remote = remoteAdapter;
        // No promotion: CursorSyncCapable is not a RemoteAdapter subtype.
        if (remote is CursorSyncCapable<T>) return _readFeed(remote as CursorSyncCapable<T>, null, userId, scope);
      }
    }
    return await remoteAdapter.readAll(userId: userId, scope: scope);
  }

  /// A cursor or delta read, when the adapter supports one and this device
  /// has a position to read from; otherwise null (do a full read).
  Future<List<T>?> _fetchIncremental(String userId, DatumSyncScope? scope) async {
    final remote = remoteAdapter;
    if (remote is CursorSyncCapable<T>) {
      // Cursor-based incremental pull — the generalized (v2) path. A null
      // cursor means "from the beginning", so even the first sync goes
      // through the feed; the returned cursor persists via sync metadata.
      final metadata = await localAdapter.getSyncMetadata(userId);
      final cursor = metadata?.customMetadata?[syncCursorKey] as String?;
      logger.info('Cursor pull for user $userId (cursor: ${cursor ?? '<start>'}).');
      return _readFeed(remote as CursorSyncCapable<T>, cursor, userId, scope);
    }
    if (remote is! DeltaSyncCapable<T>) return null;
    final metadata = await localAdapter.getSyncMetadata(userId);
    // Prefer the server's own clock when the adapter recorded one; fall
    // back to the local sync stamp.
    final watermark = metadata?.serverTimestamp ?? metadata?.lastSyncTime;
    if (watermark == null) return null;
    // Incremental pull: only rows modified since the watermark, widened by
    // the configured overlap to tolerate clock skew. Re-delivered rows are
    // dropped by the strictly-newer check, so the overlap is idempotent.
    final since = watermark.subtract(config.deltaSyncOverlap);
    logger.info('Delta pull for user $userId: entities modified since $since.');
    return (remote as DeltaSyncCapable<T>).readSince(since, userId: userId, scope: scope);
  }

  /// Reads the change feed from [cursor] and stages the cursor it returns.
  Future<List<T>> _readFeed(CursorSyncCapable<T> feed, String? cursor, String userId, DatumSyncScope? scope) async {
    final page = await feed.readChanges(cursor, userId: userId, scope: scope);
    _pendingCursors[userId] = page.nextCursor;
    return page.items;
  }

  /// Where a pulled, non-conflicting [remoteItem] goes: [toCreate] when new,
  /// [toUpdate] when strictly newer than [localItem], else null (skip).
  List<T>? _pullTarget(T? localItem, T remoteItem, List<T> toCreate, List<T> toUpdate) => switch (localItem) {
        // A tombstone for a row this device never had deletes nothing: do
        // not store it (fresh devices skip the remote's deletion history).
        null when remoteItem.isDeleted => null,
        null => toCreate,
        // Equal versions must not produce redundant update() calls, spurious
        // change events and sync loops. Concurrent edits already went to the
        // resolver.
        final T local when _isRemoteStrictlyNewer(local, remoteItem) => toUpdate,
        _ => null,
      };

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
    // Non-conflicting writes are applied in bulk after the loop so adapters
    // with native batching (e.g. one SQLite transaction) commit once per batch.
    final toCreate = <T>[];
    final toUpdate = <T>[];
    final pull = (
      userId: userId,
      events: generatedEvents,
      resolver: options?.conflictResolver ?? conflictResolver,
      resolve: options?.resolveConflicts ?? true,
      pending: _opIdsByEntity(await queueManager.getPending(userId)),
    );

    // Get local items for this batch only
    final localItemsMap = await localAdapter.readByIds(
      remoteBatch.map((e) => e.id).toList(),
      userId: userId,
    );

    for (var i = 0; i < remoteBatch.length; i++) {
      final remoteItem = remoteBatch[i];
      final localItem = localItemsMap[remoteItem.id];
      // Locally hard-deleted, delete not pushed yet: don't resurrect it.
      if (localItem == null && pull.pending.containsKey(remoteItem.id)) continue;

      final context = conflictDetector.detect(
        localItem: localItem,
        remoteItem: remoteItem,
        userId: userId,
      );

      if (context != null) {
        await _resolvePulledConflict(pull, context, localItem, remoteItem);
        continue;
      }

      // A new item is created. An existing one with no detected conflict is
      // applied only if the remote is *actually* newer — equal versions must
      // not produce redundant update() calls, spurious change events and sync
      // noise/loops. Concurrent edits were already routed to the resolver.
      final target = _pullTarget(localItem, remoteItem, toCreate, toUpdate);
      if (target == null) {
        logger.debug('Skipping remote update for ${remoteItem.id}: local is newer or identical.');
      } else {
        target.add(remoteItem);
        batchBytes += jsonEncode(remoteItem.toDatumMap()).length;
      }

      // Note: syncedCount is not incremented for pull operations in the global sync result
      // as per the design where only push operations contribute to the global synced count

      // Emit progress event less frequently to reduce allocations
      // Only emit every N items or when batch is complete
      final currentTotal = processedCount + i + 1;
      if (currentTotal % config.progressEventFrequency == 0 || i == remoteBatch.length - 1) {
        _record(
          generatedEvents,
          DatumSyncProgressEvent<T>(
            userId: userId,
            completed: currentTotal,
            total: -1, // Unknown total for streaming approach
            bytesPulled: cumulativeBytesSoFar + batchBytes,
          ),
        );
      }
    }

    await _applyPulledWrites(userId, toCreate, toUpdate);
    return batchBytes;
  }

  /// Commits a pull batch's non-conflicting writes in bulk.
  Future<void> _applyPulledWrites(String userId, List<T> toCreate, List<T> toUpdate) async {
    if (toCreate.isNotEmpty) await localAdapter.createAll(toCreate);
    if (toUpdate.isNotEmpty) await localAdapter.updateAll(toUpdate);
    if (toCreate.isNotEmpty || toUpdate.isNotEmpty) hashCache.invalidate(userId);
  }

  /// Routes a pulled item's conflict through the resolver and applies the
  /// outcome locally (and to the push queue when the remote must converge).
  Future<void> _resolvePulledConflict(
    _PullContext<T> pull,
    DatumConflictContext context,
    T? localItem,
    T remoteItem,
  ) async {
    _record(
      pull.events,
      ConflictDetectedEvent<T>(
        userId: pull.userId,
        context: context,
        localData: localItem,
        remoteData: remoteItem,
      ),
    );
    if (!pull.resolve) {
      logger.info('Conflict on ${remoteItem.id} reported but left unresolved (resolveConflicts: false).');
      return;
    }

    final resolution = await pull.resolver.resolve(
      local: localItem,
      remote: remoteItem,
      context: context,
    );

    switch (resolution.strategy) {
      case DatumResolutionStrategy.takeLocal:
        // Local wins, but the remote copy is still divergent: queue a push
        // of the winning local state so the remote converges. Previously
        // nothing was propagated, so the very same conflict re-fired on
        // every subsequent sync and the winner never reached other devices.
        // An unchanged local winner whose own op is still queued needs no
        // extra push: that op delivers it.
        final winner = resolution.resolvedData ?? localItem;
        final alreadyQueued = winner == localItem && pull.pending.containsKey(context.entityId);
        if (winner != null && !alreadyQueued) {
          await _enqueueResolutionPush(pull.userId, winner);
        }
      case DatumResolutionStrategy.takeRemote:
        // Honor a resolver-transformed value (`useRemote(tweaked)`); the raw
        // remoteItem was previously written unconditionally, silently
        // discarding resolvedData.
        await localAdapter.update(resolution.resolvedData ?? remoteItem);
        hashCache.invalidate(pull.userId);
        // The losing local ops must not push over the winner afterwards.
        for (final opId in pull.pending[context.entityId] ?? const <String>[]) {
          await queueManager.dequeue(opId);
        }
      case DatumResolutionStrategy.merge:
        if (resolution.resolvedData == null) {
          throw StateError('Merge resolution must provide a merged item.');
        }
        final merged = resolution.resolvedData!;
        await localAdapter.update(merged);
        hashCache.invalidate(pull.userId);
        // The merged value must also reach the remote, or the merge repeats
        // forever and never propagates to other devices.
        await _enqueueResolutionPush(pull.userId, merged);
      // abort/askUser change nothing — reporting them as "resolved" both
      // inflated conflictsResolved and emitted a misleading resolved event.
      case DatumResolutionStrategy.abort:
        logger.warn('Conflict resolution aborted for ${context.entityId}');
        return;
      case DatumResolutionStrategy.askUser:
        logger.warn(
          'Conflict resolution requires user input for ${context.entityId}',
        );
        return;
    }

    _record(
      pull.events,
      ConflictResolvedEvent<T>(
        userId: pull.userId,
        entityId: context.entityId,
        resolution: resolution,
      ),
    );
    statusSubject.add(
      statusSubject.value.copyWith(
        conflictsResolved: statusSubject.value.conflictsResolved + 1,
      ),
    );
  }

  /// Queues a push of a conflict-resolution winner so the remote (and other
  /// devices) converge on the resolved state.
  Future<void> _enqueueResolutionPush(String userId, T item) async {
    final payload = item.toDatumMap(target: MapTarget.remote);
    await queueManager.enqueue(DatumSyncOperation<T>(
      // Stable per entity: a repeat resolution replaces the queued push
      // instead of piling up another one each pull.
      id: 'conflict-${item.id}',
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
    _eachObserver(switch ((operation.type, operation.data)) {
      (DatumOperationType.create, final T item?) => (o) => o.onCreateStart(item),
      (DatumOperationType.update, final T item?) => (o) => o.onUpdateStart(item),
      (DatumOperationType.delete, _) => (o) => o.onDeleteStart(operation.entityId),
      _ => null,
    });
  }

  void _notifyPostOperationObservers(
    DatumSyncOperation<T> operation, {
    required bool success,
  }) {
    if (eventController.isClosed) return;
    _eachObserver(switch ((operation.type, operation.data)) {
      (DatumOperationType.create, final T item?) => (o) => o.onCreateEnd(item),
      (DatumOperationType.update, final T item?) => (o) => o.onUpdateEnd(item),
      (DatumOperationType.delete, _) => (o) => o.onDeleteEnd(operation.entityId, success: success),
      _ => null,
    });
  }

  void _notifyObservers(DatumSyncEvent<T> event) {
    if (eventController.isClosed) return;
    switch (event) {
      case DatumSyncStartedEvent():
        _eachObserver((o) => o.onSyncStart());
      case DatumSyncCompletedEvent(:final result):
        _eachObserver((o) => o.onSyncEnd(result));
      case ConflictDetectedEvent<T>(localData: final T local?, remoteData: final T remote?, :final context):
        _eachObserver((o) => o.onConflictDetected(local, remote, context));
      case ConflictResolvedEvent<T>(:final resolution):
        for (final observer in localObservers) {
          observer.onConflictResolved(resolution);
        }
        for (final observer in globalObservers) {
          // Global observers expect the generic DatumEntity resolution type.
          observer.onConflictResolved(resolution.copyWithNewType<DatumEntityInterface>());
        }
      case DatumSyncErrorEvent<T>():
        // There's no specific `onSyncError` in the observer; it is treated as
        // `onSyncEnd` so both local and global observers learn the sync ended.
        final errorResult = DatumSyncResult<T>.fromError(event.userId, event.error);
        _eachObserver((o) => o.onSyncEnd(errorResult));
      case _:
        // Other events like progress, conflict, etc.
        break;
    }
  }

  /// Invokes [notify] on every local observer, then every global observer.
  /// A null [notify] means the event has nothing to report.
  void _eachObserver(void Function(DatumObserver<DatumEntityInterface> observer)? notify) {
    if (notify == null) return;
    for (final observer in localObservers) {
      notify(observer);
    }
    for (final observer in globalObservers) {
      notify(observer);
    }
  }

  /// Store size above which the metadata rehash runs on a background isolate.
  static const _isolateHashThreshold = 500;

  Future<void> _updateMetadata(String userId, {bool pulledRemote = true}) async {
    try {
      final (hash: contentHash, count: itemCount) = await _contentHash(userId);
      final existingMetadata = await localAdapter.getSyncMetadata(userId);

      // Persist the cursor staged by a cursor-based pull this cycle. The
      // cursor is per-DEVICE progress: it lives in the LOCAL metadata only
      // and is stripped from the remote beacon — if another device ever
      // adopted a foreign cursor it would silently skip changes it has
      // never seen. Only a PULL cycle may pop it: a push-only cycle
      // persisting a cursor staged by an earlier aborted pull would skip
      // every row behind it forever.
      final stagedCursor = pulledRemote ? _pendingCursors.remove(userId) : null;
      final stagedWatermark = pulledRemote ? _pendingServerWatermarks.remove(userId) : null;
      // Monotonic: overlap re-deliveries can carry older stamps.
      final serverTimestamp = _later(existingMetadata?.serverTimestamp, stagedWatermark);
      final localCustomMetadata = stagedCursor == null ? existingMetadata?.customMetadata : {...?existingMetadata?.customMetadata, syncCursorKey: stagedCursor};
      final remoteCustomMetadata = _withoutCursor(localCustomMetadata);

      final updatedDevices = <String, DateTime>{...?existingMetadata?.devices};
      if (deviceId != null) {
        updatedDevices[deviceId!] = DateTime.now();
      }
      final devices = updatedDevices.isEmpty ? null : updatedDevices;

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
        devices: devices,
        entityCounts: updatedEntityCounts,
        // Preserve other fields from existing metadata or set defaults
        lastSuccessfulSyncTime: DateTime.now(),
        customMetadata: localCustomMetadata,
        syncStatus: SyncStatus.synced,
        syncVersion: existingMetadata?.syncVersion ?? 1,
        serverTimestamp: serverTimestamp,
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
              devices: devices,
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

  /// The local store's order-independent content hash and item count.
  ///
  /// Reuses the cached value when no write chokepoint invalidated it since the
  /// last computation — the common idle auto-sync cycle then skips both the
  /// O(n) readAll and the O(n) rehash.
  Future<({String hash, int count})> _contentHash(String userId) async {
    final cached = config.enableMetadataHashCache ? hashCache.peek(userId) : null;
    if (cached != null) return cached;
    final items = await localAdapter.readAll(userId: userId);
    final maps = [for (final e in items) e.toDatumMap(target: MapTarget.remote)];
    // Canonicalize + SHA-256 per entity is the heavy part: move large
    // stores off the calling (UI) isolate.
    final hash = maps.length < _isolateHashThreshold ? DatumHashGenerator.hashMapsUnordered(maps) : await isolateHelper.run(() => DatumHashGenerator.hashMapsUnordered(maps));
    hashCache.store(userId, hash: hash, count: items.length);
    return (hash: hash, count: items.length);
  }

  /// Performs a health check on the local and remote adapters.
  ///
  /// This method checks the connectivity and the individual health of both
  /// adapters, combines them into a [DatumHealth] object, updates the
  /// status stream, and returns the result.
  Future<DatumHealth> checkHealth() async {
    final [localStatus, remoteStatus] = await Future.wait([localAdapter.checkHealth(), remoteAdapter.checkHealth()]);
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

  /// Groups consecutive batchable operations (same type and user; creates,
  /// deletes and full updates only) into [DatumSyncBatchOperation]s of at most
  /// `remoteSyncBatchSize`.
  List<DatumSyncOperation<T>> _groupOperations(List<DatumSyncOperation<T>> operations, int batchSize) {
    final result = <DatumSyncOperation<T>>[];
    var currentBatch = <DatumSyncOperation<T>>[];

    for (final op in operations) {
      if (currentBatch.isNotEmpty && !(_canBatchWith(currentBatch.last, op) && currentBatch.length < batchSize)) {
        result.add(_collapseBatch(currentBatch));
        currentBatch = [];
      }
      currentBatch.add(op);
    }

    if (currentBatch.isNotEmpty) result.add(_collapseBatch(currentBatch));
    return result;
  }

  Future<int> _processBatchOperation(
    DatumSyncBatchOperation<T> batch, {
    required List<DatumSyncEvent<T>> generatedEvents,
  }) async {
    // A held-back entity's later op must not overtake its failed earlier one:
    // go per-op, where the ordering barrier applies.
    if (batch.operations.any((op) => _blockedEntityIds.contains(op.entityId))) {
      return _processIndividually(batch, generatedEvents);
    }
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
      logger.error(
        'Batch operation ${batch.id} failed: $e — falling back to per-operation processing.',
        stackTrace,
      );

      // A batch call is all-or-nothing from the adapter's perspective, but
      // its operations are NOT: one already-deleted id (EntityNotFound) or
      // one rejected entity must not discard siblings that were never
      // individually attempted. Re-run each operation through the single-op
      // path, which has the full semantics: EntityNotFound tolerance for
      // deletes, update→create conversion, per-op retry accounting, and the
      // per-entity ordering barrier. A permanently failed op is parked and
      // counted (failedOperations) inside that path; the CYCLE still
      // completes so its result carries failedCount > 0 — the contract the
      // metrics layer builds on.
      return _processIndividually(batch, generatedEvents);
    }
  }

  /// Runs a batch's operations one by one through the single-op path; a
  /// permanently failed (parked) op doesn't stop its siblings.
  Future<int> _processIndividually(DatumSyncBatchOperation<T> batch, List<DatumSyncEvent<T>> generatedEvents) async {
    var bytes = 0;
    for (final op in batch.operations) {
      try {
        bytes += await _processPendingOperation(op, generatedEvents: generatedEvents);
      } on SyncExceptionWithEvents<T> catch (permanent) {
        logger.warn(
          'Operation ${op.id} in batch ${batch.id} failed permanently '
          '(${permanent.originalError}); continuing with remaining siblings.',
        );
      }
    }
    return bytes;
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

/// The per-batch state shared by every conflict resolved during a pull.
typedef _PullContext<T extends DatumEntityInterface> = ({
  String userId,
  List<DatumSyncEvent<T>> events,
  DatumConflictResolver<T> resolver,
  // False (`resolveConflicts: false`): conflicts are reported, not resolved.
  bool resolve,
  // entityId -> ids of its still-queued local ops.
  Map<String, List<String>> pending,
});

/// entityId -> ids of its queued ops.
Map<String, List<String>> _opIdsByEntity(List<DatumSyncOperation> ops) {
  final byEntity = <String, List<String>>{};
  for (final op in ops) {
    (byEntity[op.entityId] ??= []).add(op.id);
  }
  return byEntity;
}

/// The later of two optional timestamps (null-tolerant).
DateTime? _later(DateTime? current, DateTime? candidate) {
  if (current == null) return candidate;
  if (candidate == null) return current;
  return candidate.isAfter(current) ? candidate : current;
}

/// [custom] without the device-local sync cursor, or null when nothing remains.
Map<String, dynamic>? _withoutCursor(Map<String, dynamic>? custom) {
  if (custom == null) return null;
  final stripped = {...custom}..remove(DatumSyncEngine.syncCursorKey);
  return stripped.isEmpty ? null : stripped;
}

/// Whether [op] may join a batch whose last operation is [last]: same type
/// and user, and not a delta (patch) update.
bool _canBatchWith<T extends DatumEntityInterface>(DatumSyncOperation<T> last, DatumSyncOperation<T> op) => op.type == last.type && op.userId == last.userId && (op.type != DatumOperationType.update || (op.delta?.isEmpty ?? true));

DatumSyncOperation<T> _collapseBatch<T extends DatumEntityInterface>(List<DatumSyncOperation<T>> batch) => batch.length == 1 ? batch.first : DatumSyncBatchOperation<T>(operations: batch);
