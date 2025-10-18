import 'dart:async';

import 'package:datum/datum.dart';
import 'package:datum/source/utils/duration_formatter.dart';

import 'package:rxdart/rxdart.dart';

// ANSI color codes for logging
const _ansiReset = '\x1B[0m';
const _ansiYellow = '\x1B[33m';
const _ansiGreen = '\x1B[32m';
const _ansiCyan = '\x1B[36m';

// Top-level private functions for colored logging
String _green(Object text) => '$_ansiGreen$text$_ansiReset';
String _yellow(Object text) => '$_ansiYellow$text$_ansiReset';
String _cyan(Object text) => '$_ansiCyan$text$_ansiReset';

class Datum {
  /// The singleton instance of the Datum engine.
  static Datum? _instance;
  static Datum get instance {
    if (_instance == null) {
      throw StateError(
        'Datum has not been initialized. Call Datum.initialize() first.',
      );
    }
    return _instance!;
  }

  static Datum? get instanceOrNull => _instance;

  final DatumConfig config;
  final Map<Type, DatumManager<DatumEntity>> _managers = {};
  final Map<Type, AdapterPair> _adapterPairs = {};
  final DatumConnectivityChecker connectivityChecker;
  final List<GlobalDatumObserver> globalObservers = [];
  final DatumLogger logger;
  final List<StreamSubscription<DatumSyncEvent<DatumEntity>>>
      _managerSubscriptions = [];

  // Stream controllers for events and status
  final StreamController<DatumSyncEvent<DatumEntity>> _eventController =
      StreamController.broadcast();
  Stream<DatumSyncEvent> get events => _eventController.stream;

  final BehaviorSubject<Map<String, DatumSyncStatusSnapshot>> _statusSubject =
      BehaviorSubject.seeded({});
  Stream<DatumSyncStatusSnapshot?> statusForUser(String userId) =>
      _statusSubject.stream.map((map) => map[userId]);

  final Map<String, DatumSyncStatusSnapshot> _snapshots = {};

  // Stream controller for metrics
  final BehaviorSubject<DatumMetrics> _metricsSubject = BehaviorSubject.seeded(
    const DatumMetrics(),
  );
  Stream<DatumMetrics> get metrics => _metricsSubject.stream;
  DatumMetrics get currentMetrics => _metricsSubject.value;

  /// A stream that aggregates the health status of all registered managers.
  ///
  /// It emits a map where the key is the entity [Type] and the value is the
  /// latest [DatumHealth] for that manager. This is useful for building a
  /// global health dashboard.
  Stream<Map<Type, DatumHealth>> get allHealths {
    if (_managers.isEmpty) {
      return Stream.value({});
    }
    // Extract the streams and their corresponding types (keys).
    final healthStreams = _managers.values.map((m) => m.health).toList();
    final types = _managers.keys.toList();

    // Combine the latest values from all health streams into a single list.
    return CombineLatestStream.list(healthStreams).map((healthList) {
      // Reconstruct the map from the types and the emitted health list.
      return Map.fromIterables(types, healthList);
    });
  }

  Datum._({
    required this.config,
    required this.connectivityChecker,
    DatumLogger? logger,
  }) : logger = logger ?? DatumLogger(enabled: config.enableLogging);

  /// Initializes the central Datum engine as a singleton.
  ///
  /// This must be called once before accessing [Datum.instance] or any other methods.
  static Future<Datum> initialize({
    required DatumConfig config,
    required DatumConnectivityChecker connectivityChecker,
    DatumLogger? logger,
    List<DatumRegistration> registrations = const [],
    List<GlobalDatumObserver> observers = const [],
  }) async {
    if (_instance != null) {
      // Prevent re-initialization to avoid unpredictable behavior.
      // If re-configuration is needed, a `Datum.dispose()` or `Datum.reset()`
      // should be called first.
      throw StateError('Datum has already been initialized.');
    }
    // If logging is disabled in the config, we should not produce any logs,
    // even if a custom logger is provided.
    if (!config.enableLogging) {
      return _initializeSilently(
          config, connectivityChecker, logger, registrations, observers);
    }
    // Initialize logger early to use it for initialization logging.
    final initLogger = logger ?? DatumLogger(enabled: config.enableLogging);
    final logBuffer = StringBuffer();

    final datum = Datum._(
      config: config,
      connectivityChecker: connectivityChecker,
      logger: logger,
    );
    datum.globalObservers.addAll(observers);

    datum._logInitializationHeader(logBuffer,
        config: config, connectivityChecker: connectivityChecker);
    datum._logObservers(logBuffer);
    if (registrations.isNotEmpty) {
      logBuffer.writeln('├─ 📦 Registering Entities');
    }
    for (final reg in registrations) {
      // ignore: unused_local_variable
      // Use <TT> to avoid shadowing the generic type from the capture method.
      reg.capture(
        <TT extends DatumEntity>() =>
            datum._register<TT>(reg as DatumRegistration<TT>, logBuffer),
      );
    }
    await datum._initializeManagers(logBuffer);
    await datum._logPendingOperationsSummary(logBuffer);

    logBuffer.write('└─ ✅ Initialization Complete.');
    initLogger.info(logBuffer.toString());

    datum._listenToEventsForMetrics();
    return _instance = datum;
  }

