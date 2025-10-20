import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/models/datum_registration.dart';
import 'package:datum/source/core/engine/datum_core.dart';
import 'package:datum/source/core/engine/datum_observer.dart';
import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/middleware/datum_middleware.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

// Helper to hold adapter pairs before managers are created.
abstract class AdapterPair {
  DatumManager<DatumEntity> createManager(Datum datum);
}

class AdapterPairImpl<T extends DatumEntity> implements AdapterPair {
  final LocalAdapter<T> local;
  final RemoteAdapter<T> remote;
  final DatumConflictResolver<T>? conflictResolver;
  final DatumConfig<T>? config;
  final List<DatumMiddleware<T>>? middlewares;
  final List<DatumObserver<T>>? observers;

  AdapterPairImpl(
    this.local,
    this.remote, {
    this.conflictResolver,
    this.middlewares,
    this.config,
    this.observers,
  });

  factory AdapterPairImpl.fromRegistration(DatumRegistration<T> registration) {
    return AdapterPairImpl<T>(
      registration.localAdapter,
      registration.remoteAdapter,
      conflictResolver: registration.conflictResolver,
      middlewares: registration.middlewares,
      config: registration.config,
      observers: registration.observers,
    );
  }

  @override
  DatumManager<T> createManager(Datum datum) {
    // Keep specific return type here
    final manager = DatumManager<T>(
      localAdapter: local,
      remoteAdapter: remote,
      conflictResolver: conflictResolver,
      localObservers: observers,
      globalObservers: datum.globalObservers,
      middlewares: middlewares,
      datumConfig: config ?? datum.config.copyWith<T>(),
      connectivity: datum.connectivityChecker,
      logger: datum.logger,
    );
    return manager;
  }
}
