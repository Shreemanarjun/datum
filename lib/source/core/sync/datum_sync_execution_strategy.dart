import 'dart:async';

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';

import '_isolate_runner_io.dart' if (dart.library.html) '_isolate_runner_web.dart';

/// A flag to determine if the code is running in a test environment.
const bool isTest = bool.fromEnvironment('dart.vm.product') == false && bool.fromEnvironment('flutter.test') == true;

/// Defines the execution strategy for processing the sync queue.
abstract class DatumSyncExecutionStrategy {
  /// A strategy that processes pending operations one by one.
  const factory DatumSyncExecutionStrategy.sequential() = SequentialStrategy;

  /// A strategy that processes pending operations in parallel batches.
  const factory DatumSyncExecutionStrategy.parallel({int batchSize}) = ParallelStrategy;

  /// A strategy that runs the sync process in a background isolate to avoid
  /// blocking the UI thread.
  ///
  /// It wraps another [DatumSyncExecutionStrategy] (e.g., `sequential` or `parallel`)
  /// which will be executed within the isolate.
  const factory DatumSyncExecutionStrategy.isolate(
    DatumSyncExecutionStrategy strategy, {
    // Add the optional parameter to the factory constructor as well.
    bool forceIsolateInTest,
  }) = IsolateStrategy.new;

  /// Executes the push operations according to the strategy.
  ///
  /// - [operations]: The list of operations to process.
  /// - [processOperation]: A function that processes a single operation.
  /// - [isCancelled]: A function to check if the sync has been cancelled.
  /// - [onProgress]: A callback to report progress.
  Future<void> execute<T extends DatumEntityBase>(
    List<DatumSyncOperation<T>> operations,
    Future<void> Function(DatumSyncOperation<T> operation) processOperation,
    bool Function() isCancelled,
    void Function(int completed, int total) onProgress,
  );
}

/// Processes pending operations one by one.
/// This is safer and less resource-intensive.
class SequentialStrategy implements DatumSyncExecutionStrategy {
  /// Creates a strategy that processes operations sequentially.
  const SequentialStrategy();

  @override
  Future<void> execute<T extends DatumEntityBase>(
    List<DatumSyncOperation<T>> operations,
    Future<void> Function(DatumSyncOperation<T> operation) processOperation,
    bool Function() isCancelled,
    void Function(int completed, int total) onProgress,
  ) async {
    var completedOps = 0;
    // Iterate over a copy to prevent concurrent modification errors.
    for (final operation in operations.toList()) {
      if (isCancelled()) break;
      await processOperation(operation);
      completedOps++;
      onProgress(completedOps, operations.length);
    }
  }
}

/// A strategy that executes another [DatumSyncExecutionStrategy] in a background
/// isolate. This is ideal for long-running syncs to prevent UI jank.
class IsolateStrategy implements DatumSyncExecutionStrategy {
  /// Creates a strategy that wraps another strategy to run it in a background
  /// isolate.
  ///
  /// For example: `IsolateStrategy(SequentialStrategy())` will run the
  /// sequential sync process in a background isolate.
  const IsolateStrategy(
    this.wrappedStrategy, {
    this.forceIsolateInTest = false,
  });

  /// The underlying strategy (e.g., sequential or parallel) to be executed
  /// in the background isolate.
  final DatumSyncExecutionStrategy wrappedStrategy;

  /// When running in a test environment (`isTest` is true), this flag can be
  /// set to `true` to force the creation of a real isolate. This is useful
  /// for integration tests that need to verify the isolate communication logic.
  /// Defaults to `false`.
  final bool forceIsolateInTest;

  @override
  Future<void> execute<T extends DatumEntityBase>(
    List<DatumSyncOperation<T>> operations,
    Future<void> Function(DatumSyncOperation<T> operation) processOperation,
    bool Function() isCancelled,
    void Function(int completed, int total) onProgress,
  ) {
    // The `compute` function is a simpler way to run a function in an isolate.
    // However, it's designed for one-off computations and doesn't support
    // the two-way communication needed to report progress or handle cancellation
    // mid-flight. The current Isolate.spawn implementation is more suitable
    // for this complex, stateful synchronization task.
    //
    // For testing purposes, we can simulate the behavior without a real isolate
    // to speed up tests and avoid isolate-related complexities.
    if (isTest && !forceIsolateInTest) {
      return wrappedStrategy.execute<T>(
        operations,
        processOperation,
        isCancelled,
        onProgress,
      );
    } else {
      // Use the platform-specific runner.
      return spawnIsolate<T>(
        operations,
        processOperation,
        isCancelled,
        onProgress,
        wrappedStrategy,
      );
    }
  }
}

/// Processes pending operations in parallel batches.
class ParallelStrategy implements DatumSyncExecutionStrategy {
  /// Creates a strategy that processes operations in parallel.
  ///
  /// [batchSize] determines how many operations are processed concurrently.
  /// [failFast] if true, stops processing remaining operations when the first error occurs.
  const ParallelStrategy({this.batchSize = 10, this.failFast = true});

  /// The number of operations to process concurrently in a single batch.
  final int batchSize;

  /// Whether to stop processing when the first error occurs.
  final bool failFast;

  @override
  Future<void> execute<T extends DatumEntityBase>(
    List<DatumSyncOperation<T>> operations,
    Future<void> Function(DatumSyncOperation<T> operation) processOperation,
    bool Function() isCancelled,
    void Function(int completed, int total) onProgress,
  ) async {
    final totalOps = operations.length;
    final errors = <Object>[];

    for (var i = 0; i < totalOps; i += batchSize) {
      if (isCancelled()) break;

      // If we already have errors and failFast is enabled, stop processing
      if (failFast && errors.isNotEmpty) break;

      final end = (i + batchSize < totalOps) ? i + batchSize : totalOps;
      final batch = operations.sublist(i, end);

      if (failFast) {
        // Use Future.wait with eagerError for fail-fast behavior
        try {
          await Future.wait(
            batch.map((op) => processOperation(op)),
            eagerError: failFast,
          );
          // Report progress only on successful batch completion
          onProgress(i + batch.length, totalOps);
        } catch (e) {
          // When failing fast, we rethrow immediately. Progress for this batch is not reported.
          rethrow;
        }
      } else {
        // Original behavior: collect all errors
        final results = await Future.wait(
          batch.map((op) async {
            try {
              await processOperation(op);
              return null; // Success
            } catch (e) {
              return e; // Failure
            }
          }),
        );

        errors.addAll(results.whereType<Object>());
        // Report progress even if there were errors in the batch, as failFast is false.
        onProgress(i + batch.length, totalOps);
      }
    }

    // After all batches are processed, if we collected any errors (in non-failFast mode),
    // throw the first one to signal that the overall sync failed.
    if (errors.isNotEmpty) {
      throw errors.first;
    }
  }
}
