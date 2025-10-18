import 'dart:async';

import 'package:collection/collection.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/engine/conflict_detector.dart';
import 'package:datum/source/core/engine/datum_core.dart';
import 'package:datum/source/core/engine/datum_observer.dart';
import 'package:datum/source/core/engine/datum_sync_engine.dart';
import 'package:datum/source/core/engine/isolate_helper.dart';
import 'package:datum/source/core/engine/queue_manager.dart';
import 'package:datum/source/core/events/conflict_detected_event.dart';
import 'package:datum/source/core/events/data_change_event.dart';
import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/events/user_switched_event.dart';
import 'package:datum/source/core/health/datum_health.dart' show DatumHealth;
import 'package:datum/source/core/middleware/datum_middleware.dart';
import 'package:datum/source/core/migration/migration_executor.dart';
import 'package:datum/source/core/models/datum_change_detail.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_exception.dart';
import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_pagination.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/models/datum_sync_options.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:datum/source/core/models/datum_sync_scope.dart';
import 'package:datum/source/core/models/datum_sync_status_snapshot.dart';
import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:datum/source/core/models/user_switch_models.dart';
import 'package:datum/source/core/query/datum_query.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/resolver/last_write_wins_resolver.dart';
import 'package:datum/source/utils/connectivity_checker.dart';
import 'package:datum/source/utils/datum_logger.dart';

class DatumManager<T extends DatumEntity> {
  final LocalAdapter<T> localAdapter;
  final RemoteAdapter<T> remoteAdapter;

  bool _initialized = false;
  bool _disposed = false;

  // Core dependencies
  final DatumConflictResolver<T> _conflictResolver;
  final DatumConfig<T> _config;
  final DatumConnectivityChecker _connectivity;
  final DatumLogger _logger;
  final List<DatumObserver<T>> _localObservers = [];
  final List<GlobalDatumObserver> _globalObservers = [];
  final List<DatumMiddleware<T>> _middlewares = [];

  // Internal state management
  final StreamController<DatumSyncEvent<T>> _eventController =
      StreamController.broadcast();
  final BehaviorSubject<DatumSyncStatusSnapshot> _statusSubject;
  final BehaviorSubject<DatumSyncMetadata> _metadataSubject = BehaviorSubject();
  final Map<String, Timer> _autoSyncTimers = {};

  /// A cache to track recently processed external change IDs to prevent echoes
  /// and de-duplicate events. The key is the entity ID.
  final Map<String, DateTime> _recentChangeCache = {};

  late final QueueManager<T> _queueManager;
  late final IsolateHelper _isolateHelper;
  late final DatumConflictDetector<T> _conflictDetector;
  late final DatumSyncEngine<T> _syncEngine;

  /// Exposes the queue manager for central orchestration.
  QueueManager<T> get queueManager => _queueManager;

  StreamSubscription<DatumChangeDetail<T>>? _localChangeSubscription;
  StreamSubscription<dynamic>? _remoteChangeSubscription;

  /// Public event streams
  Stream<DatumSyncEvent<T>> get eventStream => _eventController.stream;
  Stream<DataChangeEvent<T>> get onDataChange =>
      eventStream.whereType<DataChangeEvent<T>>();
  Stream<DatumSyncStartedEvent<T>> get onSyncStarted =>
      eventStream.whereType<DatumSyncStartedEvent<T>>();
  Stream<DatumSyncProgressEvent<T>> get onSyncProgress =>
      eventStream.whereType<DatumSyncProgressEvent<T>>();
  Stream<DatumSyncCompletedEvent<T>> get onSyncCompleted =>
      eventStream.whereType<DatumSyncCompletedEvent<T>>();
  Stream<ConflictDetectedEvent<T>> get onConflict =>
      eventStream.whereType<ConflictDetectedEvent<T>>();
  Stream<UserSwitchedEvent<T>> get onUserSwitched =>
      eventStream.whereType<UserSwitchedEvent<T>>();
  Stream<DatumSyncErrorEvent<T>> get onSyncError =>
      eventStream.whereType<DatumSyncErrorEvent<T>>();