  /// A private helper to initialize Datum without any logging output.
  static Future<Datum> _initializeSilently(
    DatumConfig config,
    DatumConnectivityChecker connectivityChecker,
    DatumLogger? logger,
    List<DatumRegistration> registrations,
    List<GlobalDatumObserver> observers,
  ) async {
    final datum = Datum._(
      config: config,
      connectivityChecker: connectivityChecker,
      logger: null, // Force a disabled logger when logging is off.
    );
    datum.globalObservers.addAll(observers);

    for (final reg in registrations) {
      reg.capture(
        <TT extends DatumEntity>() =>
            datum._register<TT>(reg as DatumRegistration<TT>),
      );
    }
    await datum._initializeManagers(StringBuffer());
    datum._listenToEventsForMetrics();
    return _instance = datum;
  }

  void _logInitializationHeader(
    StringBuffer logBuffer, {
    required DatumConfig config,
    required DatumConnectivityChecker connectivityChecker,
  }) {
    logBuffer.writeln('🚀 Initializing Datum...');
    logBuffer.writeln(_cyan(
        '   Hello! Datum is your smart offline-first data synchronization framework 😊'));
    logBuffer.writeln('├─ ⚙️  Configuration');
    logBuffer.writeln(
        '│  ├─ 📝 ${_yellow('Logging')}: ${_green(config.enableLogging)} (Shows detailed logs in console)');
    logBuffer.writeln(
        '│  ├─ 🔄 ${_yellow('Auto-sync')}: ${_green(config.autoStartSync)} (Interval: ${_cyan(formatDuration(config.autoSyncInterval))} - how often to sync in background)');
    if (config.autoStartSync) {
      final initialUserId = config.initialUserId;
      if (initialUserId != null) {
        logBuffer.writeln(
            '│  │  └─ 🎯 Targeting initial user: ${_green(initialUserId)}');
      } else {
        logBuffer.writeln('│  │  └─ 🎯 Discovering all local users to sync.');
      }
    }
    logBuffer.writeln(
        '│  ├─ 🏗️  ${_yellow('Schema')}: v${_green(config.schemaVersion)} (Migrations: ${_green(config.migrations.length)} - your data model version)');
    logBuffer.writeln(
        '│  ├─ 🌐 ${_yellow('Connectivity')}: ${_green(connectivityChecker.runtimeType)} (How the app checks for internet)');
    logBuffer.writeln(
        '│  ├─ 🧭 ${_yellow('Sync Direction')}: ${_green(config.defaultSyncDirection.name)} (Order of push/pull operations)');
    logBuffer.writeln(
        '│  ├─ 🚦 ${_yellow('Sync Strategy')}: ${_green(config.syncExecutionStrategy.runtimeType)} (How to process pending changes)');
    logBuffer.writeln(
        '│  ├─ ⏳ ${_yellow('Sync Timeout')}: ${_cyan(formatDuration(config.syncTimeout))} (Max time for one sync cycle)');
    logBuffer.writeln(
        '│  ├─ ↪️  ${_yellow('User Switch')}: ${_green(config.defaultUserSwitchStrategy.name)} (Action on user login/logout)');
    logBuffer.writeln(
        '│  ├─ 🛡️  ${_yellow('Error Recovery')}: ${_green(config.errorRecoveryStrategy.runtimeType)} (Retries: ${_cyan(config.errorRecoveryStrategy.maxRetries)} - how to handle temporary network errors)');
    logBuffer.writeln(
        '│  └─ ⚡ ${_yellow('Event Handling')} (For real-time updates from server):');
    logBuffer.writeln(
        '│     ├─ ⏱️  Debounce: ${_cyan(formatDuration(config.remoteEventDebounceTime))} (Groups multiple remote changes into one)');
    logBuffer.writeln(
        '│     └─ 🗑️  Cache TTL: ${_cyan(formatDuration(config.changeCacheDuration))} (Prevents processing the same event twice)');
  }

