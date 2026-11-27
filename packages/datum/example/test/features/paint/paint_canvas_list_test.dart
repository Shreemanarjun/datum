import 'dart:async';

import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:example/features/paint/view/paint_canvas_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// Scenarios: ui.paintings (packages/datum/doc/SYNC_SCENARIOS.md)
void main() {
  testWidgets(
      'stroke counts follow the strokes, also when they arrive after the list is shown',
      (tester) async {
    final counts = StreamController<Map<String, int>>();
    addTearDown(counts.close);
    PaintCanvas canvas(String id, String title) => PaintCanvas(
          id: id,
          userId: 'u1',
          title: title,
          createdAt: DateTime(2026),
          modifiedAt: DateTime(2026),
        );

    await tester.pumpWidget(ShadApp(
      home: Scaffold(
        body: PaintCanvasList(
          onCanvasSelected: (_) {},
          watchCanvases: () =>
              Stream.value([canvas('c1', 'Sketch'), canvas('c2', 'Empty')]),
          watchStrokeCounts: () => counts.stream,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('2 Paintings'), findsOneWidget);
    expect(find.textContaining('0 strokes'), findsNWidgets(2),
        reason: 'no counts yet');

    // The counts arrive late (the strokes were still loading), then change
    // as another device draws and undoes.
    for (final (strokes, shown) in [
      (3, '3 strokes'),
      (4, '4 strokes'),
      (0, '0 strokes')
    ]) {
      counts.add({if (strokes > 0) 'c1': strokes});
      await tester.pump();
      await tester.pump();
      expect(find.textContaining(shown),
          strokes == 0 ? findsNWidgets(2) : findsOneWidget,
          reason: 'after the count became $strokes');
    }
  });
}
