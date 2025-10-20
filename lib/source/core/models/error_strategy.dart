import 'dart:async';
import 'dart:math';
import 'package:datum/source/core/models/datum_exception.dart';

/// Abstract base class for retry backoff strategies.
abstract class DatumBackoffStrategy {
  /// Calculates the delay for a given retry attempt.
  /// Can return a [Duration] directly or a [Future<Duration>].
  FutureOr<Duration> getDelay(int attemptNumber);
}

/// Implements an exponential backoff retry strategy.
class ExponentialBackoff implements DatumBackoffStrategy {
  /// Creates an exponential backoff strategy.
  const ExponentialBackoff({
    this.baseDelay = const Duration(seconds: 1),
    this.multiplier = 2.0,
    this.maxDelay = const Duration(minutes: 5),
  });

  /// Initial delay before the first retry.
  final Duration baseDelay;

  /// The multiplier applied to each subsequent retry delay.
  final double multiplier;

  /// The maximum delay cap to prevent excessively long waits.
  final Duration maxDelay;

  @override
  Duration getDelay(int attemptNumber) {
    final delayMs = baseDelay.inMilliseconds * pow(multiplier, attemptNumber - 1);
    final delay = Duration(milliseconds: delayMs.round());
    return delay < maxDelay ? delay : maxDelay;
  }
}

/// Implements a linear backoff retry strategy where the delay increases by a fixed amount.
class LinearBackoff implements DatumBackoffStrategy {
  /// Creates a linear backoff strategy.
  const LinearBackoff({this.increment = const Duration(seconds: 5)});

  /// The time increment added for each retry attempt.
  final Duration increment;

  @override
  Duration getDelay(int attemptNumber) => increment * attemptNumber;
}

/// Implements a fixed backoff retry strategy where the delay is always the same.
class FixedBackoff implements DatumBackoffStrategy {
  /// Creates a fixed backoff strategy with a constant delay.
  const FixedBackoff({this.delay = const Duration(seconds: 5)});

  /// The fixed delay duration for every retry attempt.
  final Duration delay;

  @override
  Duration getDelay(int attemptNumber) {
    return delay;
  }
}

/// Implements a custom backoff strategy defined by a function.
/// Useful for testing or complex retry logic.
class CustomBackoff implements DatumBackoffStrategy {
  /// Creates a custom backoff strategy.
  const CustomBackoff(this.delayCalculator);

  /// A function that takes the attempt number and returns the delay duration.
  final FutureOr<Duration> Function(int attemptNumber) delayCalculator;

  @override
  FutureOr<Duration> getDelay(int attemptNumber) {
    return delayCalculator(attemptNumber);
  }
}

/// Defines a strategy for how the sync engine should behave on errors.
class DatumErrorRecoveryStrategy {
  /// Creates an error recovery strategy.
  const DatumErrorRecoveryStrategy({
    required this.shouldRetry,
    this.maxRetries = 3,
    this.backoffStrategy = const ExponentialBackoff(),
    this.onError,
  });

  /// The maximum number of times to retry a failed operation.
  final int maxRetries;

  /// The strategy for calculating the delay between retries.
  final DatumBackoffStrategy backoffStrategy;

  /// A function that determines if a given error should trigger a retry.
  ///
  /// It receives a [DatumException] and should return a `Future<bool>`
  /// indicating whether a retry should be attempted.
  final Future<bool> Function(DatumException error) shouldRetry;

  /// An optional callback invoked when an error occurs that will not be retried,
  /// or after all retries have been exhausted. This is useful for logging
  /// or triggering alerts for persistent failures.
  final Future<void> Function(DatumException error)? onError;
}
