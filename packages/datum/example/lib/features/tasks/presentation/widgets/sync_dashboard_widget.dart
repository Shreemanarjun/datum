import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:datum/datum.dart';
import 'package:example/features/tasks/presentation/controllers/sync_streams.dart';

/// Comprehensive sync dashboard widget showing data transfer, sync status, and health
class SyncDashboardWidget extends SignalStatefulWidget {
  final String userId;

  const SyncDashboardWidget({
    super.key,
    required this.userId,
  });

  @override
  State<SyncDashboardWidget> createState() => _SyncDashboardWidgetState();
}

class _SyncDashboardWidgetState extends State<SyncDashboardWidget> {
  late final _statuses = streamSignal(allEntitiesSyncStatus);
  late final _lastSyncTime = streamSignal(() => lastSyncTime(widget.userId));

  @override
  void dispose() {
    _statuses.dispose();
    _lastSyncTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_statuses.value) {
      AsyncData(:final value) =>
        _buildDashboard(context, value, _lastSyncTime.value.value),
      AsyncError() => _buildErrorDashboard(context),
      _ => _buildLoadingDashboard(context),
    };
  }

  Widget _buildDashboard(
      BuildContext context,
      Map<Type, DatumSyncStatusSnapshot> entityStatuses,
      DateTime? lastSyncTime) {
    // Calculate aggregate metrics
    final totalSynced = entityStatuses.values
        .fold<int>(0, (sum, status) => sum + status.syncedCount);
    final totalPending = entityStatuses.values
        .fold<int>(0, (sum, status) => sum + status.pendingOperations);
    final totalConflicts = entityStatuses.values
        .fold<int>(0, (sum, status) => sum + status.conflictsResolved);
    final totalFailed = entityStatuses.values
        .fold<int>(0, (sum, status) => sum + status.failedOperations);

    // Get overall health status
    final overallHealth = _calculateOverallHealth(entityStatuses);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.dashboard, size: 24, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Sync Dashboard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _buildOverallStatusBadge(entityStatuses),
              ],
            ),
            const SizedBox(height: 16),

            // Sync Operations Section
            _buildSectionHeader('Sync Operations'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Synced',
                    totalSynced.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard(
                    'Pending',
                    totalPending.toString(),
                    Icons.schedule,
                    totalPending > 0 ? Colors.orange : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'Conflicts',
                    totalConflicts.toString(),
                    Icons.warning,
                    totalConflicts > 0 ? Colors.amber : Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard(
                    'Failed',
                    totalFailed.toString(),
                    Icons.error,
                    totalFailed > 0 ? Colors.red : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Status Information Section
            _buildSectionHeader('Status Information'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    'Last Sync',
                    lastSyncTime != null
                        ? _formatLastSync(lastSyncTime)
                        : 'Never',
                    Icons.access_time,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoCard(
                    'Health',
                    _getHealthStatusText(overallHealth),
                    Icons.health_and_safety,
                    _getHealthColor(overallHealth),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Entity Status Section
            _buildSectionHeader('Entity Status'),
            const SizedBox(height: 8),
            ..._buildEntityStatusList(entityStatuses),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ShadTheme.of(context).colorScheme.foreground,
      ),
    );
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildOverallStatusBadge(
      Map<Type, DatumSyncStatusSnapshot> entityStatuses) {
    final isAnySyncing = entityStatuses.values
        .any((status) => status.status == DatumSyncStatus.syncing);
    final hasAnyPending =
        entityStatuses.values.any((status) => status.pendingOperations > 0);
    final hasAnyFailed =
        entityStatuses.values.any((status) => status.failedOperations > 0);

    Color color;
    String text;
    IconData icon;

    if (isAnySyncing) {
      color = Colors.blue;
      text = 'Syncing';
      icon = Icons.sync;
    } else if (hasAnyFailed) {
      color = Colors.red;
      text = 'Issues';
      icon = Icons.error;
    } else if (hasAnyPending) {
      color = Colors.orange;
      text = 'Pending';
      icon = Icons.schedule;
    } else {
      color = Colors.green;
      text = 'Synced';
      icon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEntityStatusList(
      Map<Type, DatumSyncStatusSnapshot> entityStatuses) {
    return entityStatuses.entries.map((entry) {
      final entityType = entry.key;
      final status = entry.value;
      final entityName = _getEntityName(entityType);

      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Text(
              entityName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (status.pendingOperations > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${status.pendingOperations} pending',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              _getStatusIcon(status),
              size: 14,
              color: _getStatusColor(status),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildLoadingDashboard(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading sync dashboard...'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorDashboard(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.error, size: 48, color: Colors.red),
              SizedBox(height: 16),
              Text('Failed to load sync dashboard'),
            ],
          ),
        ),
      ),
    );
  }

  DatumSyncHealth _calculateOverallHealth(
      Map<Type, DatumSyncStatusSnapshot> entityStatuses) {
    // Return the worst health status among all entities
    final healthStatuses =
        entityStatuses.values.map((status) => status.health.status).toList();

    if (healthStatuses.contains(DatumSyncHealth.error)) {
      return DatumSyncHealth.error;
    } else if (healthStatuses.contains(DatumSyncHealth.degraded)) {
      return DatumSyncHealth.degraded;
    } else if (healthStatuses.contains(DatumSyncHealth.offline)) {
      return DatumSyncHealth.offline;
    } else if (healthStatuses.contains(DatumSyncHealth.pending)) {
      return DatumSyncHealth.pending;
    } else if (healthStatuses.contains(DatumSyncHealth.syncing)) {
      return DatumSyncHealth.syncing;
    } else {
      return DatumSyncHealth.healthy;
    }
  }

  String _formatLastSync(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  String _getHealthStatusText(DatumSyncHealth health) {
    switch (health) {
      case DatumSyncHealth.healthy:
        return 'Healthy';
      case DatumSyncHealth.syncing:
        return 'Syncing';
      case DatumSyncHealth.pending:
        return 'Pending';
      case DatumSyncHealth.degraded:
        return 'Degraded';
      case DatumSyncHealth.offline:
        return 'Offline';
      case DatumSyncHealth.error:
        return 'Error';
    }
  }

  Color _getHealthColor(DatumSyncHealth health) {
    switch (health) {
      case DatumSyncHealth.healthy:
        return Colors.green;
      case DatumSyncHealth.syncing:
        return Colors.blue;
      case DatumSyncHealth.pending:
        return Colors.orange;
      case DatumSyncHealth.degraded:
        return Colors.amber;
      case DatumSyncHealth.offline:
        return Colors.grey;
      case DatumSyncHealth.error:
        return Colors.red;
    }
  }

  Color _getStatusColor(DatumSyncStatusSnapshot status) {
    switch (status.status) {
      case DatumSyncStatus.syncing:
        return Colors.blue;
      case DatumSyncStatus.completed:
        return Colors.green;
      case DatumSyncStatus.failed:
        return Colors.red;
      case DatumSyncStatus.paused:
        return Colors.orange;
      case DatumSyncStatus.cancelled:
        return Colors.grey;
      case DatumSyncStatus.idle:
        return status.pendingOperations > 0 ? Colors.orange : Colors.green;
    }
  }

  IconData _getStatusIcon(DatumSyncStatusSnapshot status) {
    switch (status.status) {
      case DatumSyncStatus.syncing:
        return Icons.sync;
      case DatumSyncStatus.completed:
        return Icons.check_circle;
      case DatumSyncStatus.failed:
        return Icons.error;
      case DatumSyncStatus.paused:
        return Icons.pause;
      case DatumSyncStatus.cancelled:
        return Icons.cancel;
      case DatumSyncStatus.idle:
        return status.pendingOperations > 0
            ? Icons.schedule
            : Icons.check_circle;
    }
  }

  String _getEntityName(Type entityType) {
    final typeName = entityType.toString();
    // Remove generic type parameters if present
    final baseName = typeName.split('<').first;
    // Convert PascalCase to Title Case
    return baseName.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => match.group(1) == baseName[0]
          ? match.group(1)!
          : ' ${match.group(1)!}',
    );
  }
}
