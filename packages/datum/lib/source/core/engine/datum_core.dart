import 'dart:async';

import 'package:datum/datum.dart';
import 'package:datum/source/core/cascade_delete.dart';
import 'package:datum/source/core/models/datum_either.dart';
import 'package:datum/source/core/persistence/datum_persistence.dart';
import 'package:datum/source/core/persistence/in_memory_datum_persistence.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

/// The central engine for the Datum framework, managing data synchronization,
/// entity registration, and communication between local and remote sources.
///
/// `Datum` is designed as a singleton, providing a single point of access to all
/// data management capabilities. Before using any of its features, it must be
/// initialized via [Datum.initialize].
///
/// ## Usage
///
/// 1. **Initialization**:
///    Start by initializing the `Datum` singleton at the beginning of your
///    application's lifecycle. This sets up the necessary configurations,
///    registers your data models ([DatumEntity]), and prepares the synchronization
///    engine.
///
///    ```dart
///    await Datum.initialize(
///      config: DatumConfig(
///        // Your configuration here...
///      ),
///      registrations: [
///        DatumRegistration<MyModel>(
///          localAdapter: MyModelLocalAdapter(),
///          remoteAdapter: MyModelRemoteAdapter(),
///        ),
///      ],
///    );
///    ```
///
/// 2. **Accessing Managers**:
///    Once initialized, you can access a specific [DatumManager] for each
///    registered entity type. The manager is the primary interface for all
///    operations related to that entity.
///
///    ```dart
///    final myModelManager = Datum.manager<MyModel>();
///    ```
///
/// 3. **Performing Operations**:
///    Use the manager to perform CRUD (Create, Read, Update, Delete) operations,
///    watch for changes, and trigger synchronization.
///
///    ```dart
///    // Create a new item
///    await myModelManager.push(item: myNewModel, userId: 'user123');
///
///    // Read all items for a user
///    final allItems = await myModelManager.readAll(userId: 'user123');
///
///    // Watch for real-time updates
///    myModelManager.watchAll(userId: 'user123').listen((items) {
///      print('Updated items: $items');
///    });
///
/// 4. **Global Synchronization**:
///    To trigger a synchronization for all registered entities for a specific user,
///    you can use the global `synchronize` method.
///
///    ```dart
///    final syncResult = await Datum.instance.synchronize('user123');
///    print('Sync completed: ${syncResult.syncedCount} items synced.');
///    ```
///
/// ## Defining Models
///
/// All data models in Datum must be built upon [DatumEntityInterface]. You have two main
/// approaches: extending abstract classes or using mixins.
///
/// ### 1. Extending Abstract Classes (Recommended)
///
/// This is the simplest way to get started.
///
/// - **For simple models**: Extend [DatumEntity].
/// - **For models with relationships**: Extend [RelationalDatumEntity].
///
/// ```dart
/// // A simple model
/// class MyModel extends DatumEntity {
///   final String name;
///
///   MyModel({required super.id, required this.name, required super.userId});
///
///   // Implement fromJson, toJson, and copyWith...
/// }
///
/// // A model with relationships
/// class Post extends RelationalDatumEntity {
///   final String title;
///
///   Post({required super.id, required this.title, required super.userId});
///
///   @override
///   Map<String, Relation> get relations => {
///         'comments': HasMany('postId'), // Assumes Comment has a 'postId' field
///       };
///
///   // ... fromJson, toJson, copyWith
/// }
/// ```
///
/// ### 2. Using Mixins
///
/// For more advanced use cases, such as integrating Datum with an existing
/// class hierarchy, you can use mixins. This approach provides greater flexibility.
///
/// - **For simple models**: Use [DatumEntityMixin].
/// - **For models with relationships**: Extend [RelationalDatumEntity].
///
/// ```dart
/// // A model with relationships using mixins

///   @override
///   final String id;
///   @override
///   final String userId;
///   @override
///   final DateTime modifiedAt;
///   @override
///   final DateTime createdAt;
///   @override
///   final int version;
///   @override
///   final bool isDeleted;
///
///   final String content;
///   final String postId; // Foreign key for the Post relationship
///
///   // ... constructor, fromJson, toJson, copyWith, diff, props
///
///   // No need to override 'relations' if this is the "belongs to" side
/// }
/// ```
///
/// By using mixins, you can compose Datum's capabilities into your own base
/// classes, allowing for a clean and maintainable architecture.
bool isSubtype<S, T>() => <T>[] is List<S>;

/// A type-safe registry for storing and retrieving managers.
class TypeSafeManagerRegistry {
  final Map<Type, Object> _managers = {};

  /// Registers a manager for a specific entity type.
  void register<T extends DatumEntityInterface>(DatumManager<T> manager) {
    _managers[T] = manager;
  }

  /// Retrieves a type-safe manager for the specified entity type.
  DatumManager<T> get<T extends DatumEntityInterface>() {
    // Prevent using DatumEntityInterface directly as it is the base interface
    if (T == DatumEntityInterface) {
      throw ArgumentError(
        'Cannot use DatumEntityInterface directly. You must use a concrete entity type that implements DatumEntityInterface. '
        'For example: Datum.manager<MyEntity>() instead of Datum.manager<DatumEntityInterface>().',
      );
    }

    final manager = _managers[T];
    if (manager == null) {
      throw StateError('Entity type $T is not registered.');
    }
    // This cast is safe because registration ensures type correctness
    return manager as DatumManager<T>;
  }

