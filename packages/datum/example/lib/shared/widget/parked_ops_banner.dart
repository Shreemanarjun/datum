import 'package:collection/collection.dart';
import 'package:datum/datum.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/features/settings/user_settings.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Every entity type the app syncs.
const syncedEntityTypes = [Task, PaintStroke, PaintCanvas, UserSettings];

/// [userId]'s parked operations (writes the server rejected for good), across
/// every synced entity type, refreshed on each sync or data event.
Stream<List<DatumSyncOperation>> _parked(String userId) => Datum.instance.events
    .cast<Object?>()
    .startWith(null)
    .asyncMap((_) async => [
          for (final type in syncedEntityTypes)
            ...await Datum.managerByType(type).getParkedOperations(userId),
        ])
    .distinct(const ListEquality<DatumSyncOperation>().equals);

/// Tells the user that some changes could not sync and lets them retry.
/// A parked write also blocks later edits of the same item, so it must not
/// stay hidden.
class ParkedOpsBanner extends StatefulWidget {
  const ParkedOpsBanner({super.key, required this.userId});

  final String userId;

  @override
  State<ParkedOpsBanner> createState() => _ParkedOpsBannerState();
}

class _ParkedOpsBannerState extends State<ParkedOpsBanner> {
  late final _ops = streamSignal(() => _parked(widget.userId));

  @override
  void dispose() {
    _ops.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    for (final type in syncedEntityTypes) {
      await Datum.managerByType(type).retryParkedOperations(widget.userId);
    }
    // A still-rejected write simply parks again; the banner shows why.
    await Datum.instance
        .synchronize(widget.userId)
        .then<void>((_) {}, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) => SignalBuilder(builder: (context) {
        final ops = _ops.value.value ?? const [];
        if (ops.isEmpty) return const SizedBox.shrink();
        return ShadAlert.destructive(
          icon: const Icon(LucideIcons.cloudAlert),
          title: Text('${ops.length} change${ops.length == 1 ? '' : 's'} '
              "couldn't sync"),
          description: Row(
            children: [
              Expanded(
                child: Text(ops.first.parkedError ?? '',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              ShadButton.outline(onPressed: _retry, child: const Text('Retry')),
            ],
          ),
        );
      });
}
