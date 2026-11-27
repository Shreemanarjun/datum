import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/shared/widget/parked_ops_banner.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Live strip of the latest sync activity per entity type, newest first, on
/// every screen:
///
/// - `Task sync 82 ms ↑1 ↓240 B`: a sync cycle this device ran, how long it
///   took, what it uploaded and how much it downloaded;
/// - `Task live ↓1 · 6 ms to apply · 410 ms after the edit`: changes another
///   device made, received over realtime. No sync cycle runs for those, so
///   they are reported separately.
class SyncTimingStrip extends StatefulWidget {
  const SyncTimingStrip({super.key});

  @override
  State<SyncTimingStrip> createState() => _SyncTimingStripState();
}

class _SyncTimingStripState extends State<SyncTimingStrip> {
  /// Latest activity per type; insertion order is oldest first.
  final _latest = <Type, String>{};
  late final List<StreamSubscription<void>> _subscriptions;

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      for (final type in syncedEntityTypes) ...[
        Datum.managerByType(type).onSyncCompleted.listen((event) {
          if (!event.result.wasSkipped) _show(type, _sync(event.result));
        }),
        Datum.managerByType(type).onLiveChangesApplied.listen((event) => _show(
            type,
            [
              'live ↓${event.count}',
              '${event.duration.inMilliseconds} ms to apply',
              ..._sinceEdit(event),
            ].join(' · '))),
      ],
    ];
    for (final type in syncedEntityTypes) {
      unawaited(_showLastSync(type));
    }
  }

  /// A sync that finished before this widget existed (the one at app start
  /// often does) is shown too, unless something newer already is.
  Future<void> _showLastSync(Type type) async {
    final manager = Datum.managerByType(type);
    for (final userId in manager.autoSyncUserIds) {
      final last = await manager.getLastSyncResult(userId);
      final shown = _latest.containsKey(type);
      if (last != null && !last.wasSkipped && !shown) _show(type, _sync(last));
    }
  }

  static String _sync(DatumSyncResult result) => [
        'sync ${result.duration.inMilliseconds} ms',
        if (result.syncedCount > 0) '↑${result.syncedCount}',
        if (result.bytesPulledInCycle > 0) '↓${result.bytesPulledInCycle} B',
      ].join(' ');

  void _show(Type type, String activity) {
    if (!mounted) return;
    setState(() => _latest
      ..remove(type)
      ..[type] = activity);
  }

  /// How long the change took to get here. Device clocks differ, so a value
  /// that cannot be right (negative, or minutes) is left out.
  static List<String> _sinceEdit(LiveChangesAppliedEvent event) {
    final madeAt = event.lastChangedAt;
    if (madeAt == null) return const [];
    final delay = event.timestamp.difference(madeAt);
    final plausible = !delay.isNegative && delay < const Duration(minutes: 1);
    return [if (plausible) '${delay.inMilliseconds} ms after the edit'];
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final style = theme.textTheme.muted.copyWith(fontSize: 11);
    final activity = _latest.isEmpty
        ? 'No sync has run yet in this session'
        : [
            for (final MapEntry(key: type, value: activity)
                in _latest.entries.toList().reversed)
              '$type $activity',
          ].join('   |   ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          activity,
          style: style,
          semanticsLabel: 'Last sync timings: $activity',
        ),
      ),
    );
  }
}
