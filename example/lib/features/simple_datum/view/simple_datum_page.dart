import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/controller/simple_datum_provider.dart';
import 'package:example/features/simple_datum/view/sync_info_widget.dart';
import 'package:example/shared/helper/global_helper.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

final simpleDatumControllerProvider = Provider.autoDispose(
  (ref) => SimpleDatumController(ref),
  name: 'simpleDatumControllerProvider',
);

/// A provider that acts as an event channel to signal UI updates.
/// The UI will listen to this and show a snackbar when the value changes.
final syncResultEventProvider =
    StateProvider<DatumSyncResult<Task>?>((ref) => null);

class SimpleDatumController {
  SimpleDatumController(this.ref);

  final Ref ref;

  DatumManager<Task> get _taskManager => Datum.manager<Task>();

  void _notifySyncResult(DatumSyncResult<Task> result) {
    ref.read(syncResultEventProvider.notifier).state = result;
  }

  Future<void> createTask({
    required String title,
    String? description,
  }) async {
    final newTask = Task.create(title: title, description: description);
    final (_, syncResult) =
        await _taskManager.pushAndSync(item: newTask, userId: newTask.userId);
    _notifySyncResult(syncResult);
  }

  Future<DatumSyncResult<Task>> updateTask(Task task) async {
    final (_, syncResult) =
        await _taskManager.updateAndSync(item: task, userId: task.userId);
    return syncResult;
  }

  Future<void> deleteTask(Task task) async {
    final (_, syncResult) =
        await _taskManager.deleteAndSync(id: task.id, userId: task.userId);
    _notifySyncResult(syncResult);
  }
}

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
          child: _TaskForm(
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
            .read(simpleDatumControllerProvider)
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
          child: _TaskForm(
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
        final syncResult = await ref
            .read(simpleDatumControllerProvider)
            .updateTask(updatedTask);
        _handleSyncResult(syncResult, operation: 'Update');
      } catch (e) {
        showErrorSnack(child: Text('Error updating task: $e'));
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    try {
      await ref.read(simpleDatumControllerProvider).deleteTask(task);
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
                  child: _TaskList(
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

class _TaskForm extends StatefulWidget {
  const _TaskForm({
    this.task,
    required this.titleController,
    required this.descriptionController,
  });

  final Task? task;
  final TextEditingController titleController;
  final TextEditingController descriptionController;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  @override
  void initState() {
    super.initState();
    widget.titleController.text = widget.task?.title ?? '';
    widget.descriptionController.text = widget.task?.description ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadInput(
          controller: widget.titleController,
          placeholder: const Text('Task title...'),
        ),
        const SizedBox(height: 8),
        ShadInput(
          controller: widget.descriptionController,
          placeholder: const Text('Description (optional)'),
        ),
      ],
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({
    required this.tasksAsync,
    required this.onUpdate,
    required this.onDelete,
  });

  final AsyncValue<List<Task>> tasksAsync;
  final void Function(Task) onUpdate;
  final void Function(Task) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return tasksAsync.easyWhen(
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
            return _TaskListItem(
              task: task,
              onUpdate: onUpdate,
              onDelete: onDelete,
            );
          },
        );
      },
      loadingWidget: () => const Center(child: Text("Watching tasks...")),
    );
  }
}

class _TaskListItem extends ConsumerWidget {
  const _TaskListItem({
    required this.task,
    required this.onUpdate,
    required this.onDelete,
  });

  final Task task;
  final void Function(Task) onUpdate;
  final void Function(Task) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CheckboxListTile(
      title: Text(
        task.title,
        style: task.isCompleted
            ? const TextStyle(
                decoration: TextDecoration.lineThrough, color: Colors.grey)
            : null,
      ),
      subtitle: Text(
        task.description ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      value: task.isCompleted,
      onChanged: (isCompleted) async {
        final updatedTask =
            task.copyWith(isCompleted: isCompleted, modifiedAt: DateTime.now());
        try {
          final syncResult = await ref
              .read(simpleDatumControllerProvider)
              .updateTask(updatedTask); // This now returns a sync result
          (context as Element)
              .findAncestorStateOfType<_SimpleDatumPageState>()
              ?._handleSyncResult(syncResult, operation: 'Update');
        } catch (e) {
          // Errors are now caught at the page level.
          // We can show a generic snackbar here if needed, but the controller
          // should ideally handle its own errors and signal the UI.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating task: $e')),
          );
        }
      },
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => onUpdate(task),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => onDelete(task),
          ),
        ],
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
