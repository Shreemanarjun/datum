import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/features/tasks/presentation/controllers/simple_datum_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// PROVIDERS
// ============================================================================

final simpleDatumControllerProvider =
    NotifierProvider.autoDispose<SimpleDatumController, void>(
  SimpleDatumController.new,
  name: 'simpleDatumControllerProvider',
);

final syncResultEventProvider =
    StateProvider<DatumSyncResult<DatumEntityInterface>?>(
  (ref) => null,
  name: "syncResultEventProvider",
);

final tasksStreamProvider =
    StreamProvider.autoDispose.family<List<Task>, String>(
  (ref, userId) async* {
    yield* Datum.manager<Task>()
        .watchAll(userId: userId, includeInitialData: true);
  },
  name: 'tasksStreamProvider',
);

final syncStatusProvider =
    StreamProvider.autoDispose.family<DatumSyncStatusSnapshot?, String>(
  (ref, userId) async* {
    final datum = ref.watch(simpleDatumProvider);
    yield* datum.statusForUser(userId);
  },
  name: 'syncStatusProvider',
);

// ============================================================================
// CONTROLLER
// ============================================================================

class SimpleDatumController extends AutoDisposeNotifier<void> {
  SimpleDatumController();

  void _notifySyncResult(DatumSyncResult<DatumEntityInterface> result) {
    ref.read(syncResultEventProvider.notifier).state = result;
  }

  Future<void> createTask({
    required String title,
    String? description,
  }) async {
    final newTask = Task.create(title: title, description: description);
    final (_, syncResult) =
        await Datum.instance.pushAndSync(item: newTask, userId: newTask.userId);
    _notifySyncResult(syncResult);
  }

  Future<void> updateTask(Task task) async {
    final (_, syncResult) =
        await Datum.instance.updateAndSync(item: task, userId: task.userId);
    _notifySyncResult(syncResult);
  }

  Future<void> deleteTask(Task task) async {
    final (_, syncResult) = await Datum.instance
        .deleteAndSync<Task>(id: task.id, userId: task.userId);
    _notifySyncResult(syncResult);
  }

  @override
  void build() {
    return;
  }
}
