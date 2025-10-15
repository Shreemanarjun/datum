import 'dart:async';

import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/resolver/merge_resolver.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';

/// A resolver that delegates the conflict decision to the user via a prompt.
class UserPromptResolver<T extends DatumEntity>
    implements DatumConflictResolver<T> {
  /// Function that prompts the user to choose a resolution strategy.
  final Future<DatumResolutionStrategy> Function(
    DatumConflictContext context,
    T? local,
    T? remote,
  )
  onPrompt;

  /// An optional function that defines how to merge a local and remote entity
  /// if the user chooses the `merge` strategy.
  final DatumMergeFunction<T>? onMerge;

  /// Creates a user prompt resolver with a custom prompt function.
  UserPromptResolver({required this.onPrompt, this.onMerge});

  @override
  String get name => 'UserPrompt';

  @override
  Future<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  }) async {
    final choice = await onPrompt(context, local, remote);

    switch (choice) {
      case DatumResolutionStrategy.takeLocal:
        if (local == null) {
          return DatumConflictResolution.abort(
            'Local data unavailable for chosen strategy.',
          );
        }
        return DatumConflictResolution.useLocal(local);
      case DatumResolutionStrategy.takeRemote:
        if (remote == null) {
          return DatumConflictResolution.abort(
            'Remote data unavailable for chosen strategy.',
          );
        }
        return DatumConflictResolution.useRemote(remote);
      case DatumResolutionStrategy.merge:
        if (onMerge == null) {
          return DatumConflictResolution.abort(
            'Merge strategy chosen, but no `onMerge` function was provided.',
          );
        }
        if (local == null || remote == null) {
          return DatumConflictResolution.abort(
            'Merge requires both local and remote data to be available.',
          );
        }
        final merged = await onMerge!(local, remote, context);
        if (merged == null) {
          return DatumConflictResolution.abort(
            'User cancelled merge operation.',
          );
        }
        return DatumConflictResolution.merge(merged);
      case DatumResolutionStrategy.askUser:
        // This case indicates the UI wants to handle it, but the resolver needs a concrete action.
        return DatumConflictResolution.requireUserInput(
          'Additional user input required.',
        );
      case DatumResolutionStrategy.abort:
        return DatumConflictResolution.abort('User cancelled resolution.');
    }
  }
}
