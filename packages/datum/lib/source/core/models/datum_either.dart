/// A sealed class representing a value that can be one of two types.
///
/// This is often used to represent a value that can be either a success or a failure.
/// By convention, `L` is the error type and `R` is the success type.
sealed class DatumEither<L, R> {
  const DatumEither();

  /// Returns `true` if this is a `Failure`.
  bool isFailure() => this is Failure<L, R>;

  /// Returns `true` if this is a `Success`.
  bool isSuccess() => this is Success<L, R>;

  /// Folds the `Either` into a single value.
  ///
  /// If this is a `Failure`, the `onFailure` function is called with the value.
  /// If this is a `Success`, the `onSuccess` function is called with the value.
  T fold<T>(T Function(L l, StackTrace? s) onFailure, T Function(R r) onSuccess);

  /// Performs an action on the success value.
  void onSuccess(void Function(R r) onSuccess) {
    switch (this) {
      case Success<L, R>(value: final r):
        onSuccess(r);
      case Failure<L, R>():
        break;
    }
  }

  /// Performs an action on the failure value.
  void onFailure(void Function(L l, StackTrace? s) onFailure) {
    switch (this) {
      case Success<L, R>():
        break;
      case Failure<L, R>(value: final l, stackTrace: final s):
        onFailure(l, s);
    }
  }

  /// Returns the failure value, or throws an exception if this is a `Success`.
  (L, StackTrace?) getError() {
    return switch (this) {
      Success<L, R>() => throw StateError('Cannot get error value from a Success.'),
      Failure<L, R>(value: final l, stackTrace: final s) => (l, s),
    };
  }

  R getSuccess() {
    return switch (this) {
      Success<L, R>(value: final r) => r,
      Failure<L, R>() => throw StateError('Cannot get success value from a Failure.'),
    };
  }

  /// Returns the success value, or `null` if this is a `Failure`.
  R? get successOrNull {
    return switch (this) {
      Success<L, R>(value: final r) => r,
      Failure<L, R>() => null,
    };
  }

  /// Returns the error value, or `null` if this is a `Success`.
  L? get errorOrNull {
    return switch (this) {
      Success<L, R>() => null,
      Failure<L, R>(value: final l) => l,
    };
  }

  /// The success value, or `null` if this is a `Failure`. Alias of
  /// [successOrNull] for a concise `result.success!` style.
  R? get success => successOrNull;

  /// The failure value, or `null` if this is a `Success`. Alias of
  /// [errorOrNull] for a concise `result.failure!` style.
  L? get failure => errorOrNull;
}

/// Represents the failure case of an `Either`.
class Failure<L, R> extends DatumEither<L, R> {
  const Failure(this.value, [this.stackTrace]);

  final L value;
  final StackTrace? stackTrace;

  @override
  T fold<T>(T Function(L l, StackTrace? s) onFailure, T Function(R r) onSuccess) => onFailure(value, stackTrace);
}

/// Represents the success case of an `Either`.
class Success<L, R> extends DatumEither<L, R> {
  const Success(this.value);

  final R value;

  @override
  T fold<T>(T Function(L l, StackTrace? s) onFailure, T Function(R r) onSuccess) => onSuccess(value);
}
