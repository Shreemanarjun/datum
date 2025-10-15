import 'dart:async';

import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/events/datum_event.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/models/datum_sync_options.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:datum/source/core/models/datum_sync_status_snapshot.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:rxdart/rxdart.dart';
import 'package:datum/source/utils/connectivity_checker.dart';
import 'package:datum/source/utils/datum_logger.dart';
import 'package:datum/source/core/middleware/datum_middleware.dart';
import 'package:datum/source/core/engine/datum_observer.dart';

class Datum {
  final DatumConfig config;
  final Map<Type, DatumManager<DatumEntity>> _managers = {};
  final Map<Type, _AdapterPair<DatumEntity>> _adapterPairs = {};
  final ConnectivityChecker _connectivityChecker;
  final List<GlobalDatumObserver> _globalObservers = [];
  final List<StreamSubscription<DatumSyncEvent<DatumEntity>>>
  _managerSubscriptions = [];
  final DatumLogger _logger;

  // Stream controllers for events and status
  final StreamController<DatumSyncEvent<DatumEntity>> _eventController =
      StreamController.broadcast();
  Stream<DatumSyncEvent> get events => _eventController.stream;

  final BehaviorSubject<Map<String, DatumSyncStatusSnapshot>> _statusSubject =
      BehaviorSubject.seeded({});
  Stream<DatumSyncStatusSnapshot?> statusForUser(String userId) =>
      _statusSubject.stream.map((map) => map[userId]);

  final Map<String, DatumSyncStatusSnapshot> _snapshots = {};

  Datum({
    required this.config,
    required ConnectivityChecker connectivityChecker,
    DatumLogger? logger,
  }) : _connectivityChecker = connectivityChecker,
       _logger = logger ?? DatumLogger(enabled: config.enableLogging);

  /// Adds a global observer to listen to events from all managers.
  void addObserver(GlobalDatumObserver observer) {
    _globalObservers.add(observer);
  }

  /// Registers an entity type with its specific adapters.
  void register<T extends DatumEntity>({
    required LocalAdapter<T> localAdapter,
    required RemoteAdapter<T> remoteAdapter,
    DatumConflictResolver<T>? conflictResolver,
    DatumConfig<T>? config,
    List<DatumMiddleware<T>>? middlewares,
    List<DatumObserver<T>>? observers,
  }) {
    _adapterPairs[T] = _AdapterPairImpl<T>(
      localAdapter,
      remoteAdapter,
      conflictResolver: conflictResolver,
      middlewares: middlewares,
      config: config,
      observers: observers,
    );
  }

  /// Initializes all registered managers and the central engine.
  Future<void> initialize() async {
    for (final type in _adapterPairs.keys) {
      final adapters = _adapterPairs[type]!;
      // The generic factory helps create the correctly typed manager.
      final manager = adapters.createManager(this);
      _managers[type] = manager;
      // Subscribe to the manager's event stream and pipe events to the global controller.
      final subscription = manager.eventStream.listen(
        _eventController.add,
        onError: _eventController.addError,
      );
      _managerSubscriptions.add(subscription);
      await manager.initialize();
    }
    // Pass shared components from a new central SyncEngine

    // Initialize a new "RelationalSyncEngine" that knows about all managers.
  }

  /// Provides access to the specific manager for an entity type.
  /// This preserves the familiar `SynqManager` API.
  DatumManager<T> manager<T extends DatumEntity>() {
    final manager = _managers[T];
    if (manager == null) {
      throw StateError('Entity type $T is not registered.');
    }
    return manager as DatumManager<T>;
  }

