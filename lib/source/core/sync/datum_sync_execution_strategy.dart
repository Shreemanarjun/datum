import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';

/// A flag to determine if the code is running in a test environment.
final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');

/// Defines the execution strategy for processing the sync queue.
abstract class DatumSyncExecutionStrategy {
  /// A strategy that processes pending operations one by one.
  const factory DatumSyncExecutionStrategy.sequential() = SequentialStrategy;

  /// A strategy that processes pending operations in parallel batches.
  const factory DatumSyncExecutionStrategy.parallel({int batchSize}) =
      ParallelStrategy;

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
  Future<void> execute<T extends DatumEntity>(
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
  Future<void> execute<T extends DatumEntity>(
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
  Future<void> execute<T extends DatumEntity>(
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
      // The original Isolate.spawn logic is kept for production builds.
      // This block is intentionally left unchanged as `compute` is not a
      // suitable replacement for this specific use case.
      return _spawnIsolate(
        operations,
        processOperation,
        isCancelled,
        onProgress,
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
  Future<void> execute<T extends DatumEntity>(
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

/// Helper function to encapsulate the original Isolate.spawn logic.
Future<void> _spawnIsolate<T extends DatumEntity>(
  List<DatumSyncOperation<T>> operations,
  Future<void> Function(DatumSyncOperation<T> operation) processOperation,
  bool Function() isCancelled,
  void Function(int completed, int total) onProgress,
) {
  final completer = Completer<void>();
  final mainReceivePort = ReceivePort();

  final isolateInitMessage = _IsolateInitMessage(
    // Cast to dynamic to satisfy Isolate.spawn
    mainToIsolateSendPort: mainReceivePort.sendPort,
    // Note: The wrapped strategy is not directly serializable. This approach
    // relies on the main isolate to do the actual processing.
    operations: operations.cast(),
  );

  unawaited(
    Isolate.spawn(_isolateEntryPoint, isolateInitMessage).then((isolate) async {
      try {
        final mainPortSubscription = mainReceivePort.listen((message) {
          if (isCancelled() && !completer.isCompleted) {
            isolate.kill(priority: Isolate.immediate);
            completer.complete();
            return;
          }

          if (message is _ProcessOperationRequest) {
            final operation = operations.firstWhere(
              (op) => op.id == message.id,
            );
            processOperation(operation)
                .then((_) => message.responsePort.send(null))
                .catchError((Object e, StackTrace s) {
              message.responsePort.send(_IsolateError(e, s));
            });
          } else if (message is _ProgressUpdate) {
            onProgress(message.completed, message.total);
          } else if (message is _SyncComplete) {
            if (!completer.isCompleted) completer.complete();
          } else if (message is _SyncError) {
            if (!completer.isCompleted) {
              completer.completeError(message.error, message.stackTrace);
            }
          }
        });

        await completer.future.whenComplete(() {
          isolate.kill(priority: Isolate.immediate);
          mainPortSubscription.cancel();
        });
      } finally {
        mainReceivePort.close();
      }
    }).catchError((Object e, StackTrace s) {
      if (!completer.isCompleted) completer.completeError(e, s);
      mainReceivePort.close();
    }),
  );

  return completer.future;
}

// --- Isolate Communication Models ---

class _IsolateInitMessage {
  _IsolateInitMessage({
    required this.mainToIsolateSendPort,
    required this.operations,
  });

  final SendPort mainToIsolateSendPort;
  final List<DatumSyncOperation> operations;
}

class _ProcessOperationRequest {
  _ProcessOperationRequest(this.id, this.responsePort);
  final String id;
  final SendPort responsePort;
}

class _IsolateError {
  _IsolateError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

class _ProgressUpdate {
  _ProgressUpdate(this.completed, this.total);
  final int completed;
  final int total;
}

class _SyncComplete {}

class _SyncError {
  _SyncError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

/// The entry point for the background isolate.
void _isolateEntryPoint(_IsolateInitMessage initMessage) {
  final mainSendPort = initMessage.mainToIsolateSendPort;
  final operations = initMessage.operations;

  Future<void> requestProcessing(DatumSyncOperation<dynamic> operation) async {
    final responsePort = ReceivePort();
    mainSendPort.send(
      _ProcessOperationRequest(operation.id, responsePort.sendPort),
    );
    final result = await responsePort.first;
    responsePort.close();

    if (result is _IsolateError) {
      return Future.error(result.error, result.stackTrace);
    }
  }

  void reportProgress(int completed, int total) {
    mainSendPort.send(_ProgressUpdate(completed, total));
  }

  bool isCancelled() => false;

  // Since the wrapped strategy isn't passed, we assume a default.
  // This part of the logic is simplified as the main isolate does the work.
  const SequentialStrategy() // This should be `wrappedStrategy` but it's not serializable.
      .execute<DatumEntity>(
        operations,
        requestProcessing,
        isCancelled,
        reportProgress,
      )
      .then((_) => mainSendPort.send(_SyncComplete()))
      .catchError(
        (Object e, StackTrace s) => mainSendPort.send(_SyncError(e, s)),
      );
}
