---
title: Health Module
---

The Health module provides monitoring and diagnostics for the Datum system's operational status.

## Overview

Health monitoring is crucial for maintaining reliable data synchronization. The Health module tracks the status of each manager and its adapters so the system's condition is always observable.

## Key Components

### DatumHealth

Represents the operational health of a sync manager.

**Properties:**
- `status`: The overall manager health (`DatumSyncHealth`)
- `localAdapterStatus`: Health of the local data adapter (`AdapterHealthStatus`)
- `remoteAdapterStatus`: Health of the remote data adapter (`AdapterHealthStatus`)

**Methods:**
- `describe()`: A human-readable, multi-line health summary suitable for logging

### DatumSyncHealth Enum

Describes the overall health of a synchronization process:

- `healthy`: Everything is functioning normally
- `syncing`: A sync cycle is currently running
- `pending`: Operations are queued and waiting to sync
- `degraded`: The system works but with reduced capability
- `offline`: The remote is unreachable
- `error`: The last sync ended in an error

### AdapterHealthStatus Enum

Describes the health of an individual adapter:

- `healthy`: The adapter is functioning correctly
- `unhealthy`: The adapter is unreachable or has failed

## Health Monitoring

### Manager Health

Each `DatumManager` provides health monitoring:

```dart
// Check health of a specific manager (probes both adapters)
final taskHealth = await Datum.manager<Task>().checkHealth();

// Get the current health from the live status snapshot
final currentHealth = Datum.manager<Task>().currentStatus.health;

// Watch health changes reactively
Datum.manager<Task>().health.listen((health) {
  switch (health.status) {
    case DatumSyncHealth.healthy:
      print('Tasks manager is healthy');
    case DatumSyncHealth.offline:
      print('Tasks manager is offline');
    case DatumSyncHealth.error:
      print('Tasks manager reported an error');
    default:
      print('Tasks manager status: ${health.status.name}');
  }
});
```

### Global Health Monitoring

Monitor health across all managers with `Datum.instance.allHealths`, a `Stream<Map<Type, DatumHealth>>`:

```dart
// Get health status of all managers
final allHealths = await datum.allHealths.first;

allHealths.forEach((entityType, health) {
  print('$entityType: ${health.status.name}');
});

// Watch global health changes
datum.allHealths.listen((healthMap) {
  final errorCount = healthMap.values
      .where((health) => health.status == DatumSyncHealth.error)
      .length;

  if (errorCount > 0) {
    print('Warning: $errorCount managers report errors');
  }
});
```

## Health Checks

### Automatic Health Checks

The health carried by `currentStatus` and the `health` stream is refreshed as the manager operates — during initialization, sync cycles, and connectivity changes.

### Manual Health Checks

Trigger health checks manually:

```dart
// Probe a manager directly
final taskHealth = await Datum.manager<Task>().checkHealth();

// Or gather the latest health of every registered manager at once
final healthMap = await datum.allHealths.first;
final hasErrors = healthMap.values.any((h) => h.status == DatumSyncHealth.error);
```

### Adapter Health

Adapters implement their own health checks. `checkHealth()` on an adapter returns an `AdapterHealthStatus` directly:

```dart
// Local adapter health
final localHealth = await manager.localAdapter.checkHealth();

// Remote adapter health
final remoteHealth = await manager.remoteAdapter.checkHealth();

if (localHealth == AdapterHealthStatus.unhealthy) {
  print('Local storage is failing');
}
```

Custom adapters should override `checkHealth()` to provide a meaningful probe (e.g. check that a database file is accessible, or ping a server endpoint). The default implementation returns `AdapterHealthStatus.healthy`.

## Health Diagnostics

### Health Details

A manager health check reports the overall status plus each adapter's state; combine it with the status snapshot for operational counters:

```dart
final health = await manager.checkHealth();

print(health.describe());
// Health: healthy
//   local adapter:  healthy
//   remote adapter: healthy

print('Status: ${health.status.name}');
print('Local adapter: ${health.localAdapterStatus.name}');
print('Remote adapter: ${health.remoteAdapterStatus.name}');

// Operational counters live on the status snapshot
final snapshot = manager.currentStatus;
print('Pending operations: ${snapshot.pendingOperations}');
print('Failed operations: ${snapshot.failedOperations}');
print('Progress: ${(snapshot.progress * 100).round()}%');
```

### Common Health Issues

**Local Adapter Issues:**
- Database connection failures
- Storage quota exceeded
- File system permissions
- Corruption detection

**Remote Adapter Issues:**
- Network connectivity problems
- Authentication failures
- API rate limiting
- Service unavailability

**Sync Issues:**
- Long-running sync operations
- High conflict rates
- Large pending operation queues
- Memory pressure

## Health-Based Actions

### Automatic Recovery

Configure automatic retries for transient failures:

```dart
final config = DatumConfig(
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    shouldRetry: (error) async => error is NetworkException && error.isRetryable,
    maxRetries: 3,
    backoffStrategy: const ExponentialBackoff(),
  ),
);
```

### Manual Recovery

Implement manual recovery logic:

