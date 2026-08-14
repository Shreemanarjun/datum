import 'dart:async';

import 'package:datum/datum.dart';

/// Strategies for handling errors within error boundaries.
enum ErrorBoundaryStrategy {
  /// Isolate the error - log it but don't rethrow, allowing fallback behavior
  isolate,

  /// Retry the operation after a delay
  retry,

  /// Use fallback value or operation
  fallback,

  /// Escalate the error to the caller
  escalate,
}

/// Configuration for error boundary behavior.
class ErrorBoundaryConfig {
  final ErrorBoundaryStrategy strategy;
  final Duration retryDelay;
  final int maxRetries;
  final Object? fallbackValue;
  final Future<Object?> Function()? fallbackOperation;

  const ErrorBoundaryConfig({
    this.strategy = ErrorBoundaryStrategy.isolate,
    this.retryDelay = const Duration(seconds: 1),
    this.maxRetries = 3,
    this.fallbackValue,
    this.fallbackOperation,
  });
}

/// An error boundary that isolates operations and provides configurable error recovery.
///
/// Error boundaries prevent cascading failures by containing errors within specific
/// operation scopes and providing fallback behaviors or recovery strategies.
class ErrorBoundary<T> {
  final ErrorBoundaryConfig config;
  final DatumLogger _logger;

  ErrorBoundary({
    ErrorBoundaryConfig? config,
    DatumLogger? logger,
  })  : config = config ?? const ErrorBoundaryConfig(),
        _logger = logger ?? DatumLogger();

  /// Executes an operation within the error boundary.
  ///
  /// Returns the result of the operation or handles errors according to the configured strategy.
  Future<T> execute(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (e, stack) {
      return await _handleError(e, stack, operation, 0);
    }
  }

  /// Executes a void operation within the error boundary.
  ///
  /// This is a convenience method for operations that don't return a value.
  Future<void> executeVoid(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e, stack) {
      // For void operations, we handle errors but don't return anything
      switch (config.strategy) {
        case ErrorBoundaryStrategy.isolate:
          _logger.error('Error isolated in boundary: $e', stack);
        case ErrorBoundaryStrategy.retry:
          if (0 < config.maxRetries) {
            _logger.warn('Retrying operation after error: $e (attempt 1/${config.maxRetries})');
            await Future.delayed(config.retryDelay);
            try {
              await operation();
            } catch (retryError, retryStack) {
              _logger.error('Retry failed: $retryError', retryStack);
            }
          } else {
            _logger.error('Max retries exceeded for error: $e', stack);
          }
        case ErrorBoundaryStrategy.fallback:
          _logger.warn('Using fallback for error: $e');
        case ErrorBoundaryStrategy.escalate:
          _logger.debug('Escalating error: $e');
          await Future.error(e, stack);
      }
    }
  }

  Future<T> _handleError(
    Object error,
    StackTrace stack,
    Future<T> Function() retryOperation,
    int retryCount,
  ) async {
    switch (config.strategy) {
      case ErrorBoundaryStrategy.isolate:
        _logger.error('Error isolated in boundary: $error', stack);
        return await _provideFallback();

      case ErrorBoundaryStrategy.retry:
        if (retryCount < config.maxRetries) {
          _logger.warn('Retrying operation after error: $error (attempt ${retryCount + 1}/${config.maxRetries})');
          await Future.delayed(config.retryDelay);
          try {
            return await retryOperation();
          } catch (retryError, retryStack) {
            return await _handleError(retryError, retryStack, retryOperation, retryCount + 1);
          }
        } else {
          _logger.error('Max retries exceeded for error: $error', stack);
          return await _provideFallback();
        }

      case ErrorBoundaryStrategy.fallback:
        _logger.warn('Using fallback for error: $error');
        return await _provideFallback();

      case ErrorBoundaryStrategy.escalate:
        _logger.debug('Escalating error: $error');
        // Re-throw the original error with its original stack.
        Error.throwWithStackTrace(error, stack);
    }
  }

  Future<T> _provideFallback() async {
    if (config.fallbackValue != null) {
      return config.fallbackValue as T;
    }

    if (config.fallbackOperation != null) {
      final result = await config.fallbackOperation!();
      return result as T;
    }

    throw StateError('No fallback provided for error boundary with ${config.strategy} strategy');
  }
}

/// Utility class for creating common error boundary configurations.
class ErrorBoundaries {
  /// Creates an error boundary that isolates sync operations.
  ///
  /// Sync operations are isolated to prevent one failed sync from affecting others.
  static ErrorBoundary<DatumSyncResult<T>> syncIsolation<T extends DatumEntityInterface>({
    DatumLogger? logger,
  }) {
    return ErrorBoundary<DatumSyncResult<T>>(
      config: const ErrorBoundaryConfig(
        strategy: ErrorBoundaryStrategy.isolate,
        fallbackValue: null, // Sync failures return null result
      ),
      logger: logger,
    );
  }

  /// Creates an error boundary that retries adapter operations.
  ///
  /// Adapter operations like read/write may benefit from retries on transient failures.
  static ErrorBoundary<T> adapterRetry<T>({
    int maxRetries = 2,
    Duration retryDelay = const Duration(milliseconds: 500),
    DatumLogger? logger,
  }) {
    return ErrorBoundary<T>(
      config: ErrorBoundaryConfig(
        strategy: ErrorBoundaryStrategy.retry,
        maxRetries: maxRetries,
        retryDelay: retryDelay,
      ),
      logger: logger,
    );
  }

  /// Creates an error boundary that provides fallbacks for read operations.
  ///
  /// Read operations can return empty results or cached data as fallbacks.
  static ErrorBoundary<T?> readWithFallback<T>({
    T? fallbackValue,
    Future<T?> Function()? fallbackOperation,
    DatumLogger? logger,
  }) {
    return ErrorBoundary<T?>(
      config: ErrorBoundaryConfig(
        strategy: ErrorBoundaryStrategy.fallback,
        fallbackValue: fallbackValue,
        fallbackOperation: fallbackOperation,
      ),
      logger: logger,
    );
  }

  /// Creates an error boundary that isolates observer notifications.
  ///
  /// Observer errors should not affect the main operation flow.
  static ErrorBoundary<void> observerIsolation({
    DatumLogger? logger,
  }) {
    return ErrorBoundary<void>(
      config: const ErrorBoundaryConfig(
        strategy: ErrorBoundaryStrategy.isolate,
      ),
      logger: logger,
    );
  }
}
