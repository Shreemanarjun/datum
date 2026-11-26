import 'package:collection/collection.dart';
import 'package:datum/datum.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/shared/widget/parked_ops_banner.dart';
import 'package:kaisel/kaisel.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:example/features/tasks/presentation/widgets/sync_dashboard_widget.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final theme = ShadTheme.of(context);
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Dashboard Overview',
                style: theme.textTheme.h3
                    .copyWith(color: theme.colorScheme.foreground),
              ),
              centerTitle: false,
              titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
            ),
            backgroundColor: theme.colorScheme.background,
            elevation: 0,
            automaticallyImplyLeading: false, // Sidebar handles navigation
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildWelcomeHeader(context, user),
                const SizedBox(height: 32),
                if (user != null)
                  _LiveStats(
                      key: ValueKey(user.id),
                      userId: user.id,
                      isMobile: isMobile),
                const SizedBox(height: 32),
                _buildSyncStatusSection(context, user?.id),
                const SizedBox(height: 32),
                _buildQuickActions(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader(BuildContext context, User? user) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back, ${user?.email?.split('@').first ?? 'Explorer'}! 👋',
          style: theme.textTheme.h3,
        ),
        const SizedBox(height: 8),
        Text(
          'Here is what is happening with your data sync today.',
          style: theme.textTheme.muted,
        ),
      ],
    );
  }

  Widget _buildSyncStatusSection(BuildContext context, String? userId) {
    if (userId == null) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Sync Health', style: theme.textTheme.h4),
            ShadButton.outline(
              child: const Text('View Logs'),
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 16),
        SyncDashboardWidget(key: ValueKey(userId), userId: userId),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: theme.textTheme.h4),
        const SizedBox(height: 16),
        Row(
          children: [
            _QuickActionCard(
              title: 'Add New Task',
              icon: LucideIcons.plus,
              onTap: () => context.shell().switchTo(1),
              color: Colors.blue,
            ),
            const SizedBox(width: 16),
            _QuickActionCard(
              title: 'Start Drawing',
              icon: LucideIcons.brush,
              onTap: () => context.shell().switchTo(2),
              color: Colors.purple,
            ),
          ],
        ),
      ],
    );
  }
}

/// Live numbers from the sync engine for [userId], across every synced type.
class _LiveStats extends StatefulWidget {
  const _LiveStats({super.key, required this.userId, required this.isMobile});

  final String userId;
  final bool isMobile;

  @override
  State<_LiveStats> createState() => _LiveStatsState();
}

class _LiveStatsState extends State<_LiveStats> {
  Stream<int> _total(Stream<int> Function(Type type) each) =>
      Rx.combineLatestList([for (final type in syncedEntityTypes) each(type)])
          .map((values) => values.sum);

  late final _pending = _total(
      (type) => Datum.managerByType(type).watchPendingCount(widget.userId));
  late final _bytes = _total((type) =>
      Datum.managerByType(type).watchStorageSize(userId: widget.userId));
  late final _items = Rx.combineLatest2(
    Datum.manager<Task>().watchAll(userId: widget.userId),
    Datum.manager<PaintCanvas>().watchAll(userId: widget.userId),
    (List<Task> tasks, List<PaintCanvas> canvases) =>
        (tasks: tasks.length, paintings: canvases.length),
  );

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: widget.isMobile ? 1 : 3,
      childAspectRatio: 2.5,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: [
        StreamBuilder(
          stream: _pending,
          builder: (context, snapshot) {
            final waiting = snapshot.data ?? 0;
            return _StatCard(
              title: 'Waiting to upload',
              value: '$waiting',
              icon: LucideIcons.cloudUpload,
              trend: waiting == 0
                  ? 'Everything is uploaded'
                  : 'Sent on the next sync',
              trendPositive: waiting == 0,
            );
          },
        ),
        StreamBuilder(
          stream: _items,
          builder: (context, snapshot) => _StatCard(
            title: 'Your data',
            value: '${snapshot.data?.tasks ?? 0} tasks',
            icon: LucideIcons.layers,
            trend: '${snapshot.data?.paintings ?? 0} paintings',
            trendPositive: true,
          ),
        ),
        StreamBuilder(
          stream: _bytes,
          builder: (context, snapshot) => _StatCard(
            title: 'Stored on this device',
            value: _size(snapshot.data ?? 0),
            icon: LucideIcons.database,
            trend: 'Local copy of your synced data',
            trendPositive: true,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final String trend;
  final bool trendPositive;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.trend,
    required this.trendPositive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: theme.textTheme.muted.copyWith(fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: theme.textTheme.h4),
                const SizedBox(height: 4),
                Text(
                  trend,
                  style: theme.textTheme.muted.copyWith(
                    fontSize: 11,
                    color: trendPositive
                        ? Colors.green
                        : theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: ShadCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 16),
              Text(title,
                  style:
                      theme.textTheme.p.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
