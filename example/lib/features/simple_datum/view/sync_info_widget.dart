import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/controller/last_sync_result_notifier.dart';
import 'package:example/features/simple_datum/controller/metrics_provider.dart';
import 'package:example/features/simple_datum/view/health_status_widget.dart';

import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncInfoWidget extends ConsumerWidget {
  const SyncInfoWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const SizedBox.shrink();

    final healthAsync = ref.watch(allHealths);
    final pendingOpsAsync = ref.watch(pendingOperationsProvider(userId));
    final nextSyncTimeAsync = ref.watch(nextSyncTimeProvider);
    final storageSizeStream = ref.watch(storageSizeProvider(userId));
    final lastSyncResult = ref.watch(lastSyncResultProvider);

    return ShadCard(
      title: const Text('Sync Status'),
      description: const Text('Real-time synchronization details.'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Health'),
                healthAsync.easyWhen(
                  data: (healthMap) {
                    final health = healthMap[Task];
                    return Tooltip(
                      message:
                          'Local: ${health?.localAdapterStatus.name ?? '??'} | Remote: ${health?.remoteAdapterStatus.name ?? '??'}',
                      child: Row(
                        children: [const HealthStatusWidget()],
                      ),
                    );
                  },
                  loadingWidget: () => const Text('Checking...'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pending Syncs'),
                pendingOpsAsync.easyWhen(
                  data: (count) => Text(count.toString()),
                  loadingWidget: () => const Text('...'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Local Data Size'),
                storageSizeStream.easyWhen(
                  data: (size) =>
                      Text('${(size / 1024).toStringAsFixed(1)} KB'),
                  loadingWidget: () => const Text('...'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Next Auto-Sync'),
                nextSyncTimeAsync.easyWhen(
                  data: (time) => Text(time != null
                      ? '${time.hour}:${time.minute.toString().padLeft(2, '0')}'
                      : 'Not scheduled'),
                  loadingWidget: () => const Text('...'),
                ),
              ],
            ),
            if (lastSyncResult != null && !lastSyncResult.wasSkipped) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Last Sync'),
                  Text(
                    '${lastSyncResult.syncedCount}/${lastSyncResult.totalOperations} items',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Data Transferred'),
                  Text(
                    '↑${(lastSyncResult.bytesPushedInCycle / 1024).toStringAsFixed(2)} KB ↓${(lastSyncResult.bytesPulledInCycle / 1024).toStringAsFixed(2)} KB',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Data'),
                  Text(
                      '↑${(lastSyncResult.totalBytesPushed / 1024).toStringAsFixed(2)} KB ↓${(lastSyncResult.totalBytesPulled / 1024).toStringAsFixed(2)} KB'),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}
