import 'package:datum/source/core/models/relational_datum_entity.dart';
import 'package:equatable/equatable.dart';

/// The target for serialization, allowing different fields for local vs. remote.
enum MapTarget {
  /// For serialization to the local database.
  local,

  /// For serialization to the remote data source.
  remote,
}

/// Base sealed class for all Datum entities
sealed class DatumEntityBase extends Equatable {
  const DatumEntityBase();

  String get id;
  String get userId;
  DateTime get modifiedAt;
  DateTime get createdAt;
  int get version;
  bool get isDeleted;

  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local});
  DatumEntityBase copyWith({DateTime? modifiedAt, int? version, bool? isDeleted});
  Map<String, dynamic>? diff(covariant DatumEntityBase oldVersion);

  @override
  List<Object?> get props => [id, userId, modifiedAt, createdAt, version, isDeleted];
}

/// Base class for all entities managed by Datum.
///
/// This abstract class defines the essential properties and methods that
/// any data model must implement to be compatible with the Datum synchronization
/// engine. It promotes immutability through the `copyWith` method and provides
/// mechanisms for serialization and change detection. It extends [Equatable]
/// to provide value-based equality on the entity's [id].
/// Entity without relationships
abstract class DatumEntity extends DatumEntityBase {
  const DatumEntity();
}

/// Entity with relationships
abstract class RelationalDatumEntity extends DatumEntityBase {
  const RelationalDatumEntity();

  Map<String, Relation> get relations => {};
}
