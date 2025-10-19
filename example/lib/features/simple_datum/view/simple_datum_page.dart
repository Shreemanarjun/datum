import 'dart:math';

import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/controller/simple_datum_provider.dart';
import 'package:example/shared/helper/global_helper.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

final tasksStreamProvider =
    StreamProvider.autoDispose.family<List<Task>, String?>(
  (ref, userId) {
    final taskRepository = Datum.manager<Task>();
    // watchAll can return null if the adapter doesn't support it
    return taskRepository.watchAll(userId: userId, includeInitialData: true) ??
        const Stream.empty();
  },
  name: 'tasksStreamProvider',
);

final syncStatusProvider =
    StreamProvider.autoDispose.family<DatumSyncStatusSnapshot?, String>(
  (ref, userId) async* {
    final datum = await ref.watch(simpleDatumProvider.future);

    yield* datum.statusForUser(userId);
  },
);

final lastSyncResultProvider =
    NotifierProvider<LastSyncResultNotifier, DatumSyncResult<Task>?>(
  LastSyncResultNotifier.new,
);

class LastSyncResultNotifier extends Notifier<DatumSyncResult<Task>?> {
  @override
  DatumSyncResult<Task>? build() {
    // Load the initial value from storage.
    _load();
    return null; // Start with null, update when loaded.
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    state = await Datum.manager<Task>().getLastSyncResult(userId);
  }

  void update(DatumSyncResult<Task> result) {
    state = result;
    // The manager now automatically saves the result, so we don't need to do it here.
  }
}

@RoutePage()
class SimpleDatumPage extends ConsumerStatefulWidget {
  const SimpleDatumPage({super.key});

  @override
  ConsumerState<SimpleDatumPage> createState() => _SimpleDatumPageState();
}

