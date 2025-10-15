import 'dart:async';

import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';

/// Strategies used when resolving conflicts.
enum DatumResolutionStrategy {
  /// Choose the local version of the entity.
  takeLocal,

  /// Choose the remote version of the entity.
  takeRemote,

  /// Merge both versions together.
  merge,

  /// Defer the decision to the user.
  askUser,

  /// Abort the operation.
  abort,
}

/// Result of a conflict resolution attempt.
class DatumConflictResolution<T extends DatumEntity> {
  /// The strategy used to resolve the conflict.
  final DatumResolutionStrategy strategy;

  /// The resolved entity data.
  final T? resolvedData;

  /// Whether user input is required to proceed.
  final bool requiresUserInput;

  /// Optional message about the resolution.
  final String? message;

  /// Creates a conflict resolution result.
  const DatumConflictResolution({
    required this.strategy,
    this.resolvedData,
    this.requiresUserInput = false,
    this.message,
  });

  /// Creates a resolution that uses the local version.
  factory DatumConflictResolution.useLocal(T localData) =>
      DatumConflictResolution(
        strategy: DatumResolutionStrategy.takeLocal,
        resolvedData: localData,
      );

  /// Creates a resolution that uses the remote version.
  factory DatumConflictResolution.useRemote(T remoteData) =>
      DatumConflictResolution(
        strategy: DatumResolutionStrategy.takeRemote,
        resolvedData: remoteData,
      );

  /// Creates a resolution with merged data.
  factory DatumConflictResolution.merge(T mergedData) =>
      DatumConflictResolution(
        strategy: DatumResolutionStrategy.merge,
        resolvedData: mergedData,
      );

  /// Creates a resolution requiring user input.
  factory DatumConflictResolution.requireUserInput(String message) =>
      DatumConflictResolution(
        strategy: DatumResolutionStrategy.askUser,
        requiresUserInput: true,
        message: message,
      );

  /// Creates an aborted resolution.
  factory DatumConflictResolution.abort(String reason) =>
      DatumConflictResolution(
        strategy: DatumResolutionStrategy.abort,
        message: reason,
      );

  /// Creates a copy of the resolution with a different generic type.
  /// This is useful for upcasting to `DatumConflictResolution<DatumEntity>`.
  DatumConflictResolution<E> copyWithNewType<E extends DatumEntity>() {
    // This is safe because T extends DatumEntity, and E also extends DatumEntity.
    // The resolvedData is being upcast.
    return DatumConflictResolution<E>(
      strategy: strategy,
      resolvedData: resolvedData as E?,
      requiresUserInput: requiresUserInput,
      message: message,
    );
  }
}

/// Base interface for components that resolve synchronization conflicts.
abstract class DatumConflictResolver<T extends DatumEntity> {
  /// A descriptive name for the resolver strategy (e.g., "LastWriteWins").
  String get name;

  /// Resolves a conflict between a local and remote version of an entity.
  FutureOr<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  });
}