  Future<void> _logPendingOperationsSummary(StringBuffer logBuffer) async {
    final allUserIds = <String>{};
    for (final manager in _managers.values) {
      try {
        final userIds = await manager.localAdapter.getAllUserIds();
        allUserIds.addAll(userIds);
      } catch (e) {
        logger.warn(
          'Could not get user IDs from ${manager.localAdapter.runtimeType}: $e',
        );
      }
    }

    if (_managers.isNotEmpty) {
      logBuffer.writeln('├─ ❤️  Initial Health Status');
      for (final managerEntry in _managers.entries) {
        final health = managerEntry.value.currentStatus.health;
        logBuffer.writeln(
          '│  └─ ${_cyan(managerEntry.key)}: ${_green(health.status.name)}',
        );
      }
    }

    if (allUserIds.isEmpty) {
      logBuffer.writeln('├─ 📊 Sync Status: No local users found.');
      logBuffer.writeln('├─ 🔬 Initial Metrics: Tracking enabled.');
      return;
    }

    logBuffer.writeln('├─ 📊 Sync Status & Pending Operations');
    var totalPending = 0;
    var totalItems = 0;

    for (final userId in allUserIds) {
      logBuffer.writeln('│  ├─ 👤 User: ${_cyan(userId)}');
      DatumSyncMetadata? metadata;
      // Try to get metadata from any manager
      if (_managers.isNotEmpty) {
        metadata =
            await _managers.values.first.localAdapter.getSyncMetadata(userId);
      }

      if (metadata?.lastSyncTime != null) {
        logBuffer.writeln(
          '│  │  ├─ 🕒 Last Sync: ${_cyan(formatDuration(DateTime.now().difference(metadata!.lastSyncTime!)))} ago',
        );
      } else {
        logBuffer.writeln('│  │  ├─ 🕒 Last Sync: Never');
      }

      var userHasContent = false;
      for (final managerEntry in _managers.entries) {
        final entityType = managerEntry.key;
        final manager = managerEntry.value;
        final count = await manager.getPendingCount(userId);
        final itemCount =
            (await manager.localAdapter.readAll(userId: userId)).length;
        totalItems += itemCount;
        totalPending += count;

        if (itemCount > 0 || count > 0) {
          userHasContent = true;
          logBuffer.writeln('│  │  ├─ ${_cyan(entityType)}:');
          logBuffer.writeln(
            '│  │  │  └─ Items: ${_green(itemCount)}, Pending: ${_yellow(count)}',
          );
        }
      }
      if (!userHasContent) {
        logBuffer.writeln('│  │  └─ No local data or pending operations.');
      }
    }
    logBuffer.writeln(
        '│  └─ 📈 Totals: Items: ${_green(totalItems)}, Pending: ${_yellow(totalPending)}');
  }

  void _logObservers(StringBuffer logBuffer) {
    if (globalObservers.isNotEmpty) {
      logBuffer.writeln(
        '├─ 👀 Global Observers Registered (${_green(globalObservers.length)}):',
      );
      for (final observer in globalObservers) {
        logBuffer.writeln('│  └─ ${_green(observer.runtimeType)}');
      }
    }
  }

  /// Adds a global observer to listen to events from all managers.
  void addObserver(GlobalDatumObserver observer) {
    globalObservers.add(observer);
  }

  /// Registers an entity type with its specific adapters.
  ///
  /// This can be called after `Datum.initialize()` to dynamically add support
  /// for new entity types. It will create and initialize the manager for the
  /// given registration.
  Future<void> register<T extends DatumEntity>({
    required DatumRegistration<T> registration,
  }) async {
    _register<T>(registration);
    // Initialization now happens inside the main initialize flow.
    // If called dynamically, we need a log buffer.
    final logBuffer = StringBuffer();
    await _initializeManagerForType(T, logBuffer);
    logger.info(logBuffer.toString());
  }

