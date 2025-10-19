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
    return taskRepository.watchAll(userId: userId) ?? const Stream.empty();
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

  Future<void> _createTask(Datum datum) async {
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
      await datum.create(newTask);
      await datum.synchronize(newTask.userId);
    }
  }

  Future<void> _updateTask(Datum datum, Task task) async {
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
      await datum.update(updatedTask);
      await datum.synchronize(updatedTask.userId);
    }
  }

  Future<void> _deleteTask(Datum datum, Task task) async {
    await datum.delete<Task>(
      id: task.id,
      userId: task.userId,
    );
    await datum.synchronize(task.userId);
  }

  @override
  Widget build(BuildContext context) {
    final simpleDatumAsync = ref.watch(simpleDatumProvider);
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Datum'),
        actions: [
          Builder(builder: (context) {
            return simpleDatumAsync.easyWhen(
              data: (datum) {
                final syncStatusAsync = ref.watch(syncStatusProvider(userId!));
                return syncStatusAsync.easyWhen(
                  data: (status) {
                    if (status?.status == DatumSyncStatus.syncing) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }
                    return Builder(builder: (mcontext) {
                      return Tooltip(
                          message: 'Manually sync with remote',
                          child: IconButton(
                            icon: const Icon(Icons.sync),
                            onPressed: () async {
                              showInfoSnack(child: Text('Syncing...'));
                              await datum.synchronize(userId);
                            },
                          ));
                    });
                  },
                );
              },
            );
          })
        ],
      ),
      floatingActionButton: simpleDatumAsync.maybeWhen(
        data: (datum) => FloatingActionButton(
          onPressed: () => _createTask(datum),
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
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      HealthStatusWidget(),
                      MetricsStatusWidget(),
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
                              await data.update(updatedTask);
                              // Immediately synchronize the change.
                              await data.synchronize(updatedTask.userId);
                            },
                            secondary: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _updateTask(data, task),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _deleteTask(data, task),
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
}

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
          // Assuming we want to show the health of the Task manager.
          final userHealth = healthMap[Task];
          if (userHealth == null) return const SizedBox.shrink();

          // A manager is considered healthy if it's operating normally or has pending
          // changes waiting for the next sync.
          final isHealthy = userHealth.status == DatumSyncHealth.healthy ||
              userHealth.status == DatumSyncHealth.pending;

          return Icon(
            isHealthy ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: isHealthy ? Colors.green : Colors.red,
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
