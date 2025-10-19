import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:example/features/simple_datum/controller/simple_datum_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final nextSyncTimeProvider = StreamProvider.autoDispose<DateTime?>(
  (ref) {
    // This provider does not depend on the user, so it can be a simple provider.
    final taskManager = Datum.manager<Task>();
    return taskManager.onNextSyncTimeChanged;
  },
  name: 'nextSyncTimeProvider',
);

final storageSizeProvider = StreamProvider.autoDispose.family<int, String>(
  (ref, userId) {
    final taskManager = Datum.manager<Task>();
    return taskManager.watchStorageSize(userId: userId);
  },
  name: 'storageSizeProvider',
);

final allHealths = StreamProvider(
  (ref) async* {
    final datum = await ref.watch(simpleDatumProvider.future);
    yield* datum.allHealths;
  },
  name: 'allHealths',
);

final metricsProvider = StreamProvider(
  (ref) async* {
    final datum = await ref.watch(simpleDatumProvider.future);
    yield* datum.metrics;
  },
  name: 'metricsProvider',
);

final pendingOperationsProvider =
    StreamProvider.autoDispose.family<int, String>(
  (ref, userId) async* {
    final datum = await ref.watch(simpleDatumProvider.future);
    yield* datum.statusForUser(userId).map((snapshot) {
      return snapshot?.pendingOperations ?? 0;
    });
  },
  name: 'pendingOperationsProvider',
);