  /// A global sync that can coordinate across all managers.
  Future<DatumSyncResult> synchronize(
    String userId, {
    DatumSyncOptions? options,
  }) async {
    final snapshot = _getSnapshot(userId);
    if (snapshot.status == DatumSyncStatus.syncing) {
      _logger.info('Sync already in progress for user $userId. Skipping.');
      return DatumSyncResult.skipped(userId, snapshot.pendingOperations);
    }

    final stopwatch = Stopwatch()..start();
    _updateSnapshot(userId, (s) => s.copyWith(status: DatumSyncStatus.syncing));
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
            allPending.addAll(res.pendingOperations.cast());
          }
          break;
        case SyncDirection.pullThenPush:
          final pullResults = await _pullChanges(userId, options);
          for (final res in pullResults) {
            totalSynced += res.syncedCount;
            totalFailed += res.failedCount;
            totalConflicts += res.conflictsResolved;
            allPending.addAll(res.pendingOperations.cast());
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
            allPending.addAll(res.pendingOperations.cast());
          }
          break;
      }

      final result = DatumSyncResult(
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
      return result;
    } catch (e, stack) {
      _logger.error('Synchronization failed for user $userId', stack);
      _updateSnapshot(
        userId,
        (s) => s.copyWith(status: DatumSyncStatus.failed, errors: [e]),
      );
      _eventController.add(
        DatumSyncErrorEvent(userId: userId, error: e, stackTrace: stack),
      );
      rethrow;
    }
  }

  Future<void> _pushChanges(String userId, DatumSyncOptions? options) async {
    _logger.info('Starting global push phase for user $userId...');
    // Ensure we only perform a push operation, respecting the original options.
    final pushOnlyOptions = (options ?? const DatumSyncOptions()).copyWith(
      direction: SyncDirection.pushOnly,
    );

    for (final manager in _managers.values) {
      // We call synchronize with pushOnly to process the queue for each manager.
      await manager.synchronize(userId, options: pushOnlyOptions);
    }
  }

  Future<List<DatumSyncResult>> _pullChanges(
    String userId,
    DatumSyncOptions? options,
  ) async {
    _logger.info('Starting global pull phase for user $userId...');
    // Ensure we only perform a pull operation, respecting the original options.
    final pullOnlyOptions = (options ?? const DatumSyncOptions()).copyWith(
      direction: SyncDirection.pullOnly,
    );

    final results = <DatumSyncResult>[];
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
    return manager<T>().push(item: entity, userId: entity.userId);
  }

  /// Reads a single entity of type T by its ID.
  Future<T?> read<T extends DatumEntity>(String id, {String? userId}) {
    // In a multi-manager setup, we might need to know which manager to ask.
    // For now, we assume the first one that can handle type T.
    return manager<T>().read(id, userId: userId);
  }

  /// Reads all entities of type T.
  Future<List<T>> readAll<T extends DatumEntity>({String? userId}) {
    return manager<T>().readAll(userId: userId);
  }

  /// Updates an existing entity of type T.
  Future<T> update<T extends DatumEntity>(T entity) {
    return manager<T>().push(item: entity, userId: entity.userId);
  }

  /// Deletes an entity of type T by its ID.
  Future<bool> delete<T extends DatumEntity>({
    required String id,
    required String userId,
  }) async {
    return manager<T>().delete(id: id, userId: userId);
  }

  Future<void> dispose() async {
    // Await all disposals and cancellations concurrently for efficiency.
    await Future.wait([
      ..._managers.values.map((m) => m.dispose()),
      ..._managerSubscriptions.map((s) => s.cancel()),
    ]);
    await _eventController.close();
    await _statusSubject.close();
  }
}

// Helper to hold adapter pairs before managers are created.
abstract class _AdapterPair<T extends DatumEntity> {
  DatumManager<T> createManager(Datum datum);
}

class _AdapterPairImpl<T extends DatumEntity> implements _AdapterPair<T> {
  final LocalAdapter<T> local;
  final RemoteAdapter<T> remote;
  final DatumConflictResolver<T>? conflictResolver;
  final DatumConfig<T>? config;
  final List<DatumMiddleware<T>>? middlewares;
  final List<DatumObserver<T>>? observers;

  _AdapterPairImpl(
    this.local,
    this.remote, {
    this.conflictResolver,
    this.middlewares,
    this.config,
    this.observers,
  });

  @override
  DatumManager<T> createManager(Datum datum) {
    // The main Datum engine can pass down its config and shared services.
    return DatumManager<T>(
      localAdapter: local,
      remoteAdapter: remote,
      conflictResolver: conflictResolver,
      localObservers: observers,
      globalObservers: datum._globalObservers,
      middlewares: middlewares,
      datumConfig: config ?? datum.config.copyWith<T>(),
      connectivity: datum._connectivityChecker,
      logger: datum._logger,
    );
  }
}
