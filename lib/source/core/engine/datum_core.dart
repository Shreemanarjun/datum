import 'dart:async';

import 'package:datum/datum.dart';
import 'package:datum/source/core/engine/_internal.dart'; // Correct import
import 'package:flutter/foundation.dart';
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

  /// Returns the singleton instance if it has been initialized, otherwise null.
  /// For testing purposes.
  @visibleForTesting
  static Datum? get instanceOrNull => _instance;

  final DatumConfig config;
  final Map<Type, DatumManager<DatumEntity>> _managers = {};
  final Map<Type, AdapterPair> _adapterPairs = {};
  final ConnectivityChecker connectivityChecker;
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
    required ConnectivityChecker connectivityChecker,
    DatumLogger? logger,
    List<DatumRegistration> registrations = const [],
  }) async {
    final datum = Datum._(
      config: config,
      connectivityChecker: connectivityChecker,
      logger: logger,
    );
    for (final reg in registrations) {
      // ignore: unused_local_variable
      // Use <TT> to avoid shadowing the generic type from the capture method.
      reg.capture(
        <TT extends DatumEntity>() =>
            datum._register<TT>(reg as DatumRegistration<TT>),
      );
    }
    await datum._initializeManagers();
    datum._listenToEventsForMetrics();
    return _instance = datum;
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
    await _initializeManagerForType(T);
  }

  void _register<T extends DatumEntity>(DatumRegistration<T> registration) {
    // With modern Dart, using the generic type T directly as a map key is reliable.
    if (_managers.containsKey(T)) {
      logger.warn('Entity type $T is already registered. Overwriting.');
    }
    _adapterPairs[T] = AdapterPairImpl<T>.fromRegistration(registration);
  }

  /// Initializes all registered managers and the central engine.
  Future<void> _initializeManagers() async {
    for (final type in _adapterPairs.keys) {
      await _initializeManagerForType(type);
    }
    // Pass shared components from a new central SyncEngine

    // Initialize a new "RelationalSyncEngine" that knows about all managers.
  }

  Future<void> _initializeManagerForType(Type type) async {
    final adapters = _adapterPairs[type];
    if (adapters == null) {
      throw StateError(
        'AdapterPair not found for type $type during initialization.',
      );
    }

    // The generic factory helps create the correctly typed manager.
    final manager = adapters.createManager(this);
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
      logger.info('Sync already in progress for user $userId. Skipping.');
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
      rethrow;
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

  /// Resets the singleton instance. For testing purposes only.
  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }
}
