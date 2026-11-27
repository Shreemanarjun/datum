import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/features/paint/view/paint_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// Scenarios: ui.sheet (packages/datum/doc/SYNC_SCENARIOS.md)
void main() {
  testWidgets(
      'the sheet has the same 2:3 shape on a phone, a tablet and an unfolded foldable, so a drawing made on one is whole on the others',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    // Points are stored as fractions of the sheet's width; this stroke
    // reaches the sheet's bottom-right corner (x = 1, y = 1.5).
    final stroke = PaintStroke(
      id: 's1',
      userId: 'u1',
      canvasId: 'c1',
      points: const [Offset(0.1, 0.1), Offset(1, 1.5)],
      color: Colors.black,
      strokeWidth: 2,
      order: 0,
      createdAt: DateTime(2026),
      modifiedAt: DateTime(2026),
    );

    for (final screen in const [
      Size(390, 844), // phone
      Size(820, 1180), // tablet
      Size(1840, 2208), // unfolded foldable
      Size(1280, 720), // landscape
    ]) {
      tester.view.physicalSize = screen;
      await tester.pumpWidget(ShadApp(
        home: Scaffold(
          body: PaintCanvas(
            key: ValueKey(screen),
            canvasId: 'c1',
            watchStrokes: (_) => Stream.value([stroke]),
          ),
        ),
      ));
      await tester.pump();

      final sheet = tester.getRect(find.byType(AspectRatio));
      expect(sheet.width / sheet.height, closeTo(2 / 3, 0.005),
          reason: 'sheet shape on $screen');
      expect(
          Offset.zero & screen,
          predicate<Rect>((all) =>
              all.contains(sheet.topLeft) &&
              all.contains(sheet.bottomRight - const Offset(1, 1))),
          reason: 'the whole sheet is on screen on $screen');
      // The lowest point of the stroke (y = 1.5 widths) is the sheet's
      // bottom edge on every screen: nothing is cut off.
      expect(sheet.width * 1.5, closeTo(sheet.height, 1),
          reason: 'stroke extent on $screen');
    }
  });
}
