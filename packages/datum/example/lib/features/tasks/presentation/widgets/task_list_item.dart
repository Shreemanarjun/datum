import 'package:example/features/tasks/data/entities/task.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TaskListItem extends StatelessWidget {
  const TaskListItem({
    super.key,
    required this.task,
    required this.pendingIds,
    required this.onToggle,
    required this.onUpdate,
    required this.onDelete,
  });

  final Task task;
  final AsyncState<Set<String>> pendingIds;
  final void Function(Task) onToggle;
  final void Function(Task) onUpdate;
  final void Function(Task) onDelete;

  @override
  Widget build(BuildContext context) {
    // Theme colors, so titles stay readable in dark mode.
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ShadCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox
            Transform.scale(
              scale: 1.2,
              child: Checkbox(
                value: task.isCompleted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                activeColor: colors.primary,
                checkColor: colors.primaryForeground,
                onChanged: (isCompleted) {
                  if (isCompleted == null) return;
                  onToggle(task.copyWith(
                    isCompleted: isCompleted,
                    modifiedAt: DateTime.now(),
                  ));
                },
              ),
            ),
            const SizedBox(width: 8),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8), // Align with checkbox roughly
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      decoration:
                          task.isCompleted ? TextDecoration.lineThrough : null,
                      color: task.isCompleted
                          ? colors.mutedForeground
                          : colors.foreground,
                    ),
                  ),
                  if (task.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description!,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.mutedForeground,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Actions & Sync Status
            Column(
              children: [
                _buildSyncStatus(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShadButton.ghost(
                      width: 32,
                      height: 32,
                      padding: EdgeInsets.zero,
                      onPressed: () => onUpdate(task),
                      child: const Icon(Icons.edit, size: 16),
                    ),
                    ShadButton.ghost(
                      width: 32,
                      height: 32,
                      padding: EdgeInsets.zero,
                      hoverBackgroundColor: Colors.red.withValues(alpha: 0.1),
                      foregroundColor: Colors.red,
                      onPressed: () => onDelete(task),
                      child:
                          const Icon(Icons.delete, size: 16, color: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatus() {
    return pendingIds.map(
      data: (pendingIds) {
        if (!pendingIds.contains(task.id)) return const SizedBox.shrink();

        return Tooltip(
          message: 'Pending sync',
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Icon(
              Icons.cloud_upload_outlined,
              size: 14,
              color: Colors.orange.shade700,
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: () => const Icon(Icons.error_outline, size: 14, color: Colors.red),
    );
  }
}
