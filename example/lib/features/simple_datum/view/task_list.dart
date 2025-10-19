import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/view/task_list_item.dart';

import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaskList extends ConsumerWidget {
  const TaskList({
    super.key,
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
            return TaskListItem(
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
