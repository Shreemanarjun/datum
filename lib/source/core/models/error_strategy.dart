import 'dart:async';
import 'dart:math';

import 'package:datum/source/core/models/datum_exception.dart';

/// Abstract base class for retry backoff strategies.
abstract class DatumBackoffStrategy {
  /// Calculates the delay for a given retry attempt.
  Duration getDelay(int attemptNumber);
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
    final delayMs =
        baseDelay.inMilliseconds * pow(multiplier, attemptNumber - 1);
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
  final bool Function(DatumException error) shouldRetry;

  /// An optional callback invoked when an error occurs.
  final Future<void> Function(DatumException error)? onError;
}
