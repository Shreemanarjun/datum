import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/features/tasks/presentation/widgets/task_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

Task _task(String id, String title,
        {String? description, bool done = false, DateTime? modifiedAt}) =>
    Task(
      id: id,
      title: title,
      description: description,
      isCompleted: done,
      createdAt: DateTime(2026),
      modifiedAt: modifiedAt ?? DateTime(2026, 1, 2),
      userId: 'user1',
    );

void main() {
  final toggled = <Task>[];
  final updated = <Task>[];
  final deleted = <Task>[];

  setUp(() {
    toggled.clear();
    updated.clear();
    deleted.clear();
  });

  Future<void> pumpList(
    WidgetTester tester, {
    required AsyncState<List<Task>> tasks,
    AsyncState<DateTime?>? lastSyncTime,
  }) =>
      tester.pumpWidget(ShadApp(
        home: Scaffold(
          body: TaskList(
            tasks: tasks,
            lastSyncTime: lastSyncTime ?? AsyncState.loading(),
            onToggle: toggled.add,
            onUpdate: updated.add,
            onDelete: deleted.add,
          ),
        ),
      ));

  testWidgets('loading, error and empty states', (tester) async {
    await pumpList(tester, tasks: AsyncState.loading());
    expect(find.text('Loading tasks...'), findsOneWidget);

    await pumpList(tester,
        tasks: AsyncState.error(StateError('db closed'), StackTrace.empty));
    expect(find.textContaining('db closed'), findsOneWidget);

    await pumpList(tester, tasks: AsyncState.data(const []));
    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.text('Create a task to get started!'), findsOneWidget);
  });

  testWidgets('renders tasks, sync state and forwards every action',
      (tester) async {
    final active = _task('1', 'Active Task', description: 'Description');
    final done = _task('2', 'Completed Task',
        done: true, modifiedAt: DateTime(2026, 1, 3));

    // Last sync between the two edits: only `done` is pending.
    await pumpList(
      tester,
      tasks: AsyncState.data([active, done]),
      lastSyncTime: AsyncState.data(DateTime(2026, 1, 2, 12)),
    );

    expect(find.text('Active Task'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    final checkboxes =
        tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(checkboxes.map((c) => c.value), [false, true]);
    expect(
      tester.widget<Text>(find.text('Completed Task')).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      tester.widget<Text>(find.text('Active Task')).style?.decoration,
      isNull,
    );
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);

    // Toggle forwards a completed copy with a fresh modifiedAt.
    await tester.tap(find.byType(Checkbox).first);
    expect(toggled.single.id, '1');
    expect(toggled.single.isCompleted, isTrue);
    expect(toggled.single.modifiedAt.isAfter(active.modifiedAt), isTrue);

    await tester.tap(find.byIcon(Icons.edit).last);
    expect(updated.single.id, '2');
    await tester.tap(find.byIcon(Icons.delete).first);
    expect(deleted.single.id, '1');

    // Never synced: everything is pending.
    await pumpList(tester,
        tasks: AsyncState.data([active, done]),
        lastSyncTime: AsyncState.data(null));
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNWidgets(2));

    // Synced after both edits: nothing pending.
    await pumpList(tester,
        tasks: AsyncState.data([active, done]),
        lastSyncTime: AsyncState.data(DateTime(2027)));
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);

    // Sync time still loading / failed.
    await pumpList(tester, tasks: AsyncState.data([active]));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await pumpList(tester,
        tasks: AsyncState.data([active]),
        lastSyncTime: AsyncState.error('offline', StackTrace.empty));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
