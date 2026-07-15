// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:datum/datum.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

/// Provider that exposes cold start sync status for all entities
final allEntitiesColdStartStatusProvider = StreamProvider.autoDispose
    .family<Map<Type, ColdStartStatus>, String>((ref, userId) {
  // Create a periodic stream that emits every 2 seconds with current cold start status
  // Cold start status changes infrequently, so polling is acceptable here
  return Stream.periodic(const Duration(seconds: 2), (_) {
    return <Type, ColdStartStatus>{
      Task: ColdStartStatus(
        isColdStart:
            Datum.manager<Task>().coldStartManager.isColdStartForUser(userId),
        lastColdStartTime: Datum.manager<Task>()
            .coldStartManager
            .getLastColdStartTimeForUser(userId),
        strategy: Datum.manager<Task>().config.coldStartConfig.strategy,
      ),
      PaintStroke: ColdStartStatus(
        isColdStart: Datum.manager<PaintStroke>()
            .coldStartManager
            .isColdStartForUser(userId),
        lastColdStartTime: Datum.manager<PaintStroke>()
            .coldStartManager
            .getLastColdStartTimeForUser(userId),
        strategy: Datum.manager<PaintStroke>().config.coldStartConfig.strategy,
      ),
      PaintCanvas: ColdStartStatus(
        isColdStart: Datum.manager<PaintCanvas>()
            .coldStartManager
            .isColdStartForUser(userId),
        lastColdStartTime: Datum.manager<PaintCanvas>()
            .coldStartManager
            .getLastColdStartTimeForUser(userId),
        strategy: Datum.manager<PaintCanvas>().config.coldStartConfig.strategy,
      ),
    };
  }).startWith(<Type, ColdStartStatus>{
    Task: ColdStartStatus(
      isColdStart:
          Datum.manager<Task>().coldStartManager.isColdStartForUser(userId),
      lastColdStartTime: Datum.manager<Task>()
          .coldStartManager
          .getLastColdStartTimeForUser(userId),
      strategy: Datum.manager<Task>().config.coldStartConfig.strategy,
    ),
    PaintStroke: ColdStartStatus(
      isColdStart: Datum.manager<PaintStroke>()
          .coldStartManager
          .isColdStartForUser(userId),
      lastColdStartTime: Datum.manager<PaintStroke>()
          .coldStartManager
          .getLastColdStartTimeForUser(userId),
      strategy: Datum.manager<PaintStroke>().config.coldStartConfig.strategy,
    ),
    PaintCanvas: ColdStartStatus(
      isColdStart: Datum.manager<PaintCanvas>()
          .coldStartManager
          .isColdStartForUser(userId),
      lastColdStartTime: Datum.manager<PaintCanvas>()
          .coldStartManager
          .getLastColdStartTimeForUser(userId),
      strategy: Datum.manager<PaintCanvas>().config.coldStartConfig.strategy,
    ),
  });
});

/// Provider that exposes cold start sync status for the Task entity (kept for backward compatibility)
final coldStartStatusProvider =
    StreamProvider.autoDispose.family<ColdStartStatus, String>((ref, userId) {
  final taskManager = Datum.manager<Task>();

  return Stream.value(ColdStartStatus(
    isColdStart: taskManager.coldStartManager.isColdStartForUser(userId),
    lastColdStartTime:
        taskManager.coldStartManager.getLastColdStartTimeForUser(userId),
    strategy: taskManager.config.coldStartConfig.strategy,
  ));
});

/// Simple data class to represent cold start status
class ColdStartStatus {
  final bool isColdStart;
  final DateTime? lastColdStartTime;
  final ColdStartStrategy strategy;

  const ColdStartStatus({
    required this.isColdStart,
    required this.lastColdStartTime,
    required this.strategy,
  });

  static const unknown = ColdStartStatus(
    isColdStart: false,
    lastColdStartTime: null,
    strategy: ColdStartStrategy.disabled,
  );

  String get statusText {
    if (isColdStart) {
      return 'Cold Start Active (${strategy.name})';
    } else {
      return 'Cold Start Completed (${strategy.name})';
    }
  }

  String get lastSyncText {
    if (lastColdStartTime == null) {
      return 'Never synced';
    }
    final duration = DateTime.now().difference(lastColdStartTime!);
    if (duration.inMinutes < 1) {
      return 'Just now';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes}m ago';
    } else if (duration.inDays < 1) {
      return '${duration.inHours}h ago';
    } else {
      return '${duration.inDays}d ago';
    }
  }

  @override
  bool operator ==(covariant ColdStartStatus other) {
    if (identical(this, other)) return true;

    return other.isColdStart == isColdStart &&
        other.lastColdStartTime == lastColdStartTime &&
        other.strategy == strategy;
  }

  @override
  int get hashCode =>
      isColdStart.hashCode ^ lastColdStartTime.hashCode ^ strategy.hashCode;
}
