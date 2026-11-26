import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/features/tasks/presentation/widgets/task_list_item.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

class TaskList extends StatelessWidget {
  const TaskList({
    super.key,
    required this.tasks,
    required this.pendingIds,
    required this.onToggle,
    required this.onUpdate,
    required this.onDelete,
  });

  final AsyncState<List<Task>> tasks;
  final AsyncState<Set<String>> pendingIds;
  final void Function(Task) onToggle;
  final void Function(Task) onUpdate;
  final void Function(Task) onDelete;

  @override
  Widget build(BuildContext context) {
    return tasks.map(
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.task_alt,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'No tasks yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a task to get started!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80), // Space for FAB
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return TaskListItem(
              key: ValueKey(task.id),
              task: task,
              pendingIds: pendingIds,
              onToggle: onToggle,
              onUpdate: onUpdate,
              onDelete: onDelete,
            );
          },
        );
      },
      error: (error, _) => Center(child: Text('Error: $error')),
      loading: () => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Loading tasks..."),
          ],
        ),
      ),
    );
  }
}
