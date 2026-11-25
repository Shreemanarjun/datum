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

/// Last sync time for [userId], refreshed after every completed sync.
Stream<DateTime?> lastSyncTime(String userId) async* {
  yield await Datum.instance.getLastSyncTime(userId);
  yield* Datum.instance.events
      .where((e) => e is DatumSyncCompletedEvent && e.userId == userId)
      .asyncMap((_) => Datum.instance.getLastSyncTime(userId));
}