  void _register<T extends DatumEntity>(
    DatumRegistration<T> registration, [
    StringBuffer? logBuffer,
  ]) {
    // With modern Dart, using the generic type T directly as a map key is reliable.
    if (_managers.containsKey(T)) {
      throw StateError(
        'Entity type $T is already registered. Duplicate registration is not allowed. '
        'Please ensure each entity type is registered only once.',
      );
    }

    final hasMiddlewares = registration.middlewares?.isNotEmpty ?? false;
    final hasObservers = registration.observers?.isNotEmpty ?? false;
    bool isRelational = false;
    int relationCount = 0;

    // Check for relational capabilities.
    try {
      final sample = registration.localAdapter.sampleInstance;
      if (sample.isRelational && sample is RelationalDatumEntity) {
        isRelational = sample.isRelational;
        relationCount = sample.relations.length;
      }
    } catch (_) {
      // If creating a sample instance fails, we just skip this log.
    }

    final lastCharForConfig =
        hasMiddlewares || hasObservers || isRelational ? '├' : '└';

    logBuffer?.writeln('│  └─ 🧩 Entity: ${_cyan(T)}');
    logBuffer?.writeln(
        '│     ├─ 🏠 Local Adapter: ${_green(registration.localAdapter.runtimeType)}');
    logBuffer?.writeln(
        '│     ├─ ☁️  Remote Adapter: ${_green(registration.remoteAdapter.runtimeType)}');
    logBuffer?.writeln(
        '│     ├─ ⚖️  Conflict Resolver: ${_green(registration.conflictResolver?.runtimeType ?? 'Default (LastWriteWinsResolver)')}');
    logBuffer?.writeln(
        '│     $lastCharForConfig─ 🔧 Custom Config: ${_green(registration.config != null)}');

    if (hasMiddlewares) {
      final lastCharForMiddleware = hasObservers || isRelational ? '├' : '└';
      logBuffer?.writeln(
          '│     $lastCharForMiddleware─ 🔗 Middlewares (${_green(registration.middlewares!.length)}):');
      for (final middleware in registration.middlewares!) {
        logBuffer?.writeln('│     │  └─ ${_green(middleware.runtimeType)}');
      }
    }
    if (hasObservers) {
      final lastCharForObserver = isRelational ? '├' : '└';
      logBuffer?.writeln(
          '│     $lastCharForObserver─ 👀 Observers (${_green(registration.observers!.length)}):');
      for (final observer in registration.observers!) {
        logBuffer?.writeln('│     │  └─ ${_green(observer.runtimeType)}');
      }
    }
    if (isRelational) {
      logBuffer?.writeln(
          '│     └─ 🤝 Relational: ${_green(true)} (Relations: ${_cyan(relationCount)})');
    } else {
      // Explicitly log that it's not relational if no other optional logs follow.
      if (!hasMiddlewares && !hasObservers) {
        logBuffer?.writeln('│     └─ 🤝 Relational: ${_green(false)}');
      }
    }

    _adapterPairs[T] = AdapterPairImpl<T>.fromRegistration(registration);
  }

  /// Initializes all registered managers and the central engine.
  Future<void> _initializeManagers(StringBuffer logBuffer) async {
    if (_adapterPairs.isNotEmpty) {
      logBuffer.writeln('├─ 🚀 Initializing Managers');
    }
    for (final type in _adapterPairs.keys) {
      await _initializeManagerForType(type, logBuffer);
    }
  }

  Future<void> _initializeManagerForType(
      Type type, StringBuffer logBuffer) async {
    final adapters = _adapterPairs[type];
    if (adapters == null) {
      throw StateError(
        'AdapterPair not found for type $type during initialization.',
      );
    }

    // The generic factory helps create the correctly typed manager.
    final manager = adapters.createManager(this);
    logBuffer.writeln('│  └─ ✨ Manager for ${_cyan(type)} ready.');
    _managers[type] = manager;
    // Subscribe to the manager's event stream and pipe events to the global controller.
    final subscription = manager.eventStream.listen(
      _eventController.add,
      onError: _eventController.addError,
    );
    _managerSubscriptions.add(subscription);
    await manager.initialize(); // This calls DatumManager.initialize()
  }

