import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/shared/widget/parked_ops_banner.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

typedef _Timing = ({Duration took, int uploaded, int downloadedBytes});

/// Live strip of how long the last sync cycle of each entity type took, what
/// it uploaded and how much it downloaded — shown on every screen so slow
/// cycles are visible while using the app.
class SyncTimingStrip extends StatefulWidget {
  const SyncTimingStrip({super.key});

  @override
  State<SyncTimingStrip> createState() => _SyncTimingStripState();
}

class _SyncTimingStripState extends State<SyncTimingStrip> {
  final _last = <Type, _Timing>{};
  late final List<StreamSubscription<void>> _subscriptions;

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      for (final type in syncedEntityTypes)
        Datum.managerByType(type).onSyncCompleted.listen((event) {
          final result = event.result;
          if (!mounted || result.wasSkipped) return;
          setState(() => _last[type] = (
                took: result.duration,
                uploaded: result.syncedCount,
                downloadedBytes: result.bytesPulledInCycle,
              ));
        }),
    ];
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          _last.isEmpty
              ? 'No sync has run yet in this session'
              : [
                  for (final MapEntry(key: type, value: t) in _last.entries)
                    '$type ${t.took.inMilliseconds} ms'
                        '${t.uploaded > 0 ? ' ↑${t.uploaded}' : ''}'
                        '${t.downloadedBytes > 0 ? ' ↓${t.downloadedBytes} B' : ''}',
                ].join('  ·  '),
          style: style,
          semanticsLabel: 'Last sync timings',
        ),
      ),
    );
  }
}
