// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:math';

import 'package:datum/datum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:datum_generator/annotations.dart';

import 'paint_stroke.dart';

part 'paint_canvas.g.dart';

//-- Create paint_canvases table - COMPATIBLE WITH SUPABASE
/*
-- Step 1: Create the table
CREATE TABLE public.paint_canvases (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    thumbnail_stroke_data JSONB,
    stroke_count INTEGER DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    modified_at TIMESTAMPTZ DEFAULT NOW()
);

-- Step 2: Enable Row Level Security
ALTER TABLE public.paint_canvases ENABLE ROW LEVEL SECURITY;

-- Step 3: Create RLS policy
CREATE POLICY "Users can only access their own paint canvases" ON public.paint_canvases
    FOR ALL USING (auth.uid()::text = user_id);

-- Step 4: Create indexes
CREATE INDEX idx_paint_canvases_user_id ON public.paint_canvases(user_id);
CREATE INDEX idx_paint_canvases_modified_at ON public.paint_canvases(modified_at);

-- Step 5: Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.paint_canvases;
*/

@DatumSerializable(tableName: 'paint_canvases', generateMixin: true)
class PaintCanvas extends RelationalDatumEntity with _$PaintCanvasMixin {
  @override
  final String id;

  @override
  final String userId;

  final String title;

  final String? description;

  final List<Map<String, dynamic>>? thumbnailStrokeData;

  final int strokeCount;

  // Define relationship using annotation - will be auto-generated
  @HasManyRelation<PaintStroke>('canvasId', cascadeDelete: 'cascade')
  final List<PaintStroke>? _strokes = null;

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
  PaintCanvas({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.thumbnailStrokeData,
    this.strokeCount = 0,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  static PaintCanvas create({
    required String title,
    String? description,
  }) {
    final now = DateTime.now();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Cannot create paint canvas: user is not logged in.');
    }
    return PaintCanvas(
      id: '${now.millisecondsSinceEpoch}${Random().nextInt(9999)}',
      userId: userId,
      title: title,
      description: description,
      strokeCount: 0,
      createdAt: now,
      modifiedAt: now,
    );
  }
}