  void _listenToEventsForMetrics() {
    events.listen((event) {
      final current = _metricsSubject.value;
      DatumMetrics next;

      switch (event) {
        case DatumSyncStartedEvent():
          next = current.copyWith(
            totalSyncOperations: current.totalSyncOperations + 1,
            activeUsers: {...current.activeUsers, event.userId},
          );
        case DatumSyncCompletedEvent():
          final newActiveUsers = {...current.activeUsers, event.userId};
          if (event.result.failedCount == 0) {
            next = current.copyWith(
              successfulSyncs: current.successfulSyncs + 1,
              conflictsDetected:
                  current.conflictsDetected + event.result.conflictsResolved,
              activeUsers: newActiveUsers,
            );
          } else {
            next = current.copyWith(
              failedSyncs: current.failedSyncs + 1,
              conflictsDetected:
                  current.conflictsDetected + event.result.conflictsResolved,
              activeUsers: newActiveUsers,
            );
          }
        case DatumSyncErrorEvent():
          next = current.copyWith(failedSyncs: current.failedSyncs + 1);
        case UserSwitchedEvent():
          next = current.copyWith(userSwitchCount: current.userSwitchCount + 1);
        case ConflictResolvedEvent():
          next = current.copyWith(
            conflictsResolvedAutomatically:
                current.conflictsResolvedAutomatically + 1,
          );
        case _:
          return; // No change, don't emit a new value.
      }
      _metricsSubject.add(next);
    });
  }

  /// Provides access to the specific manager for an entity type.
  /// This preserves the familiar `SynqManager` API.
  static DatumManager<T> manager<T extends DatumEntity>() {
    final manager = instance._managers[T];
    // By checking the type with 'is', Dart's flow analysis promotes `manager`
    // to the specific `DatumManager<T>` type, making the return type-safe.
    if (manager is DatumManager<T>) {
      return manager;
    }
    throw StateError(
      'Entity type $T is not registered or has a manager of the wrong type.',
    );
  }

  /// Provides access to a manager for a given entity [Type].
  ///
  /// This is useful for relational data fetching where the type of the
  /// related entity is not known at compile time.
  static DatumManager<DatumEntity> managerByType(Type type) {
    final manager = instance._managers[type];
    if (manager != null) {
      return manager;
    }
    throw StateError(
      'Entity type $type is not registered or has a manager of the wrong type.',
    );
  }

  /// A global sync that can coordinate across all managers.
  Future<DatumSyncResult<DatumEntity>> synchronize(
    String userId, {
    DatumSyncOptions? options,
  }) async {
    final snapshot = _getSnapshot(userId);
    if (snapshot.status == DatumSyncStatus.syncing) {
      logger.info(
        '[Global] Sync for user $userId skipped: another global sync is already in progress.',
      );
      return DatumSyncResult.skipped(userId, snapshot.pendingOperations);
    }

    final stopwatch = Stopwatch()..start();
    _updateSnapshot(userId, (s) => s.copyWith(status: DatumSyncStatus.syncing));
    for (final observer in globalObservers) {
      observer.onSyncStart();
    }

    var totalSynced = 0;
    var totalFailed = 0;
    var totalConflicts = 0;
    final allPending = <DatumSyncOperation<DatumEntity>>[];

    try {
      final direction = options?.direction ?? config.defaultSyncDirection;

      switch (direction) {
        case SyncDirection.pushThenPull:
          await _pushChanges(userId, options);
          final pullResults = await _pullChanges(userId, options);
          for (final res in pullResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            totalConflicts += res.conflictsResolved;
            allPending.addAll(res.pendingOperations);
          }
          break;
        case SyncDirection.pullThenPush:
          final pullResults = await _pullChanges(userId, options);
          for (final res in pullResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            totalConflicts += res.conflictsResolved;
            allPending.addAll(res.pendingOperations);
          }
          await _pushChanges(userId, options);
          break;
        case SyncDirection.pushOnly:
          await _pushChanges(userId, options);
          break;
        case SyncDirection.pullOnly:
          final pullResults = await _pullChanges(userId, options);
          for (final res in pullResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            totalConflicts += res.conflictsResolved;
            allPending.addAll(res.pendingOperations);
          }
          break;
      }

      final result = DatumSyncResult<DatumEntity>(
        userId: userId,
        duration: stopwatch.elapsed,
        syncedCount: totalSynced,
        failedCount: totalFailed,
        conflictsResolved: totalConflicts,
        pendingOperations: allPending,
      );

      _updateSnapshot(
        userId,
        (s) => s.copyWith(status: DatumSyncStatus.completed),
      );
      for (final observer in globalObservers) {
        observer.onSyncEnd(result);
      }
      return result;
    } catch (e, stack) {
      logger.error('Synchronization failed for user $userId', stack);
      _updateSnapshot(
        userId,
        (s) => s.copyWith(status: DatumSyncStatus.failed, errors: [e]),
      );
      // CRITICAL: Using `return Future.error` instead of a synchronous `throw`
      // is essential to prevent race conditions. It ensures that any error
      // events emitted from the underlying managers have a chance to be
      // delivered to listeners on the global `Datum.instance.events` stream
      // *before* the Future returned by this `synchronize()` method completes
      // with an error.
      return Future.error(e, stack);
    }
  }

