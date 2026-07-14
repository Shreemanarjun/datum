import 'package:equatable/equatable.dart';

import 'datum_exception.dart';

/// A **sealed, pattern-matchable error type** for Datum's result-returning
/// (`tryX`) API surface.
///
/// Where [DatumException] is the throwing taxonomy (with a wide
/// [DatumExceptionCode] enum), [DatumError] is a small, exhaustive set of cases
/// designed for `switch` handling at call sites:
///
/// ```dart
/// final result = await manager.tryRead(id, userId: userId);
/// final message = switch (result) {
///   Success(value: final task) => task == null ? 'Not stored' : task.title,
///   Failure(value: final error) => switch (error) {
///     NotFoundError() => 'Gone',
///     NetworkError(isRetryable: final r) => r ? 'Retry soon' : 'Offline',
///     ValidationError() => 'Bad input',
///     ConflictError() => 'Conflict',
///     StorageError() => 'Storage failure',
///     UnknownError() => 'Unexpected',
///   },
/// };
/// ```
///
/// Every case preserves the originating [cause] (often a [DatumException]) and
/// [stackTrace] so nothing is lost when mapping from the throwing API.
///
/// Implements [Exception] so a failed [DatumEither] error can be rethrown
/// directly (`throw result.failure!`).
sealed class DatumError extends Equatable implements Exception {
  const DatumError(this.message, {this.cause, this.stackTrace});

  /// A human-readable description of what went wrong.
  final String message;

  /// The original error/exception this was mapped from, if any.
  final Object? cause;

  /// The stack trace captured when the error was created, if available.
  final StackTrace? stackTrace;

  /// Maps an arbitrary thrown [error] into the closest [DatumError] case.
  ///
  /// [DatumException]s are routed by their [DatumExceptionCode]; everything else
  /// becomes an [UnknownError] that still carries the original [error].
  factory DatumError.from(Object error, [StackTrace? stackTrace]) {
    if (error is DatumError) return error;
    if (error is DatumException) {
      final msg = error.message;
      switch (error.code) {
        case DatumExceptionCode.entityNotFound:
          return NotFoundError(msg, cause: error, stackTrace: stackTrace);
        case DatumExceptionCode.conflictDetected:
          return ConflictError(msg, cause: error, stackTrace: stackTrace);
        case DatumExceptionCode.networkError:
        case DatumExceptionCode.timeout:
        case DatumExceptionCode.unavailable:
        case DatumExceptionCode.serverError:
          final retryable = error is NetworkException ? error.isRetryable : true;
          return NetworkError(
            msg,
            isRetryable: retryable,
            cause: error,
            stackTrace: stackTrace,
          );
        case DatumExceptionCode.validationError:
        case DatumExceptionCode.badRequest:
        case DatumExceptionCode.preconditionFailed:
          return ValidationError(msg, cause: error, stackTrace: stackTrace);
        case DatumExceptionCode.adapterError:
        case DatumExceptionCode.serializationError:
        case DatumExceptionCode.schemaMismatch:
        case DatumExceptionCode.migrationError:
          return StorageError(msg, cause: error, stackTrace: stackTrace);
        case DatumExceptionCode.authenticationError:
        case DatumExceptionCode.authorizationError:
        case DatumExceptionCode.cancelled:
        case DatumExceptionCode.userSwitchError:
        case DatumExceptionCode.unknown:
          return UnknownError(msg, cause: error, stackTrace: stackTrace);
      }
    }
    return UnknownError(error.toString(), cause: error, stackTrace: stackTrace);
  }

  @override
  List<Object?> get props => [runtimeType, message];

  @override
  bool get stringify => true;
}

/// The requested entity does not exist locally or remotely.
final class NotFoundError extends DatumError {
  const NotFoundError(super.message, {this.id, super.cause, super.stackTrace});

  /// The id that was not found, when known.
  final String? id;

  @override
  List<Object?> get props => [...super.props, id];
}

/// A synchronization conflict could not be resolved automatically.
final class ConflictError extends DatumError {
  const ConflictError(super.message, {super.cause, super.stackTrace});
}

/// A network/transport failure (no connection, timeout, server error).
final class NetworkError extends DatumError {
  const NetworkError(
    super.message, {
    this.isRetryable = true,
    super.cause,
    super.stackTrace,
  });

  /// Whether retrying the operation may succeed.
  final bool isRetryable;

  @override
  List<Object?> get props => [...super.props, isRetryable];
}

/// Input or precondition validation failed (bad request, invalid data).
final class ValidationError extends DatumError {
  const ValidationError(super.message, {super.cause, super.stackTrace});
}

/// A local/remote storage, serialization, schema, or migration failure.
final class StorageError extends DatumError {
  const StorageError(super.message, {super.cause, super.stackTrace});
}

/// An error that does not map to a more specific case.
final class UnknownError extends DatumError {
  const UnknownError(super.message, {super.cause, super.stackTrace});
}
