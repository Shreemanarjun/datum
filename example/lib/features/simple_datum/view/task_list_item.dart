import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/view/simple_datum_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaskListItem extends ConsumerWidget {
  const TaskListItem({
    super.key,
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
          await ref
              .read(simpleDatumControllerProvider.notifier)
              .updateTask(updatedTask);
        } catch (e) {
          if (!context.mounted) {
            return;
          }
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
