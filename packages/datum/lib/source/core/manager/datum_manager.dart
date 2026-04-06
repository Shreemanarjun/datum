import 'dart:async';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:datum/datum.dart';
import 'package:datum/source/core/persistence/datum_persistence.dart';

import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../cascade_delete.dart';
import '../engine/error_boundary.dart';

import 'cold_start_manager.dart';
import '../utils/lru_cache.dart';

// Internal class representing a step in the cascade delete plan.
enum _CascadeStepType { delete, update }

// Internal class representing a step in the cascade delete plan.
class _CascadeDeleteStep {
  final DatumEntityInterface entity;
  final dynamic manager;
  final String? relationName;
  final _CascadeStepType type;
  final Map<String, dynamic>? updateData;

  const _CascadeDeleteStep({
    required this.entity,
    required this.manager,
    this.relationName,
    this.type = _CascadeStepType.delete,
    this.updateData,
  });
}

/// Internal class representing the complete cascade delete plan.
class _CascadeDeletePlan<T extends DatumEntityInterface> {
  final T mainEntity;
  final List<_CascadeDeleteStep> steps;
  final bool canDelete;
  final Map<String, List<DatumEntityInterface>> restrictedRelations;

  const _CascadeDeletePlan({
    required this.mainEntity,
    required this.steps,
    required this.canDelete,
    required this.restrictedRelations,
  });
}

/// Represents a preview of the cascade delete operation.
class CascadeDeletePreview {
  final String mainEntityType;
  final String mainEntityId;
  final List<CascadeDeleteStepPreview> steps;
  final bool canDelete;
  final List<String> warningMessages;

  CascadeDeletePreview({
    required this.mainEntityType,
    required this.mainEntityId,
    required this.steps,
    required this.canDelete,
    required this.warningMessages,
  });
}

/// Represents a single step in the cascade delete preview.
class CascadeDeleteStepPreview {
  final String entityType;
  final String entityId;
  final String action; // "Delete" or "SetNull"
  final Map<String, dynamic>? details;

  CascadeDeleteStepPreview({
    required this.entityType,
    required this.entityId,
    required this.action,
    this.details,
  });
}

// Weak reference wrapper for observers to prevent memory leaks
class _WeakObserver<U extends Object> {
  final WeakReference<U> _ref;

  _WeakObserver(U observer) : _ref = WeakReference(observer);

  U? get target => _ref.target;

  bool get isAlive => target != null;
}

class DatumManager<T extends DatumEntityInterface> with Disposable {
  final LocalAdapter<T> localAdapter;
  final RemoteAdapter<T> remoteAdapter;

  bool _initialized = false;
  bool _isSyncPaused = false;
  bool _isSubscribedToRemoteChanges = true;
  DatumSyncStatus? _prePauseStatus;
  final Set<String> _pausedAutoSyncUserIds = {};
  bool get isInitialized => _initialized;

  /// Whether the manager is currently subscribed to remote change events.
  bool get isSubscribedToRemoteChanges => _isSubscribedToRemoteChanges;

  // Core dependencies
  final DatumConflictResolver<T> _conflictResolver;
  final DatumConfig<T> config;
  final DatumConnectivityChecker _connectivity;
  final DatumLogger _logger;
  final List<_WeakObserver<DatumObserver<T>>> _localObservers = [];
  final List<_WeakObserver<GlobalDatumObserver>> _globalObservers = [];
  final List<DatumMiddleware<T>> _middlewares = [];
  final DatumSyncRequestStrategy _syncRequestStrategy;
  final String? deviceId;
  final DatumPersistence? persistence;

  // Internal state management
  final Map<String, Timer> _autoSyncTimers = {};

  /// A cache to track recently processed external change IDs to prevent echoes
  /// and de-duplicate events. The key is the entity ID.
  final Map<String, DateTime> _recentChangeCache = {};

  /// Last cache cleanup time
  DateTime _lastCacheCleanup = DateTime.now();

  /// Cache for relationship query results to improve performance
  late final LRUCache<String, List<DatumEntityInterface>> _relationshipQueryCache;

  /// Cache for entity existence checks
  late final LRUCache<String, bool> _entityExistenceCache;

  /// Cache for query results
  late final LRUCache<String, List<T>> _queryCache;

  late final QueueManager<T> _queueManager;
  late final IsolateHelper _isolateHelper;
  late final DatumConflictDetector<T> _conflictDetector;
  late final ColdStartManager _coldStartManager;
  DatumSyncEngine<T>? _syncEngine;

