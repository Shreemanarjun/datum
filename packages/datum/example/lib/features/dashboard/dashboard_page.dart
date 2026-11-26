import 'package:example/features/home/view/home_page.dart';
import 'package:example/features/paint/view/paint_page.dart';
import 'package:example/features/settings/settings_page.dart';
import 'package:example/features/tasks/presentation/views/simple_datum_page.dart';
import 'package:flutter/material.dart';
import 'package:kaisel/kaisel.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The dashboard's tabs; each keeps its own back stack.
sealed class TabRoute extends KaiselRoute {
  const TabRoute();
}

final class OverviewTab extends TabRoute {
  const OverviewTab();
}

final class TasksTab extends TabRoute {
  const TasksTab();
}

final class PaintTab extends TabRoute {
  const PaintTab();
}

final class SettingsTab extends TabRoute {
  const SettingsTab();
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return KaiselShell<TabRoute>(
      branchInitials: const [OverviewTab(), TasksTab(), PaintTab(), SettingsTab()],
      pageBuilder: (context, route) => switch (route) {
        OverviewTab() => const HomePage(),
        TasksTab() => const SimpleDatumPage(),
        PaintTab() => const PaintPage(),
        SettingsTab() => const SettingsPage(),
      },
      chromeBuilder: (context, activeIndex, child, switchTo) {
        final isMobile = ResponsiveBreakpoints.of(context).isMobile;
        return Scaffold(
          body: Row(
            children: [
              if (!isMobile)
                _Sidebar(activeIndex: activeIndex, onNavItemTapped: switchTo),
              Expanded(child: child),
            ],
          ),
          bottomNavigationBar: isMobile
              ? _BottomNav(activeIndex: activeIndex, onNavItemTapped: switchTo)
              : null,
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onNavItemTapped;

  const _Sidebar({
    required this.activeIndex,
    required this.onNavItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: ShadTheme.of(context).colorScheme.background,
        border: Border(
          right: BorderSide(
            color: ShadTheme.of(context).colorScheme.border,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: ShadTheme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.data_exploration,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Datum Sync',
                  style: ShadTheme.of(context).textTheme.h4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _SidebarItem(
                    label: 'Overview',
                    icon: LucideIcons.layoutDashboard,
                    isActive: activeIndex == 0,
                    onTap: () => onNavItemTapped(0),
                  ),
                  _SidebarItem(
                    label: 'Tasks',
                    icon: LucideIcons.listTodo,
                    isActive: activeIndex == 1,
                    onTap: () => onNavItemTapped(1),
                  ),
                  _SidebarItem(
                    label: 'Paint Canvas',
                    icon: LucideIcons.palette,
                    isActive: activeIndex == 2,
                    onTap: () => onNavItemTapped(2),
                  ),
                  _SidebarItem(
                    label: 'Settings',
                    icon: LucideIcons.settings,
                    isActive: activeIndex == 3,
                    onTap: () => onNavItemTapped(3),
                  ),
                ],
              ),
            ),
          ),
          _ProfileSection(),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ShadButton.ghost(
        onPressed: onTap,
        width: double.infinity,
        backgroundColor: isActive ? theme.colorScheme.accent : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? theme.colorScheme.accentForeground
                  : theme.colorScheme.mutedForeground,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: theme.textTheme.p.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? theme.colorScheme.accentForeground
                    : theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onNavItemTapped;

  const _BottomNav({
    required this.activeIndex,
    required this.onNavItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          top: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: LucideIcons.layoutDashboard,
                isActive: activeIndex == 0,
                onTap: () => onNavItemTapped(0),
              ),
              _BottomNavItem(
                icon: LucideIcons.listTodo,
                isActive: activeIndex == 1,
                onTap: () => onNavItemTapped(1),
              ),
              _BottomNavItem(
                icon: LucideIcons.palette,
                isActive: activeIndex == 2,
                onTap: () => onNavItemTapped(2),
              ),
              _BottomNavItem(
                icon: LucideIcons.settings,
                isActive: activeIndex == 3,
                onTap: () => onNavItemTapped(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return IconButton(
      icon: Icon(
        icon,
        color: isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.mutedForeground,
      ),
      onPressed: onTap,
    );
  }
}

class _ProfileSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final theme = ShadTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.border),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ShadAvatar(
                'https://api.dicebear.com/7.x/avataaars/svg?seed=${user?.email}',
                placeholder:
                    Text(user?.email?.substring(0, 2).toUpperCase() ?? 'U'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.email?.split('@').first ?? 'User',
                      style: theme.textTheme.small
                          .copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Online',
                      style: theme.textTheme.muted.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              ShadButton.ghost(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: Icon(LucideIcons.logOut,
                    size: 16, color: theme.colorScheme.destructive),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
