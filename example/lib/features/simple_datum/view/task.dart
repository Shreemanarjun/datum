import 'package:example/data/task/entity/task.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TaskForm extends StatefulWidget {
  const TaskForm({
    super.key,
    this.task,
    required this.titleController,
    required this.descriptionController,
  });

  final Task? task;
  final TextEditingController titleController;
  final TextEditingController descriptionController;

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
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
