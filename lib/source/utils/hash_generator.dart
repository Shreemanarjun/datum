import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Utility for generating consistent hashes for data integrity checks.
class DatumHashGenerator {
  /// Creates a hash generator.
  const DatumHashGenerator();

  /// Generates a SHA-256 hash from a list of entities.
  ///
  /// The entities are sorted by ID before serialization to ensure a consistent
  /// order, resulting in a stable hash for the same set of data.
  String hashEntities<T extends DatumEntity>(List<T> entities) {
    final sorted = List<T>.from(entities)..sort((a, b) => a.id.compareTo(b.id));
    final jsonList =
        sorted.map((e) => e.toDatumMap(target: MapTarget.remote)).toList();
    return _hashJson(jsonList);
  }

  /// Generates a SHA-256 hash from any JSON-encodable object.
  String _hashJson(Object data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    return sha256.convert(bytes).toString();
  }
}
