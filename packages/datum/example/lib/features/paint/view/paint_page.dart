import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:example/features/paint/view/paint_canvas.dart';
import 'package:example/features/paint/view/paint_canvas_list.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

@RoutePage()
class PaintPage extends StatefulWidget {
  const PaintPage({super.key});

  @override
  State<PaintPage> createState() => _PaintPageState();
}

class _PaintPageState extends State<PaintPage> {
  String? _selectedCanvasId;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedCanvasId != null ? 'Edit Painting' : 'Paintings',
          style: theme.textTheme.h4,
        ),
        backgroundColor: theme.colorScheme.background,
        elevation: 0,
        centerTitle: false,
        leading: _selectedCanvasId != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedCanvasId = null),
              )
            : null,
        actions: _selectedCanvasId != null
            ? [
                ShadButton.ghost(
                  child: const Text('View All'),
                  onPressed: () => setState(() => _selectedCanvasId = null),
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: _selectedCanvasId != null
          ? PaintCanvas(canvasId: _selectedCanvasId!)
          : PaintCanvasList(
              onCanvasSelected: (canvasId) =>
                  setState(() => _selectedCanvasId = canvasId),
            ),
    );
  }
}