class _SimpleDatumPageState extends ConsumerState<SimpleDatumPage>
    with GlobalHelper {
  final _random = Random();

  String _generateRandomId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      _random.nextInt(9999).toString();
  Future<void> _createTask() async {
    final titleController = TextEditingController();

    final didCreate = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
          title: const Text('Create Task'),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Create'),
            ),
          ],
          child: ShadInput(
            controller: titleController,
            placeholder: const Text('Task title...'),
          )),
    );

    if (didCreate == true && titleController.text.isNotEmpty) {
      final newTask = Task(
        id: _generateRandomId(),
        userId: Supabase.instance.client.auth.currentUser!.id,
        title: titleController.text,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );
      try {
        final (_, syncResult) = await Datum.manager<Task>().pushAndSync(
          item: newTask,
          userId: newTask.userId,
        );
        _handleSyncResult(syncResult, operation: 'Create');
      } catch (e) {
        showErrorSnack(child: Text('Error creating task: $e'));
      }
    }
  }

  Future<void> _updateTask(Task task) async {
    final titleController = TextEditingController(text: task.title);

    final didUpdate = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
          title: const Text('Update Task'),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Update'),
            ),
          ],
          child: ShadInput(
            controller: titleController,
            placeholder: const Text('Task title...'),
          )),
    );

    if (didUpdate == true && titleController.text.isNotEmpty) {
      final updatedTask = task.copyWith(
        title: titleController.text,
        modifiedAt: DateTime.now(),
      );
      try {
        final (_, syncResult) = await Datum.manager<Task>().updateAndSync(
          item: updatedTask,
          userId: updatedTask.userId,
        );
        _handleSyncResult(syncResult, operation: 'Update');
      } catch (e) {
        showErrorSnack(child: Text('Error updating task: $e'));
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    try {
      final (_, syncResult) = await Datum.manager<Task>().deleteAndSync(
        id: task.id,
        userId: task.userId,
      );
      _handleSyncResult(syncResult, operation: 'Delete');
    } catch (e) {
      showErrorSnack(child: Text('Error deleting task: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final simpleDatumAsync = ref.watch(simpleDatumProvider);
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Datum'),
        actions: [
          if (userId != null)
            Tooltip(
              message: 'Pull latest changes from remote',
              child: IconButton(
                icon: const Icon(Icons.cloud_download_outlined),
                onPressed: () async {
                  showInfoSnack(child: const Text('Refreshing...'));
                  try {
                    final result = await Datum.manager<Task>().synchronize(
                      userId,
                      options: const DatumSyncOptions(
                        direction: SyncDirection.pullOnly,
                      ),
                    );
                    _handleSyncResult(result, operation: 'Refresh');
                  } catch (e) {
                    showErrorSnack(child: Text('Refresh failed: $e'));
                  }
                },
              ),
            ),
          if (userId != null)
            ref.watch(syncStatusProvider(userId)).easyWhen(
                  data: (status) {
                    if (status?.status == DatumSyncStatus.syncing) {
                      return Padding(
                        padding: EdgeInsets.all(16.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: Tooltip(
                            message:
                                'Syncing... ${(status!.progress * 100).toStringAsFixed(0)}%',
                            child: CircularProgressIndicator(
                              value:
                                  status.progress > 0 ? status.progress : null,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      );
                    }
                    return Tooltip(
                      message: 'Push and pull changes with remote',
                      child: IconButton(
                        icon: const Icon(Icons.sync),
                        onPressed: () async {
                          ref.invalidate(syncStatusProvider(userId));
                          showInfoSnack(child: const Text('Syncing...'));
                          try {
                            final result =
                                await Datum.manager<Task>().synchronize(userId);
                            _handleSyncResult(result, operation: 'Sync');
                          } catch (e) {
                            showErrorSnack(child: Text('Sync failed: $e'));
                          }
                        },
                      ),
                    );
                  },
                  loadingWidget: () => const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
        ],
      ),
      floatingActionButton: simpleDatumAsync.maybeWhen(
        data: (_) => FloatingActionButton(
          onPressed: _createTask,
          child: const Icon(Icons.add),
        ),
        orElse: () => null,
      ),
      body: Builder(builder: (context) {
        return simpleDatumAsync.easyWhen(
          data: (data) {
            if (userId == null) {
              return const Center(child: Text("Not logged in"));
            }
            final tasksAsync = ref.watch(tasksStreamProvider(userId));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      const SyncInfoWidget(),
                    ],
                  ),
                ),
                Expanded(
                  child: tasksAsync.easyWhen(
                    data: (tasks) {
                      if (tasks.isEmpty) {
                        return const Center(
                          child: Text('No tasks found. Add one!'),
                        );
                      }
                      return ListView.builder(
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return CheckboxListTile(
                            title: Text(
                              task.title,
                              style: task.isCompleted
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: Colors.grey)
                                  : null,
                            ),
                            value: task.isCompleted,
                            onChanged: (isCompleted) async {
                              final updatedTask = task.copyWith(
                                  isCompleted: isCompleted,
                                  modifiedAt: DateTime.now());
                              try {
                                final (_, syncResult) =
                                    await Datum.manager<Task>().updateAndSync(
                                  item: updatedTask,
                                  userId: updatedTask.userId,
                                );
                                _handleSyncResult(syncResult,
                                    operation: 'Update');
                              } catch (e) {
                                showErrorSnack(
                                    child: Text('Error updating task: $e'));
                              }
                            },
                            secondary: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _updateTask(task),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _deleteTask(task),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    loadingWidget: () =>
                        const Center(child: Text("Watching tasks...")),
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  void _handleSyncResult(DatumSyncResult<Task> result,
      {String operation = 'Sync'}) {
    ref.read(lastSyncResultProvider.notifier).update(result);

    if (!mounted) return;

    if (result.wasSkipped) {
      showInfoSnack(child: Text('$operation skipped.'));
      return;
    }

    if (result.isSuccess) {
      final itemsSynced = result.syncedCount > 0
          ? '${result.syncedCount} item(s) pushed. '
          : 'No local changes to push. ';

      final bytesPushed = result.bytesPushedInCycle > 0
          ? '↑${(result.bytesPushedInCycle / 1024).toStringAsFixed(2)}KB'
          : '';

      final bytesPulled = result.bytesPulledInCycle > 0
          ? '↓${(result.bytesPulledInCycle / 1024).toStringAsFixed(2)}KB'
          : '';

      final dataTransferMessage =
          [bytesPushed, bytesPulled].where((s) => s.isNotEmpty).join(' ');

      final message = [
        '$operation complete. $itemsSynced',
        if (dataTransferMessage.isNotEmpty) dataTransferMessage
      ].join(' ').replaceAll(' .', '.'); // Clean up spacing

      showSuccessSnack(child: Text(message.trim()));
    } else {
      showErrorSnack(
          child: Text(
              '$operation failed. ${result.failedCount} item(s) failed to sync.'));
    }
  }
}

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

final nextSyncTimeProvider = StreamProvider.autoDispose<DateTime?>((ref) {
  // This provider does not depend on the user, so it can be a simple provider.
  final taskManager = Datum.manager<Task>();
  return taskManager.onNextSyncTimeChanged;
});

final storageSizeProvider =
    StreamProvider.autoDispose.family<int, String>((ref, userId) {
  final taskManager = Datum.manager<Task>();
  return taskManager.watchStorageSize(userId: userId);
});

final allHealths = StreamProvider(
  (ref) async* {
    final datum = await ref.watch(simpleDatumProvider.future);
    yield* datum.allHealths;
  },
  name: 'allHealths',
);

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

final metricsProvider = StreamProvider((ref) async* {
  final datum = await ref.watch(simpleDatumProvider.future);
  yield* datum.metrics;
});

final pendingOperationsProvider =
    StreamProvider.autoDispose.family<int, String>((ref, userId) async* {
  final datum = await ref.watch(simpleDatumProvider.future);
  yield* datum.statusForUser(userId).map((snapshot) {
    return snapshot?.pendingOperations ?? 0;
  });
});

class MetricsStatusWidget extends ConsumerWidget {
  const MetricsStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the new top-level provider for pending operations count.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const SizedBox.shrink();
    final pendingOpsAsync = ref.watch(pendingOperationsProvider(userId));

    return pendingOpsAsync.easyWhen(
      data: (count) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Badge(
          label: Text(count.toString()),
          isLabelVisible: count > 0,
          child: const Icon(Icons.pending_actions),
        ),
      ),
      loadingWidget: () => const SizedBox.shrink(),
      errorWidget: (e, st) => const SizedBox.shrink(),
    );
  }
}
