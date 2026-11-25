import 'package:datum/datum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';

/// Provider that exposes sync status for all entities
final allEntitiesSyncStatusProvider = StreamProvider.autoDispose
    .family<Map<Type, DatumSyncStatusSnapshot>, String>(
  (ref, userId) {
    // Create streams for each entity manager
    final taskManager = Datum.manager<Task>();
    final paintStrokeManager = Datum.manager<PaintStroke>();
    final paintCanvasManager = Datum.manager<PaintCanvas>();

    // Combine all status streams reactively
    return Rx.combineLatest3(
      taskManager.statusStream,
      paintStrokeManager.statusStream,
      paintCanvasManager.statusStream,
      (DatumSyncStatusSnapshot taskStatus,
          DatumSyncStatusSnapshot paintStrokeStatus,
          DatumSyncStatusSnapshot paintCanvasStatus) {
        return <Type, DatumSyncStatusSnapshot>{
          Task: taskStatus,
          PaintStroke: paintStrokeStatus,
          PaintCanvas: paintCanvasStatus,
        };
      },
    );
  },
  name: "allEntitiesSyncStatusProvider",
);

/// Provider for individual entity sync status
final entitySyncStatusProvider = StreamProvider.autoDispose
    .family<DatumSyncStatusSnapshot, ({String userId, Type entityType})>(
  (ref, params) {
    final manager = Datum.managerByType(params.entityType);
    return manager.statusStream;
  },
  name: "entitySyncStatusProvider",
);

/// Provider for last sync time that automatically updates when sync operations complete
final lastSyncTimeProvider =
    StreamProvider.autoDispose.family<DateTime?, String>(
  (ref, userId) {
    // Watch for sync completion events and refresh the last sync time
    final eventsStream = Datum.instance.events.where(
        (event) => event is DatumSyncCompletedEvent && event.userId == userId);

    // Combine the events stream with a periodic refresh to ensure reactivity
    return Stream.fromFuture(Datum.instance.getLastSyncTime(userId))
        .asyncExpand((initialTime) {
      return eventsStream.asyncMap((_) async {
        return await Datum.instance.getLastSyncTime(userId);
      }).startWith(initialTime);
    });
  },
  name: "lastSyncTimeProvider",
);
