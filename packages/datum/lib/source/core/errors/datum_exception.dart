// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:equatable/equatable.dart';

enum DatumExceptionCode {
  /// An unknown or unhandled error occurred.
  unknown,

  /// A network-related error occurred (e.g., no internet connection, timeout).
  networkError,

  /// A conflict was detected during synchronization that could not be resolved automatically.
  conflictDetected,

  /// The local and remote schema versions do not match, requiring a migration.
  schemaMismatch,

  /// An entity with the specified ID was not found.
  entityNotFound,

  /// An error occurred within a LocalAdapter or RemoteAdapter implementation.
  adapterError,

  /// An error occurred during serialization or deserialization of data.
  serializationError,

  /// Authentication failed (e.g., invalid credentials, token expired).
  authenticationError,

  /// Authorization failed (e.g., insufficient permissions to access a resource).
  authorizationError,

  /// A validation error occurred (e.g., invalid input data).
  validationError,

  /// An operation timed out.
  timeout,

  /// The operation was cancelled.
  cancelled,

  /// A precondition for an operation was not met.
  preconditionFailed,

  /// The server responded with an error.
  serverError,

  /// The client made a bad request.
  badRequest,

  /// The requested resource is unavailable.
  unavailable,

  /// Migration Failed
  migrationError,

  /// User switch failed
  userSwitchError,
}

/// Base exception class for all errors originating from the Datum library.
///
/// Provides a standardized way to categorize and handle errors.
class DatumException extends Equatable implements Exception {
  /// A unique code identifying the type of exception.
  final DatumExceptionCode code;

  /// A human-readable message describing the exception.
  final String message;

  /// Optional: A map containing additional details about the exception,
  /// useful for debugging or more specific error handling.
  final Map<String, dynamic>? details;

  /// Creates a [DatumException].
  const DatumException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  List<Object?> get props => [code, message, details];

  @override
  bool get stringify => true;

  @override
  String toString() {
    String detailString = '';
    if (details != null && details!.isNotEmpty) {
      detailString = ' Details: $details';
    }
    return 'DatumException(${code.name}): $message$detailString';
  }

  /// Creates a [DatumException] from an existing error or exception.
  ///
  /// This can be used to wrap third-party exceptions into a standardized DatumException.
  factory DatumException.fromError(
    Object error, {
    DatumExceptionCode code = DatumExceptionCode.unknown,
    String? message,
    StackTrace? stackTrace,
  }) {
    return DatumException(
      code: code,
      message: message ?? error.toString(),
      details: {
        'originalError': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      },
    );
  }
}

/// Exception thrown when a network-related error occurs.
class NetworkException extends DatumException {
  final bool isRetryable;
  const NetworkException({
    required super.message,
    super.details,
    this.isRetryable = true,
  }) : super(code: DatumExceptionCode.networkError);

  @override
  List<Object?> get props => [...super.props, isRetryable];
}

/// Exception thrown when a conflict is detected during synchronization.
class ConflictException extends DatumException {
  const ConflictException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.conflictDetected);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when an entity with the specified ID is not found.
class EntityNotFoundException extends DatumException {
  const EntityNotFoundException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.entityNotFound);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when an error occurs within an adapter implementation.
class AdapterException extends DatumException {
  final String error;
  final StackTrace? stackTrace;
  const AdapterException({
    required super.message,
    super.details = const {},
    required this.error,
    this.stackTrace,
  }) : super(code: DatumExceptionCode.adapterError);

  @override
  List<Object?> get props => [...super.props, error, stackTrace];

  @override
  String toString() => 'AdapterException(error: $error, stackTrace: $stackTrace)';
}

/// Exception thrown when an error occurs during data serialization or deserialization.
class SerializationException extends DatumException {
  const SerializationException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.serializationError);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when authentication fails.
class AuthenticationException extends DatumException {
  const AuthenticationException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.authenticationError);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when authorization fails.
class AuthorizationException extends DatumException {
  const AuthorizationException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.authorizationError);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when a validation error occurs.
class ValidationException extends DatumException {
  const ValidationException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.validationError);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when an operation times out.
class TimeoutException extends DatumException {
  const TimeoutException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.timeout);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when an operation is cancelled.
class CancellationException extends DatumException {
  const CancellationException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.cancelled);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when a precondition for an operation is not met.
class PreconditionFailedException extends DatumException {
  const PreconditionFailedException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.preconditionFailed);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when the server responds with an error.
class ServerException extends DatumException {
  const ServerException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.serverError);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when the client makes a bad request.
class BadRequestException extends DatumException {
  const BadRequestException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.badRequest);

  @override
  List<Object?> get props => [...super.props];
}

/// Exception thrown when the requested resource is unavailable.
class UnavailableException extends DatumException {
  const UnavailableException({
    required super.message,
    super.details,
  }) : super(code: DatumExceptionCode.unavailable);

  @override
  List<Object?> get props => [...super.props];
}

// Exception thrown when migration failed
class MigrationException extends DatumException {
  final Object? e;
  final StackTrace? stackTrace;
  MigrationException({
    this.e,
    super.code = DatumExceptionCode.migrationError,
    required super.message,
    this.stackTrace,
  }) : super(details: {
          if (e != null) 'e': e.toString(),
          if (stackTrace != null) 'stackTrace': stackTrace.toString(),
        });

  @override
  List<Object?> get props => [...super.props, e, stackTrace];
}

// Exception thrown when a typed schema read fails (wrong type / missing key).
class SchemaReadException extends DatumException {
  final String? entity;
  final String fieldName;
  final Type expectedType;
  final Object? actualValue;
  final Object? cause;

  SchemaReadException({
    this.entity,
    required this.fieldName,
    required this.expectedType,
    this.actualValue,
    this.cause,
  }) : super(
          code: DatumExceptionCode.schemaMismatch,
          message: 'Failed to read field "$fieldName"'
              '${entity != null ? ' of $entity' : ''}: expected $expectedType, '
              'got ${actualValue == null ? 'null' : '${actualValue.runtimeType} ($actualValue)'}'
              '${cause != null ? ' — $cause' : ''}',
          details: {
            'field': fieldName,
            'expectedType': expectedType.toString(),
            if (entity != null) 'entity': entity,
            if (actualValue != null) 'actualValue': actualValue.toString(),
            if (cause != null) 'cause': cause.toString(),
          },
        );

  @override
  List<Object?> get props => [...super.props, entity, fieldName, expectedType, actualValue];
}

// Exception thrown when user switch failed
class UserSwitchException extends DatumException {
  final String? oldUserId;
  final String newUserId;

  const UserSwitchException({
    super.code = DatumExceptionCode.userSwitchError,
    required super.message,
    required this.oldUserId,
    required this.newUserId,
  });

  @override
  List<Object?> get props => [...super.props, oldUserId, newUserId];

  @override
  String toString() => 'UserSwitchException(oldUserId: $oldUserId, newUserId: $newUserId,message: $message,code: $code)';
}

/// Exception thrown when original exception unknown
class UnknownException extends DatumException {
  final String? error;
  UnknownException({
    super.code = DatumExceptionCode.unknown,
    required super.message,
    this.error,
  }) : super(details: error != null ? {'error': error} : null);

  @override
  List<Object?> get props => [...super.props, error];
}
