import 'dart:math';

import 'package:datum/datum.dart';
import 'package:example/data/user/entity/user.dart';
import 'package:example/features/simple_datum/controller/simple_datum_provider.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

final usersStreamProvider =
    StreamProvider.autoDispose.family<List<User>, String?>(
  (ref, userId) {
    final userRepository = Datum.manager<User>();
    // watchAll can return null if the adapter doesn't support it.
    // We also pass the userId to ensure we only watch the relevant user's data.
    return userRepository.watchAll(userId: userId) ?? const Stream.empty();
  },
  name: 'usersStreamProvider',
);

final syncStatusProvider =
    StreamProvider.autoDispose.family<DatumSyncStatusSnapshot?, String>(
  (ref, userId) async* {
    final datum = await ref.watch(simpleDatumProvider.future);
    // Yield the initial status, then updates.
    yield Datum.manager<User>().currentStatus;
    yield* datum.statusForUser(userId);
  },
);

@RoutePage()
class SimpleDatumPage extends ConsumerStatefulWidget {
  const SimpleDatumPage({super.key});

  @override
  ConsumerState<SimpleDatumPage> createState() => _SimpleDatumPageState();
}

class _SimpleDatumPageState extends ConsumerState<SimpleDatumPage> {
  final _random = Random();

  String _generateRandomId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      _random.nextInt(9999).toString();

  Future<void> _createUser(Datum datum) async {
    final nameController = TextEditingController();

    final didCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (didCreate == true) {
      final newUser = User(
        id: _generateRandomId(),
        userId: 'default_user', // Using a fixed userId for simplicity
        name: nameController.text,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );
      await datum.create(newUser);
    }
  }

  Future<void> _updateUser(Datum datum, User user) async {
    final nameController = TextEditingController(text: user.name);

    final didUpdate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (didUpdate == true) {
      final updatedUser = user.copyWith(
        name: nameController.text,
        modifiedAt: DateTime.now(),
      );
      await datum.update(updatedUser);
    }
  }

  Future<void> _deleteUser(Datum datum, User user) async {
    await datum.delete<User>(
      id: user.id,
      userId: user.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final simpleDatumAsync = ref.watch(simpleDatumProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Datum'),
        actions: [
          simpleDatumAsync.easyWhen(
            data: (datum) {
              final syncStatusAsync =
                  ref.watch(syncStatusProvider('default_user'));
              return syncStatusAsync.easyWhen(
                data: (status) {
                  if (status?.status == DatumSyncStatus.syncing) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    );
                  }
                  return Tooltip(
                    message: 'Manually sync with remote',
                    child: IconButton(
                      icon: const Icon(Icons.sync),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Syncing...')),
                        );
                        datum.synchronize('default_user');
                      },
                    ),
                  );
                },
                loadingWidget: () => const SizedBox.shrink(),
              );
            },
          ),
        ],
      ),
      floatingActionButton: simpleDatumAsync.maybeWhen(
        data: (datum) => FloatingActionButton(
          onPressed: () => _createUser(datum),
          child: const Icon(Icons.add),
        ),
        orElse: () => null,
      ),
      body: simpleDatumAsync.easyWhen(
        data: (data) {
          // Pass the specific userId to the provider instead of the whole datum object.
          const userId = 'default_user';
          final usersAsync = ref.watch(usersStreamProvider(userId));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: const [
                    HealthStatusWidget(),
                    MetricsStatusWidget(),
                  ],
                ),
              ),
              Expanded(
                child: usersAsync.easyWhen(
                  data: (users) {
                    if (users.isEmpty) {
                      return const Center(
                        child: Text('No users found. Add one!'),
                      );
                    }
                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          title: Text(user.name),
                          subtitle: Text('ID: ${user.id}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _updateUser(data, user),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteUser(data, user),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loadingWidget: () =>
                      const Center(child: Text("Watching users...")),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// This widget seems to depend on `datum.health.watch()`, which doesn't exist.
// The `allHealths` stream on the Datum instance is a better fit.
final allHealths = StreamProvider(
  (ref) async* {
    final datum = await ref.watch(simpleDatumProvider.future);
    yield* datum.allHealths;
  },
  name: 'allHealths',
);

class HealthStatusWidget extends ConsumerWidget {
  const HealthStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allHealthsAsync = ref.watch(allHealths);
    return allHealthsAsync.easyWhen(
        data: (healthMap) {
          // Assuming we want to show the health of the User manager.
          final userHealth = healthMap[User];
          if (userHealth == null) return const SizedBox.shrink();

          // A manager is considered healthy if it's operating normally or has pending
          // changes waiting for the next sync.
          final isHealthy = userHealth.status == DatumSyncHealth.healthy ||
              userHealth.status == DatumSyncHealth.pending;

          return Icon(
            isHealthy ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: isHealthy ? Colors.green : Colors.red,
          );
        },
        loadingWidget: () => const SizedBox.shrink());
  }
}

final metricsProvider = StreamProvider((ref) async* {
  final datum = await ref.watch(simpleDatumProvider.future);
  yield* datum.metrics;
});

final pendingOperationsProvider = StreamProvider<int>((ref) async* {
  final datum = await ref.watch(simpleDatumProvider.future);
  // Assuming 'default_user' is the one we are interested in.
  // In a real app, this would be the currently logged-in user's ID.
  await for (final status in datum.statusForUser('default_user')) {
    yield status?.pendingOperations ?? 0;
  }
});

class MetricsStatusWidget extends ConsumerWidget {
  const MetricsStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the new top-level provider for pending operations count.
    final pendingOpsAsync = ref.watch(pendingOperationsProvider);

    return pendingOpsAsync.easyWhen(
      data: (count) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Badge(
          label: Text(count.toString()),
          isLabelVisible: count > 0,
          child: const Icon(Icons.pending_actions),
        ),
      ),
      loadingWidget: () => const SizedBox.shrink(),
      errorWidget: (e, st) => const SizedBox.shrink(),
    );
  }
}