  Future<void> _pushChanges(String userId, DatumSyncOptions? options) async {
    logger.info('Starting global push phase for user $userId...');
    // Ensure we only perform a push operation, respecting the original options.
    final pushOnlyOptions = (options ?? const DatumSyncOptions()).copyWith(
      direction: SyncDirection.pushOnly,
    );

    for (final manager in _managers.values) {
      // We call synchronize with pushOnly to process the queue for each manager.
      await manager.synchronize(userId, options: pushOnlyOptions);
    }
  }

  Future<List<DatumSyncResult<DatumEntity>>> _pullChanges(
    String userId,
    DatumSyncOptions? options,
  ) async {
    logger.info('Starting global pull phase for user $userId...');
    // Ensure we only perform a pull operation, respecting the original options.
    final pullOnlyOptions = (options ?? const DatumSyncOptions()).copyWith(
      direction: SyncDirection.pullOnly,
    );

    final results = <DatumSyncResult<DatumEntity>>[];
    for (final manager in _managers.values) {
      // We call synchronize with pullOnly for each manager.
      results.add(await manager.synchronize(userId, options: pullOnlyOptions));
    }
    return results;
  }

  DatumSyncStatusSnapshot _getSnapshot(String userId) {
    return _snapshots[userId] ?? DatumSyncStatusSnapshot.initial(userId);
  }

  void _updateSnapshot(
    String userId,
    DatumSyncStatusSnapshot Function(DatumSyncStatusSnapshot) updater,
  ) {
    final current = _getSnapshot(userId);
    final updated = updater(current);
    _snapshots[userId] = updated;
    _statusSubject.add(_snapshots);
  }

  /// Creates a new entity of type T.
  Future<T> create<T extends DatumEntity>(T entity) {
    return Datum.manager<T>().push(item: entity, userId: entity.userId);
  }

  /// Reads a single entity of type T by its ID.
  Future<T?> read<T extends DatumEntity>(String id, {String? userId}) {
    // In a multi-manager setup, we might need to know which manager to ask.
    // For now, we assume the first one that can handle type T.
    return Datum.manager<T>().read(id, userId: userId);
  }

  /// Reads all entities of type T.
  Future<List<T>> readAll<T extends DatumEntity>({String? userId}) {
    return Datum.manager<T>().readAll(userId: userId);
  }

  /// Updates an existing entity of type T.
  Future<T> update<T extends DatumEntity>(T entity) {
    return Datum.manager<T>().push(item: entity, userId: entity.userId);
  }

  /// Deletes an entity of type T by its ID.
  Future<bool> delete<T extends DatumEntity>({
    required String id,
    required String userId,
  }) async {
    return Datum.manager<T>().delete(id: id, userId: userId);
  }

  Future<void> dispose() async {
    // Await all disposals and cancellations concurrently for efficiency.
    await Future.wait([
      ..._managers.values.map((m) => m.dispose()),
      ..._managerSubscriptions.map((s) => s.cancel()),
    ]);
    await _eventController.close();
    // ignore: invalid_use_of_protected_member
    await _metricsSubject.close();
    await _statusSubject.close();
  }

  static void resetForTesting() {
    _instance = null;
  }
}
