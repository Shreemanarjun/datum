import 'dart:ui' as ui;
import 'package:example/bootstrap.dart';
import 'package:example/shared/helper/global_helper.dart';
import 'package:flutter/material.dart';
import 'package:datum/datum.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Every stroke of [canvasId], oldest first, soft-deleted ones included:
/// undo and redo are derived from them, so they work on any device.
Stream<List<PaintStroke>> _watchStrokes(String canvasId) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);

  return Datum.manager<PaintStroke>()
      .watchAll(userId: userId, includeInitialData: true, includeDeleted: true)
      .map((allStrokes) =>
          allStrokes.where((stroke) => stroke.canvasId == canvasId).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
}

List<PaintStroke> _live(List<PaintStroke> all) => [
      for (final s in all)
        if (!s.isDeleted) s
    ];

/// Undone strokes that redo can bring back, latest undo last: those deleted
/// after the newest visible stroke was drawn (drawing again ends redo).
List<PaintStroke> _redoable(List<PaintStroke> all) {
  final live = _live(all);
  final newest = live.isEmpty ? null : live.last.createdAt;
  return [
    for (final s in all)
      if (s.isDeleted && (newest == null || s.modifiedAt.isAfter(newest))) s
  ]..sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
}

class PaintCanvas extends SignalStatefulWidget {
  final String canvasId;

  const PaintCanvas({super.key, required this.canvasId});

  @override
  State<PaintCanvas> createState() => _PaintCanvasState();
}

class _PaintCanvasState extends State<PaintCanvas> with GlobalHelper {
  late final _strokes = streamSignal(() => _watchStrokes(widget.canvasId));

  /// High-performance notifier for the active stroke being drawn
  final ValueNotifier<List<Offset>> _currentPointsNotifier = ValueNotifier([]);

  /// Optimistic UI: Strokes that have "ended" but aren't yet reflected in the
  /// reactive data stream from the database.
  final List<PaintStroke> _optimisticStrokes = [];

  Color _selectedColor = Colors.black;
  double _strokeWidth = 2.0;

  @override
  void dispose() {
    _strokes.dispose();
    _currentPointsNotifier.dispose();
    super.dispose();
  }

  /// Canvas width, the unit stroke points are stored in: devices with
  /// different screens draw the same picture at their own scale.
  double _canvasWidth = 1;

  void _startStroke(Offset position) {
    _currentPointsNotifier.value = [position / _canvasWidth];
  }

  void _updateStroke(Offset position) {
    _currentPointsNotifier.value = [
      ..._currentPointsNotifier.value,
      position / _canvasWidth
    ];
  }

  Future<void> _endStroke() async {
    final points = _currentPointsNotifier.value;
    if (points.isEmpty) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // 1. Create the stroke object
    final stroke = PaintStroke.create(
      points: List<Offset>.from(points),
      color: _selectedColor,
      strokeWidth: _strokeWidth,
      order: 0, // Simplified order for creation
      canvasId: widget.canvasId,
    );

    // 2. Add to optimistic cache and clear the active drawing buffer
    // This happens BEFORE we push to the database to ensure the line stays on screen.
    setState(() {
      _optimisticStrokes.add(stroke);
      _currentPointsNotifier.value = [];
    });

    // 3. Save to Datum
    try {
      await Datum.manager<PaintStroke>().push(
        item: stroke,
        userId: userId,
      );
    } catch (e) {
      talker.error('Error saving stroke: $e');
      setState(() {
        _optimisticStrokes.removeWhere((s) => s.id == stroke.id);
      });
    }
  }

  List<PaintStroke> get _all => _strokes.peek().value ?? const [];

  /// Soft-deletes or restores [stroke], stamped now so the change wins on
  /// every device and orders the redo list.
  Future<void> _setDeleted(PaintStroke stroke, bool deleted) =>
      Datum.manager<PaintStroke>().push(
        item:
            stroke.copyWithAll(isDeleted: deleted, modifiedAt: DateTime.now()),
        userId: stroke.userId,
      );

  Future<void> _undo() async {
    final live = _live(_all);
    if (live.isNotEmpty) await _setDeleted(live.last, true);
  }

  Future<void> _redo() async {
    final undone = _redoable(_all);
    if (undone.isNotEmpty) await _setDeleted(undone.last, false);
  }

  Future<void> _clearCanvas() async {
    for (final stroke in _live(_all)) {
      await _setDeleted(stroke, true);
    }
    setState(_optimisticStrokes.clear);
  }

