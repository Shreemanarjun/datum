import 'dart:async';

import 'package:datum/datum.dart';
import 'package:equatable/equatable.dart';

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
class DatumConflictResolution<T extends DatumEntityInterface> extends Equatable {
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

  /// Creates a resolution with merged data. [message] can carry a warning
  /// about how the merge was produced (e.g. a degraded default merge).
  const DatumConflictResolution.merge(T mergedData, {String? message}) : this._(strategy: DatumResolutionStrategy.merge, resolvedData: mergedData, message: message);

  /// Creates a resolution requiring user input.
  const DatumConflictResolution.requireUserInput(String message)
      : this._(
          strategy: DatumResolutionStrategy.askUser,
          requiresUserInput: true,
          message: message,
        );

  /// Creates an aborted resolution.
  const DatumConflictResolution.abort(String reason) : this._(strategy: DatumResolutionStrategy.abort, message: reason);

  /// Creates a resolution that **accepts a remote deletion**, removing the local
  /// copy of the entity.
  ///
  /// Intended for a [DatumConflictType.deletionConflict] where the remote no
  /// longer has the entity (remote is null). It uses
  /// [DatumResolutionStrategy.takeRemote] with no resolved data, which the sync
  /// engine applies as a local delete.
  const DatumConflictResolution.deleteLocal([String? message]) : this._(strategy: DatumResolutionStrategy.takeRemote, message: message);

  /// Creates a copy of the resolution with a different generic type.
  /// This is useful for upcasting to `DatumConflictResolution<DatumEntity>`.
  DatumConflictResolution<E> copyWithNewType<E extends DatumEntityInterface>() {
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
      resolvedData: setResolvedDataToNull ? null : (resolvedData ?? this.resolvedData),
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
abstract class DatumConflictResolver<T extends DatumEntityInterface> {
  /// A descriptive name for the resolver strategy (e.g., "LastWriteWins").
  String get name;

  /// Resolves a conflict between a local and remote version of an entity.
  FutureOr<DatumConflictResolution<T>> resolve({
    T? local,
    T? remote,
    required DatumConflictContext context,
  });
}

/// Adapts a conflict resolver declared for a broader entity type [S] so it can
/// be used where a resolver for a more specific type [E] is required
/// (`E` must be a subtype of `S`).
///
/// Dart generics are invariant, so a `DatumConflictResolver<DatumEntityInterface>`
/// (e.g. a global default set on [DatumConfig]) is **not** directly a
/// `DatumConflictResolver<Person>`. Casting across that boundary throws at
/// runtime, and an `is` check silently fails — which previously caused the
/// global resolver to be dropped when deriving a per-entity config. This wrapper
/// bridges the two without losing the resolver: it forwards [E] values to the
/// base resolver and re-types the result via
/// [DatumConflictResolution.copyWithNewType].
class TypeAdaptedConflictResolver<E extends DatumEntityInterface, S extends DatumEntityInterface> implements DatumConflictResolver<E> {
  /// Wraps [base] (a resolver for the broader type [S]).
  TypeAdaptedConflictResolver(this.base);

  /// The underlying resolver for the broader entity type.
  final DatumConflictResolver<S> base;

  @override
  String get name => base.name;

  @override
  FutureOr<DatumConflictResolution<E>> resolve({
    E? local,
    E? remote,
    required DatumConflictContext context,
  }) async {
    // E is a subtype of S, so these upcasts are safe at runtime.
    final result = await base.resolve(
      local: local as S?,
      remote: remote as S?,
      context: context,
    );
    return result.copyWithNewType<E>();
  }
}
