import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// How relation, cascade and user-switch code reaches sibling managers.
///
/// The `Datum` facade sits above the manager layer, so code down here must not
/// import it. The facade installs its lookups instead; until it has, every
/// lookup throws the same "not initialized" error the facade would.
abstract final class ManagerLocator {
  static DatumManager<R> Function<R extends DatumEntityInterface>()? _of;
  static DatumManager<DatumEntityInterface> Function(Type type)? _byType;
  static Future<void> Function()? _refreshStreams;

  /// Called by the facade when it is created.
  static void install({
    required DatumManager<R> Function<R extends DatumEntityInterface>() of,
    required DatumManager<DatumEntityInterface> Function(Type type) byType,
    required Future<void> Function() refreshStreams,
  }) {
    _of = of;
    _byType = byType;
    _refreshStreams = refreshStreams;
  }

  static Never _notInstalled() => throw StateError('Datum has not been initialized. Call Datum.initialize() first.');

  /// The manager registered for entity type [R].
  static DatumManager<R> of<R extends DatumEntityInterface>() => (_of ?? _notInstalled())<R>();

  /// The manager registered for [type].
  static DatumManager<DatumEntityInterface> byType(Type type) => (_byType ?? _notInstalled())(type);

  /// Re-emits every manager's watch streams; a no-op without a facade.
  static Future<void> refreshStreams() => _refreshStreams?.call() ?? Future<void>.value();
}
