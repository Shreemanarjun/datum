import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:datum/datum.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:example/bootstrap.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final paintCanvasesStreamProvider =
    StreamProvider.autoDispose<List<PaintCanvas>>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  return Datum.manager<PaintCanvas>()
      .watchAll(userId: userId, includeInitialData: true)
      .map((canvases) => canvases.where((c) => !c.isDeleted).toList()
        ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt)));
});

class PaintCanvasList extends ConsumerWidget {
  final Function(String) onCanvasSelected;

  const PaintCanvasList({super.key, required this.onCanvasSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvasesAsync = ref.watch(paintCanvasesStreamProvider);
    final theme = ShadTheme.of(context);

    return canvasesAsync.when(
      data: (canvases) => _buildList(context, ref, canvases, theme),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref,
      List<PaintCanvas> canvases, ShadThemeData theme) {
    if (canvases.isEmpty) {
      return _buildEmptyState(context, ref, theme);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '${canvases.length} Painting${canvases.length == 1 ? '' : 's'}',
                style: theme.textTheme.h4,
              ),
              const Spacer(),
              ShadButton.outline(
                onPressed: () => _createNewCanvas(context, ref),
                leading: const Icon(LucideIcons.plus, size: 16),
                child: const Text('New Painting'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: canvases.length,
            itemBuilder: (context, index) {
              final canvas = canvases[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ShadCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.brush,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      canvas.title,
                      style: theme.textTheme.p
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${canvas.strokeCount} strokes • Modified ${canvas.modifiedAt.toString().split(' ')[0]}',
                      style: theme.textTheme.muted,
                    ),
                    trailing: _buildPopupMenu(context, ref, canvas, theme),
                    onTap: () => onCanvasSelected(canvas.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
      BuildContext context, WidgetRef ref, ShadThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.palette,
            size: 64,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(height: 16),
          Text(
            'No paintings yet',
            style: theme.textTheme.h3,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first painting to get started!',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 24),
          ShadButton(
            onPressed: () => _createNewCanvas(context, ref),
            leading: const Icon(LucideIcons.plus, size: 16),
            child: const Text('Create New Painting'),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupMenu(BuildContext context, WidgetRef ref,
      PaintCanvas canvas, ShadThemeData theme) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'delete') {
          _deleteCanvas(context, ref, canvas);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(LucideIcons.trash2, color: Colors.red, size: 16),
              SizedBox(width: 8),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createNewCanvas(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController(text: 'New Painting');
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Painting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter painting title',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Enter painting description',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true && titleController.text.isNotEmpty) {
      try {
        final canvas = PaintCanvas.create(
          title: titleController.text.trim(),
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
        );

        await Datum.manager<PaintCanvas>()
            .push(item: canvas, userId: canvas.userId);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created "${canvas.title}"'),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        onCanvasSelected(canvas.id);
      } catch (e) {
        talker.error('Failed to create canvas: $e');
      }
    }
  }

  Future<void> _deleteCanvas(
      BuildContext context, WidgetRef ref, PaintCanvas canvas) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Painting'),
        content: Text(
            'Are you sure you want to delete "${canvas.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final deletedCanvas = canvas.copyWith(isDeleted: true) as PaintCanvas;
        await Datum.manager<PaintCanvas>()
            .push(item: deletedCanvas, userId: deletedCanvas.userId);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${canvas.title}"'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        talker.error('Failed to delete canvas: $e');
      }
    }
  }
}