  Future<void> _syncToRemote() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await Datum.instance.synchronize(userId);
      if (mounted) {
        showSuccessSnack(child: const Text('Sync complete!'));
      }
    } catch (e) {
      talker.error(e);
      if (mounted) {
        showErrorSnack(child: Text('Failed to sync: $e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strokesAsync = _strokes.value;
    final theme = ShadTheme.of(context);

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.background,
            border: Border(bottom: BorderSide(color: theme.colorScheme.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildColorPicker(theme),
                _buildDivider(theme),
                _buildWidthPicker(theme),
                _buildDivider(theme),
                strokesAsync.maybeMap(
                  data: (all) => _buildActions(all, theme),
                  orElse: () => _buildDisabledActions(theme),
                ),
                _buildDivider(theme),
                ShadButton.ghost(
                  onPressed: _syncToRemote,
                  child: Icon(LucideIcons.cloudUpload,
                      size: 20, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
        // Canvas
        Expanded(
          child: Container(
            color: Colors.white,
            child: strokesAsync.map(
              data: (all) {
                final strokes = _live(all);
                // Sync optimistic cache: Remove strokes that have now safely
                // arrived in the stream.
                if (_optimisticStrokes.isNotEmpty) {
                  final strokeIds = all.map((s) => s.id).toSet();
                  _optimisticStrokes
                      .removeWhere((s) => strokeIds.contains(s.id));
                }

                // Combine stream data with remaining optimistic strokes
                final combinedStrokes = [...strokes, ..._optimisticStrokes];

                return LayoutBuilder(builder: (context, constraints) {
                  _canvasWidth = constraints.maxWidth;
                  return RepaintBoundary(
                    child: GestureDetector(
                      onPanStart: (details) =>
                          _startStroke(details.localPosition),
                      onPanUpdate: (details) =>
                          _updateStroke(details.localPosition),
                      onPanEnd: (details) => _endStroke(),
                      child: ValueListenableBuilder<List<Offset>>(
                        valueListenable: _currentPointsNotifier,
                        builder: (context, currentPoints, _) {
                          return CustomPaint(
                            painter: _CanvasPainter(
                              strokes: combinedStrokes,
                              currentPoints: currentPoints,
                              currentColor: _selectedColor,
                              currentStrokeWidth: _strokeWidth,
                            ),
                            size: Size.infinite,
                          );
                        },
                      ),
                    ),
                  );
                });
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorPicker(ShadThemeData theme) {
    final colors = [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple
    ];
    return Row(
      children: colors.map((color) {
        final isSelected = _selectedColor == color;
        return GestureDetector(
          onTap: () => setState(() => _selectedColor = color),
          child: Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWidthPicker(ShadThemeData theme) {
    final widths = [2.0, 4.0, 8.0];
    return Row(
      children: widths.map((w) {
        final isSelected = _strokeWidth == w;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ShadButton.ghost(
            width: 36,
            height: 36,
            padding: EdgeInsets.zero,
            backgroundColor: isSelected ? theme.colorScheme.accent : null,
            onPressed: () => setState(() => _strokeWidth = w),
            child: Container(
              width: w + 2,
              height: w + 2,
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.accentForeground
                    : theme.colorScheme.mutedForeground,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActions(List<PaintStroke> all, ShadThemeData theme) {
    final strokes = _live(all);
    return Row(
      children: [
        ShadButton.ghost(
          onPressed: (strokes.isNotEmpty || _optimisticStrokes.isNotEmpty)
              ? _undo
              : null,
          child: const Icon(LucideIcons.undo2, size: 20),
        ),
        ShadButton.ghost(
          onPressed: _redoable(all).isNotEmpty ? _redo : null,
          child: const Icon(LucideIcons.redo2, size: 20),
        ),
        ShadButton.ghost(
          onPressed: (strokes.isNotEmpty || _optimisticStrokes.isNotEmpty)
              ? _clearCanvas
              : null,
          child: const Icon(LucideIcons.trash2, size: 20),
        ),
      ],
    );
  }

  Widget _buildDisabledActions(ShadThemeData theme) {
    return Row(
      children: [
        ShadButton.ghost(
            enabled: false, child: const Icon(LucideIcons.undo2, size: 20)),
        ShadButton.ghost(
            enabled: false, child: const Icon(LucideIcons.redo2, size: 20)),
        ShadButton.ghost(
            enabled: false, child: const Icon(LucideIcons.trash2, size: 20)),
      ],
    );
  }

  Widget _buildDivider(ShadThemeData theme) {
    return Container(
      width: 1,
      height: 24,
      color: theme.colorScheme.border,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final List<PaintStroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentStrokeWidth;

  _CanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentStrokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Points are stored as fractions of the canvas width.
    canvas.scale(size.width);
    // 1. Draw all completed (and optimistic) strokes
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth / size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke;

      if (stroke.points.isEmpty) continue;

      if (stroke.points.length == 1) {
        canvas.drawPoints(ui.PointMode.points, stroke.points, paint);
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    // 2. Draw the stroke currently being drawn
    if (currentPoints.isNotEmpty) {
      final paint = Paint()
        ..color = currentColor
        ..strokeWidth = currentStrokeWidth / size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke;

      if (currentPoints.length == 1) {
        canvas.drawPoints(ui.PointMode.points, currentPoints, paint);
      } else {
        final path = Path();
        path.moveTo(currentPoints.first.dx, currentPoints.first.dy);
        for (int i = 1; i < currentPoints.length; i++) {
          path.lineTo(currentPoints[i].dx, currentPoints[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) => true;
}
