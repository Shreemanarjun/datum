import 'dart:async';
import 'dart:isolate';

import 'package:datum/datum.dart';
import 'package:equatable/equatable.dart';

/// Spawns an isolate to run the sync process. This is for non-web platforms.
Future<void> spawnIsolate<T extends DatumEntityInterface>(
  List<DatumSyncOperation<T>> operations,
  Future<void> Function(DatumSyncOperation<T> operation) processOperation,
  bool Function() isCancelled,
  void Function(int completed, int total) onProgress,
  DatumSyncExecutionStrategy wrappedStrategy,
  DatumLogger logger,
) {
  final completer = Completer<void>();
  final mainReceivePort = ReceivePort();

  // Optimization: Instead of sending full entity objects (which might contain
  // non-sendable fields like closures or complex generic types), we send
  // their map representations. This ensures safe cross-isolate communication.
  final rawOperations = operations.map((op) => op.toMap()).toList();

  final isolateInitMessage = _IsolateInitMessage(
    mainToIsolateSendPort: mainReceivePort.sendPort,
    rawOperations: rawOperations,
    wrappedStrategy: wrappedStrategy,
    // Ensure we only send a sendable worker logger, not the main isolate logger
    // which might contain a non-sendable ReceivePort.
    workerLogger: logger.getWorkerLogger(),
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
    required this.rawOperations,
    required this.wrappedStrategy,
    required this.workerLogger,
  });

  final SendPort mainToIsolateSendPort;
  final List<Map<String, dynamic>> rawOperations;
  final DatumSyncExecutionStrategy wrappedStrategy;
  final DatumLogger workerLogger;
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

/// A minimal entity used within the worker isolate to represent the data payload
/// without requiring the full specific entity class or its dependencies.
class _ProxyEntity extends Equatable implements DatumEntityInterface {
  final Map<String, dynamic> _data;

  const _ProxyEntity(this._data);

  @override
  String get id => _data['id'] as String? ?? '';
  @override
  String get userId => _data['userId'] as String? ?? '';
  @override
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(0);
  @override
  DateTime get modifiedAt => DateTime.fromMillisecondsSinceEpoch(0);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  @override
  VectorClock? get vectorClock => null;
  @override
  bool get isRelational => false;

  @override
  Set<String> get deviceOnlyFields => const {};
  Map<String, Relation> get relations => {};

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      _data;

  DatumEntityInterface copyWith(
          {DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;

  @override
  DatumEntityInterface incrementClock(String replicaId) => this;

  @override
  DatumEntityInterface merge(DatumEntityInterface other) => this;

  @override
  List<Object?> get props => [_data];

  @override
  bool get stringify => true;
}

/// The entry point for the background isolate.
void _isolateEntryPoint(_IsolateInitMessage initMessage) {
  final mainSendPort = initMessage.mainToIsolateSendPort;
  final workerLogger = initMessage.workerLogger;

  // Reconstruct operation objects from the raw maps. We use a ProxyEntity
  // to avoid needing the specific T types in the worker isolate.
  final operations = initMessage.rawOperations.map((m) {
    return DatumSyncOperation<DatumEntityInterface>(
      id: m['id'] as String,
      userId: m['userId'] as String,
      entityId: m['entityId'] as String,
      type: DatumOperationType.values.byName(m['type'] as String),
      timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
      data: m['data'] == null
          ? null
          : _ProxyEntity(Map<String, dynamic>.from(m['data'] as Map)),
      delta: m['delta'] == null
          ? null
          : Map<String, dynamic>.from(m['delta'] as Map),
      retryCount: m['retryCount'] as int? ?? 0,
      sizeInBytes: m['sizeInBytes'] as int? ?? 0,
    );
  }).toList();

  workerLogger.info(
      'Starting isolate sync execution with ${operations.length} operations');

  Future<void> requestProcessing(
      DatumSyncOperation<DatumEntityInterface> operation) async {
    final responsePort = ReceivePort();
    mainSendPort.send(
      _ProcessOperationRequest(operation.id, responsePort.sendPort),
    );
    final result = await responsePort.first;
    responsePort.close();

    if (result is _IsolateError) {
      workerLogger
          .warn('Operation ${operation.id} failed in isolate: ${result.error}');
      return Future.error(result.error, result.stackTrace);
    }
  }

  void reportProgress(int completed, int total) {
    if (completed % 10 == 0 || completed == total) {
      workerLogger
          .debug('Isolate progress: $completed/$total operations completed');
    }
    mainSendPort.send(_ProgressUpdate(completed, total));
  }

  bool isCancelled() => false;

  initMessage.wrappedStrategy
      .execute<DatumEntityInterface>(
    operations,
    requestProcessing,
    isCancelled,
    reportProgress,
  )
      .then((_) {
    workerLogger.info('Isolate sync execution completed successfully');
    mainSendPort.send(_SyncComplete());
  }).catchError(
    (Object e, StackTrace s) {
      workerLogger.error('Isolate sync execution failed: $e');
      mainSendPort.send(_SyncError(e, s));
    },
  );
}
