import 'package:datum/source/core/models/data_source.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query.dart';

/// What a relation needs to load its target: the read side of a manager.
///
/// Implemented by `DatumManager`. It is declared in the model layer so that
/// entity models (and the relation objects they hold) never import the
/// manager layer.
abstract interface class RelatedSource<T extends DatumEntityInterface> {
  Future<T?> read(String id, {String? userId});

  Future<List<T>> query(DatumQuery query, {DataSource source, String? userId});
}

/// Finds the [RelatedSource] for an entity type. The layer that owns the
/// managers installs the lookups; until then every lookup throws.
abstract final class RelatedSources {
  static RelatedSource<R> Function<R extends DatumEntityInterface>()? _of;
  static RelatedSource<DatumEntityInterface> Function(Type type)? _byType;

  static void install({
    required RelatedSource<R> Function<R extends DatumEntityInterface>() of,
    required RelatedSource<DatumEntityInterface> Function(Type type) byType,
  }) {
    _of = of;
    _byType = byType;
  }

  static Never _notInstalled() => throw StateError('Datum has not been initialized. Call Datum.initialize() first.');

  /// The source for entity type [R].
  static RelatedSource<R> of<R extends DatumEntityInterface>() => (_of ?? _notInstalled())<R>();

  /// The source for [type].
  static RelatedSource<DatumEntityInterface> byType(Type type) => (_byType ?? _notInstalled())(type);
}