```dart
Future<void> recoverFromHealthIssues() async {
  final allHealths = await Datum.instance.allHealths.first;

  for (final entry in allHealths.entries) {
    final entityType = entry.key;
    final health = entry.value;

    if (health.status == DatumSyncHealth.error) {
      print('Attempting to recover $entityType...');

      final manager = Datum.managerByType(entityType);

      // Pause, re-probe, and resume the manager
      manager.pauseSync();
      final refreshed = await manager.checkHealth();
      manager.resumeSync();

      print('Re-checked $entityType: ${refreshed.status.name}');
    }
  }
}
```

## Health Metrics

### Performance Metrics

Global sync metrics are exposed through `Datum.instance.metrics` (a `Stream<DatumMetrics>`) and `currentMetrics`:

```dart
final metrics = datum.currentMetrics;

print('Total syncs: ${metrics.totalSyncOperations}');
print('Successful: ${metrics.successfulSyncs}');
print('Failed: ${metrics.failedSyncs}');
print('Conflicts detected: ${metrics.conflictsDetected}');
print('Bytes pushed: ${metrics.totalBytesPushed}');
print('Bytes pulled: ${metrics.totalBytesPulled}');

// Or reactively
datum.metrics.listen((m) {
  final total = m.totalSyncOperations;
  if (total > 0) {
    print('Sync success rate: ${(m.successfulSyncs / total * 100).round()}%');
  }
});
```

### Trend Analysis

Monitor health trends over time:

```dart
class HealthMonitor {
  final List<DatumHealth> _healthHistory = [];

  void recordHealth(DatumHealth health) {
    _healthHistory.add(health);

    // Keep only recent history
    if (_healthHistory.length > 100) {
      _healthHistory.removeAt(0);
    }

    // Analyze trends
    if (_healthHistory.length >= 10) {
      final recentHealth = _healthHistory.sublist(_healthHistory.length - 10);
      final errorCount = recentHealth
          .where((h) => h.status == DatumSyncHealth.error)
          .length;

      if (errorCount > 5) {
        print('Warning: Health deteriorating');
      }
    }
  }
}
```

## Health Alerts

### Alert Configuration

Set up health-based alerts:

```dart
class HealthAlertSystem {
  void setupAlerts() {
    // Monitor all managers
    Datum.instance.allHealths.listen((healthMap) {
      for (final entry in healthMap.entries) {
        final entityType = entry.key;
        final health = entry.value;

        if (health.status == DatumSyncHealth.error) {
          sendAlert(
            title: '$entityType Manager Unhealthy',
            message: health.describe(),
          );
        }
      }
    });
  }

  void sendAlert({
    required String title,
    required String message,
  }) {
    // Send alert via email, Slack, etc.
    print('ALERT: $title - $message');
  }
}
```

### Alert Types

**Critical Alerts:**
- Complete system failure
- Data corruption detected
- Authentication failures

**Warning Alerts:**
- Degraded performance
- High error rates
- Storage capacity warnings

**Info Alerts:**
- Recovery actions taken
- Configuration changes
- Maintenance notifications

## Best Practices

### Health Check Design

1. **Make health checks fast**: Keep checks lightweight to avoid impacting performance
2. **Provide actionable information**: Include specific details for troubleshooting
3. **Use appropriate timeouts**: Don't let health checks hang indefinitely
4. **Check dependencies**: Verify all required services are accessible

### Monitoring Strategy

1. **Monitor continuously**: Set up ongoing health monitoring
2. **Alert on degradation**: Catch issues before they become critical
3. **Automate recovery**: Implement automatic recovery where possible
4. **Log health changes**: Maintain history for trend analysis

### Alert Management

1. **Avoid alert fatigue**: Only alert on actionable issues
2. **Escalate appropriately**: Different severity levels for different issues
3. **Include context**: Provide enough information to diagnose issues
4. **Test alerts**: Ensure alerts work and reach the right people

### Performance Impact

1. **Minimize overhead**: Health checks should not significantly impact performance
2. **Use sampling**: For high-frequency metrics, consider sampling
3. **Cache results**: Cache health check results when appropriate
4. **Async checks**: Run health checks asynchronously to avoid blocking

## Troubleshooting

### Common Health Issues

**Database Connection Issues:**
```dart
// Check local adapter health
final localHealth = await manager.localAdapter.checkHealth();
if (localHealth == AdapterHealthStatus.unhealthy) {
  // Re-initialize the local adapter
  await manager.localAdapter.initialize();
}
```

**Network Connectivity Issues:**
```dart
// Check remote adapter health
final remoteHealth = await manager.remoteAdapter.checkHealth();
if (remoteHealth == AdapterHealthStatus.unhealthy) {
  // Wait for connectivity to recover, then re-check
  await datum.connectivityChecker.onStatusChange
      .where((connected) => connected)
      .first;
  await manager.checkHealth();
}
```

**Sync Performance Issues:**
```dart
// Check for large pending queues
final pendingCount = await manager.getPendingCount(userId);
if (pendingCount > 1000) {
  print('Warning: Large pending queue may cause performance issues');
}
```

### Health Check Debugging

```dart
// Enable detailed logging
final config = DatumConfig(
  enableLogging: true,
  logLevel: LogLevel.debug,
);

// Manually run health checks with timing
final stopwatch = Stopwatch()..start();
final health = await manager.checkHealth();
stopwatch.stop();

print('Health check took ${stopwatch.elapsedMilliseconds}ms');
print(health.describe());
```
