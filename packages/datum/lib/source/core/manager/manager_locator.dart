import 'package:datum/source/core/manager/datum_manager.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/related_source.dart';
import 'package:datum/source/core/models/relational_datum_entity.dart';

/// How relation, cascade and user-switch code reaches sibling managers.
///
/// The `Datum` facade sits above the manager layer, so code down here must not
/// import it. The facade installs its lookups instead; until it has, every
/// lookup throws the same "not initialized" error the facade would.
abstract final class ManagerLocator {
  static Future<void> Function()? _refreshStreams;

  /// Called by the facade when it is created.
  static void install({
    required DatumManager<R> Function<R extends DatumEntityInterface>() of,
    required DatumManager<DatumEntityInterface> Function(Type type) byType,
    required Future<void> Function() refreshStreams,
  }) {
    RelatedSources.install(of: of, byType: byType);
    _refreshStreams = refreshStreams;
  }

  /// The manager registered for entity type [R].
  static DatumManager<R> of<R extends DatumEntityInterface>() => RelatedSources.of<R>() as DatumManager<R>;

  /// The manager registered for [type].
  static DatumManager<DatumEntityInterface> byType(Type type) => RelatedSources.byType(type) as DatumManager<DatumEntityInterface>;

  /// Re-emits every manager's watch streams; a no-op without a facade.
  static Future<void> refreshStreams() => _refreshStreams?.call() ?? Future<void>.value();
}

/// The full manager behind a relation's target, for manager-layer code.
extension RelationManager on Relation<DatumEntityInterface> {
  DatumManager<DatumEntityInterface> get relatedManager => getRelatedManager() as DatumManager<DatumEntityInterface>;
}
