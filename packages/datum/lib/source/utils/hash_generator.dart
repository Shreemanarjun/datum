import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/models/datum_entity.dart';

/// Utility for generating consistent hashes for data integrity checks.
class DatumHashGenerator {
  /// Creates a hash generator.
  const DatumHashGenerator();

  /// Generates a SHA-256 hash from a list of entities.
  ///
  /// The entities are sorted by ID before serialization to ensure a consistent
  /// order, resulting in a stable hash for the same set of data.
  ///
  /// This is O(n log n) (sort) plus a full serialization of the whole set on
  /// every call. For large datasets synced frequently, prefer
  /// [hashEntitiesUnordered] (no sort) or [DatumRollingHash] (O(1) incremental
  /// updates).
  String hashEntities<T extends DatumEntityInterface>(List<T> entities) {
    final sorted = List<T>.from(entities)..sort((a, b) => a.id.compareTo(b.id));
    final jsonList = sorted.map((e) => e.toDatumMap(target: MapTarget.remote)).toList();
    return _hashJson(jsonList);
  }

  /// An **order-independent** hash of a set of entities.
  ///
  /// Each entity is hashed individually and the digests are XOR-combined, so the
  /// result does not depend on iteration order — no sort is required. This is
  /// the basis for incremental maintenance via [DatumRollingHash]: to update the
  /// set hash after one write, XOR the changed entity's digest in/out instead of
  /// re-hashing everything.
  String hashEntitiesUnordered<T extends DatumEntityInterface>(List<T> entities) {
    final acc = Uint8List(32);
    for (final e in entities) {
      final d = datumEntityDigest(e.toDatumMap(target: MapTarget.remote));
      for (var i = 0; i < 32; i++) {
        acc[i] ^= d[i];
      }
    }
    return _hex(acc);
  }

  /// Generates a SHA-256 hash from any JSON-encodable object.
  String _hashJson(Object data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    return sha256.convert(bytes).toString();
  }
}

/// Computes the canonical 32-byte SHA-256 digest of a single serialized entity
/// [map]. Map keys are sorted recursively so the digest is independent of key
/// insertion order (local vs remote serialization).
Uint8List datumEntityDigest(Map<String, dynamic> map) {
  final canonical = jsonEncode(_canonicalize(map));
  return Uint8List.fromList(sha256.convert(utf8.encode(canonical)).bytes);
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonicalize(value[k])};
  }
  if (value is List) {
    return value.map(_canonicalize).toList();
  }
  return value;
}

String _hex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// An **incrementally maintainable** set hash for change/drift detection.
///
/// Maintains a 256-bit XOR accumulator of per-entity digests. Because XOR is its
/// own inverse, [add] and [remove] are O(1): the engine can keep this in sync as
/// entities are created/updated/deleted instead of re-hashing the whole dataset
/// each sync cycle (which [DatumHashGenerator.hashEntities] does in O(n)).
///
/// ```dart
/// final rolling = DatumRollingHash()..addAll(entities);
/// // on update: swap the old snapshot for the new one
/// rolling..removeMap(oldMap)..addMap(newMap);
/// final digest = rolling.value; // compare against the remote's value
/// ```
class DatumRollingHash {
  final Uint8List _acc = Uint8List(32);

  /// Whether no entities are currently folded in (accumulator is all-zero).
  bool get isEmpty => _acc.every((b) => b == 0);

  void _xor(Uint8List digest) {
    for (var i = 0; i < 32; i++) {
      _acc[i] ^= digest[i];
    }
  }

  /// Folds an entity into the accumulator.
  void add(DatumEntityInterface entity) => addMap(entity.toDatumMap(target: MapTarget.remote));

  /// Removes an entity from the accumulator (XOR is self-inverse).
  void remove(DatumEntityInterface entity) => removeMap(entity.toDatumMap(target: MapTarget.remote));

  /// Folds a pre-serialized entity map into the accumulator.
  void addMap(Map<String, dynamic> map) => _xor(datumEntityDigest(map));

  /// Removes a pre-serialized entity map from the accumulator.
  void removeMap(Map<String, dynamic> map) => _xor(datumEntityDigest(map));

  /// Folds all [entities] into the accumulator.
  void addAll(Iterable<DatumEntityInterface> entities) {
    for (final e in entities) {
      add(e);
    }
  }

  /// The current 64-character hex digest of the set.
  String get value => _hex(_acc);

  /// Resets the accumulator to empty.
  void reset() => _acc.fillRange(0, 32, 0);
}
