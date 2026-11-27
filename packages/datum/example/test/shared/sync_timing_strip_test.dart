import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart' show TestConnectivityChecker;
import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/features/settings/user_settings.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/shared/widget/sync_timing_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../test/mocks/mock_adapters.dart';

/// The strip is what tells a user (and us) that a device is keeping up: it
/// must move for a sync this device ran AND for a change it only received.
// Scenarios: ui.strip (packages/datum/doc/SYNC_SCENARIOS.md)
void main() {
  late MockRemoteAdapter<Task> tasks;
  late MockRemoteAdapter<PaintStroke> strokes;

  DatumRegistration<T> register<T extends DatumEntityInterface>(
          T Function(Map<String, dynamic>) fromMap,
          MockRemoteAdapter<T> remote) =>
      DatumRegistration<T>(
        localAdapter: InMemoryLocalAdapter<T>(fromMap: fromMap),
        remoteAdapter: remote,
      );

  setUp(() async {
    tasks = MockRemoteAdapter<Task>(fromJson: Task.fromMap);
    strokes =
        MockRemoteAdapter<PaintStroke>(fromJson: PaintStrokeFactory.fromMap);
    (await Datum.initialize(
      config: const DatumConfig(
          enableLogging: false, remoteEventDebounceTime: Duration.zero),
      connectivityChecker: TestConnectivityChecker(),
      registrations: [
        register<Task>(Task.fromMap, tasks),
        register<UserSettings>(UserSettings.fromMap,
            MockRemoteAdapter<UserSettings>(fromJson: UserSettings.fromMap)),
        register<PaintStroke>(PaintStrokeFactory.fromMap, strokes),
        register<PaintCanvas>(
            PaintCanvasFactory.fromMap,
            MockRemoteAdapter<PaintCanvas>(
                fromJson: PaintCanvasFactory.fromMap)),
      ],
    ))
        .fold((error, _) => throw error, (_) {});
  });

  tearDown(() async {
    await Datum.instance.dispose();
    Datum.resetForTesting();
  });

  Task task(String id, String title, {DateTime? at}) => Task(
        id: id,
        userId: 'u1',
        title: title,
        createdAt: at ?? DateTime.now(),
        modifiedAt: at ?? DateTime.now(),
      );

  testWidgets(
      'shows a sync this device ran and a change it received live, newest first',
      (tester) async {
    String shown() => tester.widget<Text>(find.byType(Text)).data!;
    Future<void> settle(Future<void> Function() work) async {
      await tester.runAsync(() async {
        await work();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
    }

    await tester
        .pumpWidget(const ShadApp(home: Scaffold(body: SyncTimingStrip())));
    expect(shown(), 'No sync has run yet in this session');

    // This device edits and syncs while the strip is not on screen (as at
    // app start): the strip shows that sync when it appears.
    await tester.pumpWidget(const ShadApp(home: Scaffold()));
    await settle(() async {
      Datum.manager<Task>().startAutoSync('u1');
      await Datum.manager<Task>()
          .push(item: task('mine', 'mine'), userId: 'u1');
      await Datum.manager<Task>().synchronize('u1');
    });
    await tester
        .pumpWidget(const ShadApp(home: Scaffold(body: SyncTimingStrip())));
    await settle(() async {});
    expect(shown(), matches(RegExp(r'^Task sync \d+ ms ↑1')));

    // And one it runs while the strip is showing.
    await settle(() async {
      await Datum.manager<Task>()
          .push(item: task('mine too', 'mine too'), userId: 'u1');
      await Datum.manager<Task>().synchronize('u1');
    });
    expect(shown(), matches(RegExp(r'^Task sync \d+ ms ↑1')));

    // Another device's edit arrives over the feed: no sync runs here, and
    // the strip must still move.
    final madeAt = DateTime.now().subtract(const Duration(milliseconds: 300));
    await settle(() async {
      final theirs = task('theirs', 'theirs', at: madeAt);
      tasks.emitChange(DatumChangeDetail(
          type: DatumOperationType.create,
          entityId: theirs.id,
          userId: 'u1',
          timestamp: madeAt,
          data: theirs));
    });
    expect(
        shown(),
        matches(RegExp(
            r'^Task live ↓1 · \d+ ms to apply · \d+ ms after the edit$')));
    expect(
        await tester
            .runAsync(() => Datum.manager<Task>().getPendingCount('u1')),
        0,
        reason: 'a received change is not queued for upload');

    // A change of another type becomes the first entry; Task stays behind it.
    await settle(() async {
      final stroke = PaintStroke(
          id: 's1',
          userId: 'u1',
          points: const [],
          color: Colors.black,
          strokeWidth: 2,
          order: 0,
          canvasId: 'c1',
          createdAt: madeAt,
          modifiedAt: madeAt);
      strokes.emitChange(DatumChangeDetail(
          type: DatumOperationType.create,
          entityId: stroke.id,
          userId: 'u1',
          timestamp: madeAt,
          data: stroke));
    });
    expect(shown(),
        matches(RegExp(r'^PaintStroke live ↓1 · .* \|   Task live ↓1 · ')));

    // The same change delivered again is not news.
    final before = shown();
    await settle(() async {
      final theirs = task('theirs', 'theirs', at: madeAt);
      tasks.emitChange(DatumChangeDetail(
          type: DatumOperationType.create,
          entityId: theirs.id,
          userId: 'u1',
          timestamp: madeAt,
          data: theirs));
    });
    expect(shown(), before);
  });
}
