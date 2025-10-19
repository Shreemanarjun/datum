import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/controller/metrics_provider.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HealthStatusWidget extends ConsumerWidget {
  const HealthStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allHealthsAsync = ref.watch(allHealths);
    return allHealthsAsync.easyWhen(
        data: (healthMap) {
          final userHealth = healthMap[Task];
          if (userHealth == null) return const SizedBox.shrink();

          final isHealthy = userHealth.status == DatumSyncHealth.healthy ||
              userHealth.status == DatumSyncHealth.pending;
          final isSyncing = userHealth.status == DatumSyncHealth.syncing;

          return Tooltip(
            message: 'Sync status: ${userHealth.status.name}',
            child: Icon(
              isSyncing
                  ? Icons.cloud_sync_outlined
                  : (isHealthy
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined),
              color: isHealthy ? Colors.green : Colors.red,
            ),
          );
        },
        loadingWidget: () => const SizedBox.shrink());
  }
}