  /// A stream of the manager's current health status.
  Stream<DatumHealth> get health => _statusSubject.stream.map((s) => s.health);

  /// The most recent snapshot of the manager's sync status.
  DatumSyncStatusSnapshot get currentStatus => _statusSubject.value;

  DatumManager({
    required this.localAdapter,
    required this.remoteAdapter,
    DatumConflictResolver<T>? conflictResolver,
    required DatumConnectivityChecker connectivity,
    DatumConfig<T>? datumConfig,
    DatumLogger? logger,
    List<DatumObserver<T>>? localObservers,
    List<DatumMiddleware<T>>? middlewares,
    List<GlobalDatumObserver>? globalObservers,
  })  : _config = datumConfig ?? const DatumConfig(),
        _connectivity = connectivity,
        _statusSubject = BehaviorSubject.seeded(
          DatumSyncStatusSnapshot.initial(''),
        ),
        // The logger's enabled status should always respect the config.
        _logger = (logger ?? DatumLogger())
            .copyWith(enabled: datumConfig?.enableLogging ?? true),
        _conflictResolver = conflictResolver ?? LastWriteWinsResolver<T>() {
    _localObservers.addAll(localObservers ?? []);
    _globalObservers.addAll(globalObservers ?? []);
    _middlewares.addAll(middlewares ?? []);

    _initializeInternalComponents();
  }

