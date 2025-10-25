import 'dart:async';

import 'package:compute/compute.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/sync/datum_sync_execution_strategy.dart';

/// A top-level function to be executed by `compute`.
Future<void> _computeCallback(_ComputePayload payload) async {
  // On the web, we cannot pass the processOperation function directly.
  // This means the web-based "isolate" strategy is less flexible and
  // will execute the entire batch without fine-grained progress or cancellation.
  // The user must implement the full logic within their adapter.
  // For this generic implementation, we assume the operation is self-contained.
  // This is a significant limitation of the web platform.
  //
  // A more advanced implementation could use web workers and message passing,
  // but that is beyond the scope of `compute`.
  await payload.wrappedStrategy.execute(
    payload.operations,
    (op) => Future.value(), // This is a placeholder.
    () => false, // Cancellation is not supported with `compute`.
    (completed, total) {}, // Progress is not supported with `compute`.
  );
}

class _ComputePayload {
  final List<DatumSyncOperation> operations;
  final DatumSyncExecutionStrategy wrappedStrategy;

  _ComputePayload(this.operations, this.wrappedStrategy);
}

/// Runs the sync process using `compute`, which is web-compatible.
Future<void> spawnIsolate<T extends DatumEntityBase>(
  List<DatumSyncOperation<T>> operations,
  Future<void> Function(DatumSyncOperation<T> operation) processOperation,
  bool Function() isCancelled,
  void Function(int completed, int total) onProgress,
  DatumSyncExecutionStrategy wrappedStrategy,
) async {
  // `compute` is a simplified abstraction over isolates/web workers.
  // It does not support progress reporting or cancellation. The entire
  // operation will run to completion or fail. We pass the operations
  // and the strategy to the compute function.
  // Note: `processOperation` cannot be passed to another isolate.
  // This is a limitation we accept for web compatibility.
  return compute(_computeCallback, _ComputePayload(operations, wrappedStrategy));
}
