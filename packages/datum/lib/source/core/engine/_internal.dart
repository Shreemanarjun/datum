import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/manager/datum_sync_request_strategy.dart';
import 'package:datum/source/core/models/datum_registration.dart';
import 'package:datum/source/core/engine/datum_core.dart';
import 'package:datum/source/core/engine/datum_observer.dart';
import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/middleware/datum_middleware.dart';
import 'package:datum/source/core/models/datum_sync_options.dart';

import 'package:datum/source/core/resolver/conflict_resolution.dart';

import '../models/datum_entity.dart';

// Helper to hold adapter pairs before managers are created.
abstract class AdapterPair {
  DatumManager<DatumEntityInterface> createManager(Datum datum);
}

class AdapterPairImpl<T extends DatumEntityInterface> implements AdapterPair {
  final LocalAdapter<T> local;
  final RemoteAdapter<T> remote;
  final DatumConflictResolver<T>? conflictResolver;
  final DatumConfig<T>? config;
  final List<DatumMiddleware<T>>? middlewares;
  final List<DatumObserver<T>>? observers;
  final DatumSyncRequestStrategy? syncRequestStrategy;

  AdapterPairImpl(
    this.local,
    this.remote, {
    this.conflictResolver,
    this.middlewares,
    this.config,
    this.observers,
    this.syncRequestStrategy,
  });

  factory AdapterPairImpl.fromRegistration(DatumRegistration<T> registration) {
    return AdapterPairImpl<T>(
      registration.localAdapter,
      registration.remoteAdapter,
      conflictResolver: registration.conflictResolver,
      middlewares: registration.middlewares,
      config: registration.config,
      observers: registration.observers,
      syncRequestStrategy: registration.syncRequestStrategy,
    );
  }

  @override
  DatumManager<T> createManager(Datum datum) {
    // This is a testing hook. If the config is a special type, return the mock manager from it.
    // This allows us to inject a mock manager during Datum.initialize() in tests.
    final registrationConfig = config ?? datum.config.copyWith<T>(
      defaultConflictResolver: (datum.config.defaultConflictResolver != null)
          ? DatumConflictResolverAdapter<T>(datum.config.defaultConflictResolver!)
          : null,
      defaultSyncOptions: datum.config.defaultSyncOptions?.toTyped<T>()
    );
    if (registrationConfig is CustomManagerConfig<T>) {
      final customConfig = registrationConfig;
      // Return the mock manager provided by the custom config.
      // We still need to pass some dependencies to it for initialization.
      // This part is a bit of a hack for testing purposes.
      return customConfig.mockManager;
    }

    // Keep specific return type here
    final manager = DatumManager<T>(
      localAdapter: local,
      remoteAdapter: remote,
      conflictResolver: conflictResolver ?? registrationConfig.defaultConflictResolver,
      localObservers: observers,
      globalObservers: datum.globalObservers,
      middlewares: middlewares,
      datumConfig: registrationConfig,
      connectivity: datum.connectivityChecker,
      logger: datum.logger,
      syncRequestStrategy: syncRequestStrategy ?? registrationConfig.syncRequestStrategy,
      persistence: datum.persistence,
      userChangeStream: datum.userChangeStream,
    );
    return manager;
  }
}

/// A testing-only config to smuggle a mock manager into the creation process.
class CustomManagerConfig<T extends DatumEntityInterface> extends DatumConfig<T> {
  final DatumManager<T> mockManager;

  const CustomManagerConfig(this.mockManager);
}
