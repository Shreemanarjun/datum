import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
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
import 'package:datum/source/core/query/datum_query.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/utils/hash_generator.dart';
import 'package:datum/source/utils/connectivity_checker.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:datum/source/core/engine/metadata_hash_cache.dart';

import 'package:signals_core/signals_core.dart';

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
  /// The sync status this engine writes as it works. Disposing it is how the
  /// manager tells a running cycle to stop.
  final Signal<DatumSyncStatusSnapshot> statusSignal;

  /// The sync metadata of the last completed cycle; null before the first.
  final Signal<DatumSyncMetadata?> metadataSignal;
  final IsolateHelper isolateHelper;
  final List<DatumObserver<T>> localObservers;
  final List<GlobalDatumObserver> globalObservers;
  final String? deviceId;

  String? _lastActiveUserId;

  String? get lastActiveUserId => _lastActiveUserId;

  /// Returns true if a synchronization process is currently active.
  bool get isSyncing => statusSignal.peek().status == DatumSyncStatus.syncing;

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
    required this.statusSignal,
    required this.metadataSignal,
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
    final snapshot = statusSignal.peek();
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
    final skipped = await _preflightSkip(userId, options, scope, pendingAtStart, snapshot.pendingOperations);
    if (skipped != null) return (skipped, <DatumSyncEvent<T>>[]);

    // Fetch the last sync result to get the previous total byte counts.
    final lastSyncResult = await localAdapter.getLastSyncResult(userId);

    final stopwatch = Stopwatch()..start();

    // Reset the snapshot for the new sync cycle, preserving only the user ID.
    statusSignal.set(
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
      if (statusSignal.disposed) {
        logger.warn(
          'Sync for user $userId was cancelled mid-process due to manager disposal.',
        );
        _discardStagedPullState(userId);
        return (
          DatumSyncResult<T>.cancelled(userId, statusSignal.peek().syncedCount),
          generatedEvents,
        );
      }
      if (statusSignal.peek().status != DatumSyncStatus.syncing) {
        logger.warn(
          'Sync for user $userId was interrupted (status: ${statusSignal.peek().status.name}); reporting a cancelled result.',
        );
        _discardStagedPullState(userId);
        return (await _cycleResult(userId, stopwatch, totals, wasCancelled: true), generatedEvents);
      }

      // Update metadata after a genuinely completed sync cycle.
      await _updateMetadata(userId, pulledRemote: _directionOf(options) != SyncDirection.pushOnly, scopeKey: _scopeKey(scope));

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
    DatumSyncScope? scope,
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

    // An incremental pull asks the server itself what changed since this
    // device's position: one cheap request, and the authority. The metadata
    // comparison below relies on a beacon that only Datum clients write, at
    // the end of a cycle — a writer that was killed before that, or any
    // other writer, leaves it unchanged, and devices that trusted it would
    // show old data until their next local change.
    if (_pullsIncrementally(options, scope)) return null;

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

    // Compare relevant metadata fields for skipping. A scope is compared by
    // the beacon value seen when this device last pulled THAT scope: the
    // beacon says nothing about a scope that was never pulled.
    final key = _scopeKey(scope);
    final metadataMatches = localMetadata != null &&
        remoteMetadata != null &&
        (key.isEmpty
            ? localMetadata.dataHash == remoteMetadata.dataHash && _deepCompareEntityCounts(localMetadata.entityCounts, remoteMetadata.entityCounts)
            : remoteMetadata.dataHash != null && _pullState(localMetadata, key).hash == remoteMetadata.dataHash);

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
    _refusedEntityIds.clear();
    final direction = _directionOf(options);
    final first = switch (direction) {
      SyncDirection.pushThenPull => (pushed: await push(), pulled: await pull()),
      SyncDirection.pullThenPush => (pulled: await pull(), pushed: await push()),
      SyncDirection.pushOnly => (pushed: await push(), pulled: 0),
      SyncDirection.pullOnly => (pushed: 0, pulled: await pull()),
    };
    // The remote refused an upload because the row changed there (see
    // [GuardedWriteCapable]). Settle it now instead of next cycle: read the
    // row if this cycle has not done so since, let the resolver decide, and
    // send what it decided.
    if (_refusedEntityIds.isEmpty || direction == SyncDirection.pushOnly) return first;
    final pulledAgain = direction == SyncDirection.pullThenPush ? await pull() : 0;
    return (pushed: first.pushed + await push(), pulled: first.pulled + pulledAgain);
  }

  Future<DatumSyncResult<T>> _cycleResult(
    String userId,
    Stopwatch stopwatch,
    ({int pushed, int pulled, DatumSyncResult<T>? previous}) totals, {
    bool wasCancelled = false,
  }) async {
    final pending = await queueManager.getPending(userId);
    final status = statusSignal.peek();
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

    statusSignal.set(
      statusSignal.peek().copyWith(
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
    if (!statusSignal.disposed) statusSignal.set(update(statusSignal.peek()));
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
      () => statusSignal.peek().status != DatumSyncStatus.syncing,
      (completed, total) {
        if (!statusSignal.disposed && !eventController.isClosed) {
          // The status should remain 'syncing' while progress is being reported.
          // Only the progress value within the snapshot is updated.
          final progress = total > 0 ? completed / total : 1.0;
          statusSignal.set(
            statusSignal.peek().copyWith(progress: progress),
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
    if (statusSignal.disposed) return 0;
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
      if (statusSignal.disposed) return 0;
      statusSignal.set(
        statusSignal.peek().copyWith(
          syncedCount: statusSignal.peek().syncedCount + 1,
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
    if (e is ConflictException && _isGuarded(operation)) {
      _refuse(operation);
      return 0;
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
    if (_travelsAlone(operation)) return _sendGuarded(operation);
    switch (operation.type) {
      case DatumOperationType.create:
        if (operation.data == null) {
          throw ArgumentError('Create op needs data');
        }
        logger.debug('Creating entity ${operation.entityId} on remote.');
        if ((await _createAll([operation.data!])).isNotEmpty) {
          throw ConflictException(message: 'Entity ${operation.entityId} already exists on the remote.');
        }
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

  /// Whether the remote checks [operation] before applying it: a create must
  /// find no row, an edit must find the row where it started.
  bool _isGuarded(DatumSyncOperation<T> operation) =>
      remoteAdapter is GuardedWriteCapable<T> && (operation.type == DatumOperationType.create || operation.baseVersion != null);

  /// A guarded edit is checked against its own base, so it is sent by
  /// itself. Creates still go out in bulk.
  bool _travelsAlone(DatumSyncOperation<T> operation) => _isGuarded(operation) && operation.type != DatumOperationType.create;

  /// Creates [entities] on the remote; returns the ids a guarded remote
  /// refused because a row was already there.
  Future<Set<String>> _createAll(List<T> entities) async {
    final remote = remoteAdapter;
    if (remote is GuardedWriteCapable<T>) return (remote as GuardedWriteCapable<T>).createAllIfAbsent(entities);
    entities.length == 1 ? await remote.create(entities.single) : await remote.createAll(entities);
    return const {};
  }

  /// Leaves [operation] queued after the remote refused it: not a failure,
  /// another device changed the row first. Nothing later for this entity may
  /// overtake it, and the pull that follows gives both versions to the
  /// resolver.
  void _refuse(DatumSyncOperation<T> operation) {
    logger.info('Upload of ${operation.entityId} refused: the row changed remotely since the edit started.');
    _refusedEntityIds.add(operation.entityId);
    _blockedEntityIds.add(operation.entityId);
    _notifyPostOperationObservers(operation, success: false);
  }

  /// Sends an edit the remote applies only if the row is still where the
  /// edit started. A refusal surfaces as a `ConflictException`.
  Future<void> _sendGuarded(DatumSyncOperation<T> operation) async {
    final guard = remoteAdapter as GuardedWriteCapable<T>;
    final base = operation.baseVersion!;
    if (operation.type == DatumOperationType.delete) {
      try {
        await guard.deleteIfUnchanged(operation.entityId, baseVersion: base, userId: operation.userId);
      } on EntityNotFoundException {
        // Already gone remotely: the delete has nothing left to do.
        logger.warn('Entity ${operation.entityId} not found on remote during delete - considering operation successful');
      }
      return;
    }
    final delta = operation.delta ?? const <String, dynamic>{};
    await guard.patchIfUnchanged(
      id: operation.entityId,
      delta: delta.isNotEmpty ? delta : operation.data!.toDatumMap(target: MapTarget.remote),
      baseVersion: base,
      userId: operation.userId,
    );
  }

  /// Entities whose guarded upload the remote refused this cycle: the row
  /// changed there since the edit started. The edit stays queued; the pull
  /// that follows gives both versions to the resolver.
  final Set<String> _refusedEntityIds = {};

  bool _isForced(DatumSyncOptions<T>? options) => options?.forceFullSync ?? false;

  /// Whether this cycle pulls and can do so incrementally (cursor or delta).
  bool _pullsIncrementally(DatumSyncOptions<T>? options, DatumSyncScope? scope) {
    final remote = remoteAdapter;
    final capable = remote is CursorSyncCapable<T> || remote is DeltaSyncCapable<T>;
    return capable && config.enableDeltaSync && _directionOf(options) != SyncDirection.pushOnly && !_detectsDeletions(options, scope);
  }

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
        if (statusSignal.peek().status != DatumSyncStatus.syncing) break;
      }
    }

    // Process remaining items in the last batch
    if (remoteBatch.isNotEmpty && statusSignal.peek().status == DatumSyncStatus.syncing) {
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
    if (seenRemoteIds != null && statusSignal.peek().status == DatumSyncStatus.syncing) {
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
      if (!statusSignal.disposed) {
        statusSignal.set(
          statusSignal.peek().copyWith(
            conflictsResolved: statusSignal.peek().conflictsResolved + 1,
          ),
        );
      }
    }
  }

  /// The reserved key holding the incremental-pull cursor inside sync
  /// metadata `customMetadata`.
  static const String syncCursorKey = '__sync_cursor__';

  /// The reserved key holding this device's pull state per [DatumSyncScope]
  /// inside sync metadata `customMetadata`: `{scope: {hash, cursor, since}}`.
  ///
  /// A pull position (cursor or watermark) and the "nothing changed" beacon
  /// describe the rows that were asked for. Kept once per device, a sync of
  /// a second scope started from the first scope's position and never read
  /// the rows it had filtered out.
  static const String syncScopesKey = '__sync_scopes__';

  // ponytail: fixed cap; a dropped scope is read in full again. Make it a
  // config value if an app really cycles through more scopes than this.
  static const _maxTrackedScopes = 16;

  /// Identifies [scope] among this device's pull states; empty when the pull
  /// is not narrowed.
  String _scopeKey(DatumSyncScope? scope) {
    final query = scope?.query.toString();
    return query == null || query == const DatumQuery().toString() ? '' : query;
  }

  /// This device's pull state for [scopeKey]. The unscoped state is the
  /// metadata's own fields; a scope's lives under [syncScopesKey].
  ({String? hash, String? cursor, DateTime? since}) _pullState(DatumSyncMetadata? metadata, String scopeKey) {
    final scopes = metadata?.customMetadata?[syncScopesKey] as Map?;
    if (scopeKey.isEmpty) {
      // The sync stamp stands in for a missing watermark only while no
      // scoped pull has moved it without reading everything.
      final since = metadata?.serverTimestamp ?? (scopes == null ? metadata?.lastSyncTime : null);
      return (hash: metadata?.dataHash, cursor: metadata?.customMetadata?[syncCursorKey] as String?, since: since);
    }
    final state = scopes?[scopeKey] as Map?;
    return (hash: state?['hash'] as String?, cursor: state?['cursor'] as String?, since: DateTime.tryParse(state?['since'] as String? ?? ''));
  }

  /// [custom] with the pull position this cycle reached for [scopeKey].
  Map<String, dynamic>? _withPullState(Map<String, dynamic>? custom, String scopeKey, {required String hash, String? cursor, DateTime? since}) {
    if (scopeKey.isEmpty) return cursor == null ? custom : {...?custom, syncCursorKey: cursor};
    final scopes = {...?(custom?[syncScopesKey] as Map?)?.cast<String, dynamic>()};
    final previous = scopes.remove(scopeKey) as Map?;
    // Re-inserted last: the map's order is least recently pulled first.
    scopes[scopeKey] = {
      'hash': hash,
      'cursor': cursor ?? previous?['cursor'],
      'since': _later(DateTime.tryParse(previous?['since'] as String? ?? ''), since)?.toIso8601String(),
    };
    while (scopes.length > _maxTrackedScopes) {
      scopes.remove(scopes.keys.first);
    }
    return {...?custom, syncScopesKey: scopes};
  }

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
      final cursor = _pullState(await localAdapter.getSyncMetadata(userId), _scopeKey(scope)).cursor;
      logger.info('Cursor pull for user $userId (cursor: ${cursor ?? '<start>'}).');
      return _readFeed(remote as CursorSyncCapable<T>, cursor, userId, scope);
    }
    if (remote is! DeltaSyncCapable<T>) return null;
    // The server's own clock when the adapter recorded one, else the local
    // sync stamp; null when this scope was never pulled (read it in full).
    final watermark = _pullState(await localAdapter.getSyncMetadata(userId), _scopeKey(scope)).since;
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
    // In milliseconds, as the conflict detector compares them.
    return remote.modifiedAt.millisecondsSinceEpoch > local.modifiedAt.millisecondsSinceEpoch;
  }

  /// Whether a pulled row must leave the local one alone. A local hard delete
  /// still waiting to upload is not resurrected. And a remote row that has
  /// not moved past the version this device's unsynced edit started from is
  /// not news: the local row is ahead of it and will be pushed. (Treating
  /// that as a conflict let a remote-priority resolver throw the edit away.)
  ///
  /// From a live feed, a row older than the local one is left alone too: it
  /// may only be a late event, and says nothing about what the server holds
  /// now. (A pull does say that, and its older row is a conflict.)
  bool _keepsLocal(T? local, T remote, _PullContext<T> pull) {
    final queued = pull.queued[remote.id] ?? const [];
    if (local == null) return queued.isNotEmpty;
    final base = _baseVersion(queued);
    if (base != null) return remote.version <= base;
    return pull.live && remote.version < local.version;
  }

  /// Drops the queued edits of [remote]'s row that have evidently been
  /// uploaded already: the remote row is exactly the result of one of them,
  /// so it and the edits before it arrived, and only their acknowledgement
  /// was lost (a crash, a dropped connection). Without this, a remote that
  /// guards writes would refuse the replay as stale for ever.
  Future<void> _dropDelivered(_PullContext<T> pull, T remote) async {
    final queued = pull.queued[remote.id];
    if (queued == null) return;
    final landed = queued.lastIndexWhere((op) => _isSameRow(op.data, remote, pull.userId));
    for (final op in queued.sublist(0, landed + 1)) {
      await queueManager.dequeue(op.id);
    }
    queued.removeRange(0, landed + 1);
    if (queued.isEmpty) pull.queued.remove(remote.id);
  }

  /// Same version and same content, as the conflict detector compares them.
  bool _isSameRow(T? a, T b, String userId) => a != null && a.version == b.version && conflictDetector.detect(localItem: a, remoteItem: b, userId: userId) == null;

  /// Whether a detected difference is only the remote being ahead of a row
  /// this device has no unsynced edit of. Nothing was edited here, so there
  /// is nothing to resolve: the newer row is simply taken.
  ///
  /// Rows carrying vector clocks are judged by those instead, and a row
  /// owned by another user is never taken.
  bool _isFastForward(DatumConflictContext context, T? local, T remote, _PullContext<T> pull) {
    if (local == null || context.type == DatumConflictType.userMismatch) return false;
    final clocked = local.vectorClock != null && remote.vectorClock != null;
    return !clocked && remote.version > local.version && !pull.queued.containsKey(remote.id);
  }

  /// Screens rows received from the remote change feed by the rules of a
  /// pull. A row that competes with an unsynced local edit is resolved here.
  /// A row that is identical to, older than, or the starting point of what
  /// this device has is dropped (feeds repeat and reorder events). Returns
  /// the rows to save as they are (new, or newer than a local row with
  /// nothing unsynced) and the conflict events the screening produced.
  Future<({List<T> toSave, List<DatumSyncEvent<T>> events})> screenRemoteChanges(String userId, List<T> items) async {
    final events = <DatumSyncEvent<T>>[];
    final sorted = await _sortRemoteBatch(items, userId, null, events, 0, 0, live: true);
    return (toSave: [...sorted.toCreate, ...sorted.toUpdate], events: events..removeWhere((e) => e is DatumSyncProgressEvent<T>));
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
    final sorted = await _sortRemoteBatch(remoteBatch, userId, options, generatedEvents, processedCount, cumulativeBytesSoFar);
    await _applyPulledWrites(userId, sorted.toCreate, sorted.toUpdate, sorted.deviceOnly);
    return sorted.bytes;
  }

  /// Decides what each remote row means for the local store: resolves the
  /// conflicts, and returns the rows to create or update as they are.
  Future<({List<T> toCreate, List<T> toUpdate, Map<String, Set<String>> deviceOnly, int bytes})> _sortRemoteBatch(
    List<T> remoteBatch,
    String userId,
    DatumSyncOptions<T>? options,
    List<DatumSyncEvent<T>> generatedEvents,
    int processedCount,
    int cumulativeBytesSoFar, {
    bool live = false,
  }) async {
    int batchBytes = 0;
    // Non-conflicting writes are applied in bulk by the caller so adapters
    // with native batching (e.g. one SQLite transaction) commit once per batch.
    final toCreate = <T>[];
    final toUpdate = <T>[];
    final queued = await queueManager.getPending(userId);
    final pull = (
      userId: userId,
      events: generatedEvents,
      resolver: options?.conflictResolver ?? conflictResolver,
      resolve: options?.resolveConflicts ?? true,
      queued: queued.groupListsBy((op) => op.entityId),
      live: live,
    );

    // Get local items for this batch only
    final localItemsMap = await localAdapter.readByIds(
      remoteBatch.map((e) => e.id).toList(),
      userId: userId,
    );

    for (var i = 0; i < remoteBatch.length; i++) {
      final remoteItem = remoteBatch[i];
      final localItem = localItemsMap[remoteItem.id];
      await _dropDelivered(pull, remoteItem);
      if (_keepsLocal(localItem, remoteItem, pull)) continue;

      final context = conflictDetector.detect(
        localItem: localItem,
        remoteItem: remoteItem,
        userId: userId,
      );

      if (context != null && !_isFastForward(context, localItem, remoteItem, pull)) {
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

    return (toCreate: toCreate, toUpdate: toUpdate, deviceOnly: _deviceOnlyOf(toUpdate, localItemsMap), bytes: batchBytes);
  }

  /// id -> the device-only fields of the local row each update will replace.
  Map<String, Set<String>> _deviceOnlyOf(List<T> toUpdate, Map<String, T> locals) => {
        for (final item in toUpdate)
          if (locals[item.id]?.deviceOnlyFields case final fields? when fields.isNotEmpty) item.id: fields,
      };

  /// Commits a pull batch's non-conflicting writes in bulk.
  Future<void> _applyPulledWrites(String userId, List<T> toCreate, List<T> toUpdate, Map<String, Set<String>> deviceOnly) async {
    if (toCreate.isNotEmpty) await localAdapter.createAll(toCreate);
    final replaced = [
      for (final item in toUpdate)
        if (!deviceOnly.containsKey(item.id)) item
    ];
    if (replaced.isNotEmpty) await localAdapter.updateAll(replaced);
    for (final item in toUpdate) {
      final keep = deviceOnly[item.id];
      if (keep != null) await _patchShared(item, keep);
    }
    if (toCreate.isNotEmpty || toUpdate.isNotEmpty) hashCache.invalidate(userId);
  }

  /// Saves [remote] over the local row, leaving the [keep] fields (the local
  /// row's device-only ones, which a remote row never carries) as they are.
  Future<void> _patchShared(T remote, Set<String> keep) =>
      localAdapter.patch(id: remote.id, delta: remote.toDatumMap()..removeWhere((key, _) => keep.contains(key)), userId: remote.userId);

  /// Saves [remote] over [local], keeping [local]'s device-only fields.
  Future<void> _replaceLocal(T remote, T? local) async {
    final keep = local?.deviceOnlyFields ?? const <String>{};
    keep.isEmpty ? await localAdapter.update(remote) : await _patchShared(remote, keep);
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
        final winner = resolution.resolvedData ?? localItem;
        if (winner != null) await _queueWinner(pull, winner, remoteItem.version);
      case DatumResolutionStrategy.takeRemote:
        // Honor a resolver-transformed value (`useRemote(tweaked)`); the raw
        // remoteItem was previously written unconditionally, silently
        // discarding resolvedData.
        await _replaceLocal(resolution.resolvedData ?? remoteItem, localItem);
        hashCache.invalidate(pull.userId);
        // The losing local ops must not push over the winner afterwards.
        await _dropQueued(pull, context.entityId);
      case DatumResolutionStrategy.merge:
        if (resolution.resolvedData == null) {
          throw StateError('Merge resolution must provide a merged item.');
        }
        final merged = resolution.resolvedData!;
        await localAdapter.update(merged);
        hashCache.invalidate(pull.userId);
        // The merged value must also reach the remote, or the merge repeats
        // forever and never propagates to other devices.
        await _queueWinner(pull, merged, remoteItem.version);
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
    statusSignal.set(
      statusSignal.peek().copyWith(
        conflictsResolved: statusSignal.peek().conflictsResolved + 1,
      ),
    );
  }

  /// Removes every operation queued for [entityId]: the resolver's decision
  /// replaces what they would have uploaded.
  Future<void> _dropQueued(_PullContext<T> pull, String entityId) async {
    for (final op in pull.queued.remove(entityId) ?? const []) {
      await queueManager.dequeue(op.id);
    }
  }

  /// Makes [winner] the one thing queued for its row: the edits queued
  /// before were made against a remote row that has since changed (a guarded
  /// remote would refuse them again), and the winner already holds their
  /// outcome.
  Future<void> _queueWinner(_PullContext<T> pull, T winner, int remoteVersion) async {
    await _dropQueued(pull, winner.id);
    await _enqueueResolutionPush(pull.userId, winner, baseVersion: remoteVersion);
  }

  /// Queues a push of a conflict-resolution winner so the remote (and other
  /// devices) converge on the resolved state.
  ///
  /// [baseVersion] is the remote version the resolver saw: while the remote
  /// stays there, the queued winner is not in conflict with it again.
  Future<void> _enqueueResolutionPush(String userId, T item, {int? baseVersion}) async {
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
      baseVersion: baseVersion,
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

  Future<void> _updateMetadata(String userId, {bool pulledRemote = true, String scopeKey = ''}) async {
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
      // A scoped pull read only part of the data: it records its own
      // position and leaves the unscoped one (the metadata's own fields)
      // describing the last full reconciliation.
      final reconciledAll = pulledRemote && scopeKey.isEmpty;
      // Monotonic: overlap re-deliveries can carry older stamps.
      final serverTimestamp = _later(existingMetadata?.serverTimestamp, stagedWatermark);
      final localCustomMetadata = pulledRemote ? _withPullState(existingMetadata?.customMetadata, scopeKey, hash: contentHash, cursor: stagedCursor, since: stagedWatermark) : existingMetadata?.customMetadata;
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
      final localMetadata = reconciledAll
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
      if (!metadataSignal.disposed) {
        metadataSignal.set(localMetadata);
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
    statusSignal.set(statusSignal.peek().copyWith(health: health));

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
      // A guarded edit is checked against its own base: it travels alone.
      final batchable = currentBatch.isEmpty || (!_travelsAlone(op) && !_travelsAlone(currentBatch.last) && _canBatchWith(currentBatch.last, op) && currentBatch.length < batchSize);
      if (!batchable) {
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
      var refused = const <String>{};
      switch (batch.type) {
        case DatumOperationType.create:
          final entities = batch.operations.map((op) => op.data!).toList();
          refused = await _createAll(entities);
        case DatumOperationType.update:
          final entities = batch.operations.map((op) => op.data!).toList();
          await remoteAdapter.updateAll(entities);
        case DatumOperationType.delete:
          final ids = batch.operations.map((op) => op.entityId).toList();
          await remoteAdapter.deleteAll(ids, userId: batch.userId);
      }

      for (final op in batch.operations) {
        if (refused.contains(op.entityId)) {
          _refuse(op);
          continue;
        }
        await queueManager.dequeue(op.id);
        _notifyPostOperationObservers(op, success: true);
      }

      if (!statusSignal.disposed) {
        statusSignal.set(
          statusSignal.peek().copyWith(
            syncedCount: statusSignal.peek().syncedCount + batch.operations.length - refused.length,
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
  // entityId -> its still-queued local edits, oldest first.
  Map<String, List<DatumSyncOperation<T>>> queued,
  // The rows come from a change feed, not from a read of the remote.
  bool live,
});

/// The version a row's queued edits started from (the oldest one's base);
/// null when any of them does not know: a create, or an operation queued by
/// a build that did not record it.
int? _baseVersion(List<DatumSyncOperation> queued) {
  int? base;
  for (final op in queued) {
    final opBase = op.baseVersion;
    if (opBase == null) return null;
    if (base == null || opBase < base) base = opBase;
  }
  return base;
}

/// The later of two optional timestamps (null-tolerant).
DateTime? _later(DateTime? current, DateTime? candidate) {
  if (current == null) return candidate;
  if (candidate == null) return current;
  return candidate.isAfter(current) ? candidate : current;
}

/// [custom] without the device-local pull positions (the cursor and the
/// per-scope states), or null when nothing remains.
Map<String, dynamic>? _withoutCursor(Map<String, dynamic>? custom) {
  if (custom == null) return null;
  final stripped = {...custom}
    ..remove(DatumSyncEngine.syncCursorKey)
    ..remove(DatumSyncEngine.syncScopesKey);
  return stripped.isEmpty ? null : stripped;
}

/// Whether [op] may join a batch whose last operation is [last]: same type
/// and user, and not a delta (patch) update.
bool _canBatchWith<T extends DatumEntityInterface>(DatumSyncOperation<T> last, DatumSyncOperation<T> op) => op.type == last.type && op.userId == last.userId && (op.type != DatumOperationType.update || (op.delta?.isEmpty ?? true));

DatumSyncOperation<T> _collapseBatch<T extends DatumEntityInterface>(List<DatumSyncOperation<T>> batch) => batch.length == 1 ? batch.first : DatumSyncBatchOperation<T>(operations: batch);
