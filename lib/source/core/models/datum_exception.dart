import 'package:datum/source/core/models/datum_entity.dart';

/// Base exception for all Datum related errors.
abstract class DatumException implements Exception {
  /// A descriptive message for the exception.
  String get message;
}

/// Exception thrown for network-related issues.
class NetworkException extends DatumException {
  /// Creates a [NetworkException].
  NetworkException(this.message, {this.isRetryable = true});

  @override
  final String message;

  /// Whether the operation that caused this exception can be retried.
  /// Defaults to true for most network errors.
  final bool isRetryable;

  @override
  String toString() => 'NetworkException: $message (retryable: $isRetryable)';
}

/// Exception thrown when a schema migration fails.
class MigrationException extends DatumException {
  /// Creates a [MigrationException].
  MigrationException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MigrationException: $message';
}

/// Exception thrown when a user switch operation is rejected by a strategy.
class UserSwitchException<T extends DatumEntity> extends DatumException {
  /// Creates a [UserSwitchException].
  UserSwitchException(this.oldUserId, this.newUserId, this.message);

  /// The user ID being switched from.
  final String? oldUserId;

  /// The user ID being switched to.
  final String newUserId;

  @override
  final String message;

  @override
  String toString() => 'UserSwitchException: $message (from: $oldUserId, to: $newUserId)';
}

/// Exception thrown by adapters during their operations.
class AdapterException extends DatumException {
  /// Creates an [AdapterException].
  AdapterException(this.adapterName, this.message, [this.stackTrace]);

  /// The name of the adapter that threw the exception.
  final String adapterName;

  @override
  final String message;

  /// The stack trace associated with the error, if available.
  final StackTrace? stackTrace;

  @override
  String toString() => 'AdapterException in $adapterName: $message${stackTrace == null ? '' : '\n$stackTrace'}';
}

/// Exception thrown when an entity is not found, typically during an
/// update or delete operation on a remote data source.
class EntityNotFoundException extends DatumException {
  /// Creates an [EntityNotFoundException].
  EntityNotFoundException(this.message);

  @override
  final String message;

  @override
  String toString() => 'EntityNotFoundException: $message';
}