  void _initializeInternalComponents() {
    _conflictDetector = DatumConflictDetector<T>();
    _isolateHelper = IsolateHelper();
    _queueManager = QueueManager<T>(
      localAdapter: localAdapter,
      logger: _logger,
    );
    _syncEngine = DatumSyncEngine<T>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
      conflictResolver: _conflictResolver,
      queueManager: _queueManager,
      conflictDetector: _conflictDetector,
      logger: _logger,
      config: _config,
      connectivityChecker: _connectivity,
      eventController: _eventController,
      statusSubject: _statusSubject,
      metadataSubject: _metadataSubject,
      isolateHelper: _isolateHelper,
      localObservers: _localObservers,
      globalObservers: _globalObservers,
    );
  }

  /// Initializes the manager and its adapters. Must be called before any other methods.
  Future<void> initialize() async {
    if (_initialized) return;
    if (_disposed) throw StateError('Cannot initialize a disposed manager.');

    await localAdapter.initialize();
    await _runSchemaMigrations();
    await _isolateHelper.initialize();
    await remoteAdapter.initialize();

    _initialized = true;
    _logger.info('DatumManager for $T initialized.');

    // Start auto-sync after the manager is fully initialized.
    await _setupAutoSyncIfEnabled();

    // Subscribe to external changes
    _subscribeToChangeStreams();

    // Subscribe to internal events to notify observers
    // _listenToEvents(); // This is now handled synchronously in synchronize()
  }

  Future<void> _runSchemaMigrations() async {
    // ... (rest of the method is unchanged)
    final executor = MigrationExecutor(
      localAdapter: localAdapter,
      migrations: _config.migrations,
      targetVersion: _config.schemaVersion,
      logger: _logger,
    );
    try {
      if (await executor.needsMigration()) {
        await executor.execute();
      }
    } on Object catch (e, stack) {
      _logger.error('Schema migration failed: $e', stack);
      if (_config.onMigrationError != null) {
        await _config.onMigrationError!(e, stack);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _setupAutoSyncIfEnabled() async {
    if (!_config.autoStartSync) return;

    _logger.debug('Auto-start sync enabled, discovering users');
    if (_config.initialUserId != null) {
      final userId = _config.initialUserId!;
      if (userId.isNotEmpty) {
        _logger.info('Auto-sync starting for initial user: $userId');
        // Perform an initial sync, but don't block initialization if it fails.
        unawaited(
          synchronize(
            userId,
          ).catchError((_) => DatumSyncResult.skipped(userId, 0)),
        );
        startAutoSync(userId);
      }
    } else {
      final userIds = await localAdapter.getAllUserIds();
      _logger.info(
        'Auto-sync starting for ${userIds.length} discovered users.',
      );

      // Sequentially perform an initial sync for all discovered users.
      for (final userId in userIds) {
        if (userId.isNotEmpty) {
          // We await here to prevent race conditions on the shared sync engine.
          try {
            await synchronize(userId);
          } catch (e, stack) {
            _logger.error(
              'Initial auto-sync for user $userId failed: $e',
              stack,
            );
          }
        }
      }
      // Now, start the periodic timers for all users.
      for (final userId in userIds) {
        if (userId.isNotEmpty) startAutoSync(userId);
      }
      _logger.info(
        'Periodic auto-sync timers started for ${userIds.length} discovered users.',
      );
    }
  }

  void _subscribeToChangeStreams() {
    // Subscribe to local changes
    _localChangeSubscription = localAdapter.changeStream()?.listen((change) {
      // Wrap the single local change in a list to match the handler's signature.
      _handleExternalChange([change], DataSource.local);
    }, onError: (e, s) => _logger.error('Error in local change stream', s));

    // Subscribe to remote changes.
    final remoteStream = remoteAdapter.changeStream;
    if (remoteStream == null) return;

    // If a debounce time is configured, buffer events for performance.
    if (_config.remoteEventDebounceTime > Duration.zero) {
      _remoteChangeSubscription = remoteStream
          .bufferTime(_config.remoteEventDebounceTime)
          .where((batch) => batch.isNotEmpty)
          .listen(
            (changeList) =>
                _handleExternalChange(changeList, DataSource.remote),
            onError: (e, s) =>
                _logger.error('Error in remote change stream', s),
          );
    } else {
      // Otherwise, process events individually. This is better for tests.
      _remoteChangeSubscription = remoteStream.listen((change) {
        _handleExternalChange([change], DataSource.remote);
      }, onError: (e, s) => _logger.error('Error in remote change stream', s));
    }
  }

  /// Handles changes originating from outside the manager's direct control.
  Future<void> _handleExternalChange(
    List<DatumChangeDetail<T>> changes,
    DataSource source,
  ) async {
    if (_disposed) return;

    // 1. Clean up the cache to remove old entries.
    _cleanupChangeCache();

    // 2. Filter out changes that have been recently processed.
    final newChanges = changes.whereNot((c) {
      final isRecent = _recentChangeCache.containsKey(c.entityId);
      if (isRecent) {
        _logger.debug(
          'Ignoring duplicate external change for entity ${c.entityId}',
        );
      }
      return isRecent;
    }).toList();

    if (newChanges.isEmpty) {
      return;
    }

    _logger.info(
      'Processing ${newChanges.length} new external change(s) from $source.',
    );

    // 3. Process all new changes.
    for (final change in newChanges) {
      // Add to cache *before* processing to handle race conditions.
      _recentChangeCache[change.entityId] = DateTime.now();

      try {
        if (change.type == DatumOperationType.delete) {
          // For an external delete, we bypass the main `delete` method's
          // preliminary read. We trust the event and directly call the
          // local adapter to perform the deletion. This is more efficient
          // and avoids the incorrect `read` call seen in the test failure.
          _logger.debug(
            'Applying external delete for ${change.entityId} directly to local adapter.',
          );
          final deleted = await localAdapter.delete(
            change.entityId,
            userId: change.userId,
          );
          if (deleted) {
            _eventController.add(
              DataChangeEvent<T>(
                userId: change.userId,
                // We don't have the full data for a delete event, so this is null.
                data: change.data,
                changeType: ChangeType.deleted,
                source: source,
              ),
            );
          }
        } else if (change.data != null) {
          // If change is from remote, just save locally.
          // If from local, it's an external change, so queue it for remote.
          await push(
            item: change.data!,
            userId: change.userId,
            source: source, // Let push handle the logic
          );
        }
      } on Object catch (e, stack) {
        _logger.error(
          'Failed to process external change for ${change.entityId} from $source: $e',
          stack,
        );
        // Remove from cache on failure so it can be retried if the event arrives again.
        _recentChangeCache.remove(change.entityId);
      }
    }
  }

  void _processSyncEvents(List<DatumSyncEvent<T>> events) {
    for (final event in events) {
      if (_eventController.isClosed) return;
      _eventController.add(event);
    }
  }

  void _cleanupChangeCache() {
    final cacheExpiry = DateTime.now().subtract(_config.changeCacheDuration);
    _recentChangeCache.removeWhere((key, timestamp) {
      return timestamp.isBefore(cacheExpiry);
    });
  }

  Future<T> push({
    required T item,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
  }) async {
    _ensureInitialized();
    // Check for user switch before proceeding.
    await _syncEngine.checkForUserSwitch(userId);

    final existing = await localAdapter.read(item.id, userId: userId);
    final isCreate = existing == null;

    final transformed = await _applyPreSaveTransforms(item);

    Map<String, dynamic>? delta;
    if (!isCreate) {
      delta = transformed.diff(existing);
      if (delta == null) {
        _logger.debug(
          'No changes detected for entity ${item.id}, skipping save.',
        );
        return transformed;
      }
    }

    if (isCreate) {
      _logger.debug('Notifying observers of onCreateStart for ${item.id}');
      for (final observer in _localObservers) {
        observer.onCreateStart(transformed);
      }
      for (final observer in _globalObservers) {
        observer.onCreateStart(transformed);
      }
      await localAdapter.create(transformed);
    } else if (delta != null) {
      // If a delta is available, perform a more efficient patch.
      _logger.debug('Notifying observers of onUpdateStart for ${item.id}');
      for (final observer in _localObservers) {
        observer.onUpdateStart(transformed);
      }
      for (final observer in _globalObservers) {
        observer.onUpdateStart(transformed);
      }
      await localAdapter.patch(
        id: transformed.id,
        delta: delta,
        userId: userId,
      );
    } else {
      // Fallback to a full update if no delta is calculated.
      _logger.debug('Notifying observers of onUpdateStart for ${item.id}');
      for (final observer in _localObservers) {
        observer.onUpdateStart(transformed);
      }
      for (final observer in _globalObservers) {
        observer.onUpdateStart(transformed);
      }
      await localAdapter.update(transformed);
    }

    if (source == DataSource.local || forceRemoteSync) {
      final operation = _createOperation(
        userId: userId,
        type: isCreate ? DatumOperationType.create : DatumOperationType.update,
        entityId: transformed.id,
        data: transformed,
        delta: delta,
      );
      await _queueManager.enqueue(operation);
    }

    _eventController.add(
      DataChangeEvent<T>(
        userId: userId,
        data: transformed,
        changeType: isCreate ? ChangeType.created : ChangeType.updated,
        source: source,
      ),
    );

    if (isCreate) {
      _logger.debug('Notifying observers of onCreateEnd for ${item.id}');
      for (final observer in _localObservers) {
        observer.onCreateEnd(transformed);
      }
      for (final observer in _globalObservers) {
        observer.onCreateEnd(transformed);
      }
    } else {
      _logger.debug('Notifying observers of onUpdateEnd for ${item.id}');
      for (final observer in _localObservers) {
        observer.onUpdateEnd(transformed);
      }
      for (final observer in _globalObservers) {
        observer.onUpdateEnd(transformed);
      }
    }
    return transformed;
  }

  /// Reads a single entity by its ID from the primary local adapter.
  Future<T?> read(String id, {String? userId}) async {
    _ensureInitialized();
    final entity = await localAdapter.read(id, userId: userId);
    if (entity == null) return null;
    return _applyPostFetchTransforms(entity);
  }

  /// Reads all entities from the primary local adapter.
  Future<List<T>> readAll({String? userId}) async {
    _ensureInitialized();
    final entities = await localAdapter.readAll(userId: userId);
    return Future.wait(entities.map(_applyPostFetchTransforms));
  }

  /// Watches all entities from the local adapter, emitting a new list on any change.
  /// Returns null if the adapter does not support reactive queries.
  Stream<List<T>>? watchAll({String? userId}) {
    _ensureInitialized();
    return localAdapter
        .watchAll(userId: userId)
        ?.asyncMap((list) => Future.wait(list.map(_applyPostFetchTransforms)));
  }

  /// Watches a single entity by its ID, emitting the item on change or null if deleted.
  /// Returns null if the adapter does not support reactive queries.
  Stream<T?>? watchById(String id, String? userId) {
    _ensureInitialized();
    return localAdapter.watchById(id, userId: userId)?.asyncMap((item) {
      if (item == null) {
        return Future.value(null);
      }
      return _applyPostFetchTransforms(item);
    });
  }

  /// Watches a paginated list of items.
  /// Returns null if the adapter does not support reactive queries.
  Stream<PaginatedResult<T>>? watchAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) {
    _ensureInitialized();
    return localAdapter.watchAllPaginated(config, userId: userId);
  }

  /// Watches a subset of items matching a query.
  /// Returns null if the adapter does not support reactive queries.
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) {
    _ensureInitialized();
    return localAdapter
        .watchQuery(query, userId: userId)
        ?.asyncMap((list) => Future.wait(list.map(_applyPostFetchTransforms)));
  }

  /// Executes a one-time query against the specified data source.
  ///
  /// This provides a powerful way to fetch filtered and sorted data directly
  /// from either the local or remote adapter without relying on reactive streams.
  Future<List<T>> query(
    DatumQuery query, {
    required DataSource source,
    String? userId,
  }) async {
    _ensureInitialized();
    final adapter =
        (source == DataSource.local ? localAdapter : remoteAdapter) as dynamic;
    final entities = await adapter.query(query, userId: userId) as List<T>;
    return Future.wait(entities.map(_applyPostFetchTransforms));
  }

  /// Deletes an entity by its ID from all local and remote adapters.
  Future<bool> delete({
    required String id,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
  }) async {
    _ensureInitialized();
    // Check for user switch before proceeding.
    await _syncEngine.checkForUserSwitch(userId);

    final existing = await localAdapter.read(id, userId: userId);
    if (existing == null) {
      _logger.debug(
        'Entity $id does not exist for user $userId, skipping delete',
      );
      return false;
    }

    _logger.debug('Notifying observers of onDeleteStart for $id');
    for (final observer in _localObservers) {
      observer.onDeleteStart(id);
    }
    for (final observer in _globalObservers) {
      observer.onDeleteStart(id);
    }
    final deleted = await localAdapter.delete(id, userId: userId);
    if (!deleted) {
      _logger.warn('Local adapter failed to delete entity $id');
      // Notify observers of the failure before returning.
      for (final observer in _localObservers) {
        observer.onDeleteEnd(id, success: false);
      }
      for (final observer in _globalObservers) {
        observer.onDeleteEnd(id, success: false);
      }
      return false;
    }

    _logger.debug('Notifying observers of onDeleteEnd for $id');
    for (final observer in _localObservers) {
      observer.onDeleteEnd(id, success: true);
    }
    for (final observer in _globalObservers) {
      observer.onDeleteEnd(id, success: true);
    }
    if (source == DataSource.local || forceRemoteSync) {
      final operation = _createOperation(
        userId: userId,
        type: DatumOperationType.delete,
        entityId: id,
      );
      await _queueManager.enqueue(operation);
    }

    _eventController.add(
      DataChangeEvent<T>(
        userId: userId,
        data: existing,
        changeType: ChangeType.deleted,
        source: source,
      ),
    );

    return true;
  }

  /// Fetches related entities for a given parent entity.
  ///
  /// - [parent]: The entity instance for which to fetch related data. This
  ///   must be an instance of [RelationalDatumEntity].
  /// - [relationName]: The name of the relation to fetch, as defined in the
  ///   parent's `belongsTo` or `manyToMany` maps.
  /// - [source]: The [DataSource] to fetch from (defaults to `local`).
  ///
  /// Returns a list of the related entities. Throws an [ArgumentError] if the
  /// parent is not a [RelationalDatumEntity], or an [Exception] if the
  /// relation name is not defined on the parent.
  Future<List<R>> fetchRelated<R extends DatumEntity>(
    T parent,
    String relationName, {
    DataSource source = DataSource.local,
  }) async {
    _ensureInitialized();

    if (parent is! RelationalDatumEntity) {
      throw ArgumentError(
        'The parent entity must be a RelationalDatumEntity to fetch relations.',
      );
    }

    final relation = parent.relations[relationName];
    if (relation == null) {
      throw Exception(
        'Relation "$relationName" is not defined on entity type ${parent.runtimeType}.',
      );
    }

    final relatedManager = Datum.manager<R>();

    switch (source) {
      case DataSource.local:
        return localAdapter.fetchRelated(
          parent,
          relationName,
          relatedManager.localAdapter,
        );
      case DataSource.remote:
        return remoteAdapter.fetchRelated(
          parent,
          relationName,
          relatedManager.remoteAdapter,
        );
    }
  }

  /// Reactively watches related entities for a given parent entity.
  ///
  /// This method provides a stream of related entities that automatically
  /// updates when the underlying data changes.
  ///
  /// - [parent]: The entity instance for which to watch related data.
  /// - [relationName]: The name of the relation to watch.
  ///
  /// Returns a `Stream<List<R>>` of the related entities, or `null` if the
  /// adapter does not support reactive queries. Throws an error if the
  /// relation is not defined.
  Stream<List<R>>? watchRelated<R extends DatumEntity>(
    T parent,
    String relationName,
  ) {
    _ensureInitialized();

    if (parent is! RelationalDatumEntity) {
      throw ArgumentError(
        'The parent entity must be a RelationalDatumEntity to watch relations.',
      );
    }

    final relation = parent.relations[relationName];
    if (relation == null) {
      throw Exception(
        'Relation "$relationName" is not defined on entity type ${parent.runtimeType}.',
      );
    }

    final relatedManager = Datum.manager<R>();

    return localAdapter.watchRelated(
      parent,
      relationName,
      relatedManager.localAdapter,
    );
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('DatumManager must be initialized before use.');
    }
    if (_disposed) {
      throw StateError('Cannot operate on a disposed manager.');
    }
  }

  Future<DatumSyncResult> synchronize(
    String userId, {
    DatumSyncOptions? options,
    DatumSyncScope? scope,
  }) async {
    _ensureInitialized();

    // Handle user switching logic before proceeding with synchronization.
    if (_syncEngine.lastActiveUserId != null &&
        _syncEngine.lastActiveUserId != userId) {
      if (_config.defaultUserSwitchStrategy ==
          UserSwitchStrategy.promptIfUnsyncedData) {
        final oldUserOps = await _queueManager.getPending(
          _syncEngine.lastActiveUserId!,
        );
        if (oldUserOps.isNotEmpty) {
          throw UserSwitchException(
            _syncEngine.lastActiveUserId,
            userId,
            'Cannot switch user while unsynced data exists for the previous user.',
          );
        }
      }
      // Other strategies like syncThenSwitch or clearAndFetch would be handled here.
    }

    try {
      // Convert options to the correct type if needed.
      // This handles cases where options might be passed with a different generic type from Datum.
      final typedOptions = options != null
          ? DatumSyncOptions<T>(
              includeDeletes: options.includeDeletes,
              resolveConflicts: options.resolveConflicts,
              forceFullSync: options.forceFullSync,
              overrideBatchSize: options.overrideBatchSize,
              timeout: options.timeout,
              direction: options.direction,
              conflictResolver:
                  options.conflictResolver is DatumConflictResolver<T>
                      ? options.conflictResolver as DatumConflictResolver<T>
                      : null,
            )
          : null;

      // If the direction is pushOnly and there are no pending operations,
      // we can skip the sync entirely for this manager.
      if (typedOptions?.direction == SyncDirection.pushOnly &&
          await getPendingCount(userId) == 0) {
        _logger.info(
            'Push-only sync for user $userId skipped: no pending operations.');
        return DatumSyncResult.skipped(userId, 0);
      }

      final (result, events) = await _syncEngine.synchronize(
        userId,
        options: typedOptions,
        scope: scope,
      );
      _processSyncEvents(events);
      return result;
    } on Object catch (e, stack) {
      // This block handles a special case where the sync engine fails but
      // needs to communicate events (like DatumSyncErrorEvent) back to the
      // manager before the top-level Future completes with an error.

      // If the error is already our special type, it came from the main
      // isolate. If not, it likely came from a worker isolate and lost its
      // type, so we need to re-wrap it.
      final SyncExceptionWithEvents<T> wrappedException =
          e is SyncExceptionWithEvents<T>
              ? e
              : SyncExceptionWithEvents(e, stack, []);

      _processSyncEvents(wrappedException.events);

      // CRITICAL: Re-throw the original error asynchronously.
      // Using `return Future.error` instead of a synchronous `throw` is
      // essential to prevent a race condition in tests. It ensures that the
      // event stream has a chance to deliver the `DatumSyncErrorEvent`
      // (processed in the line above) to its listeners *before* the Future
      // returned by `synchronize()` completes with an error. Without this,
      // a test awaiting both the event and the thrown exception might see
      // the exception first and terminate before the event is received,
      // leading to a timeout.
      return Future.error(
        wrappedException.originalError,
        wrappedException.originalStackTrace,
      );
    }
  }

  /// Switches the active user with configurable handling of unsynced data.
  ///
  /// **Strategies:**
  /// - [UserSwitchStrategy.syncThenSwitch]: Sync old user before switching
  /// - [UserSwitchStrategy.clearAndFetch]: Clear new user's local data
  /// - [UserSwitchStrategy.promptIfUnsyncedData]: Fail if old user has
  ///   pending ops
  /// - [UserSwitchStrategy.keepLocal]: Switch without modifications
  ///
  /// Returns [DatumUserSwitchResult] indicating success or failure with details.
  Future<DatumUserSwitchResult> switchUser({
    required String? oldUserId,
    required String newUserId,
    UserSwitchStrategy? strategy,
  }) async {
    _ensureInitialized();

    if (newUserId.isEmpty) {
      throw ArgumentError.value(newUserId, 'newUserId', 'Must not be empty');
    }

    final resolvedStrategy = strategy ?? _config.defaultUserSwitchStrategy;
    _notifyObservers(
      (o) => o.onUserSwitchStart(oldUserId, newUserId, resolvedStrategy),
    );
    final hadUnsynced = await _hasUnsyncedData(oldUserId);

    try {
      // Execute the strategy. This will throw on failure for certain strategies.
      await _executeUserSwitchStrategy(
        resolvedStrategy,
        oldUserId,
        newUserId,
        hadUnsynced,
      );

      // If the strategy succeeds, proceed with success-related logic.
      _emitUserSwitchedEvent(oldUserId, newUserId, hadUnsynced);
      _logger.info('User switched from $oldUserId to $newUserId');

      // Return the success result.
      final result = DatumUserSwitchResult.success(
        previousUserId: oldUserId,
        newUserId: newUserId,
        unsyncedOperationsHandled: hadUnsynced ? 1 : 0,
      );
      _notifyObservers((o) => o.onUserSwitchEnd(result));
      return result;
    } on UserSwitchException catch (e) {
      // Handle specific user switch failures (e.g., promptIfUnsyncedData).
      _logger.warn('User switch rejected: ${e.message}');
      final result = DatumUserSwitchResult.failure(
        previousUserId: oldUserId,
        newUserId: newUserId,
        errorMessage: e.message,
      );
      _notifyObservers((o) => o.onUserSwitchEnd(result));
      return result;
    } on Object catch (e, stack) {
      // Handle any other unexpected errors during the switch.
      _logger.error('User switch failed', stack);
      final result = DatumUserSwitchResult.failure(
        previousUserId: oldUserId,
        newUserId: newUserId,
        errorMessage: 'User switch failed: $e',
      );
      _notifyObservers((o) => o.onUserSwitchEnd(result));
      return result;
    }
  }

  Future<void> _executeUserSwitchStrategy(
    UserSwitchStrategy strategy,
    String? oldUserId,
    String newUserId,
    bool hadUnsynced,
  ) async {
    switch (strategy) {
      case UserSwitchStrategy.syncThenSwitch:
        if (oldUserId != null && hadUnsynced) await synchronize(oldUserId);
      case UserSwitchStrategy.clearAndFetch:
        await localAdapter.clearUserData(newUserId);
        await synchronize(newUserId);
      case UserSwitchStrategy.promptIfUnsyncedData:
        if (hadUnsynced) {
          throw UserSwitchException(
            oldUserId,
            newUserId,
            'Unsynced data exists.',
          );
        }
      case UserSwitchStrategy.keepLocal:
      // Do nothing, just switch.
    }
  }

  /// Starts automatic periodic synchronization for the specified user.
  ///
  /// Uses [interval] if provided, otherwise uses [DatumConfig.autoSyncInterval].
  /// Automatically stops any existing auto-sync for the same user.
  void startAutoSync(String userId, {Duration? interval}) {
    _ensureInitialized();

    if (userId.isEmpty) {
      return;
    }

    stopAutoSync(userId: userId);

    final syncInterval = interval ?? _config.autoSyncInterval;
    _autoSyncTimers[userId] = Timer.periodic(syncInterval, (_) {
      // Use an async block to allow try-catch without affecting the timer's
      // void callback signature.
      unawaited(() async {
        try {
          await synchronize(userId);
        } catch (e, stack) {
          _logger.error('Auto-sync for user $userId failed: $e', stack);
        }
      }());
    });

    _logger.info(
      'Auto-sync started for user $userId (interval: $syncInterval)',
    );
  }

  /// Stops automatic synchronization for one or all users.
  void stopAutoSync({String? userId}) {
    if (userId != null) {
      final timer = _autoSyncTimers.remove(userId);
      timer?.cancel();
      if (timer != null) {
        _logger.info('Auto-sync stopped for user: $userId');
      }
      return;
    }

    for (final timer in _autoSyncTimers.values) {
      timer.cancel();
    }
    _autoSyncTimers.clear();
  }

  /// Releases all resources held by the manager and its adapters.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _localChangeSubscription?.cancel();
    await _remoteChangeSubscription?.cancel();
    await _eventController.close();
    await _statusSubject.close();
    await _metadataSubject.close();
    await _queueManager.dispose();
    stopAutoSync();
    _isolateHelper.dispose();
    await localAdapter.dispose();
    await remoteAdapter.dispose();
  }

  Future<T> _applyPreSaveTransforms(T entity) async {
    var transformed = entity;
    for (final middleware in _middlewares) {
      transformed = await middleware.transformBeforeSave(transformed);
    }
    return transformed;
  }

  Future<T> _applyPostFetchTransforms(T entity) async {
    var transformed = entity;
    for (final middleware in _middlewares) {
      transformed = await middleware.transformAfterFetch(transformed);
    }
    return transformed;
  }

  void _emitUserSwitchedEvent(
    String? oldUserId,
    String newUserId,
    bool hadUnsynced,
  ) {
    if (oldUserId == null || oldUserId == newUserId) return;
    _eventController.add(
      UserSwitchedEvent<T>(
        previousUserId: oldUserId,
        newUserId: newUserId,
        hadUnsyncedData: hadUnsynced,
      ),
    );
  }

  Future<bool> _hasUnsyncedData(String? userId) async {
    if (userId == null || userId.isEmpty) return false;
    return (await getPendingCount(userId)) > 0;
  }

  void _notifyObservers(void Function(DatumObserver<T> observer) action) {
    for (final observer in _localObservers) {
      action(observer);
    }
  }

  DatumSyncOperation<T> _createOperation({
    required String userId,
    required DatumOperationType type,
    required String entityId,
    T? data,
    Map<String, dynamic>? delta,
  }) {
    return DatumSyncOperation<T>(
      id: const Uuid().v4(),
      userId: userId,
      type: type,
      data: data,
      delta: delta,
      entityId: entityId,
      timestamp: DateTime.now(),
    );
  }

  /// Returns the number of pending synchronization operations for the user.
  Future<int> getPendingCount(String userId) async {
    _ensureInitialized();
    return _queueManager.getPendingCount(userId);
  }

  /// Returns a list of pending synchronization operations for the user.
  Future<List<DatumSyncOperation<T>>> getPendingOperations(
      String userId) async {
    _ensureInitialized();
    return _queueManager.getPending(userId);
  }
}
