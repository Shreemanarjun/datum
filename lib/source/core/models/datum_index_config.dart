import 'package:datum/source/core/models/datum_entity.dart';

/// Configuration for database indexes on syncable entities.
abstract class DatumIndexConfig<T extends DatumEntity> {
  /// List of fields that should be indexed.
  List<String> get indexedFields;

  /// List of composite indexes (multi-field indexes).
  List<List<String>> get compositeIndexes => const [];
}
