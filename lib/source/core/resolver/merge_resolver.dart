import 'dart:async';

import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

/// A function that defines how to merge a local and remote entity.
typedef DatumMergeFunction<T extends DatumEntity> = FutureOr<T?> Function(T local, T remote, DatumConflictContext context);

/// A resolver that uses a provided function to merge conflicting entities.
class MergeResolver<T extends DatumEntity> implements DatumConflictResolver<T> {
  /// The function that contains the custom logic for merging two entities.
  final DatumMergeFunction<T> onMerge;

  /// Creates a [MergeResolver] with a custom [onMerge] function.
  MergeResolver({required this.onMerge});

  @override
  String get name => 'Merge';

  @override
  Future<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  }) async {
    if (local == null && remote == null) {
      return DatumConflictResolution.abort(
        'No entities supplied to merge resolver.',
      );
    }

    if (local == null || remote == null) {
      return DatumConflictResolution.abort(
        'Merge requires both local and remote data to be available.',
      );
    }

    final merged = await onMerge(local, remote, context);

    if (merged == null) {
      return DatumConflictResolution.abort('User cancelled merge operation.');
    }

    return DatumConflictResolution.merge(merged);
  }
}