  /// Retrieves a manager by Type, returning the base type.
  DatumManager<DatumEntityInterface> getByType(Type type) {
    // Prevent using DatumEntityInterface directly as it is the base interface
    if (type == DatumEntityInterface) {
      throw ArgumentError(
        'Cannot use DatumEntityInterface directly. You must use a concrete entity type that implements DatumEntityInterface.',
      );
    }

    final manager = _managers[type];
    if (manager == null) {
      throw StateError('Entity type $type is not registered.');
    }
    // This cast is safe because all managers extend DatumEntityInterface
    return manager as DatumManager<DatumEntityInterface>;
  }

  /// Returns all registered manager types.
  Iterable<Type> get registeredTypes => _managers.keys;

  /// Returns all registered managers as base type.
  Iterable<DatumManager<DatumEntityInterface>> get allManagers => _managers.values.map((m) => m as DatumManager<DatumEntityInterface>);

  /// Checks if a type is registered.
  bool isRegistered(Type type) => _managers.containsKey(type);

  // Map-like interface for backward compatibility
  bool get isEmpty => _managers.isEmpty;
  bool get isNotEmpty => _managers.isNotEmpty;
  Iterable<Type> get keys => _managers.keys;
  Iterable<Object> get values => _managers.values;
  Iterable<MapEntry<Type, Object>> get entries => _managers.entries;
  bool containsKey(Type key) => _managers.containsKey(key);
  Object? operator [](Type key) => _managers[key];
  void operator []=(Type key, Object value) => _managers[key] = value;
}

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

  static bool get isInitialized => _instance != null;
  static Datum? get instanceOrNull => _instance;

  final DatumConfig config;

  // Type-safe manager registry
  final TypeSafeManagerRegistry _managers = TypeSafeManagerRegistry();
  final Map<Type, AdapterPair> _adapterPairs = {};
  final DatumConnectivityChecker connectivityChecker;
  final DatumPersistence? persistence;
  final List<GlobalDatumObserver> globalObservers = [];
  final DatumLogger logger;
  final List<StreamSubscription<DatumSyncEvent<DatumEntityInterface>>> _managerSubscriptions = [];
  StreamSubscription<bool>? _connectivitySubscription;

  // Stream controllers for events and status
  final StreamController<DatumSyncEvent<DatumEntityInterface>> _eventController = StreamController.broadcast();
  Stream<DatumSyncEvent> get events => _eventController.stream;

  // Shared user change stream for reactive queries
  final StreamController<String?> _userChangeController = StreamController.broadcast();
  Stream<String?> get userChangeStream => _userChangeController.stream;

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
    final healthStreams = _managers.allManagers.map((m) => m.health).toList();
    final types = _managers.keys.toList();

    return CombineLatestStream.list(healthStreams).map((healthList) {
      return Map.fromIterables(types, healthList);
    });
  }

  Datum._({
    required this.config,
    required this.connectivityChecker,
    this.persistence,
    DatumLogger? logger,
  }) : logger = logger ?? DatumLogger(enabled: config.enableLogging);

  /// Initializes the central Datum engine as a singleton.
  static Future<DatumEither<Object, Datum>> initialize({
    required DatumConfig config,
    required DatumConnectivityChecker connectivityChecker,
    DatumPersistence? persistence,
    DatumLogger? logger,
    List<DatumRegistration> registrations = const [],
    List<GlobalDatumObserver> observers = const [],
  }) async {
    try {
      if (_instance != null) {
        return Success(_instance!);
      }

      // Default to in-memory persistence if none provided
      final DatumPersistence effectivePersistence = persistence ?? InMemoryDatumPersistence();

      // Initialize persistence before using it
      await effectivePersistence.initialize();

      if (!config.enableLogging) {
        final datum = await _initializeSilently(config, connectivityChecker, effectivePersistence, logger, registrations, observers);
        return Success(datum);
      }

      final initLogger = logger ?? DatumLogger(enabled: config.enableLogging);
      final logBuffer = StringBuffer();

      final datum = Datum._(
        config: config,
        connectivityChecker: connectivityChecker,
        persistence: effectivePersistence,
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
          <TT extends DatumEntityInterface>() => datum._register<TT>(reg as DatumRegistration<TT>, logBuffer),
        );
      }
      await datum._initializeManagers(logBuffer);
      await datum._logPendingOperationsSummary(logBuffer);

      logBuffer.write('└─ ✅ Datum Initialization Complete.');
      for (final line in logBuffer.toString().split('\n')) {
        initLogger.info(line);
      }

      datum._listenToEventsForMetrics();
      datum._startConnectivityMonitoring();
      _instance = datum;
      return Success(datum);
    } catch (e, s) {
      if (e is Exception) {
        return Failure(e, s);
      }
      return Failure(e, s);
    }
  }

  static Future<Datum> _initializeSilently(
    DatumConfig config,
    DatumConnectivityChecker connectivityChecker,
    DatumPersistence effectivePersistence,
    DatumLogger? logger,
    List<DatumRegistration> registrations,
    List<GlobalDatumObserver> observers,
  ) async {
    // Initialize persistence before using it
    await effectivePersistence.initialize();

    final datum = Datum._(
      config: config,
      connectivityChecker: connectivityChecker,
      persistence: effectivePersistence,
      logger: logger,
    );
    datum.globalObservers.addAll(observers);

    for (final reg in registrations) {
      reg.capture(
        <TT extends DatumEntityInterface>() => datum._register<TT>(reg as DatumRegistration<TT>),
      );
    }
    await datum._initializeManagers(StringBuffer());
    datum._listenToEventsForMetrics();
    datum._startConnectivityMonitoring();
    _instance = datum;
    return datum;
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
    switch (config.defaultSyncDirection) {
      case SyncDirection.pushThenPull:
        logBuffer.writeln('│  │  └─ ℹ️  Local changes will be pushed before pulling remote changes.');
        break;
      case SyncDirection.pullThenPush:
        logBuffer.writeln('│  │  └─ ℹ️  Remote changes will be pulled before pushing local changes.');
        break;
      case SyncDirection.pushOnly:
        logBuffer.writeln('│  │  └─ ℹ️  Only local changes will be pushed to the remote.');
        break;
      case SyncDirection.pullOnly:
        logBuffer.writeln('│  │  └─ ℹ️  Only remote changes will be pulled to local.');
        break;
    }
    logBuffer.writeln('│  ├─ 🚦 ${_yellow('Sync Strategy')}: ${_green(config.syncExecutionStrategy.runtimeType)}');
    if (config.syncExecutionStrategy is SequentialStrategy) {
      logBuffer.writeln('│  │  └─ ℹ️  Pending operations will be processed one by one.');
    } else if (config.syncExecutionStrategy is ParallelStrategy) {
      logBuffer.writeln('│  │  └─ ℹ️  Pending operations will be processed in parallel batches.');
    }
    logBuffer.writeln('│  ├─ 🚦 ${_yellow('Request Strategy')}: ${_green(config.syncRequestStrategy.runtimeType)}');
    if (config.syncRequestStrategy is SequentialRequestStrategy) {
      logBuffer.writeln('│  │  └─ ℹ️  Concurrent sync calls will be queued and executed in order.');
    } else if (config.syncRequestStrategy is SkipConcurrentStrategy) {
      logBuffer.writeln('│  │  └─ ℹ️  Concurrent sync calls will be skipped if a sync is already in progress.');
    } else {
      logBuffer.writeln('│  │  └─ ℹ️  Using custom request strategy.');
    }
    logBuffer.writeln('│  ├─ 🚦 ${_yellow('Conflict Resolver')}: ${_green(config.defaultConflictResolver.runtimeType)}');
    logBuffer.writeln('│  ├─ ⏳ ${_yellow('Sync Timeout')}: ${_cyan(formatDuration(config.syncTimeout))}');
    logBuffer.writeln('│  ├─ ↪️  ${_yellow('User Switch')}: ${_green(config.defaultUserSwitchStrategy.name)}');
    switch (config.defaultUserSwitchStrategy) {
      case UserSwitchStrategy.syncThenSwitch:
        logBuffer.writeln('│  │  └─ ℹ️  Syncs previous user\'s pending data before switching.');
        break;
      case UserSwitchStrategy.clearAndFetch:
        logBuffer.writeln('│  │  └─ ℹ️  Clears new user\'s local data, then fetches from remote.');
        break;
      case UserSwitchStrategy.promptIfUnsyncedData:
        logBuffer.writeln('│  │  └─ ℹ️  Fails switch if previous user has unsynced data.');
        break;
      case UserSwitchStrategy.keepLocal:
        logBuffer.writeln('│  │  └─ ℹ️  Switches user without any data modifications.');
        break;
    }
    logBuffer.writeln('│  ├─ 🛡️  ${_yellow('Error Recovery')}: ${_green(config.errorRecoveryStrategy.runtimeType)} (Retries: ${_cyan(config.errorRecoveryStrategy.maxRetries)})');
    logBuffer.writeln('│  │  └─ ℹ️  Uses a ${_green(config.errorRecoveryStrategy.backoffStrategy.runtimeType)} for retries on network errors.');
    logBuffer.writeln('│  └─ ⚡ ${_yellow('Event Handling')}:');
    logBuffer.writeln('│     ├─ ⏱️  Debounce: ${_cyan(formatDuration(config.remoteEventDebounceTime))}');
    logBuffer.writeln('│     └─ 🗑️  Cache TTL: ${_cyan(formatDuration(config.changeCacheDuration))}');
  }

  Future<void> _logPendingOperationsSummary(StringBuffer logBuffer) async {
    final allUserIds = <String>{};
    for (final manager in _managers.allManagers) {
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
        final health = (managerEntry.value as DatumManager<DatumEntityInterface>).currentStatus.health;
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
    var totalSize = 0;

    for (final userId in allUserIds) {
      logBuffer.writeln('│  ├─ 👤 User: ${_cyan(userId)}');
      DatumSyncMetadata? metadata;
      if (_managers.isNotEmpty) {
        metadata = await _managers.allManagers.first.localAdapter.getSyncMetadata(userId);
      }

      final lastSyncResult = _managers.isNotEmpty ? await _managers.allManagers.first.getLastSyncResult(userId) : null;

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
        final manager = managerEntry.value as DatumManager<DatumEntityInterface>;
        final count = await manager.getPendingCount(userId);
        final itemCount = (await manager.localAdapter.readAll(userId: userId)).length;
        final storageSize = await manager.localAdapter.getStorageSize(userId: userId);
        totalItems += itemCount;
        totalPending += count;
        totalSize += storageSize;

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
    final totalSizeInKb = (totalSize / 1024).toStringAsFixed(2);
    logBuffer.writeln('│  └─ 📈 Totals: Items: ${_green(totalItems)}, Pending: ${_yellow(totalPending)}, Size: ${_yellow('$totalSizeInKb KB')}');
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

  Future<void> register<T extends DatumEntityInterface>({
    required DatumRegistration<T> registration,
  }) async {
    _register<T>(registration);
    final logBuffer = StringBuffer();
    await _initializeManagerForType(T, logBuffer);
    logger.info(logBuffer.toString());
  }

  void _register<T extends DatumEntityInterface>(
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

    // Check if T is a subtype of RelationalDatumEntity
    if (isSubtype<RelationalDatumEntity, T>()) {
      isRelational = true;
    }

    final lastCharForConfig = hasMiddlewares || hasObservers || isRelational ? '├' : '└';

    logBuffer?.writeln('│  └─ 🧩 Entity: ${_cyan(T)}');
    logBuffer?.writeln('│     ├─ 🏠 Local Adapter: ${_green(registration.localAdapter.runtimeType)}');
    logBuffer?.writeln('│     ├─ ☁️ Remote Adapter: ${_green(registration.remoteAdapter.runtimeType)}');
    logBuffer?.writeln('│     ├─ ⚖️ Conflict Resolver: ${_green(registration.conflictResolver?.runtimeType ?? 'Default (LastWriteWinsResolver)')}');
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
      logBuffer?.writeln('│     └─ 🤝 Relational: ${_green(true)} ');
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

    // Parallel initialization of managers for better performance
    final initializationFutures = <Future<StringBuffer>>[];
    for (final type in _adapterPairs.keys) {
      initializationFutures.add(_initializeManagerForTypeParallel(type));
    }

    // Wait for all managers to initialize in parallel
    final logBuffers = await Future.wait(initializationFutures);

    // Append all log messages in the order they were initiated
    for (final buffer in logBuffers) {
      logBuffer.write(buffer);
    }
  }

  Future<StringBuffer> _initializeManagerForTypeParallel(Type type) async {
    final logBuffer = StringBuffer();
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
    return logBuffer;
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
          // Also emit to the shared user change stream for reactive queries
          if (!_userChangeController.isClosed) {
            _userChangeController.add(event.newUserId);
          }
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

  /// Starts monitoring connectivity changes and triggers sync when connectivity is restored.
  void _startConnectivityMonitoring() {
    _connectivitySubscription = connectivityChecker.onStatusChange.listen(
      (isConnected) async {
        if (isConnected) {
          logger.info('Connectivity restored - triggering sync for all users with pending changes...');
          await _syncOnConnectivityRestoration();
        } else {
          logger.info('Connectivity lost');
        }
      },
      onError: (error, stackTrace) {
        logger.error('Error monitoring connectivity changes: $error');
      },
    );
  }

  /// Synchronizes all users that have pending operations when connectivity is restored.
  Future<void> _syncOnConnectivityRestoration() async {
    final allUserIds = <String>{};
    for (final manager in _managers.allManagers) {
      try {
        final userIds = await manager.localAdapter.getAllUserIds();
        allUserIds.addAll(userIds);
      } catch (e) {
        logger.warn('Could not get user IDs from ${manager.localAdapter.runtimeType}: $e');
      }
    }

    for (final userId in allUserIds) {
      // Check if user has any pending operations
      var hasPending = false;
      for (final manager in _managers.allManagers) {
        final count = await manager.getPendingCount(userId);
        if (count > 0) {
          hasPending = true;
          break;
        }
      }

      if (hasPending) {
        try {
          logger.info('Triggering automatic sync for user $userId due to connectivity restoration');
          await synchronize(userId);
        } catch (e) {
          logger.error('Failed to synchronize user $userId on connectivity restoration: $e');
        }
      }
    }
  }

  /// Provides access to the specific manager for an entity type.
  static DatumManager<T> manager<T extends DatumEntityInterface>() {
    // Prevent using DatumEntityInterface directly as it is the base interface
    if (T == DatumEntityInterface) {
      throw ArgumentError(
        'Cannot use DatumEntityInterface directly. You must use a concrete entity type that implements DatumEntityInterface. '
        'For example: Datum.manager<MyEntity>() instead of Datum.manager<DatumEntityInterface>().',
      );
    }

    final manager = instance._managers[T];
    if (manager == null) {
      throw StateError('Entity type $T is not registered.');
    }
    return manager as DatumManager<T>;
  }

  /// Provides access to a manager for a given entity [Type].
  static DatumManager<DatumEntityInterface> managerByType(Type type) {
    // Prevent using DatumEntityInterface directly as it is the base interface
    if (type == DatumEntityInterface) {
      throw ArgumentError(
        'Cannot use DatumEntityInterface directly. You must use a concrete entity type that implements DatumEntityInterface.',
      );
    }

    final manager = instance._managers[type];
    if (manager != null) {
      return manager as DatumManager<DatumEntityInterface>;
    }
    throw StateError('Entity type $type is not registered or has a manager of the wrong type.');
  }

  /// A global sync that can coordinate across all managers.
  Future<DatumSyncResult<DatumEntityInterface>> synchronize(
    String userId, {
    DatumSyncOptions<DatumEntityInterface>? options,
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
    final allPending = <DatumSyncOperation<DatumEntityInterface>>[];

    try {
      final direction = options?.direction ?? config.defaultSyncDirection;
      final pushResults = <DatumSyncResult<DatumEntityInterface>>[];
      final pullResults = <DatumSyncResult<DatumEntityInterface>>[];

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

      final result = DatumSyncResult<DatumEntityInterface>(
        userId: userId,
        duration: stopwatch.elapsed,
        syncedCount: totalSynced,
        failedCount: totalFailed,
        conflictsResolved: totalConflicts,
        pendingOperations: allPending,
      );

      _updateSnapshot(userId, (s) => s.copyWith(status: DatumSyncStatus.completed, lastCompletedAt: DateTime.now()));
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

  Future<List<DatumSyncResult<DatumEntityInterface>>> _pushChanges(String userId, DatumSyncOptions<DatumEntityInterface>? options) async {
    logger.info('Starting global push phase for user $userId...');
    final pushOnlyOptions = (options ?? const DatumSyncOptions<DatumEntityInterface>()).copyWith(
      direction: SyncDirection.pushOnly,
    );

    final results = <DatumSyncResult<DatumEntityInterface>>[];
    for (final manager in _managers.allManagers) {
      results.add(await manager.synchronize(userId, options: pushOnlyOptions));
    }
    return results;
  }

  Future<List<DatumSyncResult<DatumEntityInterface>>> _pullChanges(
    String userId,
    DatumSyncOptions<DatumEntityInterface>? options,
  ) async {
    logger.info('Starting global pull phase for user $userId...');
    final pullOnlyOptions = (options ?? const DatumSyncOptions<DatumEntityInterface>()).copyWith(
      direction: SyncDirection.pullOnly,
    );

    final results = <DatumSyncResult<DatumEntityInterface>>[];
    for (final manager in _managers.allManagers) {
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
    if (!_statusSubject.isClosed) {
      _statusSubject.add(_snapshots);
    }
  }

  // CRUD operations remain the same but now use DatumEntityInterface

  /// Creates a new entity and pushes it to the appropriate manager.
  ///
  /// This is a convenience method that is equivalent to calling `Datum.manager<T>().push(item: entity, userId: entity.userId)`.
  Future<T> create<T extends DatumEntityInterface>(T entity) {
    return Datum.manager<T>().push(item: entity, userId: entity.userId);
  }

  Future<T?> read<T extends DatumEntityInterface>(String id, {String? userId}) {
    return Datum.manager<T>().read(id, userId: userId);
  }

  Future<List<T>> readAll<T extends DatumEntityInterface>({String? userId}) {
    return Datum.manager<T>().readAll(userId: userId);
  }

  Future<T> update<T extends DatumEntityInterface>(T entity) {
    return Datum.manager<T>().push(item: entity, userId: entity.userId);
  }

  Future<List<T>> createMany<T extends DatumEntityInterface>({
    required List<T> items,
    required String userId,
    bool andSync = false,
    DatumSyncOptions<T>? syncOptions,
  }) {
    return Datum.manager<T>().saveMany(
      items: items,
      userId: userId,
      andSync: andSync,
      syncOptions: syncOptions,
    );
  }

  Future<List<T>> updateMany<T extends DatumEntityInterface>({
    required List<T> items,
    required String userId,
    bool andSync = false,
    DatumSyncOptions<T>? syncOptions,
  }) {
    return Datum.manager<T>().saveMany(
      items: items,
      userId: userId,
      andSync: andSync,
      syncOptions: syncOptions,
    );
  }

  /// Deletes an entity by its ID.
  ///
  /// The [behavior] parameter allows overriding the global [DatumConfig.deleteBehavior]
  /// for this specific delete operation. If null, the global config value is used.
  Future<bool> delete<T extends DatumEntityInterface>({
    required String id,
    required String userId,
    DeleteBehavior? behavior,
  }) async {
    return Datum.manager<T>().delete(id: id, userId: userId, behavior: behavior);
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
  Future<CascadeDeleteResult<T>> cascadeDelete<T extends DatumEntityInterface>({
    required String id,
    required String userId,
    DataSource source = DataSource.local,
    bool forceRemoteSync = false,
  }) async {
    return Datum.manager<T>().cascadeDelete(
      id: id,
      userId: userId,
      source: source,
      forceRemoteSync: forceRemoteSync,
    );
  }

  /// Creates a fluent API builder for cascade delete operations.
  ///
  /// This provides a convenient way to configure and execute cascading delete operations
  /// with options like dry-run mode, progress callbacks, cancellation, and timeouts.
  ///
  /// Example usage:
  /// ```dart
  /// final result = await Datum.deleteCascade<Post>('post-123')
  ///   .forUser('user-456')
  ///   .dryRun()
  ///   .execute();
  /// ```
  CascadeDeleteBuilder<T> deleteCascade<T extends DatumEntityInterface>(String entityId) {
    return Datum.manager<T>().deleteCascade(entityId);
  }

  Future<(T, DatumSyncResult<T>)> pushAndSync<T extends DatumEntityInterface>({
    required T item,
    required String userId,
    DatumSyncOptions<T>? syncOptions,
  }) {
    return Datum.manager<T>().pushAndSync(
      item: item,
      userId: userId,
      syncOptions: syncOptions,
    );
  }

  Future<(T, DatumSyncResult<T>)> updateAndSync<T extends DatumEntityInterface>({
    required T item,
    required String userId,
    DatumSyncOptions<T>? syncOptions,
  }) {
    return Datum.manager<T>().updateAndSync(
      item: item,
      userId: userId,
      syncOptions: syncOptions,
    );
  }

  /// Deletes an entity and immediately triggers synchronization.
  ///
  /// The [behavior] parameter allows overriding the global [DatumConfig.deleteBehavior]
  /// for this specific delete operation. If null, the global config value is used.
  Future<(bool, DatumSyncResult<T>)> deleteAndSync<T extends DatumEntityInterface>({
    required String id,
    required String userId,
    DatumSyncOptions<T>? syncOptions,
    DeleteBehavior? behavior,
  }) =>
      Datum.manager<T>().deleteAndSync(id: id, userId: userId, syncOptions: syncOptions, behavior: behavior);

  Stream<List<T>>? watchAll<T extends DatumEntityInterface>({String? userId, bool includeInitialData = true}) {
    return Datum.manager<T>().watchAll(userId: userId, includeInitialData: includeInitialData);
  }

  Stream<T?>? watchById<T extends DatumEntityInterface>(String id, String? userId) {
    return Datum.manager<T>().watchById(id, userId);
  }

  Stream<PaginatedResult<T>>? watchAllPaginated<T extends DatumEntityInterface>(
    PaginationConfig config, {
    String? userId,
  }) {
    return Datum.manager<T>().watchAllPaginated(config, userId: userId);
  }

  Stream<List<T>>? watchQuery<T extends DatumEntityInterface>(DatumQuery query, {String? userId}) {
    return Datum.manager<T>().watchQuery(query, userId: userId);
  }

  Future<List<T>> query<T extends DatumEntityInterface>(
    DatumQuery query, {
    required DataSource source,
    String? userId,
  }) async {
    return Datum.manager<T>().query(query, source: source, userId: userId);
  }

  /// Fetches related entities with proper type checking for [RelationalDatumEntity]
  Future<List<R>> fetchRelated<P extends DatumEntityInterface, R extends DatumEntityInterface>(
    P parent,
    String relationName, {
    DataSource source = DataSource.local,
  }) async {
    // Type-safe check using sealed class pattern matching
    switch (parent) {
      case RelationalDatumEntity():
        return Datum.managerByType(parent.runtimeType).fetchRelated<R>(parent, relationName, source: source);

      case _:
        throw ArgumentError(
          'Entity of type ${parent.runtimeType} is not relational and cannot have relations. '
          'To use relations, extend RelationalDatumEntity instead of DatumEntity or use RelationalDatumEntityMixin to use `with` block.',
        );
    }
  }

  /// Reactively watches related entities with proper type checking
  Stream<List<R>>? watchRelated<P extends DatumEntityInterface, R extends DatumEntityInterface>(
    P parent,
    String relationName,
  ) {
    // Type-safe check using sealed class pattern matching
    switch (parent) {
      case RelationalDatumEntity():
        return Datum.managerByType(parent.runtimeType).watchRelated<R>(parent, relationName);
      case _:
        throw ArgumentError(
          'Entity of type ${parent.runtimeType} is not relational and cannot have relations. '
          'To use relations, extend RelationalDatumEntity instead of DatumEntity or use RelationalDatumEntityMixin to use `with` block.',
        );
    }
  }

  Future<int> getPendingCount<T extends DatumEntityInterface>(String userId) async {
    return Datum.manager<T>().getPendingCount(userId);
  }

  Future<List<DatumSyncOperation<T>>> getPendingOperations<T extends DatumEntityInterface>(String userId) async {
    return Datum.manager<T>().getPendingOperations(userId);
  }

  Future<int> getStorageSize<T extends DatumEntityInterface>({String? userId}) {
    return Datum.manager<T>().getStorageSize(userId: userId);
  }

  Stream<int> watchStorageSize<T extends DatumEntityInterface>({String? userId}) {
    return Datum.manager<T>().watchStorageSize(userId: userId);
  }

  Future<DatumSyncResult<T>?> getLastSyncResult<T extends DatumEntityInterface>(String userId) async {
    return Datum.manager<T>().getLastSyncResult(userId);
  }

  /// Fetches sync metadata from the remote server for the specified entity type.
  ///
  /// This is a convenience method that calls [getRemoteSyncMetadata] on the
  /// appropriate manager. Returns null if no metadata exists or if the remote
  /// adapter doesn't support this operation.
  Future<DatumSyncMetadata?> getRemoteSyncMetadata<T extends DatumEntityInterface>(String userId) async {
    return Datum.manager<T>().getRemoteSyncMetadata(userId);
  }

  Future<DatumHealth> checkHealth<T extends DatumEntityInterface>() async {
    return Datum.manager<T>().checkHealth();
  }

  /// Checks if this is a cold start for the specified user and entity type.
  ///
  /// Returns true if cold start sync is needed for this user.
  bool isColdStartForUser<T extends DatumEntityInterface>(String userId) {
    return Datum.manager<T>().coldStartManager.isColdStartForUser(userId);
  }

  /// Gets the last cold start time for the specified user and entity type.
  ///
  /// Returns null if no cold start has occurred for this user.
  DateTime? getLastColdStartTimeForUser<T extends DatumEntityInterface>(String userId) {
    return Datum.manager<T>().coldStartManager.getLastColdStartTimeForUser(userId);
  }

  /// Resets cold start state for the specified user and entity type.
  ///
  /// This is useful for testing or when you want to force a cold start sync.
  void resetColdStartForUser<T extends DatumEntityInterface>(String userId) {
    Datum.manager<T>().coldStartManager.resetForUser(userId);
  }

  /// Handles cold start synchronization if needed for the specified user and entity type.
  ///
  /// This method checks if a cold start sync is required based on the configured strategy
  /// and performs the sync if necessary.
  ///
  /// Returns true if a cold start sync was performed, false otherwise.
  Future<bool> handleColdStartIfNeeded<T extends DatumEntityInterface>(
    String? userId,
    Future<DatumSyncResult<T>> Function(DatumSyncOptions) syncFunction, {
    bool synchronous = false,
  }) async {
    return Datum.manager<T>().coldStartManager.handleColdStartIfNeeded(
      userId,
      (options) async {
        // Convert the generic DatumSyncOptions to the specific type expected
        final typedOptions = DatumSyncOptions<T>(
          forceFullSync: options.forceFullSync,
          timeout: options.timeout,
          direction: options.direction,
          includeDeletes: options.includeDeletes,
          resolveConflicts: options.resolveConflicts,
          overrideBatchSize: options.overrideBatchSize,
          conflictResolver: options.conflictResolver != null ? (options.conflictResolver is DatumConflictResolver<T> ? options.conflictResolver as DatumConflictResolver<T> : null) : null,
          query: options.query,
        );
        return await syncFunction(typedOptions);
      },
      entityType: T.toString(),
      synchronous: synchronous,
    );
  }

  /// Gets all active users that have cold start state for the specified entity type.
  ///
  /// Returns a set of user IDs that have been tracked by the cold start manager.
  Set<String> getColdStartActiveUsers<T extends DatumEntityInterface>() {
    return Datum.manager<T>().coldStartManager.getActiveUsers();
  }

  /// Gets the most recent last sync time across all registered entities for the specified user.
  ///
  /// This method queries the sync metadata of all registered entity managers and returns
  /// the most recent `lastSyncTime` found. Returns null if no sync has ever been performed
  /// for this user across any entity type.
  ///
  /// This is useful for displaying when the last synchronization occurred in UI components.
  ///
  /// Example:
  /// ```dart
  /// final lastSync = await Datum.instance.getLastSyncTime('user123');
  /// if (lastSync != null) {
  ///   print('Last sync was ${DateTime.now().difference(lastSync).inMinutes} minutes ago');
  /// } else {
  ///   print('No sync has been performed yet');
  /// }
  /// ```
  Future<DateTime?> getLastSyncTime(String userId) async {
    if (_managers.isEmpty) return null;

    DateTime? mostRecentSync;
    for (final manager in _managers.allManagers) {
      try {
        final metadata = await manager.localAdapter.getSyncMetadata(userId);
        if (metadata?.lastSyncTime != null) {
          if (mostRecentSync == null || metadata!.lastSyncTime!.isAfter(mostRecentSync)) {
            mostRecentSync = metadata!.lastSyncTime!;
          }
        }
      } catch (e) {
        // Continue with other managers if one fails
        logger.debug('Failed to get sync metadata from ${manager.runtimeType}: $e');
      }
    }
    return mostRecentSync;
  }

  /// Gets unified sync metadata across all entities for the specified user.
  ///
  /// This method aggregates sync metadata from all registered entity managers into a single,
  /// comprehensive view. This provides a complete picture of the user's sync state across
  /// all entity types, addressing the issue of fragmented per-entity metadata.
  ///
  /// The returned metadata includes:
  /// - Global sync status and timestamps
  /// - Entity-specific counts, hashes, and pending changes
  /// - Device information and conflict tracking
  ///
  /// Example:
  /// ```dart
  /// final metadata = await Datum.instance.getUnifiedSyncMetadata('user123');
  /// if (metadata != null) {
  ///   print('Last sync: ${metadata.lastSyncTime}');
  ///   print('Total pending changes: ${metadata.totalPendingChanges}');
  ///   print('Entity counts: ${metadata.entityCounts}');
  /// }
  /// ```
  Future<DatumSyncMetadata?> getUnifiedSyncMetadata(String userId) async {
    if (_managers.isEmpty) return null;

    // Get metadata from all managers
    final allMetadata = <DatumSyncMetadata>[];
    for (final manager in _managers.allManagers) {
      try {
        final metadata = await manager.localAdapter.getSyncMetadata(userId);
        if (metadata != null) {
          allMetadata.add(metadata);
        }
      } catch (e) {
        logger.debug('Failed to get sync metadata from ${manager.runtimeType}: $e');
      }
    }

    if (allMetadata.isEmpty) return null;

    // Find the most recent metadata as the base
    allMetadata.sort((a, b) {
      final aTime = a.lastSyncTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastSyncTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    final baseMetadata = allMetadata.first;

    // Aggregate entity counts from all metadata
    final aggregatedEntityCounts = <String, DatumEntitySyncDetails>{};
    for (final metadata in allMetadata) {
      if (metadata.entityCounts != null) {
        aggregatedEntityCounts.addAll(metadata.entityCounts!);
      }
    }

    // Aggregate device information
    final allDevices = <String, DateTime>{};
    for (final metadata in allMetadata) {
      if (metadata.devices != null) {
        allDevices.addAll(metadata.devices!);
      }
    }

    // Determine overall sync status
    final hasAnyFailed = allMetadata.any((m) => m.syncStatus == SyncStatus.failed);
    final hasAnySyncing = allMetadata.any((m) => m.syncStatus == SyncStatus.syncing);
    final hasAnyConflicts = allMetadata.any((m) => m.hasConflicts);
    final hasAnyPending = allMetadata.any((m) => m.totalPendingChanges > 0);

    SyncStatus overallStatus;
    if (hasAnyFailed) {
      overallStatus = SyncStatus.failed;
    } else if (hasAnySyncing) {
      overallStatus = SyncStatus.syncing;
    } else if (hasAnyConflicts) {
      overallStatus = SyncStatus.conflict;
    } else if (hasAnyPending) {
      overallStatus = SyncStatus.pending;
    } else if (baseMetadata.isNeverSynced) {
      overallStatus = SyncStatus.neverSynced;
    } else {
      overallStatus = SyncStatus.synced;
    }

    // Aggregate conflict count
    final totalConflicts = allMetadata.fold<int>(0, (sum, m) => sum + m.conflictCount);

    return baseMetadata.copyWith(
      entityCounts: aggregatedEntityCounts.isNotEmpty ? aggregatedEntityCounts : null,
      devices: allDevices.isNotEmpty ? allDevices : null,
      syncStatus: overallStatus,
      conflictCount: totalConflicts,
    );
  }

  Future<void> dispose() async {
    if (_instance != null) {
      pauseSync();

      await Future.wait([
        ..._managers.allManagers.map((m) => m.dispose()),
        ..._managerSubscriptions.map((s) => s.cancel()),
      ]);

      await _connectivitySubscription?.cancel();
      await _eventController.close();
      await _userChangeController.close();
      await _metricsSubject.close();
      await _statusSubject.close();
    }

    if (_instance == this) {
      _instance = null;
    }
  }

  void pauseSync() {
    logger.info('Pausing sync for all managers...');
    for (final manager in _managers.allManagers) {
      manager.pauseSync();
    }
  }

  void resumeSync() {
    logger.info('Resuming sync for all managers...');
    for (final manager in _managers.allManagers) {
      manager.resumeSync();
    }
  }

  /// Starts automatic periodic synchronization for the specified user across all managers.
  ///
  /// Uses the auto-sync interval from the configuration.
  /// Automatically stops any existing auto-sync for the same user across all managers.
  void startAutoSync(String userId) {
    logger.info('Starting auto-sync for user $userId across all managers...');
    for (final manager in _managers.allManagers) {
      manager.startAutoSync(userId);
    }
  }

  /// Unsubscribes all managers from remote change events.
  ///
  /// This method calls [DatumManager.unsubscribeFromRemoteChanges] on all registered managers,
  /// which can be useful for reducing network activity or preventing
  /// unnecessary processing during certain application states.
  ///
  /// Call [resubscribeAllToRemoteChanges] to re-enable remote change listening.
  ///
  /// Note: This only affects remote change subscriptions and does not
  /// impact local change processing or synchronization operations.
  Future<void> unsubscribeAllFromRemoteChanges() async {
    await Future.wait(
      _managers.allManagers.map((manager) => manager.unsubscribeFromRemoteChanges()),
    );
  }

  /// Re-subscribes all managers to remote change events.
  ///
  /// This method calls [DatumManager.resubscribeToRemoteChanges] on all registered managers,
  /// restoring the normal flow of remote change events being processed and
  /// applied locally.
  ///
  /// Note: This only affects remote change subscriptions and does not
  /// impact local change processing or synchronization operations.
  Future<void> resubscribeAllToRemoteChanges() async {
    await Future.wait(
      _managers.allManagers.map((manager) => manager.resubscribeToRemoteChanges()),
    );
  }

  /// Refreshes all reactive streams across all registered managers.
  ///
  /// This method clears caches and forces all reactive streams to re-evaluate
  /// their data. This is useful when external state changes (like user switches)
  /// require all streams to refresh their data.
  ///
  /// This method:
  /// - Clears internal caches in all managers
  /// - Emits special refresh events to trigger stream re-evaluation
  /// - Ensures all reactive streams show the most current data
  Future<void> refreshStreams() async {
    logger.debug('Refreshing all streams across all managers...');
    await Future.wait(
      _managers.allManagers.map((manager) => manager.refreshStreams()),
    );
    logger.debug('All streams refreshed successfully');
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }
}

// Check whether two types are the same type in Dart when working with
// generic types.
//
// Uses the same definition as the language specification for when two
// types are the same. Currently the same as mutual sub-typing.
bool sameTypes<S, V>() {
  void func<X extends S>() {}
  // Dart spec says this is only true if S and V are "the same type".
  return func is void Function<X extends V>();
}
