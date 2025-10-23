import 'dart:async';

import 'package:datum/datum.dart';
import 'package:rxdart/rxdart.dart';

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

  // Updated: Use DatumEntityBase instead of DatumEntity
  final Map<Type, DatumManager<DatumEntityBase>> _managers = {};
  final Map<Type, AdapterPair> _adapterPairs = {};
  final DatumConnectivityChecker connectivityChecker;
  final List<GlobalDatumObserver> globalObservers = [];
  final DatumLogger logger;
  final List<StreamSubscription<DatumSyncEvent<DatumEntityBase>>> _managerSubscriptions = [];

  // Stream controllers for events and status
  final StreamController<DatumSyncEvent<DatumEntityBase>> _eventController = StreamController.broadcast();
  Stream<DatumSyncEvent> get events => _eventController.stream;

  final BehaviorSubject<Map<String, DatumSyncStatusSnapshot>> _statusSubject = BehaviorSubject.seeded({});
  Stream<DatumSyncStatusSnapshot?> statusForUser(String userId) => _statusSubject.stream.map((map) => map[userId]);

  final Map<String, DatumSyncStatusSnapshot> _snapshots = {};

  // Stream controller for metrics
  final BehaviorSubject<DatumMetrics> _metricsSubject = BehaviorSubject.seeded(
    const DatumMetrics(),
  );
  Stream<DatumMetrics> get metrics => _metricsSubject.stream;
  DatumMetrics get currentMetrics => _metricsSubject.value;

  /// A stream that aggregates the health status of all registered managers.
  Stream<Map<Type, DatumHealth>> get allHealths {
    if (_managers.isEmpty) {
      return Stream.value({});
    }
    final healthStreams = _managers.values.map((m) => m.health).toList();
    final types = _managers.keys.toList();

    return CombineLatestStream.list(healthStreams).map((healthList) {
      return Map.fromIterables(types, healthList);
    });
  }

  Datum._({
    required this.config,
    required this.connectivityChecker,
    DatumLogger? logger,
  }) : logger = logger ?? DatumLogger(enabled: config.enableLogging);

  /// Initializes the central Datum engine as a singleton.
  static Future<Datum> initialize({
    required DatumConfig config,
    required DatumConnectivityChecker connectivityChecker,
    DatumLogger? logger,
    List<DatumRegistration> registrations = const [],
    List<GlobalDatumObserver> observers = const [],
  }) async {
    if (_instance != null) {
      return _instance!;
    }
    if (!config.enableLogging) {
      return _initializeSilently(config, connectivityChecker, logger, registrations, observers);
    }

    final initLogger = logger ?? DatumLogger(enabled: config.enableLogging);
    final logBuffer = StringBuffer();

    final datum = Datum._(
      config: config,
      connectivityChecker: connectivityChecker,
      logger: logger,
    );
    datum.globalObservers.addAll(observers);

    datum._logInitializationHeader(logBuffer, config: config, connectivityChecker: connectivityChecker);
    datum._logObservers(logBuffer);
    if (registrations.isNotEmpty) {
      logBuffer.writeln('├─ 📦 Registering Entities');
    }
    for (final reg in registrations) {
      reg.capture(
        <TT extends DatumEntityBase>() => datum._register<TT>(reg as DatumRegistration<TT>, logBuffer),
      );
    }
    await datum._initializeManagers(logBuffer);
    await datum._logPendingOperationsSummary(logBuffer);

    logBuffer.write('└─ ✅ Datum Initialization Complete.');
    initLogger.info(logBuffer.toString());

    datum._listenToEventsForMetrics();
    return _instance = datum;
  }

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
      logger: null,
    );
    datum.globalObservers.addAll(observers);

    for (final reg in registrations) {
      reg.capture(
        <TT extends DatumEntityBase>() => datum._register<TT>(reg as DatumRegistration<TT>),
      );
    }
    await datum._initializeManagers(StringBuffer());
    datum._listenToEventsForMetrics();
    return _instance = datum;
  }

  String _green(Object text) => logger.colors ? '\x1B[32m$text\x1B[0m' : text.toString();
  String _yellow(Object text) => logger.colors ? '\x1B[33m$text\x1B[0m' : text.toString();
  String _cyan(Object text) => logger.colors ? '\x1B[36m$text\x1B[0m' : text.toString();

  void _logInitializationHeader(
    StringBuffer logBuffer, {
    required DatumConfig config,
    required DatumConnectivityChecker connectivityChecker,
  }) {
    logBuffer.writeln('🚀 Initializing Datum...');
    logBuffer.writeln(_cyan('   Hello! Datum is your smart offline-first data synchronization framework 😊'));
    logBuffer.writeln('├─ ⚙️  Configuration');
    logBuffer.writeln('│  ├─ 📝 ${_yellow('Logging')}: ${_green(config.enableLogging)}');
    logBuffer.writeln('│  ├─ 🔄 ${_yellow('Auto-sync')}: ${_green(config.autoStartSync)} (Interval: ${_cyan(formatDuration(config.autoSyncInterval))})');
    if (config.autoStartSync) {
      final initialUserId = config.initialUserId;
      if (initialUserId != null) {
        logBuffer.writeln('│  │  └─ 🎯 Targeting initial user: ${_green(initialUserId)}');
      } else {
        logBuffer.writeln('│  │  └─ 🎯 Discovering all local users to sync.');
      }
    }
    logBuffer.writeln('│  ├─ 🏗️  ${_yellow('Schema')}: v${_green(config.schemaVersion)} (Migrations: ${_green(config.migrations.length)})');
    logBuffer.writeln('│  ├─ 🌐 ${_yellow('Connectivity')}: ${_green(connectivityChecker.runtimeType)}');
    logBuffer.writeln('│  ├─ 🧭 ${_yellow('Sync Direction')}: ${_green(config.defaultSyncDirection.name)}');
    logBuffer.writeln('│  ├─ 🚦 ${_yellow('Sync Strategy')}: ${_green(config.syncExecutionStrategy.runtimeType)}');
    logBuffer.writeln('│  ├─ ⏳ ${_yellow('Sync Timeout')}: ${_cyan(formatDuration(config.syncTimeout))}');
    logBuffer.writeln('│  ├─ ↪️  ${_yellow('User Switch')}: ${_green(config.defaultUserSwitchStrategy.name)}');
    logBuffer.writeln('│  ├─ 🛡️  ${_yellow('Error Recovery')}: ${_green(config.errorRecoveryStrategy.runtimeType)} (Retries: ${_cyan(config.errorRecoveryStrategy.maxRetries)})');
    logBuffer.writeln('│  └─ ⚡ ${_yellow('Event Handling')}:');
    logBuffer.writeln('│     ├─ ⏱️  Debounce: ${_cyan(formatDuration(config.remoteEventDebounceTime))}');
    logBuffer.writeln('│     └─ 🗑️  Cache TTL: ${_cyan(formatDuration(config.changeCacheDuration))}');
  }

  Future<void> _logPendingOperationsSummary(StringBuffer logBuffer) async {
    final allUserIds = <String>{};
    for (final manager in _managers.values) {
      try {
        final userIds = await manager.localAdapter.getAllUserIds();
        allUserIds.addAll(userIds);
      } catch (e) {
        logger.warn('Could not get user IDs from ${manager.localAdapter.runtimeType}: $e');
      }
    }

    if (_managers.isNotEmpty) {
      logBuffer.writeln('├─ ❤️  Initial Health Status');
      for (final managerEntry in _managers.entries) {
        final health = managerEntry.value.currentStatus.health;
        logBuffer.writeln('│  └─ ${_cyan(managerEntry.key)}: ${_green(health.status.name)}');
      }
    }

    if (allUserIds.isEmpty) {
      logBuffer.writeln('├─ 📊 Sync Status & Metrics: No local users found yet.');
      logBuffer.writeln('│  └─ 📈 Initial Metrics: ${_green(currentMetrics.toString())}');
      return;
    }

    logBuffer.writeln('├─ 📊 Sync Status & Pending Operations');
    var totalPending = 0;
    var totalItems = 0;

    for (final userId in allUserIds) {
      logBuffer.writeln('│  ├─ 👤 User: ${_cyan(userId)}');
      DatumSyncMetadata? metadata;
      if (_managers.isNotEmpty) {
        metadata = await _managers.values.first.localAdapter.getSyncMetadata(userId);
      }

      final lastSyncResult = _managers.isNotEmpty ? await _managers.values.first.getLastSyncResult(userId) : null;

      if (metadata?.lastSyncTime != null) {
        logBuffer.writeln('│  │  ├─ 🕒 Last Sync: ${_cyan(formatDuration(DateTime.now().difference(metadata!.lastSyncTime!)))} ago');
      } else {
        logBuffer.writeln('│  │  ├─ 🕒 Last Sync: Never synced');
      }

      if (lastSyncResult != null) {
        final totalPushed = (lastSyncResult.totalBytesPushed / 1024).toStringAsFixed(2);
        final totalPulled = (lastSyncResult.totalBytesPulled / 1024).toStringAsFixed(2);
        final cyclePushed = (lastSyncResult.bytesPushedInCycle / 1024).toStringAsFixed(2);
        final cyclePulled = (lastSyncResult.bytesPulledInCycle / 1024).toStringAsFixed(2);

        logBuffer.writeln('│  │  ├─ 💾 Total Data: ${_green('↑$totalPushed KB')} / ${_green('↓$totalPulled KB')}');
        logBuffer.writeln('│  │  ├─ 📈 Last Sync: ${_green('↑$cyclePushed KB')} / ${_green('↓$cyclePulled KB')}');
      } else {
        logBuffer.writeln('│  │  ├─ 💾 Data Transferred: No history');
      }

      var userHasContent = false;
      for (final managerEntry in _managers.entries) {
        final entityType = managerEntry.key;
        final manager = managerEntry.value;
        final count = await manager.getPendingCount(userId);
        final itemCount = (await manager.localAdapter.readAll(userId: userId)).length;
        final storageSize = await manager.localAdapter.getStorageSize(userId: userId);
        totalItems += itemCount;
        totalPending += count;

        if (itemCount > 0 || count > 0) {
          userHasContent = true;
          logBuffer.writeln('│  │  ├─ ${_cyan(entityType)}:');
          final sizeInKb = (storageSize / 1024).toStringAsFixed(2);
          logBuffer.writeln('│  │  │  └─ Items: ${_green(itemCount)}, Pending: ${_yellow(count)}, Size: ${_cyan('$sizeInKb KB')}');
        }
      }
      if (!userHasContent) {
        logBuffer.writeln('│  │  └─ 📭 No local data or pending operations.');
      }
    }
    logBuffer.writeln('│  └─ 📈 Totals: Items: ${_green(totalItems)}, Pending: ${_yellow(totalPending)}');
  }

  void _logObservers(StringBuffer logBuffer) {
    if (globalObservers.isNotEmpty) {
      logBuffer.writeln('├─ 👀 Global Observers Registered (${_green(globalObservers.length)}):');
      for (final observer in globalObservers) {
        logBuffer.writeln('│  └─ ${_green(observer.runtimeType)}');
      }
    }
  }

  void addObserver(GlobalDatumObserver observer) {
    globalObservers.add(observer);
  }

  Future<void> register<T extends DatumEntityBase>({
    required DatumRegistration<T> registration,
  }) async {
    _register<T>(registration);
    final logBuffer = StringBuffer();
    await _initializeManagerForType(T, logBuffer);
    logger.info(logBuffer.toString());
  }

  void _register<T extends DatumEntityBase>(
    DatumRegistration<T> registration, [
    StringBuffer? logBuffer,
  ]) {
    if (_managers.containsKey(T)) {
      throw StateError(
        'Entity type $T is already registered. Duplicate registration is not allowed.',
      );
    }

    final hasMiddlewares = registration.middlewares?.isNotEmpty ?? false;
    final hasObservers = registration.observers?.isNotEmpty ?? false;
    bool isRelational = false;
    int relationCount = 0;

    // Updated: Use sealed class pattern matching
    try {
      final sample = T;
      switch (sample) {
        case RelationalDatumEntity():
          isRelational = true;
          relationCount = (sample as RelationalDatumEntity).relations.length;
        case DatumEntity():
          isRelational = false;
      }
    } catch (_) {
      // If creating a sample instance fails, skip this check
    }

    final lastCharForConfig = hasMiddlewares || hasObservers || isRelational ? '├' : '└';

    logBuffer?.writeln('│  └─ 🧩 Entity: ${_cyan(T)}');
    logBuffer?.writeln('│     ├─ 🏠 Local Adapter: ${_green(registration.localAdapter.runtimeType)}');
    logBuffer?.writeln('│     ├─ ☁️   Remote Adapter: ${_green(registration.remoteAdapter.runtimeType)}');
    logBuffer?.writeln('│     ├─ ⚖️  Conflict Resolver: ${_green(registration.conflictResolver?.runtimeType ?? 'Default (LastWriteWinsResolver)')}');
    logBuffer?.writeln('│     $lastCharForConfig─ 🔧 Custom Config: ${_green(registration.config != null)}');

    if (hasMiddlewares) {
      final lastCharForMiddleware = hasObservers || isRelational ? '├' : '└';
      logBuffer?.writeln('│     $lastCharForMiddleware─ 🔗 Middlewares (${_green(registration.middlewares!.length)}):');
      for (final middleware in registration.middlewares!) {
        logBuffer?.writeln('│     │  └─ ${_green(middleware.runtimeType)}');
      }
    }
    if (hasObservers) {
      final lastCharForObserver = isRelational ? '├' : '└';
      logBuffer?.writeln('│     $lastCharForObserver─ 👀 Observers (${_green(registration.observers!.length)}):');
      for (final observer in registration.observers!) {
        logBuffer?.writeln('│     │  └─ ${_green(observer.runtimeType)}');
      }
    }
    if (isRelational) {
      logBuffer?.writeln('│     └─ 🤝 Relational: ${_green(true)} (Relations: ${_cyan(relationCount)})');
    } else {
      if (!hasMiddlewares && !hasObservers) {
        logBuffer?.writeln('│     └─ 🤝 Relational: ${_green(false)}');
      }
    }

    _adapterPairs[T] = AdapterPairImpl<T>.fromRegistration(registration);
  }

  Future<void> _initializeManagers(StringBuffer logBuffer) async {
    if (_adapterPairs.isNotEmpty) {
      logBuffer.writeln('├─ 🚀 Initializing Managers');
    }
    for (final type in _adapterPairs.keys) {
      await _initializeManagerForType(type, logBuffer);
    }
  }

  Future<void> _initializeManagerForType(Type type, StringBuffer logBuffer) async {
    final adapters = _adapterPairs[type];
    if (adapters == null) {
      throw StateError('AdapterPair not found for type $type during initialization.');
    }

    final manager = adapters.createManager(this);
    logBuffer.writeln('│  └─ ✨ Manager for ${_cyan(type)} ready.');
    _managers[type] = manager;

    final subscription = manager.eventStream.listen(
      _eventController.add,
      onError: _eventController.addError,
    );
    _managerSubscriptions.add(subscription);
    await manager.initialize();
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
              conflictsDetected: current.conflictsDetected + event.result.conflictsResolved,
              activeUsers: newActiveUsers,
              totalBytesPushed: current.totalBytesPushed + event.result.bytesPushedInCycle,
              totalBytesPulled: current.totalBytesPulled + event.result.bytesPulledInCycle,
            );
          } else {
            next = current.copyWith(
              failedSyncs: current.failedSyncs + 1,
              conflictsDetected: current.conflictsDetected + event.result.conflictsResolved,
              activeUsers: newActiveUsers,
              totalBytesPushed: current.totalBytesPushed + event.result.bytesPushedInCycle,
              totalBytesPulled: current.totalBytesPulled + event.result.bytesPulledInCycle,
            );
          }
        case DatumSyncErrorEvent():
          next = current.copyWith(failedSyncs: current.failedSyncs + 1);
        case UserSwitchedEvent():
          next = current.copyWith(userSwitchCount: current.userSwitchCount + 1);
        case ConflictResolvedEvent():
          next = current.copyWith(
            conflictsResolvedAutomatically: current.conflictsResolvedAutomatically + 1,
          );
        case _:
          return;
      }
      _metricsSubject.add(next);
    });
  }

  /// Provides access to the specific manager for an entity type.
  static DatumManager<T> manager<T extends DatumEntityBase>() {
    final manager = instance._managers[T];
    if (manager is DatumManager<T>) {
      return manager;
    }
    throw StateError('Entity type $T is not registered or has a manager of the wrong type.');
  }

  /// Provides access to a manager for a given entity [Type].
  static DatumManager<DatumEntityBase> managerByType(Type type) {
    final manager = instance._managers[type];
    if (manager != null) {
      return manager;
    }
    throw StateError('Entity type $type is not registered or has a manager of the wrong type.');
  }

  /// A global sync that can coordinate across all managers.
  Future<DatumSyncResult<DatumEntityBase>> synchronize(
    String userId, {
    DatumSyncOptions? options,
  }) async {
    final snapshot = _getSnapshot(userId);
    if (snapshot.status == DatumSyncStatus.syncing) {
      logger.info('[Global] Sync for user $userId skipped: another global sync is already in progress.');
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
    final allPending = <DatumSyncOperation<DatumEntityBase>>[];

    try {
      final direction = options?.direction ?? config.defaultSyncDirection;
      final pushResults = <DatumSyncResult<DatumEntityBase>>[];
      final pullResults = <DatumSyncResult<DatumEntityBase>>[];

      switch (direction) {
        case SyncDirection.pushThenPull:
          pushResults.addAll(await _pushChanges(userId, options));
          pullResults.addAll(await _pullChanges(userId, options));
          for (final res in pushResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            allPending.addAll(res.pendingOperations);
          }
          for (final res in pullResults) {
            totalSynced += res.syncedCount;
            totalConflicts += res.conflictsResolved;
            allPending.addAll(res.pendingOperations);
          }
        case SyncDirection.pullThenPush:
          pullResults.addAll(await _pullChanges(userId, options));
          for (final res in pullResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            totalConflicts += res.conflictsResolved;
            allPending.addAll(res.pendingOperations);
          }
          pushResults.addAll(await _pushChanges(userId, options));
          for (final res in pushResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            allPending.addAll(res.pendingOperations);
          }
        case SyncDirection.pushOnly:
          pushResults.addAll(await _pushChanges(userId, options));
          for (final res in pushResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            allPending.addAll(res.pendingOperations);
          }
        case SyncDirection.pullOnly:
          pullResults.addAll(await _pullChanges(userId, options));
          for (final res in pullResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            totalConflicts += res.conflictsResolved;
            allPending.addAll(res.pendingOperations);
          }
      }

      final result = DatumSyncResult<DatumEntityBase>(
        userId: userId,
        duration: stopwatch.elapsed,
        syncedCount: totalSynced,
        failedCount: totalFailed,
        conflictsResolved: totalConflicts,
        pendingOperations: allPending,
      );

      _updateSnapshot(userId, (s) => s.copyWith(status: DatumSyncStatus.completed));
      for (final observer in globalObservers) {
        observer.onSyncEnd(result);
      }
      return result;
    } catch (e, stack) {
      logger.error('Synchronization failed for user $userId', stack);
      _updateSnapshot(userId, (s) => s.copyWith(status: DatumSyncStatus.failed, errors: [e]));
      return Future.error(e, stack);
    }
  }

  Future<List<DatumSyncResult<DatumEntityBase>>> _pushChanges(String userId, DatumSyncOptions? options) async {
    logger.info('Starting global push phase for user $userId...');
    final pushOnlyOptions = (options ?? const DatumSyncOptions()).copyWith(
      direction: SyncDirection.pushOnly,
    );

    final results = <DatumSyncResult<DatumEntityBase>>[];
    for (final manager in _managers.values) {
      results.add(await manager.synchronize(userId, options: pushOnlyOptions));
    }
    return results;
  }

  Future<List<DatumSyncResult<DatumEntityBase>>> _pullChanges(
    String userId,
    DatumSyncOptions? options,
  ) async {
    logger.info('Starting global pull phase for user $userId...');
    final pullOnlyOptions = (options ?? const DatumSyncOptions()).copyWith(
      direction: SyncDirection.pullOnly,
    );

    final results = <DatumSyncResult<DatumEntityBase>>[];
    for (final manager in _managers.values) {
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

  // CRUD operations remain the same but now use DatumEntityBase
  Future<T> create<T extends DatumEntityBase>(T entity) {
    return Datum.manager<T>().push(item: entity, userId: entity.userId);
  }

  Future<T?> read<T extends DatumEntityBase>(String id, {String? userId}) {
    return Datum.manager<T>().read(id, userId: userId);
  }

  Future<List<T>> readAll<T extends DatumEntityBase>({String? userId}) {
    return Datum.manager<T>().readAll(userId: userId);
  }

  Future<T> update<T extends DatumEntityBase>(T entity) {
    return Datum.manager<T>().push(item: entity, userId: entity.userId);
  }

  Future<bool> delete<T extends DatumEntityBase>({
    required String id,
    required String userId,
  }) async {
    return Datum.manager<T>().delete(id: id, userId: userId);
  }

  Future<(T, DatumSyncResult<T>)> pushAndSync<T extends DatumEntityBase>({
    required T item,
    required String userId,
    DatumSyncOptions? syncOptions,
  }) {
    return Datum.manager<T>().pushAndSync(
      item: item,
      userId: userId,
      syncOptions: syncOptions,
    );
  }

  Future<(T, DatumSyncResult<T>)> updateAndSync<T extends DatumEntityBase>({
    required T item,
    required String userId,
    DatumSyncOptions? syncOptions,
  }) {
    return Datum.manager<T>().updateAndSync(
      item: item,
      userId: userId,
      syncOptions: syncOptions,
    );
  }

  Future<(bool, DatumSyncResult<T>)> deleteAndSync<T extends DatumEntityBase>({
    required String id,
    required String userId,
    DatumSyncOptions? syncOptions,
  }) =>
      Datum.manager<T>().deleteAndSync(id: id, userId: userId, syncOptions: syncOptions);

  Stream<List<T>>? watchAll<T extends DatumEntityBase>({String? userId, bool includeInitialData = true}) {
    return Datum.manager<T>().watchAll(userId: userId, includeInitialData: includeInitialData);
  }

  Stream<T?>? watchById<T extends DatumEntityBase>(String id, String? userId) {
    return Datum.manager<T>().watchById(id, userId);
  }

  Stream<PaginatedResult<T>>? watchAllPaginated<T extends DatumEntityBase>(
    PaginationConfig config, {
    String? userId,
  }) {
    return Datum.manager<T>().watchAllPaginated(config, userId: userId);
  }

  Stream<List<T>>? watchQuery<T extends DatumEntityBase>(DatumQuery query, {String? userId}) {
    return Datum.manager<T>().watchQuery(query, userId: userId);
  }

  Future<List<T>> query<T extends DatumEntityBase>(
    DatumQuery query, {
    required DataSource source,
    String? userId,
  }) async {
    return Datum.manager<T>().query(query, source: source, userId: userId);
  }

  /// Fetches related entities with proper type checking for RelationalDatumEntity
  Future<List<R>> fetchRelated<P extends DatumEntityBase, R extends DatumEntityBase>(
    P parent,
    String relationName, {
    DataSource source = DataSource.local,
  }) async {
    // Type-safe check using sealed class pattern matching
    switch (parent) {
      case RelationalDatumEntity():
        return Datum.managerByType(parent.runtimeType).fetchRelated<R>(parent, relationName, source: source);
      case DatumEntity():
        throw ArgumentError(
          'Entity of type ${parent.runtimeType} is not relational and cannot have relations. '
          'To use relations, extend RelationalDatumEntity instead of DatumEntity.',
        );
    }
  }

  /// Reactively watches related entities with proper type checking
  Stream<List<R>>? watchRelated<P extends DatumEntityBase, R extends DatumEntityBase>(
    P parent,
    String relationName,
  ) {
    // Type-safe check using sealed class pattern matching
    switch (parent) {
      case RelationalDatumEntity():
        return Datum.managerByType(parent.runtimeType).watchRelated<R>(parent, relationName);
      case DatumEntity():
        throw ArgumentError(
          'Entity of type ${parent.runtimeType} is not relational and cannot have relations. '
          'To use relations, extend RelationalDatumEntity instead of DatumEntity.',
        );
    }
  }

  Future<int> getPendingCount<T extends DatumEntityBase>(String userId) async {
    return Datum.manager<T>().getPendingCount(userId);
  }

  Future<List<DatumSyncOperation<T>>> getPendingOperations<T extends DatumEntityBase>(String userId) async {
    return Datum.manager<T>().getPendingOperations(userId);
  }

  Future<int> getStorageSize<T extends DatumEntityBase>({String? userId}) {
    return Datum.manager<T>().getStorageSize(userId: userId);
  }

  Stream<int> watchStorageSize<T extends DatumEntityBase>({String? userId}) {
    return Datum.manager<T>().watchStorageSize(userId: userId);
  }

  Future<DatumSyncResult<T>?> getLastSyncResult<T extends DatumEntityBase>(String userId) async {
    return Datum.manager<T>().getLastSyncResult(userId);
  }

  Future<DatumHealth> checkHealth<T extends DatumEntityBase>() async {
    return Datum.manager<T>().checkHealth();
  }

  Future<void> dispose() async {
    pauseAllSyncs();

    await Future.wait([
      ..._managers.values.map((m) => m.dispose()),
      ..._managerSubscriptions.map((s) => s.cancel()),
    ]);
    await _eventController.close();
    // ignore: invalid_use_of_protected_member
    await _metricsSubject.close();
    await _statusSubject.close();
  }

  void pauseSync() {
    pauseAllSyncs();
  }

  void pauseAllSyncs() {
    logger.info('Pausing sync for all managers...');
    for (final manager in _managers.values) {
      manager.pauseSync();
    }
  }

  void resumeSync() {
    resumeAllSyncs();
  }

  void resumeAllSyncs() {
    logger.info('Resuming sync for all managers...');
    for (final manager in _managers.values) {
      manager.resumeSync();
    }
  }

  static void resetForTesting() {
    _instance = null;
  }
}
