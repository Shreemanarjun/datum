import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/bootstrap.dart';
import 'package:example/features/auth/data/adapters/supabase_adapter.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/features/tasks/presentation/controllers/sync_streams.dart';
import 'package:example/features/tasks/presentation/widgets/pull_button.dart';
import 'package:example/features/tasks/presentation/widgets/sync_button.dart';
import 'package:example/features/tasks/presentation/widgets/task_dialog.dart';
import 'package:example/features/tasks/presentation/widgets/task_list.dart';
import 'package:example/shared/helper/global_helper.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class SimpleDatumPage extends SignalStatefulWidget {
  const SimpleDatumPage({super.key});

  @override
  State<SimpleDatumPage> createState() => _SimpleDatumPageState();
}

class _SimpleDatumPageState extends State<SimpleDatumPage> with GlobalHelper {
  late final AppLifecycleListener _appLifecycleListener;
  late final StreamSubscription<AuthState> _authSubscription;

  final _userId = signal(Supabase.instance.client.auth.currentUser?.id);
  final _waitingForInitialSync = signal(false);
  late final _tasks = streamSignal<List<Task>>(() {
    final userId = _userId.value;
    if (userId == null) return const Stream.empty();
    return Datum.manager<Task>()
        .watchAll(userId: userId, includeInitialData: true);
  });
  late final _pendingIds = streamSignal<Set<String>>(() {
    final userId = _userId.value;
    return userId == null ? const Stream.empty() : pendingTaskIds(userId);
  });

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(
      onStateChange: (value) => talker.debug("State $value"),
    );
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthChange);
  }

  Future<void> _onAuthChange(AuthState authState) async {
    _userId.value = authState.session?.user.id;
    if (!Datum.isInitialized) return;

    if (authState.event == AuthChangeEvent.signedOut) {
      Datum.instance.pauseSync();
    } else if (authState.event == AuthChangeEvent.signedIn) {
      final userId = authState.session?.user.id;
      if (userId == null) return;
      _waitingForInitialSync.value = true;
      unawaited(Datum.instance
          .statusForUser(userId)
          .firstWhere((s) =>
              s?.status == DatumSyncStatus.completed ||
              s?.status == DatumSyncStatus.idle ||
              s?.status == DatumSyncStatus.failed)
          .then((_) {
        if (mounted) _waitingForInitialSync.value = false;
      }, onError: (Object e) => talker.error('Initial sync wait failed: $e')));

      // Resume sync first
      Datum.instance.resumeSync();

      // Clear sync metadata to force fresh data from server
      final remoteAdapter = Datum.manager<Task>().remoteAdapter;
      if (remoteAdapter is SupabaseRemoteAdapter<Task>) {
        await remoteAdapter.clearSyncMetadata(userId);
      }

      // Cold start sync
      final coldStartPerformed =
          await Datum.instance.handleColdStartIfNeeded<Task>(
        userId,
        (options) =>
            Datum.manager<Task>().synchronize(userId, options: options),
      );

      if (!coldStartPerformed) {
        Datum.instance.synchronize(
          userId,
          options: const DatumSyncOptions(
            direction: SyncDirection.pullThenPush,
            forceFullSync: true,
          ),
        );
      }

      // Start auto-sync
      Datum.instance.startAutoSync(userId);
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _appLifecycleListener.dispose();
    _tasks.dispose();
    _pendingIds.dispose();
    _userId.dispose();
    _waitingForInitialSync.dispose();
    super.dispose();
  }

  /// Runs a Datum write and reports its sync result (or error) as a snack.
  Future<void> _run(
    String action,
    Future<(Object?, DatumSyncResult<DatumEntityInterface>)> Function() op,
  ) async {
    try {
      final (_, result) = await op();
      _handleSyncResult(result);
    } catch (e) {
      if (mounted) showErrorSnack(child: Text('Error $action task: $e'));
    }
  }

  Future<void> _createTask() async {
    if (!mounted) return;
    await TaskDialog.show(
      context: context,
      title: 'Create Task',
      confirmText: 'Create',
      onConfirm: (title, description) {
        final task = Task.create(title: title, description: description);
        return _run('creating',
            () => Datum.instance.pushAndSync(item: task, userId: task.userId));
      },
    );
  }

  Future<void> _saveTask(Task task) => _run('updating',
      () => Datum.instance.updateAndSync(item: task, userId: task.userId));

  Future<void> _updateTask(Task task) async {
    if (!mounted) return;
    await TaskDialog.show(
      context: context,
      task: task,
      title: 'Update Task',
      confirmText: 'Update',
      onConfirm: (title, description) => _saveTask(task.copyWith(
        title: title,
        description: description,
        modifiedAt: DateTime.now(),
      )),
    );
  }

  Future<void> _deleteTask(Task task) => _run(
      'deleting',
      () =>
          Datum.instance.deleteAndSync<Task>(id: task.id, userId: task.userId));

  void _handleSyncResult(
    DatumSyncResult<DatumEntityInterface> result, {
    String operation = 'Sync',
  }) {
    if (!mounted) return;

    if (result.wasSkipped) {
      showInfoSnack(child: Text('$operation skipped.'));
      return;
    }

    if (result.isSuccess) {
      showSuccessSnack(
          child:
              Text('$operation complete. ${result.syncedCount} items synced.'));
    } else {
      showErrorSnack(
          child: Text('$operation failed. ${result.failedCount} failed.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _userId.value;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text("User logged out")));
    }

    if (_waitingForInitialSync.value) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Syncing latest data...'),
            ],
          ),
        ),
      );
    }

    final tasks = _tasks.value;
    final theme = ShadTheme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _createTask,
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(
              'Tasks',
              style: theme.textTheme.h4,
            ),
            centerTitle: false,
            backgroundColor: theme.colorScheme.background,
            elevation: 0,
            floating: true,
            snap: true,
            actions: [
              PullButton(
                userId: userId,
                onPullStart: () =>
                    showInfoSnack(child: const Text('Refreshing...')),
                onPullComplete: (result) =>
                    _handleSyncResult(result, operation: 'Refresh'),
                onPullError: (e) =>
                    showErrorSnack(child: Text('Refresh failed: $e')),
              ),
              SyncButton(
                key: ValueKey(userId),
                userId: userId,
                onSyncStart: () =>
                    showInfoSnack(child: const Text('Syncing...')),
                onSyncComplete: (result) =>
                    _handleSyncResult(result, operation: 'Sync'),
                onSyncError: (e) =>
                    showErrorSnack(child: Text('Sync failed: $e')),
              ),
            ],
          ),
        ],
        body: RefreshIndicator(
          onRefresh: _tasks.refresh,
          child: Column(
            children: [
              _buildSummaryCard(tasks),
              Expanded(
                child: TaskList(
                  tasks: tasks,
                  pendingIds: _pendingIds.value,
                  onToggle: _saveTask,
                  onUpdate: _updateTask,
                  onDelete: _deleteTask,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(AsyncState<List<Task>> tasks) {
    return tasks.maybeMap(
      data: (tasks) {
        if (tasks.isEmpty) return const SizedBox.shrink();
        final completed = tasks.where((t) => t.isCompleted).length;
        final total = tasks.length;
        final pending = total - completed;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildStatCard(
                title: 'Pending',
                value: pending.toString(),
                color: Colors.blue.shade50,
                textColor: Colors.blue.shade900,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                title: 'Completed',
                value: completed.toString(),
                color: Colors.green.shade50,
                textColor: Colors.green.shade900,
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    required Color textColor,
  }) {
    return Expanded(
      child: ShadCard(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
