import 'package:collection/collection.dart';
import 'package:datum/datum.dart';
import 'package:rxdart/rxdart.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';

/// Sync status of every registered entity, combined.
Stream<Map<Type, DatumSyncStatusSnapshot>> allEntitiesSyncStatus() =>
    Rx.combineLatest3(
      Datum.manager<Task>().statusStream,
      Datum.manager<PaintStroke>().statusStream,
      Datum.manager<PaintCanvas>().statusStream,
      (DatumSyncStatusSnapshot task, DatumSyncStatusSnapshot stroke,
              DatumSyncStatusSnapshot canvas) =>
          {Task: task, PaintStroke: stroke, PaintCanvas: canvas},
    );

/// Ids of [userId]'s tasks with operations still queued for upload,
/// refreshed on every local write and sync event.
Stream<Set<String>> pendingTaskIds(String userId) {
  final manager = Datum.manager<Task>();
  return Rx.merge<Object?>([
    Stream.value(null),
    manager.eventStream,
    manager.watchAll(userId: userId, includeInitialData: false),
  ])
      .asyncMap((_) async => {
            for (final op in await manager.getPendingOperations(userId))
              op.entityId,
          })
      .distinct(const SetEquality<String>().equals);
}

/// Last sync time for [userId], refreshed after every completed sync.
Stream<DateTime?> lastSyncTime(String userId) async* {
  yield await Datum.instance.getLastSyncTime(userId);
  yield* Datum.instance.events
      .where((e) => e is DatumSyncCompletedEvent && e.userId == userId)
      .asyncMap((_) => Datum.instance.getLastSyncTime(userId));
}
