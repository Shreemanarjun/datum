import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/controller/last_sync_result_notifier.dart';
import 'package:example/features/simple_datum/controller/simple_datum_provider.dart';
import 'package:example/features/simple_datum/view/task.dart';
import 'package:example/features/simple_datum/view/task_list.dart';
import 'package:example/features/simple_datum/view/sync_info_widget.dart';
import 'package:example/shared/helper/global_helper.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

final simpleDatumControllerProvider =
    NotifierProvider.autoDispose<SimpleDatumController, void>(
  SimpleDatumController.new,
  name: 'simpleDatumControllerProvider',
);

/// A provider that acts as an event channel to signal UI updates.
/// The UI will listen to this and show a snackbar when the value changes.
final syncResultEventProvider = StateProvider<DatumSyncResult<DatumEntity>?>(
  (
    ref,
  ) =>
      null,
  name: "syncResultEventProvider",
);

class SimpleDatumController extends AutoDisposeNotifier<void> {
  SimpleDatumController();

  void _notifySyncResult(DatumSyncResult<DatumEntity> result) {
    ref.read(syncResultEventProvider.notifier).state = result;
  }

  Future<void> createTask({
    required String title,
    String? description,
  }) async {
    final newTask = Task.create(title: title, description: description);
    final (_, syncResult) =
        await Datum.instance.pushAndSync(item: newTask, userId: newTask.userId);
    _notifySyncResult(syncResult);
  }

  Future<void> updateTask(Task task) async {
    final (_, syncResult) =
        await Datum.instance.updateAndSync(item: task, userId: task.userId);
    _notifySyncResult(syncResult);
  }

  Future<void> deleteTask(Task task) async {
    final (_, syncResult) = await Datum.instance
        .deleteAndSync<Task>(id: task.id, userId: task.userId);
    _notifySyncResult(syncResult);
  }

  @override
  void build() {
    return;
  }
}

final tasksStreamProvider =
    StreamProvider.autoDispose.family<List<Task>, String?>(
  (ref, userId) {
    // watchAll can return null if the adapter doesn't support it
    return Datum.manager<Task>()
            .watchAll(userId: userId, includeInitialData: true) ??
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
  name: 'syncStatusProvider',
);

@RoutePage()
class SimpleDatumPage extends ConsumerStatefulWidget {
  const SimpleDatumPage({super.key});

  @override
  ConsumerState<SimpleDatumPage> createState() => _SimpleDatumPageState();
}

class _SimpleDatumPageState extends ConsumerState<SimpleDatumPage>
    with GlobalHelper {
  // Controllers are now managed in the _TaskForm widget.
  Future<void> _createTask() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    final didCreate = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
          // Using a key to access form state from the outside is not ideal.
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
          child: TaskForm(
            titleController: titleController,
            descriptionController: descriptionController,
          )),
    );

    final title = titleController.text;
    final description = descriptionController.text;
    titleController.dispose();
    descriptionController.dispose();

    if (didCreate == true && titleController.text.isNotEmpty) {
      try {
        await ref
            .read(simpleDatumControllerProvider.notifier)
            .createTask(title: title, description: description);
        // The snackbar is now handled by the listener on syncResultEventProvider
      } catch (e) {
        showErrorSnack(child: Text('Error creating task: $e'));
      }
    }
  }

  Future<void> _updateTask(Task task) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

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
          child: TaskForm(
            task: task,
            titleController: titleController,
            descriptionController: descriptionController,
          )),
    );

    final title = titleController.text;
    final description = descriptionController.text;
    titleController.dispose();
    descriptionController.dispose();

    if (didUpdate == true && title.isNotEmpty) {
      final updatedTask = task.copyWith(
        description: description,
        title: title,
        modifiedAt: DateTime.now(),
      );
      try {
        await ref.read(simpleDatumControllerProvider.notifier).updateTask(
            updatedTask); // This is now a void method. The listener will handle the result.
      } catch (e) {
        showErrorSnack(child: Text('Error updating task: $e'));
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    try {
      await ref.read(simpleDatumControllerProvider.notifier).deleteTask(task);
      // The snackbar is now handled by the listener on syncResultEventProvider
    } catch (e) {
      showErrorSnack(child: Text('Error deleting task: $e'));
    }
  }

  @override
  void initState() {
    super.initState();
    // Listen to the event provider to show snackbars.
    ref.listenManual(syncResultEventProvider, (previous, next) {
      if (next != null) {
        _handleSyncResult(next);
      }
    });
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
                    final result = await Datum.instance.synchronize(
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
                                await Datum.instance.synchronize(userId);
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
                  child: TaskList(
                      tasksAsync: tasksAsync,
                      onUpdate: _updateTask,
                      onDelete: _deleteTask),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  void _handleSyncResult(DatumSyncResult<DatumEntityBase> result,
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
