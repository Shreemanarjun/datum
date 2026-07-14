// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:math';
import 'dart:ui';

import 'package:datum/datum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:datum_generator/annotations.dart';

import 'paint_canvas.dart';

part 'paint_stroke.g.dart';

//-- Create paint_strokes table - COMPATIBLE WITH SUPABASE
/*
-- Step 1: Create the table
CREATE TABLE public.paint_strokes (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    points JSONB NOT NULL,
    color BIGINT NOT NULL,
    stroke_width REAL NOT NULL,
    "order" INTEGER NOT NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    modified_at TIMESTAMPTZ DEFAULT NOW()
);

-- Step 2: Enable Row Level Security
ALTER TABLE public.paint_strokes ENABLE ROW LEVEL SECURITY;

-- Step 3: Create RLS policy
CREATE POLICY "Users can only access their own paint strokes" ON public.paint_strokes
    FOR ALL USING (auth.uid()::text = user_id);

-- Step 4: Create indexes
CREATE INDEX idx_paint_strokes_user_id ON public.paint_strokes(user_id);
CREATE INDEX idx_paint_strokes_modified_at ON public.paint_strokes(modified_at);
CREATE INDEX idx_paint_strokes_order ON public.paint_strokes("order");

-- Step 5: Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.paint_strokes;

-- Step 6: Test the table (optional - run after creating)
-- INSERT INTO public.paint_strokes (id, user_id, points, color, stroke_width, "order")
-- VALUES ('test-123', 'user-456', '[{"x": 100, "y": 200}, {"x": 150, "y": 250}]', 4294198070, 5.0, 1);
*/

@DatumSerializable(tableName: 'paint_strokes', generateMixin: true)
class PaintStroke extends RelationalDatumEntity with _$PaintStrokeMixin {
  @override
  final String id;

  @override
  final String userId;

  final List<Offset> points;

  final Color color;

  final double strokeWidth;

  final int order;

  final String canvasId;

  // Define relationship using annotation
  @BelongsToRelation<PaintCanvas>('canvasId')
  final String? _canvas = null;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final bool isDeleted;

  @override
  final int version;

  // Not const: the generated relational mixin caches relations in an instance
  // field, which a const constructor cannot initialize.
  PaintStroke({
    required this.id,
    required this.userId,
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.order,
    required this.canvasId,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  static PaintStroke create({
    required List<Offset> points,
    required Color color,
    required double strokeWidth,
    required int order,
    required String canvasId,
  }) {
    final now = DateTime.now();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Cannot create paint stroke: user is not logged in.');
    }
    return PaintStroke(
      id: '${now.millisecondsSinceEpoch}${Random().nextInt(9999)}',
      userId: userId,
      points: points,
      color: color,
      strokeWidth: strokeWidth,
      order: order,
      canvasId: canvasId,
      createdAt: now,
      modifiedAt: now,
    );
  }
}
