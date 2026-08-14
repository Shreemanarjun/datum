import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/adapter/remote_adapter.dart';
import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/engine/datum_observer.dart';
import 'package:datum/source/core/manager/datum_sync_request_strategy.dart';
import 'package:datum/source/core/middleware/datum_middleware.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

/// A helper class to encapsulate the registration details for a single entity type.
class DatumRegistration<T extends DatumEntityInterface> {
  final LocalAdapter<T> localAdapter;
  final RemoteAdapter<T> remoteAdapter;
  final DatumConflictResolver<T>? conflictResolver;
  final DatumConfig<T>? config;
  final List<DatumMiddleware<T>>? middlewares;
  final List<DatumObserver<T>>? observers;
  final DatumSyncRequestStrategy? syncRequestStrategy;

  const DatumRegistration({
    required this.localAdapter,
    required this.remoteAdapter,
    this.conflictResolver,
    this.config,
    this.middlewares,
    this.observers,
    this.syncRequestStrategy,
  });

  /// A helper method to capture the generic type `T` at runtime.
  /// This is used to get a reliable `Type` object as a key for maps.
  R capture<R>(R Function<E extends DatumEntityInterface>() cb) {
    return cb<T>();
  }
}
