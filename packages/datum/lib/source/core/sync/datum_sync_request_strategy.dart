import 'dart:async';

/// Defines the strategy for handling concurrent calls to the `synchronize` method.
abstract class DatumSyncRequestStrategy {
  /// Executes the given [action] according to the strategy's rules.
  ///
  /// - [action]: The synchronization logic to be executed.
  /// - [isSyncInProgress]: A function that returns true if a sync is currently running.
  /// - [onSkipped]: A callback that is invoked if the strategy decides to skip the action.
  Future<T> execute<T>(
    Future<T> Function() action, {
    required bool Function() isSyncInProgress,
    required T Function() onSkipped,
  });

  /// Disposes of any resources held by the strategy.
  void dispose() {}
}

/// A strategy that skips new sync requests if one is already in progress.
/// This prevents re-entrant sync calls.
class SkipConcurrentStrategy implements DatumSyncRequestStrategy {
  const SkipConcurrentStrategy();

  @override
  Future<T> execute<T>(
    Future<T> Function() action, {
    required bool Function() isSyncInProgress,
    required T Function() onSkipped,
  }) {
    if (isSyncInProgress()) {
      return Future.value(onSkipped());
    }
    return action();
  }

  @override
  void dispose() {}
}

/// A strategy that queues new sync requests if one is already in progress.
///
/// This ensures that all requested syncs are executed sequentially, one after
/// the other, preventing lost updates from rapid, concurrent calls. This is
/// the recommended default for most applications to ensure data consistency.
class SequentialRequestStrategy implements DatumSyncRequestStrategy {
  /// The number of times to retry a failed synchronization action before the
  /// last error is surfaced to the caller (total attempts = `retryCount + 1`).
  ///
  /// Defaults to **0** (no whole-sync retry): the engine already retries
  /// individual operations via `DatumErrorRecoveryStrategy`, so retrying the
  /// entire cycle here multiplies remote work. (The previous implementation
  /// declared a default of 3 but never actually retried — the default now
  /// reflects the real shipped behavior; set it explicitly to opt in.)
  final int retryCount;

  /// Creates a sequential strategy with an optional [retryCount].
  const SequentialRequestStrategy({this.retryCount = 0});

  @override
  Future<T> execute<T>(
    Future<T> Function() action, {
    required bool Function() isSyncInProgress,
    required T Function() onSkipped,
  }) {
    // Sequentiality is implemented as a promise chain: each call schedules its
    // work after the previous tail. This replaces the earlier `async_queue`
    // based implementation, which had two production bugs:
    //  1. It assumed `queue.retry()` throws once retries are exhausted; it
    //     doesn't — it marks the job failed and returns — so the completer was
    //     never completed and `synchronize()` hung forever after a persistent
    //     failure.
    //  2. Its shared queue (const instances are canonicalized, so every
    //     default-config manager shares one) could be stopped/wedged, dropping
    //     other managers' queued syncs.
    final completer = Completer<T>();
    final previousTail = _tails[this] ?? Future<void>.value();

    final newTail = previousTail.then((_) async {
      var attempt = 0;
      while (true) {
        try {
          completer.complete(await action());
          return;
        } catch (e, s) {
          if (attempt >= retryCount) {
            // Always complete — the caller must never hang.
            completer.completeError(e, s);
            return;
          }
          attempt++;
        }
      }
    });

    _tails[this] = newTail;
    return completer.future;
  }

  @override
  void dispose() {
    // Detach: reset this instance's chain tail. Crucially this DROPS NOTHING —
    // already-scheduled jobs are chained futures that run to completion
    // regardless of this reference — so other managers sharing the same
    // canonicalized const instance never lose queued syncs (the old
    // async_queue implementation stopped the shared queue here, permanently
    // hanging their futures). Detaching also lets a fresh chain start even if
    // a previous action never completes (e.g. a hung remote call).
    _tails[this] = null;
  }
}

/// Per-strategy promise-chain tails, held weakly so a chain's lifetime is tied
/// to its strategy instance.
final Expando<Future<void>> _tails = Expando<Future<void>>('SequentialRequestStrategy tails');
