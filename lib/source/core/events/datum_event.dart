import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:flutter/foundation.dart';

/// Base class for all synchronization-related events.
@immutable
abstract class DatumSyncEvent<T extends DatumEntity> {
  /// Creates a base sync event.
  DatumSyncEvent({required this.userId, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// The user ID associated with this event.
  final String userId;

  /// The time at which the event occurred.
  final DateTime timestamp;

  @override
  String toString() => 'DatumSyncEvent(userId: $userId, timestamp: $timestamp)';
}

/// Event fired when a synchronization cycle starts.
class DatumSyncStartedEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates a sync started event.
  DatumSyncStartedEvent({
    required super.userId,
    this.pendingOperations = 0,
    super.timestamp,
  });

  /// The number of pending operations to be synced.
  final int pendingOperations;

  @override
  String toString() =>
      '${super.toString()}: DatumSyncStartedEvent(pendingOperations: $pendingOperations)';
}

/// Event fired to report synchronization progress.
class DatumSyncProgressEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates a sync progress event.
  DatumSyncProgressEvent({
    required super.userId,
    required this.completed,
    required this.total,
    super.timestamp,
  });

  /// The number of operations completed so far.
  final int completed;

  /// The total number of operations in this sync cycle.
  final int total;

  /// The progress of the sync as a value between 0.0 and 1.0.
  double get progress => total > 0 ? completed / total : 0.0;

  @override
  String toString() =>
      '${super.toString()}: DatumSyncProgressEvent(completed: $completed, total: $total, progress: $progress)';
}

/// Event fired when a synchronization cycle completes.
class DatumSyncCompletedEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates a sync completed event.
  DatumSyncCompletedEvent({
    required super.userId,
    required this.result,
    super.timestamp,
  });

  /// The result of the completed synchronization cycle.
  final DatumSyncResult result;

  @override
  String toString() =>
      '${super.toString()}: DatumSyncCompletedEvent(result: $result)';
}

/// Event fired when an error occurs during synchronization.
class DatumSyncErrorEvent<T extends DatumEntity> extends DatumSyncEvent<T> {
  /// Creates a sync error event.
  DatumSyncErrorEvent({
    required super.userId,
    required this.error,
    this.stackTrace,
    super.timestamp,
  });

  /// The error object or message.
  final Object error;

  /// The stack trace associated with the error, if available.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      '${super.toString()}: DatumSyncErrorEvent(error: $error, stackTrace: $stackTrace)';
}
