import 'dart:async';
import 'dart:isolate';

import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/sync/datum_sync_execution_strategy.dart';

/// Spawns an isolate to run the sync process. This is for non-web platforms.
Future<void> spawnIsolate<T extends DatumEntityBase>(
  List<DatumSyncOperation<T>> operations,
  Future<void> Function(DatumSyncOperation<T> operation) processOperation,
  bool Function() isCancelled,
  void Function(int completed, int total) onProgress,
  DatumSyncExecutionStrategy wrappedStrategy,
) {
  final completer = Completer<void>();
  final mainReceivePort = ReceivePort();

  final isolateInitMessage = _IsolateInitMessage(
    mainToIsolateSendPort: mainReceivePort.sendPort,
    operations: operations.cast(),
    wrappedStrategy: wrappedStrategy,
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
            processOperation(operation).then((_) => message.responsePort.send(null)).catchError((Object e, StackTrace s) {
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
    required this.wrappedStrategy,
  });

  final SendPort mainToIsolateSendPort;
  final List<DatumSyncOperation> operations;
  final DatumSyncExecutionStrategy wrappedStrategy;
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
@pragma('vm:entry-point')
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

  initMessage.wrappedStrategy
      .execute<DatumEntityBase>(
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