  /// Gets the sync engine, initializing it lazily if needed.
  DatumSyncEngine<T> get _syncEngineInstance {
    _syncEngine ??= DatumSyncEngine<T>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
      conflictResolver: _conflictResolver,
      queueManager: _queueManager,
      conflictDetector: _conflictDetector,
      logger: _logger,
      config: config,
      connectivityChecker: _connectivity,
      eventController: _eventController,
      statusSubject: _statusSubject,
      metadataSubject: _metadataSubject,
      isolateHelper: _isolateHelper,
      localObservers: _localObservers.map((w) => w.target).whereType<DatumObserver<T>>().toList(),
      globalObservers: _globalObservers.map((w) => w.target).whereType<GlobalDatumObserver>().toList(),
      deviceId: deviceId,
    );
    return _syncEngine!;
  }

  late final StreamController<DatumSyncEvent<T>> _eventController;
  late final BehaviorSubject<DatumSyncStatusSnapshot> _statusSubject;
  late final BehaviorSubject<DatumSyncMetadata> _metadataSubject;
  late final BehaviorSubject<DateTime?> _nextSyncTimeSubject;

  /// Exposes the queue manager for central orchestration.
  QueueManager<T> get queueManager => _queueManager;

  /// Exposes the cold start manager for testing purposes.
  ColdStartManager get coldStartManager => _coldStartManager;

  /// Public event streams
  Stream<DatumSyncEvent<T>> get eventStream => _eventController.stream;
  Stream<DataChangeEvent<T>> get onDataChange => eventStream.whereType<DataChangeEvent<T>>();
  Stream<DatumSyncStartedEvent<T>> get onSyncStarted => eventStream.whereType<DatumSyncStartedEvent<T>>();
  Stream<DatumSyncProgressEvent<T>> get onSyncProgress => eventStream.whereType<DatumSyncProgressEvent<T>>();
  Stream<DatumSyncCompletedEvent<T>> get onSyncCompleted => eventStream.whereType<DatumSyncCompletedEvent<T>>();
  Stream<ConflictDetectedEvent<T>> get onConflict => eventStream.whereType<ConflictDetectedEvent<T>>();
  Stream<UserSwitchedEvent<T>> get onUserSwitched => eventStream.whereType<UserSwitchedEvent<T>>();
  Stream<DatumSyncErrorEvent<T>> get onSyncError => eventStream.whereType<DatumSyncErrorEvent<T>>();

  /// A stream that emits when the active user changes for this manager.
  /// Reactive queries can listen to this to refresh their data when users switch.
  Stream<String?> get onUserChanged => onUserSwitched.map((event) => event.newUserId);

  /// A stream of the manager's current health status.
  Stream<DatumHealth> get health => _statusSubject.stream.map((s) => s.health);

  /// A stream of the manager's sync status snapshots.
  Stream<DatumSyncStatusSnapshot> get statusStream => _statusSubject.stream;

  /// The most recent snapshot of the manager's sync status.
  DatumSyncStatusSnapshot get currentStatus => _statusSubject.value;

  /// The most recent snapshot of the manager's sync status.
  ///
  /// Emits `null` if no auto-sync is scheduled.
  Stream<DateTime?> get watchNextSyncTime => _nextSyncTimeSubject.stream;

  /// A stream that emits the [Duration] until the next scheduled auto-sync.
  ///
  /// Emits `null` if no auto-sync is scheduled. The duration will decrease
  /// over time and the stream will emit new values periodically.
  Stream<Duration?> get watchNextSyncDuration {
    return watchNextSyncTime.switchMap((nextSync) {
      if (nextSync == null) {
        return Stream.value(null);
      }
      // Emit the duration every second until the sync time is reached.
      return Stream.periodic(const Duration(seconds: 1), (_) {
        final remaining = nextSync.difference(DateTime.now());
        return remaining.isNegative ? Duration.zero : remaining;
      }).startWith(nextSync.difference(DateTime.now()));
    });
  }

  Stream<DateTime?> get onNextSyncTimeChanged => _nextSyncTimeSubject.stream;

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
    DatumSyncRequestStrategy? syncRequestStrategy,
    this.deviceId,
    this.persistence,
    Stream<String?>? userChangeStream,
  })  : config = datumConfig ?? const DatumConfig(),
        _connectivity = connectivity,
        // The logger's enabled status should always respect the config.
        _logger = (logger ??
                DatumLogger(
                  enabled: datumConfig?.enableLogging ?? true,
                  minimumLevel: datumConfig?.logLevel ?? LogLevel.info,
                  enablePerformanceLogging: datumConfig?.enablePerformanceLogging ?? false,
                  performanceThreshold: datumConfig?.performanceLogThreshold ?? const Duration(milliseconds: 100),
                  samplers: datumConfig?.logSamplers ?? const {},
                ))
            .copyWith(
          enabled: datumConfig?.enableLogging ?? true,
          minimumLevel: datumConfig?.logLevel ?? LogLevel.info,
          enablePerformanceLogging: datumConfig?.enablePerformanceLogging ?? false,
          performanceThreshold: datumConfig?.performanceLogThreshold ?? const Duration(milliseconds: 100),
          samplers: datumConfig?.logSamplers ?? const {},
        ),
        _conflictResolver = conflictResolver ?? datumConfig?.defaultConflictResolver ?? LastWriteWinsResolver<T>(),
        _syncRequestStrategy = syncRequestStrategy ?? datumConfig?.syncRequestStrategy ?? const SequentialRequestStrategy() {
    _localObservers.addAll((localObservers ?? []).map(_WeakObserver.new));
    _globalObservers.addAll((globalObservers ?? []).map(_WeakObserver.new));
    _middlewares.addAll(middlewares ?? []);

    // If the local adapter supports user change streams, pass it along
    if (userChangeStream != null) {
      try {
        // Try to set the userChangeStream property if it exists
        (localAdapter as dynamic).userChangeStream = userChangeStream;
      } catch (e) {
        // Ignore if the adapter doesn't support user change streams
      }
    }

    _initializeInternalComponents();
  }

  void _initializeInternalComponents() {
    // Initialize controllers and manage them for automatic disposal.
    _eventController = StreamController.broadcast();
    _statusSubject = BehaviorSubject.seeded(DatumSyncStatusSnapshot.initial(''));
    _metadataSubject = BehaviorSubject();
    _nextSyncTimeSubject = BehaviorSubject.seeded(null);
    manageController(_eventController);
    manageController(_statusSubject);
    manageController(_metadataSubject);
    manageController(_nextSyncTimeSubject);

    _conflictDetector = DatumConflictDetector<T>();
    _isolateHelper = const IsolateHelper();
    _coldStartManager = ColdStartManager(config.coldStartConfig);
    _queueManager = QueueManager<T>(
      localAdapter: localAdapter,
      logger: _logger,
    );

    _relationshipQueryCache = LRUCache(config.maxRelationshipQueryCacheSize);
    _entityExistenceCache = LRUCache(config.maxEntityExistenceCacheSize);
    _queryCache = LRUCache(config.maxQueryCacheSize);
  }

  /// Initializes the manager and its adapters. Must be called before any other methods.
  Future<void> initialize() async {
    if (_initialized) return;
    ensureNotDisposed();

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
    final executor = MigrationExecutor(
      localAdapter: localAdapter,
      migrations: config.migrations,
      targetVersion: config.schemaVersion,
      logger: _logger,
    );
    try {
      if (await executor.needsMigration()) {
        final result = await executor.execute();
        if (!result.success) {
          // If the migration failed, throw the captured error to be handled by the catch block below.
          Error.throwWithStackTrace(result.migrationError!, result.migrationStack!);
        }
      }
    } on Object catch (e, stack) {
      _logger.error('Schema migration failed: $e', stack);
      if (config.onMigrationError != null) {
        await config.onMigrationError!(e, stack);
      } else {
        throw MigrationException(
          e: e,
          message: "Schema migration failed",
          code: DatumExceptionCode.schemaMismatch,
          stackTrace: stack,
        );
      }
    }
  }

  Future<void> _setupAutoSyncIfEnabled() async {
    if (!config.autoStartSync) return;

    _logger.debug('Auto-start sync enabled, discovering users');

    // Evaluate initialUserId - it's always a function that returns Future<String?>
    String? evaluatedInitialUserId;
    if (config.initialUserId != null) {
      try {
        evaluatedInitialUserId = await config.initialUserId!();
      } catch (e) {
        _logger.warn('Failed to evaluate initialUserId function: $e');
        evaluatedInitialUserId = null;
      }
    }

    final userIds = evaluatedInitialUserId != null ? [evaluatedInitialUserId] : await localAdapter.getAllUserIds();

    for (final userId in userIds) {
      if (userId.isNotEmpty) {
        // Check if cold start sync is needed
        unawaited(_coldStartManager.handleColdStartIfNeeded(
          userId,
          (options) => synchronize(userId, options: options),
          entityType: T.toString(),
        ));

        // Cold start is now asynchronous, so we always start auto-sync
        // The cold start will run in background if needed
        startAutoSync(userId);
      }
    }

    _logger.info(
      'Auto-sync setup completed for ${userIds.length} users.',
    );
  }

  void _subscribeToChangeStreams() {
    // Subscribe to local changes
    final localSub = localAdapter.changeStream()?.listen((change) {
      // Wrap the single local change in a list to match the handler's signature.
      _handleExternalChange([change], DataSource.local);
    }, onError: (e, s) => _logger.error('Error in local change stream', s));
    if (localSub != null) manageSubscription(localSub);

    // Subscribe to remote changes.
    final remoteStream = remoteAdapter.changeStream;
    if (remoteStream == null) return;
    late StreamSubscription remoteSub;

    // If a debounce time is configured, buffer events for performance.
    if (config.remoteEventDebounceTime > Duration.zero) {
      remoteSub = remoteStream.bufferTime(config.remoteEventDebounceTime).where((batch) => batch.isNotEmpty).listen(
            (changeList) => _handleExternalChange(changeList, DataSource.remote),
            onError: (e, s) => _logger.error('Error in remote change stream', s),
          );
    } else {
      // Otherwise, process events individually. This is better for tests.
      remoteSub = remoteStream.listen((change) {
        _handleExternalChange([change], DataSource.remote);
      }, onError: (e, s) => _logger.error('Error in remote change stream', s));
    }
    manageSubscription(remoteSub);
  }

  /// Handles changes originating from outside the manager's direct control.
  Future<void> _handleExternalChange(
    List<DatumChangeDetail<T>> changes,
    DataSource source,
  ) async {
    if (isDisposed) {
      _logger.warn(
        'Dropping ${changes.length} external change(s) from $source because the manager is disposed.',
      );
      return;
    }

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
              // We can't easily get the size of a deleted item from a remote
              // event, so we'll consider it 0 for bytesPulled calculation.
              // The size of the delete *operation* is calculated on push.
              DatumSyncProgressEvent<T>(userId: change.userId, bytesPulled: 0, completed: 1, total: 1),
            );
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
          // If the change is from remote, it contributes to bytesPulled.
          final payload = change.data!.toDatumMap(target: MapTarget.local);
          final size = (await _isolateHelper.computeJsonEncode(payload)).length;
          if (_eventController.isClosed) {
            _logger.warn(
              'Cannot emit sync progress event; manager is disposed.',
            );
            return;
          }
          _eventController.add(
            DatumSyncProgressEvent<T>(
              userId: change.userId,
              bytesPulled: size,
              completed: 1,
              total: 1,
            ),
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
      if (isDisposed) {
        _logger.warn(
          'Cannot process sync event ${event.runtimeType}; manager is disposed.',
        );
        return;
      }
      _eventController.add(event);
    }
  }

  void _cleanupChangeCache() {
    final now = DateTime.now();

    // Always check for expired entries based on config duration
    final cacheExpiry = now.subtract(config.changeCacheDuration);
    _recentChangeCache.removeWhere((key, timestamp) {
      return timestamp.isBefore(cacheExpiry);
    });

    // Periodic full cleanup and size management
    if (now.difference(_lastCacheCleanup) > config.changeCacheCleanupInterval) {
      // Size-based cleanup to prevent unbounded growth
      if (_recentChangeCache.length > config.maxChangeCacheSize) {
        // Remove oldest entries (keep only the most recent half)
        final entries = _recentChangeCache.entries.toList()..sort((a, b) => b.value.compareTo(a.value)); // Sort by timestamp descending

        final keepCount = config.maxChangeCacheSize ~/ 2;
        final entriesToKeep = entries.take(keepCount);
        _recentChangeCache.clear();
        _recentChangeCache.addEntries(entriesToKeep);
      }
      _lastCacheCleanup = now;
    }
  }

  Future<T> push({
    required T item,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
  }) async {
    _ensureInitialized();
    // Check for user switch before proceeding.
    await _syncEngineInstance.checkForUserSwitch(userId);

    var transformed = await _applyPreSaveTransforms(item);

    // Automatically increment vector clock if deviceId is available
    if (deviceId != null) {
      transformed = transformed.incrementClock(deviceId!) as T;
    }
    final existing = await localAdapter.read(item.id, userId: userId);

    if (existing != null) {
      // This is an update. Calculate the diff.
      final delta = transformed.diff(existing);
      if (delta == null) {
        _logger.debug(
          'No changes detected for entity ${item.id}, skipping save.',
        );
        return transformed;
      }
      // If we are here, it's a valid update with changes.
      final result = await _performUpdate(transformed, delta, source, forceRemoteSync);

      // Invalidate caches that might be affected by this update
      _invalidateCachesForEntity(result);

      return result;
    } else {
      // This is a new creation.
      final result = await _performCreate(transformed, source, forceRemoteSync);

      // Invalidate caches that might be affected by this creation
      _invalidateCachesForEntity(result);

      return result;
    }
  }

  Future<T> _performCreate(T transformed, DataSource source, bool forceRemoteSync) async {
    final userId = transformed.userId;

    // Isolate observer notifications with error boundaries
    final observerBoundary = ErrorBoundaries.observerIsolation(logger: _logger);

    _logger.debug('Notifying observers of onCreateStart for ${transformed.id}');
    unawaited(observerBoundary.executeVoid(() async {
      for (final weakObserver in _localObservers) {
        weakObserver.target?.onCreateStart(transformed);
      }
      for (final weakObserver in _globalObservers) {
        weakObserver.target?.onCreateStart(transformed);
      }
    }));

    await localAdapter.create(transformed);

    if (source == DataSource.local || forceRemoteSync) {
      final operation = _createOperation(
        userId: userId,
        type: DatumOperationType.create,
        entityId: transformed.id,
        data: transformed,
      );
      // Calculate size
      final payload = operation.delta ?? operation.data?.toDatumMap(target: MapTarget.remote);
      final encoded = payload != null ? await _isolateHelper.computeJsonEncode(payload) : '';
      final size = encoded.length;

      await _queueManager.enqueue(operation.copyWith(sizeInBytes: size));
    }

    _eventController.add(
      DataChangeEvent<T>(
        userId: userId,
        data: transformed,
        changeType: ChangeType.created,
        source: source,
      ),
    );

    _logger.debug('Notifying observers of onCreateEnd for ${transformed.id}');
    unawaited(observerBoundary.executeVoid(() async {
      for (final weakObserver in _localObservers) {
        weakObserver.target?.onCreateEnd(transformed);
      }
      for (final weakObserver in _globalObservers) {
        weakObserver.target?.onCreateEnd(transformed);
      }
    }));

    return transformed;
  }

  Future<T> _performUpdate(T transformed, Map<String, dynamic> delta, DataSource source, bool forceRemoteSync) async {
    final userId = transformed.userId;

    _logger.debug('Notifying observers of onUpdateStart for ${transformed.id}');
    for (final weakObserver in _localObservers) {
      weakObserver.target?.onUpdateStart(transformed);
    }
    for (final weakObserver in _globalObservers) {
      weakObserver.target?.onUpdateStart(transformed);
    }

    await localAdapter.patch(id: transformed.id, delta: delta, userId: userId);

    if (source == DataSource.local || forceRemoteSync) {
      final operation = _createOperation(
        userId: userId,
        type: DatumOperationType.update,
        entityId: transformed.id,
        data: transformed,
        delta: delta,
      );
      final payload = operation.delta ?? operation.data?.toDatumMap(target: MapTarget.remote);
      final encoded = payload != null ? await _isolateHelper.computeJsonEncode(payload) : '';
      final size = encoded.length;
      await _queueManager.enqueue(operation.copyWith(sizeInBytes: size));
    }

    _eventController.add(
      DataChangeEvent<T>(userId: userId, data: transformed, changeType: ChangeType.updated, source: source),
    );

    _logger.debug('Notifying observers of onUpdateEnd for ${transformed.id}');
    for (final weakObserver in _localObservers) {
      weakObserver.target?.onUpdateEnd(transformed);
    }
    for (final weakObserver in _globalObservers) {
      weakObserver.target?.onUpdateEnd(transformed);
    }
    return transformed;
  }

  /// Saves an entity locally and immediately triggers a synchronization.
  ///
  /// This is useful for operations that require immediate confirmation from the
  /// remote server. It combines `push()` and `synchronize()` into a single call.
  ///
  /// Returns a tuple containing the locally saved entity and the sync result.
  Future<(T, DatumSyncResult<T>)> pushAndSync({
    required T item,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
    DatumSyncOptions<T>? syncOptions,
    DatumSyncScope? scope,
  }) async {
    _ensureInitialized();
    final savedItem = await push(item: item, userId: userId, source: source, forceRemoteSync: forceRemoteSync);
    final syncResult = await synchronize(userId, options: syncOptions, scope: scope);
    return (savedItem, syncResult);
  }

  /// Updates an entity locally and immediately triggers a synchronization.
  ///
  /// This is an alias for [pushAndSync] and is provided for semantic clarity.
  /// It's useful for operations that require immediate confirmation from the
  /// remote server.
  ///
  /// Returns a tuple containing the locally saved entity and the sync result.
  Future<(T, DatumSyncResult<T>)> updateAndSync({
    required T item,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
    DatumSyncOptions<T>? syncOptions,
    DatumSyncScope? scope,
  }) async {
    _ensureInitialized();
    // `push` handles both create and update, so this is equivalent to pushAndSync.
    final savedItem = await push(item: item, userId: userId, source: source, forceRemoteSync: forceRemoteSync);
    final syncResult = await synchronize(userId, options: syncOptions, scope: scope);
    return (savedItem, syncResult);
  }

  Future<List<T>> saveMany({
    required List<T> items,
    required String userId,
    bool andSync = false,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
    DatumSyncOptions<T>? syncOptions,
    DatumSyncScope? scope,
  }) async {
    _ensureInitialized();
    final savedItems = <T>[];
    for (final item in items) {
      final savedItem = await push(item: item, userId: userId, source: source, forceRemoteSync: forceRemoteSync);
      savedItems.add(savedItem);
    }
    if (andSync) {
      await synchronize(userId, options: syncOptions, scope: scope);
    }
    return savedItems;
  }

  /// Reads a single entity by its ID from the primary local adapter.
  /// Reads a single entity by its ID from the primary local adapter.
  ///
  /// The [withRelated] parameter allows eager loading of related entities.
  Future<T?> read(String id, {String? userId, List<String> withRelated = const []}) async {
    _ensureInitialized();

    // Create cache key for entity existence
    final cacheKey = '${T.toString()}:$id:${userId ?? ''}';

    // Check entity existence cache first
    final cachedExists = _entityExistenceCache[cacheKey];
    if (cachedExists != null) {
      if (!cachedExists) {
        _logger.debug('Using cached entity existence (does not exist) for key: $cacheKey');
        return null;
      }
      // If cache says it exists, we still need to fetch it
    }

    final entity = await localAdapter.read(id, userId: userId);

    // Cache the existence result
    _entityExistenceCache[cacheKey] = entity != null;
    _logger.debug('Cached entity existence for key: $cacheKey (exists: ${entity != null})');

    if (entity == null) return null;

    if (withRelated.isNotEmpty) {
      await _fetchAndStitchRelations([entity], withRelated, DataSource.local, userId);
    }

    return _applyPostFetchTransforms(entity);
  }

  /// Reads all entities from the primary local adapter.
  /// Reads all entities from the primary local adapter.
  ///
  /// The [withRelated] parameter allows eager loading of related entities.
  Future<List<T>> readAll({String? userId, List<String> withRelated = const []}) async {
    _ensureInitialized();
    final entities = await localAdapter.readAll(userId: userId);

    if (withRelated.isNotEmpty && entities.isNotEmpty) {
      await _fetchAndStitchRelations(entities, withRelated, DataSource.local, userId);
    }

    final transformedEntities = <T>[];
    for (final entity in entities) {
      try {
        final transformed = await _applyPostFetchTransforms(entity);
        transformedEntities.add(transformed);
      } catch (e, stack) {
        _logger.error('Failed to apply post-fetch transforms to entity ${entity.id}: $e', stack);
        // Continue with other entities instead of failing the entire operation
        transformedEntities.add(entity); // Use original entity if transform fails
      }
    }
    return transformedEntities;
  }

  /// Watches all entities from the local adapter, emitting a new list on any change.
  ///
  /// The [includeInitialData] parameter controls whether the stream should
  /// immediately emit the current list of all items. Defaults to `true`.
  /// If `false`, the stream will only emit when a change occurs.
  /// Returns null if the adapter does not support reactive queries.
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) {
    _ensureInitialized();
    final adapterStream = localAdapter.watchAll(userId: userId, includeInitialData: includeInitialData);
    if (adapterStream == null) return null;

    return adapterStream.asyncMap((list) async {
      try {
        // Apply post-fetch transforms with error handling
        final transformedList = <T>[];
        for (final entity in list) {
          try {
            final transformed = await _applyPostFetchTransforms(entity);
            transformedList.add(transformed);
          } catch (e, stack) {
            _logger.error('Failed to apply post-fetch transforms to entity ${entity.id}: $e', stack);
            // Continue with other entities instead of failing the entire stream
            transformedList.add(entity); // Use original entity if transform fails
          }
        }
        return transformedList;
      } catch (e, stack) {
        _logger.error('Failed to transform entity list in watchAll: $e', stack);
        // Return the original list if transformation fails completely
        return list;
      }
    }).handleError((error, stack) {
      _logger.error('Error in watchAll stream for $T: $error', stack);
      // Don't rethrow - let the stream continue
    });
  }

  /// Watches a single entity by its ID, emitting the item on change or null if deleted.
  /// Returns null if the adapter does not support reactive queries.
  Stream<T?>? watchById(String id, String? userId) {
    _ensureInitialized();
    final adapterStream = localAdapter.watchById(id, userId: userId);
    if (adapterStream == null) return null;

    return adapterStream.asyncMap((item) async {
      if (item == null) {
        return null;
      }
      try {
        return await _applyPostFetchTransforms(item);
      } catch (e, stack) {
        _logger.error('Failed to apply post-fetch transforms to entity $id: $e', stack);
        return item; // Return original entity if transform fails
      }
    }).handleError((error, stack) {
      _logger.error('Error in watchById stream for $T:$id: $error', stack);
      // Don't rethrow - let the stream continue
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
    final adapterStream = localAdapter.watchQuery(query, userId: userId);
    if (adapterStream == null) return null;

    return adapterStream.asyncMap((list) async {
      try {
        // Apply post-fetch transforms with error handling
        final transformedList = <T>[];
        for (final entity in list) {
          try {
            final transformed = await _applyPostFetchTransforms(entity);
            transformedList.add(transformed);
          } catch (e, stack) {
            _logger.error('Failed to apply post-fetch transforms to entity ${entity.id}: $e', stack);
            // Continue with other entities instead of failing the entire stream
            transformedList.add(entity); // Use original entity if transform fails
          }
        }
        return transformedList;
      } catch (e, stack) {
        _logger.error('Failed to transform entity list in watchQuery: $e', stack);
        // Return the original list if transformation fails completely
        return list;
      }
    }).handleError((error, stack) {
      _logger.error('Error in watchQuery stream for $T: $error', stack);
      // Don't rethrow - let the stream continue
    });
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

    // Create a cache key for this query
    final cacheKey = _createQueryCacheKey(query, source, userId);

    // Check cache first (only for local queries without related entities for simplicity)
    if (source == DataSource.local && query.withRelated.isEmpty) {
      final cached = _getCachedQuery(cacheKey);
      if (cached != null) {
        _logger.debug('Using cached query results for key: $cacheKey');
        return Future.wait(cached.map(_applyPostFetchTransforms));
      }
    }

    final adapter = (source == DataSource.local ? localAdapter : remoteAdapter) as dynamic;
    final entities = await adapter.query(query, userId: userId) as List<T>;

    if (query.withRelated.isNotEmpty && entities.isNotEmpty) {
      await _fetchAndStitchRelations(entities, query.withRelated, source, userId);
    }

    // Cache the results (only for local queries without related entities)
    if (source == DataSource.local && query.withRelated.isEmpty) {
      _cacheQuery(cacheKey, entities);
    }

    // Apply post-fetch transforms with error handling
    final transformedEntities = <T>[];
    for (final entity in entities) {
      try {
        final transformed = await _applyPostFetchTransforms(entity);
        transformedEntities.add(transformed);
      } catch (e, stack) {
        _logger.error('Failed to apply post-fetch transforms to entity ${entity.id}: $e', stack);
        // Continue with other entities instead of failing the entire operation
        transformedEntities.add(entity); // Use original entity if transform fails
      }
    }
    return transformedEntities;
  }

  Future<void> _fetchAndStitchRelations(List<T> entities, List<String> relations, DataSource source, String? userId) async {
    if (entities.isEmpty || entities.first is! RelationalDatumEntity) {
      return;
    }

    final relationalEntities = entities.cast<RelationalDatumEntity>();
    final Map<String, dynamic> relationTree = {};
    for (final relationPath in relations) {
      final parts = relationPath.split('.');
      Map<String, dynamic> node = relationTree;
      
      for (final part in parts) {
        node = node.putIfAbsent(part, () => <String, dynamic>{});
      }
    }

    for (final entry in relationTree.entries) {
      await _loadRelationTree(relationalEntities, entry.key, entry.value, source, userId);
    }
  }

  Future<void> _loadRelationTree(
    List<RelationalDatumEntity> entities,
    String relationName,
    Map<String, dynamic> children,
    DataSource source,
    String? userId,
  ) async {
    if (entities.isEmpty) return;

    final relation = entities.first.relations[relationName];

    if (relation == null) {
      _logger.warn('Relation "$relationName" not found on entity ${T.toString()}');
      return;
    }

    final relatedManager = relation.getRelatedManager();
    final relatedEntities = <RelationalDatumEntity>[];

    if (relation is BelongsTo) {
      final foreignKeyName = relation.foreignKey;
      final foreignKeyValues = entities.map((e) => e.toDatumMap()[foreignKeyName]).nonNulls.toSet().toList();

      if (foreignKeyValues.isEmpty) return;

      final fetched = await relatedManager.query(
        DatumQuery(
          filters: [
            Filter(relation.localKey, FilterOperator.isIn, foreignKeyValues)
          ],
        ),
        source: source,
        userId: userId,
      );

      final byId = {for (var e in fetched) e.id: e};

      for (final entity in entities) {
        final fk = entity.toDatumMap()[foreignKeyName];
        final related = byId[fk];

        entity.relations[relationName]?.setRaw(related);

        if (related is RelationalDatumEntity) {
          relatedEntities.add(related);
        }
      }
    } else if (relation is HasMany) {
      final foreignKeyName = relation.foreignKey;
      final localKeyValues = entities.map((e) => e.id).toSet().toList();

      if (localKeyValues.isEmpty) return;

      final fetched = await relatedManager.query(
        DatumQuery(
          filters: [
            Filter(foreignKeyName, FilterOperator.isIn, localKeyValues)
          ],
        ),
        source: source,
        userId: userId,
      );

      final grouped = <String, List<RelationalDatumEntity>>{};

      for (final entity in fetched) {
        final parentId = (entity as RelationalDatumEntity).toDatumMap()[foreignKeyName];

        (grouped[parentId] ??= []).add(entity);
        relatedEntities.add(entity);
      }

      for (final entity in entities) {
        final related = grouped[entity.id] ?? [];
        entity.relations[relationName]?.setRaw(related);
      }
    }

    // Recurse children
    if (children.isNotEmpty && relatedEntities.isNotEmpty) {
      for (final entry in children.entries) {
        await _loadRelationTree(relatedEntities, entry.key, entry.value, source, userId);
      }
    }
  }

  /// Deletes an entity by its ID from all local and remote adapters.
  ///
  /// The [behavior] parameter allows overriding the global [DatumConfig.deleteBehavior]
  /// for this specific delete operation. If null, the global config value is used.
  Future<bool> delete({
    required String id,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
    DeleteBehavior? behavior,
  }) async {
    _ensureInitialized();
    // Check for user switch before proceeding.
    await _syncEngineInstance.checkForUserSwitch(userId);

    final existing = await localAdapter.read(id, userId: userId);
    if (existing == null) {
      _logger.debug(
        'Entity $id does not exist for user $userId, skipping delete',
      );
      return false;
    }

    _logger.debug('Notifying observers of onDeleteStart for $id');
    for (final weakObserver in _localObservers) {
      weakObserver.target?.onDeleteStart(id);
    }
    for (final weakObserver in _globalObservers) {
      weakObserver.target?.onDeleteStart(id);
    }
    // Use the provided behavior or fall back to the configured delete behavior
    final effectiveBehavior = behavior ?? config.deleteBehavior;
    T entityForEvent = existing;
    if (effectiveBehavior == DeleteBehavior.softDelete) {
      // Soft delete: mark the entity as deleted
      final delta = <String, dynamic>{
        'isDeleted': true,
        'modifiedAt': DateTime.now().toIso8601String(),
      };
      if (deviceId != null) {
        final currentClock = existing.vectorClock ?? const VectorClock();
        delta['vectorClock'] = currentClock.increment(deviceId!).toMap();
      }
      entityForEvent = await localAdapter.patch(
        id: id,
        delta: delta,
        userId: userId,
      );
    } else {
      // Hard delete: physically remove the entity
      final deleted = await localAdapter.delete(id, userId: userId);
      if (!deleted) {
        _logger.warn('Local adapter failed to delete entity $id');
        // Notify observers of the failure before returning.
        for (final weakObserver in _localObservers) {
          weakObserver.target?.onDeleteEnd(id, success: false);
        }
        for (final weakObserver in _globalObservers) {
          weakObserver.target?.onDeleteEnd(id, success: false);
        }
        return false;
      }
    }

    _logger.debug('Notifying observers of onDeleteEnd for $id');
    for (final weakObserver in _localObservers) {
      weakObserver.target?.onDeleteEnd(id, success: true);
    }
    for (final weakObserver in _globalObservers) {
      weakObserver.target?.onDeleteEnd(id, success: true);
    }
    if (source == DataSource.local || forceRemoteSync) {
      final operation = _createOperation(
        userId: userId,
        type: DatumOperationType.delete,
        entityId: id,
      );
      // Calculate size for delete operation (it's small, just the ID)
      final payload = {'id': id};
      final size = (await _isolateHelper.computeJsonEncode(payload)).length;

      await _queueManager.enqueue(operation.copyWith(sizeInBytes: size));
    }

    _eventController.add(
      DataChangeEvent<T>(
        userId: userId,
        data: entityForEvent,
        changeType: ChangeType.deleted,
        source: source,
      ),
    );

    // Invalidate caches for the deleted entity
    _invalidateCachesForEntity(entityForEvent);

    return true;
  }

  /// Deletes an entity locally and immediately triggers a synchronization.
  ///
  /// This is useful for ensuring a delete operation is persisted to the remote
  /// server as soon as possible.
  ///
  /// The [behavior] parameter allows overriding the global [DatumConfig.deleteBehavior]
  /// for this specific delete operation. If null, the global config value is used.
  ///
  /// Returns a tuple containing a boolean indicating if the local delete was
  /// successful and the result of the subsequent synchronization.
  Future<(bool, DatumSyncResult<T>)> deleteAndSync({
    required String id,
    required String userId,
    DatumSyncOptions<T>? syncOptions,
    DeleteBehavior? behavior,
  }) async {
    _ensureInitialized();
    final wasDeleted = await delete(id: id, userId: userId, behavior: behavior);
    final syncResult = await synchronize(userId, options: syncOptions);
    return (wasDeleted, syncResult);
  }

  /// Deletes an entity with cascading behavior based on relationship configurations.
  ///
  /// This method respects the [CascadeDeleteBehavior] configured on each relationship:
  /// - [CascadeDeleteBehavior.cascade]: Related entities are also deleted
  /// - [CascadeDeleteBehavior.restrict]: Delete fails if related entities exist
  /// - [CascadeDeleteBehavior.setNull]: Foreign keys are set to null (BelongsTo only)
  /// - [CascadeDeleteBehavior.none]: No cascading behavior (default)
  ///
  /// The method performs deletes in dependency order to avoid foreign key constraint violations.
  ///
  /// Returns a [CascadeDeleteResult] containing information about the operation.
  Future<CascadeDeleteResult<T>> cascadeDelete({
    required String id,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
  }) async {
    _ensureInitialized();
    // Check for user switch before proceeding.
    await _syncEngineInstance.checkForUserSwitch(userId);

    final entity = await localAdapter.read(id, userId: userId);
    if (entity == null) {
      _logger.debug('Entity $id does not exist for user $userId, skipping cascade delete');
      return CascadeDeleteResult<T>(
        success: false,
        entity: null,
        deletedEntities: {},
        restrictedRelations: {},
        errors: ['Entity $id does not exist'],
      );
    }

    if (!entity.isRelational) {
      // Fall back to regular delete for non-relational entities
      final deleted = await delete(id: id, userId: userId, source: source, forceRemoteSync: forceRemoteSync);
      return CascadeDeleteResult<T>(
        success: deleted,
        entity: entity,
        deletedEntities: deleted
            ? {
                T: [entity]
              }
            : {},
        restrictedRelations: {},
        errors: deleted ? [] : ['Failed to delete entity'],
      );
    }

    final deletePlan = await _buildCascadeDeletePlan(entity, userId, CascadeAnalyticsBuilder());

    if (!deletePlan.canDelete) {
      return CascadeDeleteResult<T>(
        success: false,
        entity: entity,
        deletedEntities: {},
        restrictedRelations: deletePlan.restrictedRelations,
        errors: ['Delete restricted by relationships'],
      );
    }

    // Execute the delete plan
    final result = await _executeCascadeDeletePlan(deletePlan, userId, source, forceRemoteSync);

    // Emit the main entity delete event
    _eventController.add(
      DataChangeEvent<T>(
        userId: userId,
        data: entity,
        changeType: ChangeType.deleted,
        source: source,
      ),
    );

    return result;
  }

  /// Creates a fluent API builder for cascade delete operations.
  CascadeDeleteBuilder<T> deleteCascade(String entityId) {
    return CascadeDeleteBuilder<T>(this, entityId);
  }

  /// Executes cascade delete with enhanced options (dry-run, progress, etc.).
  Future<CascadeResult<T>> executeCascadeDeleteWithOptions(
    String entityId,
    String userId,
    CascadeOptions options,
  ) async {
    final analyticsBuilder = CascadeAnalyticsBuilder();
    analyticsBuilder.startOperation(dryRun: options.dryRun);

    try {
      _ensureInitialized();

      // Check for cancellation at the start
      if (options.cancellationToken?.isCancelled ?? false) {
        analyticsBuilder.completeOperation();
        return CascadeFailure<T>(
          entity: null,
          error: CascadeError.cancelled(),
        );
      }

      // Check for user switch before proceeding.
      await _syncEngineInstance.checkForUserSwitch(userId);

      final entity = await localAdapter.read(entityId, userId: userId);
      analyticsBuilder.recordQueryExecuted();

      if (entity == null) {
        analyticsBuilder.completeOperation();
        return CascadeFailure<T>(
          entity: null,
          error: CascadeError.entityNotFound(entityId),
        );
      }

      analyticsBuilder.recordEntityProcessed(entity.runtimeType);

      if (!entity.isRelational) {
        // Fall back to regular delete for non-relational entities
        if (options.dryRun) {
          analyticsBuilder.recordEntityDeleted(entity.runtimeType);
          analyticsBuilder.completeOperation();
          return CascadeSuccess<T>(
            entity: entity,
            totalDeleted: 1,
            deletedEntities: {
              T: [entity]
            },
            restrictedRelations: {},
            analytics: analyticsBuilder.build(),
          );
        }

        final deleted = await delete(id: entityId, userId: userId);
        if (deleted) {
          analyticsBuilder.recordEntityDeleted(entity.runtimeType);
          analyticsBuilder.completeOperation();
          return CascadeSuccess<T>(
            entity: entity,
            totalDeleted: 1,
            deletedEntities: {
              T: [entity]
            },
            restrictedRelations: {},
            analytics: analyticsBuilder.build(),
          );
        } else {
          analyticsBuilder.recordError();
          analyticsBuilder.completeOperation();
          return CascadeFailure<T>(
            entity: entity,
            error: CascadeError.deleteFailed(T.toString(), entityId, 'Delete operation failed'),
          );
        }
      }

      final deletePlan = await _buildCascadeDeletePlan(entity, userId, analyticsBuilder);

      // For dry-run, just return the plan without executing
      if (options.dryRun) {
        final deletedEntities = <Type, List<DatumEntityInterface>>{};
        var completed = 0;

        // Simulate progress for dry-run
        for (final step in deletePlan.steps) {
          deletedEntities.putIfAbsent(step.entity.runtimeType, () => []).add(step.entity);
          analyticsBuilder.recordEntityDeleted(step.entity.runtimeType);
          completed++;
          options.onProgress?.call(CascadeProgress(
            completed: completed,
            total: deletePlan.steps.length,
            currentEntityType: step.entity.runtimeType.toString(),
            currentEntityId: step.entity.id,
            message: 'Planning deletion of ${step.entity.runtimeType.toString()}',
          ));
        }

        analyticsBuilder.completeOperation();
        return CascadeSuccess<T>(
          entity: entity,
          totalDeleted: deletePlan.steps.length,
          deletedEntities: deletedEntities,
          restrictedRelations: deletePlan.restrictedRelations,
          analytics: analyticsBuilder.build(),
        );
      }

      if (!deletePlan.canDelete) {
        final restrictedEntityIds = deletePlan.restrictedRelations.values.expand((entities) => entities).map((e) => e.id).toList();
        analyticsBuilder.recordRestrictViolation();
        analyticsBuilder.completeOperation();

        return CascadeFailure<T>(
          entity: entity,
          error: CascadeError.restrictViolation(
            deletePlan.restrictedRelations.keys.first,
            restrictedEntityIds,
          ),
        );
      }

      // Execute the delete plan with progress tracking
      final result = await _executeCascadeDeletePlanWithProgress(
        deletePlan,
        userId,
        DataSource.local,
        false,
        options,
        analyticsBuilder,
      );

      // Emit the main entity delete event
      _eventController.add(
        DataChangeEvent<T>(
          userId: userId,
          data: entity,
          changeType: ChangeType.deleted,
          source: DataSource.local,
        ),
      );

      analyticsBuilder.completeOperation();

      if (result.success) {
        return CascadeSuccess<T>(
          entity: entity,
          totalDeleted: result.totalDeleted,
          deletedEntities: result.deletedEntities,
          restrictedRelations: result.restrictedRelations,
          analytics: analyticsBuilder.build(),
        );
      } else {
        analyticsBuilder.recordError();
        return CascadeFailure<T>(
          entity: entity,
          error: CascadeError.deleteFailed(T.toString(), entityId, result.errors.join(', ')),
          errors: result.errors,
        );
      }
    } catch (e) {
      analyticsBuilder.recordError();
      analyticsBuilder.completeOperation();
      rethrow;
    }
  }

  /// Executes cascade delete plan with progress tracking and cancellation support.
  Future<CascadeDeleteResult<T>> _executeCascadeDeletePlanWithProgress(
    _CascadeDeletePlan<T> plan,
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
        if (step.type == _CascadeStepType.delete) {
          success = await step.manager.performDeleteWithoutEvents(
            id: step.entity.id,
            userId: userId,
            source: source,
            forceRemoteSync: forceRemoteSync,
          );
        } else if (step.type == _CascadeStepType.update && step.updateData != null) {
          try {
            await step.manager.localAdapter.patch(
              id: step.entity.id,
              delta: step.updateData!,
              userId: userId,
            );
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
          if (step.type == _CascadeStepType.delete) {
            analyticsBuilder.recordEntityDeleted(step.entity.runtimeType);
            deletedEntities.putIfAbsent(step.entity.runtimeType, () => []).add(step.entity);
          }
        } else {
          analyticsBuilder.recordError();
          errors.add('Failed to ${step.type == _CascadeStepType.delete ? 'delete' : 'update'} ${step.entity.runtimeType}:${step.entity.id}');
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
        message: step.type == _CascadeStepType.delete ? 'Deleting ${step.entity.runtimeType.toString()}' : 'Updating ${step.entity.runtimeType.toString()}',
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

  /// Executes a block of code within a single atomic transaction.
  ///
  /// This is crucial for multi-step processes where all steps must succeed or
  /// fail together. This mainly delegates to the local adapter.
  Future<R> transaction<R>(Future<R> Function() action) {
    _ensureInitialized();
    return localAdapter.transaction(action);
  }

  /// Returns a visualization of the delete plan for the given entity.
  /// This is useful for previewing what will happen before deleting.
  Future<CascadeDeletePreview?> getDeletePlan(String id, {String? userId}) async {
    _ensureInitialized();

    // Check for entity existence (reuse read logic but lighter? No, need entity object for plan)
    final entity = await read(id, userId: userId);
    if (entity == null) return null;

    final analyticsBuilder = CascadeAnalyticsBuilder();
    analyticsBuilder.startOperation(dryRun: true);
    final plan = await _buildCascadeDeletePlan(entity, userId ?? entity.userId, analyticsBuilder);

    final stepsPreview = plan.steps.map((step) {
      String action = 'Delete';
      Map<String, dynamic>? details;

      if (step.type == _CascadeStepType.update) {
        action = 'SetNull';
        details = step.updateData;
      }

      return CascadeDeleteStepPreview(
        entityType: step.entity.runtimeType.toString(),
        entityId: step.entity.id,
        action: action,
        details: details,
      );
    }).toList();

    final warnings = <String>[];
    if (!plan.canDelete) {
      plan.restrictedRelations.forEach((relation, entities) {
        warnings.add('Cannot delete because of restrict constraint on relation "$relation" (${entities.length} items)');
      });
    }

    return CascadeDeletePreview(
      mainEntityType: T.toString(),
      mainEntityId: id,
      steps: stepsPreview,
      canDelete: plan.canDelete,
      warningMessages: warnings,
    );
  }

  /// Builds a cascade delete plan for the given entity.
  Future<_CascadeDeletePlan<T>> _buildCascadeDeletePlan(
    T entity,
    String userId,
    CascadeAnalyticsBuilder analyticsBuilder,
  ) async {
    final restrictedRelations = <String, List<DatumEntityInterface>>{};
    final deleteOrder = <_CascadeDeleteStep>[];
    final visitedEntities = <String>{};

    // Start with the main entity
    final mainStep = _CascadeDeleteStep(
      entity: entity,
      manager: this,
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

    return _CascadeDeletePlan(
      mainEntity: entity,
      steps: deleteOrder,
      canDelete: restrictedRelations.isEmpty,
      restrictedRelations: restrictedRelations,
    );
  }

  /// Recursively builds the delete plan for cascading deletes.
  Future<void> _buildDeletePlanRecursive(
    _CascadeDeleteStep currentStep,
    String userId,
    List<_CascadeDeleteStep> deleteOrder,
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
        final relatedEntities = await _getRelatedEntities(relationalEntity, relation, userId);
        if (relatedEntities.isNotEmpty) {
          restrictedRelations[relationName] = relatedEntities;
        }
      } else if (relation.shouldCascadeDelete) {
        // Add related entities to delete plan
        final relatedEntities = await _getRelatedEntities(relationalEntity, relation, userId);
        for (final relatedEntity in relatedEntities) {
          final relatedStep = _CascadeDeleteStep(
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
          final relatedEntities = await _getRelatedEntities(relationalEntity, relation, userId);
          String? foreignKeyName;
          if (relation is HasMany) {
            foreignKeyName = relation.foreignKey;
          } else if (relation is HasOne) {
            foreignKeyName = relation.foreignKey;
          }

          if (foreignKeyName != null) {
            for (final relatedEntity in relatedEntities) {
              final relatedStep = _CascadeDeleteStep(
                entity: relatedEntity,
                manager: relation.getRelatedManager(),
                relationName: relationName,
                type: _CascadeStepType.update,
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
  Future<List<DatumEntityInterface>> _getRelatedEntities(
    DatumEntityInterface parent,
    Relation relation,
    String userId,
  ) async {
    // Create a cache key for this relationship query
    final cacheKey = '${parent.runtimeType}:${parent.id}:${relation.runtimeType}:$userId';

    // Check cache first
    final cached = _getCachedRelationshipQuery(cacheKey);
    if (cached != null) {
      return cached;
    }

    List<DatumEntityInterface> results;

    if (relation is HasMany) {
      final localKeyValue = parent.toDatumMap()[relation.localKey];
      if (localKeyValue == null) return [];

      final manager = relation.getRelatedManager();
      results = await manager.query(
        DatumQuery(filters: [Filter(relation.foreignKey, FilterOperator.equals, localKeyValue)]),
        source: DataSource.local,
        // For cascade delete, don't filter by userId to find all related entities
      );
    } else if (relation is HasOne) {
      final localKeyValue = parent.toDatumMap()[relation.localKey];
      if (localKeyValue == null) return [];

      final manager = relation.getRelatedManager();
      results = await manager.query(
        DatumQuery(filters: [Filter(relation.foreignKey, FilterOperator.equals, localKeyValue)]),
        source: DataSource.local,
        // For cascade delete, don't filter by userId to find all related entities
      );
    } else if (relation is ManyToMany) {
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
    } else if (relation is BelongsTo) {
      final foreignKeyValue = parent.toDatumMap()[relation.foreignKey];
      if (foreignKeyValue == null) return [];

      final manager = relation.getRelatedManager();
      final entity = await manager.read(foreignKeyValue); // Don't filter by userId for cascade delete
      results = entity != null ? [entity] : [];
    } else {
      results = [];
    }

    // Cache the results
    _cacheRelationshipQuery(cacheKey, results);
    return results;
  }

  /// Executes the cascade delete plan.
  Future<CascadeDeleteResult<T>> _executeCascadeDeletePlan(
    _CascadeDeletePlan<T> plan,
    String userId,
    DataSource source,
    bool forceRemoteSync,
  ) async {
    final deletedEntities = <Type, List<DatumEntityInterface>>{};
    final errors = <String>[];

    // First, handle setNull operations for BelongsTo relationships
    await _executeSetNullOperations(plan.mainEntity, userId, source, forceRemoteSync, errors);

    // Execute deletes in the planned order
    for (final step in plan.steps) {
      try {
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

  /// Executes setNull operations for BelongsTo relationships.
  Future<void> _executeSetNullOperations(
    T entity,
    String userId,
    DataSource source,
    bool forceRemoteSync,
    List<String> errors,
  ) async {
    if (!entity.isRelational) {
      return;
    }

    final relationalEntity = entity as RelationalDatumEntity;

    // Process each relationship to find setNull operations
    final relations = relationalEntity.relations;
    for (final entry in relations.entries) {
      final relationName = entry.key;
      final relation = entry.value;

      if (relation.shouldSetNullOnDelete && relation is BelongsTo) {
        try {
          // For setNull on BelongsTo, we need to find entities that reference this entity
          // and set their foreign keys to null
          final relatedManager = relation.getRelatedManager();

          // Query for entities that have this entity's ID as their foreign key
          final entitiesToUpdate = await relatedManager.query(
            DatumQuery(filters: [Filter(relation.foreignKey, FilterOperator.equals, entity.id)]),
            source: DataSource.local,
            userId: userId,
          );

          // Update each related entity to set the foreign key to null
          for (final relatedEntity in entitiesToUpdate) {
            // Create a patch operation to set the foreign key to null
            final patchData = {relation.foreignKey: null};
            await relatedManager.localAdapter.patch(
              id: relatedEntity.id,
              delta: patchData,
              userId: userId,
            );

            // Queue the update for sync if needed
            if (source == DataSource.local || forceRemoteSync) {
              final operation = relatedManager._createOperation(
                userId: userId,
                type: DatumOperationType.update,
                entityId: relatedEntity.id,
                data: relatedEntity,
                delta: patchData,
              );
              final payload = operation.delta ?? operation.data?.toDatumMap(target: MapTarget.remote);
              final encoded = payload != null ? await relatedManager._isolateHelper.computeJsonEncode(payload) : '';
              final size = encoded.length;
              await relatedManager._queueManager.enqueue(operation.copyWith(sizeInBytes: size));
            }
          }
        } catch (e) {
          errors.add('Error executing setNull operation for relation "$relationName": $e');
        }
      }
    }
  }

  /// Performs a delete without firing events (used internally for cascading).
  Future<bool> performDeleteWithoutEvents({
    required String id,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
  }) async {
    final existing = await localAdapter.read(id); // Don't filter by userId for cascade deletes
    if (existing == null) {
      return false;
    }

    final deleted = await localAdapter.delete(id, userId: existing.userId); // Use the entity's actual userId
    if (!deleted) {
      return false;
    }

    if (source == DataSource.local || forceRemoteSync) {
      final operation = _createOperation(
        userId: existing.userId, // Use the entity's actual userId
        type: DatumOperationType.delete,
        entityId: id,
      );
      // Calculate size for delete operation (it's small, just the ID)
      final payload = {'id': id};
      final size = (await _isolateHelper.computeJsonEncode(payload)).length;

      await _queueManager.enqueue(operation.copyWith(sizeInBytes: size));
    }

    return true;
  }

  /// DEPRECATED: This method will be removed in a future version. Use the `withRelated` parameter in the `query` method for eager loading, or the `fetch()` method on the relation object for lazy loading.
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
  Future<List<R>> fetchRelated<R extends DatumEntityInterface>(
    T parent,
    String relationName, {
    DataSource source = DataSource.local,
  }) async {
    _ensureInitialized();

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

  /// DEPRECATED: This method will be removed in a future version. Use the `withRelated` parameter in the `query` method for eager loading, or the `fetch()` method on the relation object for lazy loading.
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
  Stream<List<R>>? watchRelated<R extends DatumEntityInterface>(
    T parent,
    String relationName,
  ) {
    _ensureInitialized();

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

    return localAdapter.watchRelated(
      parent,
      relationName,
      relatedManager.localAdapter,
    );
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('DatumManager must be initialized before use. Call initialize() first.');
    }
    ensureNotDisposed();
  }

  Future<DatumSyncResult<T>> synchronize(
    String userId, {
    DatumSyncOptions<DatumEntityInterface>? options,
    DatumSyncScope? scope,
  }) async {
    _ensureInitialized();

    _logger.info('🔄 [${T.toString()}] Starting sync for user: $userId');

    return _syncRequestStrategy.execute(
      () async {
        if (_isSyncPaused) {
          _logger.info('Sync for user $userId skipped: manager is paused.');
          return DatumSyncResult.skipped(
            userId,
            await getPendingCount(userId),
            reason: 'Sync is paused',
          );
        }

        // Handle user switching logic before proceeding with synchronization.
        if (_syncEngineInstance.lastActiveUserId != null && _syncEngineInstance.lastActiveUserId != userId) {
          if (config.defaultUserSwitchStrategy == UserSwitchStrategy.promptIfUnsyncedData) {
            final oldUserOps = await _queueManager.getPending(
              _syncEngineInstance.lastActiveUserId ?? '',
            );
            if (oldUserOps.isNotEmpty) {
              throw UserSwitchException(
                oldUserId: _syncEngineInstance.lastActiveUserId,
                newUserId: userId,
                message: 'Cannot switch user while unsynced data exists for the previous user.',
              );
            }
          }
          // Other strategies like syncThenSwitch or clearAndFetch would be handled here.
        }

        try {
          // Merge provided options with defaults from config
          final mergedOptions = _mergeSyncOptions(options);

          // Convert options to the correct type if needed.
          // This handles cases where options might be passed with a different generic type from Datum.
          var typedOptions = mergedOptions != null
              ? DatumSyncOptions<T>(
                  includeDeletes: mergedOptions.includeDeletes,
                  resolveConflicts: mergedOptions.resolveConflicts,
                  forceFullSync: mergedOptions.forceFullSync,
                  overrideBatchSize: mergedOptions.overrideBatchSize,
                  timeout: mergedOptions.timeout,
                  direction: mergedOptions.direction,
                  conflictResolver: mergedOptions.conflictResolver is DatumConflictResolver<T> ? mergedOptions.conflictResolver as DatumConflictResolver<T> : null,
                  query: mergedOptions.query,
                )
              : null;

          // Allow custom sync direction resolution via callback
          final pendingCount = await getPendingCount(userId);
          final currentDirection = typedOptions?.direction ?? config.defaultSyncDirection;

          if (config.syncDirectionResolver != null) {
            final resolvedDirection = config.syncDirectionResolver!(pendingCount, currentDirection);
            if (resolvedDirection != null && resolvedDirection != currentDirection) {
              _logger.debug('Custom sync direction resolver changed direction from $currentDirection to $resolvedDirection for user $userId');
              final optimizedOptions = typedOptions?.copyWith(direction: resolvedDirection) ?? DatumSyncOptions<T>(direction: resolvedDirection);
              typedOptions = optimizedOptions;
            }
          }

          // If no scope is provided but options contain a query, create a scope from the query
          DatumSyncScope? effectiveScope = scope;
          if (effectiveScope == null && typedOptions?.query != null && typedOptions!.query != const DatumQuery()) {
            effectiveScope = DatumSyncScope(query: typedOptions.query);
          }

          // Check if sync should be skipped based on final direction and pending operations
          // Check if sync should be skipped based on final direction and pending operations
          final finalDirection = typedOptions?.direction ?? config.defaultSyncDirection;
          if (finalDirection == SyncDirection.pushOnly && pendingCount == 0) {
            // If the direction is pushOnly and there are no pending operations,
            // we can skip the sync entirely for this manager.
            _logger.info('Push-only sync for user $userId skipped: no pending operations.');
            return DatumSyncResult.skipped(userId, 0);
          }

          DatumSyncResult<T> result;
          List<DatumSyncEvent<T>> events;

          if (config.useIsolateSync) {
            // Capture dependencies into local variables to avoid capturing 'this' in Isolate.run
            final localAdapterCaptured = localAdapter;
            final remoteAdapterCaptured = remoteAdapter;
            final conflictResolverCaptured = _conflictResolver;
            final queueManagerCaptured = _queueManager;
            final conflictDetectorCaptured = _conflictDetector;
            final loggerCaptured = _logger.getWorkerLogger();
            // Sanitize config to remove unsendable callbacks
            final configCaptured = config.copyWith<T>(
              initialUserId: _dummyInitialUserId,
              onMigrationError: null,
              syncDirectionResolver: null,
            );
            final connectivityCaptured = _connectivity;
            final isolateHelperCaptured = _isolateHelper;
            final deviceIdCaptured = deviceId;
            final optionsCaptured = typedOptions;
            final scopeCaptured = effectiveScope;

            // Offload the entire sync process to a background isolate.
            // note: This requires Adapters and other dependencies to be sendable.
            (result, events) = await Isolate.run(() => _runSyncInIsolate<T>(
                  userId,
                  localAdapterCaptured,
                  remoteAdapterCaptured,
                  conflictResolverCaptured,
                  queueManagerCaptured,
                  conflictDetectorCaptured,
                  loggerCaptured,
                  configCaptured,
                  connectivityCaptured,
                  isolateHelperCaptured,
                  deviceIdCaptured,
                  optionsCaptured,
                  scopeCaptured,
                ));
          } else {
            (result, events) = await _syncEngineInstance.synchronize(
              userId,
              options: typedOptions,
              scope: effectiveScope,
            );
          }

          _processSyncEvents(events);
          // Persist the result of the sync operation.
          if (!result.wasSkipped) {
            await localAdapter.saveLastSyncResult(userId, result);
            // Also update sync metadata in persistence
            final metadata = await localAdapter.getSyncMetadata(userId);
            if (metadata != null) {
              await persistence?.saveSyncMetadata(userId, metadata);
            }
          }
          return result;
        } on Object catch (e, _) {
          // If it's a SyncExceptionWithEvents, process events and throw the original error
          if (e is SyncExceptionWithEvents<T>) {
            _processSyncEvents(e.events);
            throw e.originalError;
          }
          // Otherwise, re-throw the original error
          rethrow;
        }
      },
      isSyncInProgress: () => _syncEngineInstance.isSyncing,
      onSkipped: () {
        _logger.info('Sync for user $userId skipped: another sync is in progress.');
        return DatumSyncResult.skipped(
          userId,
          0, // Can't reliably get pending count here without async, so default to 0.
          reason: 'Sync in progress',
        );
      },
    );
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
    ensureNotDisposed();

    if (newUserId.isEmpty) {
      throw ArgumentError.value(newUserId, 'newUserId', 'Must not be empty');
    }

    final resolvedStrategy = strategy ?? config.defaultUserSwitchStrategy;
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
      // Stop auto-sync for the old user to prevent resource leaks.
      if (oldUserId != null) {
        stopAutoSync(userId: oldUserId);
      }

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
            oldUserId: oldUserId,
            newUserId: newUserId,
            message: 'Unsynced data exists.',
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

    final syncInterval = interval ?? config.autoSyncInterval;

    // Schedule the first sync immediately, then schedule subsequent syncs after each completes
    _scheduleNextAutoSync(userId, syncInterval);

    _logger.info(
      'Auto-sync started for user $userId (interval: $syncInterval)',
    );
  }

  /// Schedules the next auto-sync for the specified user after the given interval.
  void _scheduleNextAutoSync(String userId, Duration interval) {
    if (isDisposed || _isSyncPaused) {
      return;
    }

    _autoSyncTimers[userId] = Timer(interval, () async {
      // Remove this timer from the map since it's fired
      _autoSyncTimers.remove(userId);

      try {
        await synchronize(userId);
        // After successful sync, schedule the next one
        _scheduleNextAutoSync(userId, interval);
      } catch (e, stack) {
        _logger.error('Auto-sync for user $userId failed: $e', stack);
        // Even on failure, schedule the next sync to maintain the schedule
        _scheduleNextAutoSync(userId, interval);
      }
    });

    // Update the next sync time after the timer is scheduled
    _updateNextSyncTime();
  }

  /// Stops automatic synchronization for one or all users.
  void stopAutoSync({String? userId}) {
    if (userId != null) {
      final timer = _autoSyncTimers.remove(userId);
      timer?.cancel();
      // If we are stopping a specific user's timer, also ensure it's not
      // marked for resumption if the manager is paused.
      if (_isSyncPaused) {
        _pausedAutoSyncUserIds.remove(userId);
      }

      // Update the global next sync time after stopping this timer
      _updateNextSyncTime();

      // Only log if a timer was actually stopped
      if (timer != null) {
        _logger.info('Auto-sync stopped for user: $userId');
      }
      return;
    }

    for (final timer in _autoSyncTimers.values) {
      timer.cancel();
    }
    _autoSyncTimers.clear();
    // If we are stopping all timers, clear the list of users to resume.
    if (_isSyncPaused) {
      _pausedAutoSyncUserIds.clear();
    }

    // Update the global next sync time after stopping all timers
    _updateNextSyncTime();
  }

  /// Updates the global next sync time based on all active auto-sync timers.
  ///
  /// If no timers are active, sets the next sync time to null.
  /// If timers are active, calculates the earliest next sync time.
  void _updateNextSyncTime() {
    if (_nextSyncTimeSubject.isClosed) return;

    if (_autoSyncTimers.isEmpty) {
      _nextSyncTimeSubject.add(null);
      return;
    }

    // Since all timers use the same interval and are started at roughly the same time,
    // they should all fire at the same time. But to be safe, we'll calculate the earliest.
    final now = DateTime.now();
    final syncInterval = config.autoSyncInterval;
    final nextSyncTime = now.add(syncInterval);

    _nextSyncTimeSubject.add(nextSyncTime);
  }

  /// Unsubscribes from remote change events.
  ///
  /// This method stops the manager from listening to remote change notifications,
  /// which can be useful for reducing network activity or preventing
  /// unnecessary processing during certain application states (e.g., when the app
  /// is in background or when you want to temporarily ignore remote updates).
  ///
  /// Call [resubscribeToRemoteChanges] to re-enable remote change listening.
  ///
  /// Note: This only affects remote change subscriptions and does not
  /// impact local change processing or synchronization operations.
  Future<void> unsubscribeFromRemoteChanges() async {
    await remoteAdapter.unsubscribeFromChanges();
    _isSubscribedToRemoteChanges = false;
  }

  /// Re-subscribes to remote change events.
  ///
  /// This method re-enables listening to remote change notifications
  /// after a previous call to [unsubscribeFromRemoteChanges]. This restores
  /// the normal flow of remote change events being processed and applied locally.
  ///
  /// Note: This only affects remote change subscriptions and does not
  /// impact local change processing or synchronization operations.
  Future<void> resubscribeToRemoteChanges() async {
    await remoteAdapter.resubscribeToChanges();
    _isSubscribedToRemoteChanges = true;
  }

  /// Gets cached relationship query results.
  List<DatumEntityInterface>? _getCachedRelationshipQuery(String cacheKey) {
    final cached = _relationshipQueryCache[cacheKey];
    if (cached != null) {
      _logger.debug('Using cached relationship query results for key: $cacheKey');
    }
    return cached;
  }

  /// Caches relationship query results.
  void _cacheRelationshipQuery(String cacheKey, List<DatumEntityInterface> results) {
    _relationshipQueryCache[cacheKey] = results;
    _logger.debug('Cached relationship query results for key: $cacheKey (${results.length} entities)');
  }

  /// Creates a cache key for a query.
  String _createQueryCacheKey(DatumQuery query, DataSource source, String? userId) {
    final buffer = StringBuffer();
    buffer.write('${T.toString()}:${source.name}');
    if (userId != null) buffer.write(':$userId');

    // Include filters in cache key (order matters for consistency)
    if (query.filters.isNotEmpty) {
      buffer.write(':filters=');
      for (final filter in query.filters) {
        if (filter is Filter) {
          buffer.write('${filter.field}${filter.operator}${filter.value};');
        } else if (filter is CompositeFilter) {
          buffer.write('composite${filter.operator}${filter.conditions.length};');
        }
      }
    }

    // Include sorting in cache key
    if (query.sorting.isNotEmpty) {
      buffer.write(':sort=');
      for (final sort in query.sorting) {
        buffer.write('${sort.field}${sort.descending ? 'desc' : 'asc'};');
      }
    }

    // Include limit/offset in cache key
    if (query.limit != null) {
      buffer.write(':limit=${query.limit}');
    }
    if (query.offset != null) {
      buffer.write(':offset=${query.offset}');
    }

    return buffer.toString();
  }

  /// Gets cached query results.
  List<T>? _getCachedQuery(String cacheKey) {
    final cached = _queryCache[cacheKey];
    if (cached != null) {
      _logger.debug('Using cached query results for key: $cacheKey');
    }
    return cached;
  }

  /// Caches query results.
  void _cacheQuery(String cacheKey, List<T> results) {
    _queryCache[cacheKey] = results;
    _logger.debug('Cached query results for key: $cacheKey (${results.length} entities)');
  }

  /// Clears all caches. Useful for testing or when data consistency is critical.
  void clearCaches() {
    _relationshipQueryCache.clear();
    _entityExistenceCache.clear();
    _queryCache.clear();
    _logger.debug('All caches cleared');
  }

  /// Clears relationship caches for a specific entity type.
  void clearRelationshipCacheForType(Type entityType) {
    // Also clear related query caches
    _relationshipQueryCache.removeWhere((key, _) => key.startsWith('${entityType.toString()}:'));
    _logger.debug('Cleared relationship caches for $entityType');
  }

  /// Invalidates caches that might be affected by changes to an entity.
  void _invalidateCachesForEntity(T entity) {
    // Clear query caches that might be affected by this entity change
    _queryCache.removeWhere((key, _) {
      // For simplicity, clear all query caches when any entity changes
      // In a more sophisticated implementation, we could be more selective
      return true;
    });

    // Clear relationship query caches that involve this entity
    _relationshipQueryCache.removeWhere((key, _) {
      // Remove caches where this entity is the parent or child in relationships
      return key.startsWith('${entity.runtimeType}:${entity.id}:') || key.contains(':${entity.runtimeType}:${entity.id}');
    });

    // Clear entity existence cache for this entity
    _entityExistenceCache.remove('${entity.runtimeType}:${entity.id}');

    _logger.debug('Invalidated caches for entity ${entity.runtimeType}:${entity.id}');
  }

  /// Gets cache statistics for monitoring and debugging.
  Map<String, int> getCacheStats() {
    return {
      'relationship_queries': _relationshipQueryCache.length,
      'entity_existence': _entityExistenceCache.length,
      'queries': _queryCache.length,
    };
  }

  /// Refreshes all reactive streams by clearing caches and forcing streams to
  /// re-evaluate their data. This is useful when external state changes
  /// (like user switches) require all streams to refresh their data.
  ///
  /// This method clears internal caches and forces reactive streams to emit
  /// fresh data on their next evaluation. For adapters with reactive streams,
  /// this ensures that streams show the most current data after state changes.
  Future<void> refreshStreams() async {
    _ensureInitialized();

    // Clear all caches to ensure fresh data
    clearCaches();

    // Emit a special refresh event that will be picked up by all streams
    // We use a special marker to indicate this is a refresh event
    _eventController.add(
      DataChangeEvent<T>(
        userId: '__REFRESH_STREAMS__', // Special marker for refresh
        data: null,
        changeType: ChangeType.updated,
        source: DataSource.local,
      ),
    );

    _logger.debug('Refreshed all streams for $T');
  }

  /// Releases all resources held by the manager and its adapters.
  @override
  Future<void> dispose() async {
    if (isDisposed) return;
    stopAutoSync();
    clearCaches(); // Clear caches on dispose
    await _queueManager.dispose();
    _syncRequestStrategy.dispose();
    _isolateHelper.dispose();
    await localAdapter.dispose();
    await remoteAdapter.dispose();
    await super.dispose(); // Call the mixin's dispose
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

    // Refresh all streams to ensure they show data for the new user
    // Only call this if Datum is initialized (when using Datum singleton)
    if (Datum.isInitialized) {
      unawaited(Datum.instance.refreshStreams());
    }

    // Also emit to the shared user change stream for reactive queries
    // This is a bit of a hack since we don't have direct access to Datum._userChangeController
    // We'll emit through the event stream and let Datum handle it
  }

  Future<bool> _hasUnsyncedData(String? userId) async {
    if (userId == null || userId.isEmpty) return false;
    return (await getPendingCount(userId)) > 0;
  }

  void _notifyObservers(void Function(DatumObserver<T> observer) action) {
    for (final weakObserver in _localObservers) {
      final observer = weakObserver.target;
      if (observer != null) {
        action(observer);
      }
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
  Future<List<DatumSyncOperation<T>>> getPendingOperations(String userId) async {
    _ensureInitialized();
    return _queueManager.getPending(userId);
  }

  /// Gets the current storage size in bytes from the local adapter.
  Future<int> getStorageSize({String? userId}) {
    _ensureInitialized();
    return localAdapter.getStorageSize(userId: userId);
  }

  /// Reactively watches the storage size in bytes from the local adapter.
  Stream<int> watchStorageSize({String? userId}) {
    _ensureInitialized();
    return localAdapter.watchStorageSize(userId: userId);
  }

  /// Retrieves the result of the last synchronization for a user from local storage.
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) async {
    _ensureInitialized();
    return localAdapter.getLastSyncResult(userId);
  }

  /// Merges provided sync options with defaults from config.
  /// Provided options take precedence over defaults.
  DatumSyncOptions<DatumEntityInterface>? _mergeSyncOptions(DatumSyncOptions<DatumEntityInterface>? provided) {
    final defaults = config.defaultSyncOptions;
    if (defaults == null) return provided;
    if (provided == null) return defaults;

    // Merge provided options with defaults, preferring provided values
    return DatumSyncOptions<DatumEntityInterface>(
      includeDeletes: provided.includeDeletes,
      resolveConflicts: provided.resolveConflicts,
      forceFullSync: provided.forceFullSync,
      overrideBatchSize: provided.overrideBatchSize ?? defaults.overrideBatchSize,
      timeout: provided.timeout ?? defaults.timeout,
      direction: provided.direction ?? defaults.direction,
      conflictResolver: provided.conflictResolver ?? defaults.conflictResolver,
      query: provided.query,
    );
  }

  /// Fetches sync metadata from the remote server for this entity type.
  ///
  /// This is a convenience method that calls [RemoteAdapter.getSyncMetadata].
  /// Returns null if no metadata exists or if the remote adapter doesn't support this operation.
  Future<DatumSyncMetadata?> getRemoteSyncMetadata(String userId) async {
    _ensureInitialized();
    return remoteAdapter.getSyncMetadata(userId);
  }

  /// Performs a health check on the local and remote adapters and updates the
  /// [health] stream with the result.
  Future<DatumHealth> checkHealth() async {
    return _syncEngineInstance.checkHealth();
  }

  /// Pauses all synchronization activity for this manager.
  ///
  /// While paused, any calls to `synchronize()` will be skipped immediately.
  /// This also stops any running auto-sync timers for this manager.
  void pauseSync() {
    _prePauseStatus = currentStatus.status;
    // Remember which users had active auto-sync timers.
    _pausedAutoSyncUserIds.addAll(_autoSyncTimers.keys);
    stopAutoSync();
    _isSyncPaused = true;
    if (!_statusSubject.isClosed) {
      _statusSubject.add(currentStatus.copyWith(status: DatumSyncStatus.paused));
    }
    _logger.info('Sync paused for manager $T.');
  }

  /// Resumes synchronization activity for this manager.
  void resumeSync() {
    _isSyncPaused = false;
    // Restore the status to what it was before being paused, or default to idle.
    final statusToRestore = _prePauseStatus ?? DatumSyncStatus.idle;
    if (!_statusSubject.isClosed) {
      _statusSubject.add(currentStatus.copyWith(status: statusToRestore));
    }
    _prePauseStatus = null;

    // Restart any auto-sync timers that were active before the pause.
    _logger.info(
      'Resuming auto-sync for ${_pausedAutoSyncUserIds.length} user(s)...',
    );
    for (final userId in _pausedAutoSyncUserIds) {
      startAutoSync(userId);
    }
    _pausedAutoSyncUserIds.clear();
    _logger.info('Sync resumed for manager $T.');
  }
}

extension DatumManagerAutoSyncInfo<T extends DatumEntityInterface> on DatumManager<T> {
  /// Gets the [DateTime] of the next scheduled auto-sync as a `Future`.
  ///
  /// Returns `null` if no auto-sync is currently scheduled.
  Future<DateTime?> getNextSyncTime() async {
    return _nextSyncTimeSubject.value;
  }

  /// Gets the [Duration] until the next scheduled auto-sync as a `Future`.
  ///
  /// Returns `null` if no auto-sync is currently scheduled.
  Future<Duration?> getNextSyncDuration() async {
    final nextTime = await getNextSyncTime();
    if (nextTime == null) return null;
    return nextTime.difference(DateTime.now());
  }
}

/// A dummy function for the initial user ID to avoid closure capture issues.
Future<String?> _dummyInitialUserId() async => null;

/// Executes the sync process in a separate isolate.
Future<(DatumSyncResult<T>, List<DatumSyncEvent<T>>)> _runSyncInIsolate<T extends DatumEntityInterface>(
  String userId,
  LocalAdapter<T> localAdapter,
  RemoteAdapter<T> remoteAdapter,
  DatumConflictResolver<T> conflictResolver,
  QueueManager<T> queueManager,
  DatumConflictDetector<T> conflictDetector,
  DatumLogger logger,
  DatumConfig<T> config,
  DatumConnectivityChecker connectivityChecker,
  IsolateHelper isolateHelper,
  String? deviceId,
  DatumSyncOptions<T>? options,
  DatumSyncScope? scope,
) async {
  // Create dummy controllers for the isolated engine since we only care about the return values
  // and the side effects on the adapters.
  final dummyEventController = StreamController<DatumSyncEvent<T>>();
  final dummyStatusSubject = BehaviorSubject<DatumSyncStatusSnapshot>.seeded(DatumSyncStatusSnapshot.initial(userId));
  final dummyMetadataSubject = BehaviorSubject<DatumSyncMetadata>();

  try {
    final engine = DatumSyncEngine<T>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        conflictResolver: conflictResolver,
        queueManager: queueManager,
        conflictDetector: conflictDetector,
        logger: logger,
        config: config,
        connectivityChecker: connectivityChecker,
        eventController: dummyEventController,
        statusSubject: dummyStatusSubject,
        metadataSubject: dummyMetadataSubject,
        isolateHelper: isolateHelper,
        deviceId: deviceId);

    return await engine.synchronize(
      userId,
      options: options,
      scope: scope,
    );
  } finally {
    dummyEventController.close();
    dummyStatusSubject.close();
    dummyMetadataSubject.close();
  }
}
