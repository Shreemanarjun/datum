import 'dart:async';

import 'package:equatable/equatable.dart';
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
class DatumConflictResolution<T extends DatumEntity> extends Equatable {
  /// The strategy used to resolve the conflict.
  final DatumResolutionStrategy strategy;

  /// The resolved entity data.
  final T? resolvedData;

  /// Whether user input is required to proceed.
  final bool requiresUserInput;

  /// Optional message about the resolution.
  final String? message;

  /// Creates a conflict resolution result.
  const DatumConflictResolution._({
    required this.strategy,
    this.resolvedData,
    this.requiresUserInput = false,
    this.message,
  });

  /// Creates a resolution that uses the local version.
  const DatumConflictResolution.useLocal(T localData)
      : this._(
          strategy: DatumResolutionStrategy.takeLocal,
          resolvedData: localData,
        );

  /// Creates a resolution that uses the remote version.
  const DatumConflictResolution.useRemote(T remoteData)
      : this._(
          strategy: DatumResolutionStrategy.takeRemote,
          resolvedData: remoteData,
        );

  /// Creates a resolution with merged data.
  const DatumConflictResolution.merge(T mergedData)
      : this._(
            strategy: DatumResolutionStrategy.merge, resolvedData: mergedData);

  /// Creates a resolution requiring user input.
  const DatumConflictResolution.requireUserInput(String message)
      : this._(
          strategy: DatumResolutionStrategy.askUser,
          requiresUserInput: true,
          message: message,
        );

  /// Creates an aborted resolution.
  const DatumConflictResolution.abort(String reason)
      : this._(strategy: DatumResolutionStrategy.abort, message: reason);

  /// Creates a copy of the resolution with a different generic type.
  /// This is useful for upcasting to `DatumConflictResolution<DatumEntity>`.
  DatumConflictResolution<E> copyWithNewType<E extends DatumEntity>() {
    // This is safe because T extends DatumEntity, and E also extends DatumEntity.
    // The resolvedData is being upcast.
    return DatumConflictResolution<E>._(
      strategy: strategy,
      resolvedData: resolvedData as E?,
      requiresUserInput: requiresUserInput,
      message: message,
    );
  }

  /// Creates a copy of this resolution with updated fields.
  DatumConflictResolution<T> copyWith({
    DatumResolutionStrategy? strategy,
    T? resolvedData,
    bool? requiresUserInput,
    String? message,
    bool setResolvedDataToNull = false,
  }) {
    return DatumConflictResolution<T>._(
      strategy: strategy ?? this.strategy,
      // If setResolvedDataToNull is true, set it to null, otherwise use the
      // provided value or the existing one.
      resolvedData:
          setResolvedDataToNull ? null : (resolvedData ?? this.resolvedData),
      requiresUserInput: requiresUserInput ?? this.requiresUserInput,
      message: message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [
        strategy,
        resolvedData,
        requiresUserInput,
        message,
      ];
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
