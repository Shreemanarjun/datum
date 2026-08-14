---




title: ⚡ Performance Troubleshooting
description: Debug and optimize Datum performance issues.
---



Identify and resolve performance bottlenecks in Datum applications.

## Slow Sync Performance

### Issue: Large dataset sync taking too long

**Symptoms:** Sync operations taking minutes instead of seconds

**Diagnostic Steps:**
```dart
// 1. Measure current performance
final stopwatch = Stopwatch()..start();
final result = await manager.synchronize(userId);
stopwatch.stop();
print('Sync took: ${stopwatch.elapsed.inSeconds}s '
    '(${result.syncedCount} synced, ${result.failedCount} failed)');

// 2. Check dataset and queue sizes
final localCount = await manager.count(userId: userId);
final remoteCount =
    await manager.count(source: DataSource.remote, userId: userId);
final pendingOps = await manager.getPendingCount(userId);
print('Local: $localCount, Remote: $remoteCount, Pending ops: $pendingOps');
```

**Optimization Strategies:**
```dart
// Use parallel processing and incremental pulls for large datasets
final config = DatumConfig<Task>(
  syncExecutionStrategy: const ParallelStrategy(
    batchSize: 20, // Process 20 operations concurrently
    failFast: false, // Continue on individual failures
  ),
  // Pull only entities modified since the last sync watermark
  // (requires a remote adapter that mixes in DeltaSyncCapable)
  enableDeltaSync: true,
  deltaSyncOverlap: const Duration(minutes: 5), // clock-skew tolerance
  // Tune the pull batch sizes for your payloads
  remoteSyncBatchSize: 200,
  remoteStreamBatchSize: 100,
);

// Implement selective sync for critical data only
final criticalScope = DatumSyncScope(
  query: DatumQuery(
    filters: [Filter('priority', FilterOperator.greaterThanOrEqual, 3)],
  ),
);
await manager.synchronize(userId, scope: criticalScope);
```

### Issue: Memory spikes during sync

**Symptoms:** App memory usage spikes, potential crashes

**Memory Monitoring:**
```dart
import 'dart:io';

// Track memory usage (resident set size) during sync
final initialRss = ProcessInfo.currentRss;
print('Initial memory: ${initialRss ~/ (1024 * 1024)}MB');

final result = await manager.synchronize(userId);

final finalRss = ProcessInfo.currentRss;
print('Final memory: ${finalRss ~/ (1024 * 1024)}MB');
print('Memory delta: ${(finalRss - initialRss) ~/ (1024 * 1024)}MB');
```

**Memory Optimization:**
```dart
// Process in smaller chunks instead of materializing everything at once
const chunkSize = 50;
final all = await manager.readAll(userId: userId);

for (var i = 0; i < all.length; i += chunkSize) {
  final end = (i + chunkSize < all.length) ? i + chunkSize : all.length;
  final chunk = all.sublist(i, end);
  print('Processing ${chunk.length} items...');

  // Let the GC and event loop breathe between chunks
  await Future<void>.delayed(const Duration(milliseconds: 100));
}
```

## Database Performance Issues

### Issue: Slow local database queries

**Symptoms:** Local read/write operations are slow

**Query Optimization:**
```dart
// 1. Check query execution time
final complexQuery = DatumQuery(
  filters: [
    Filter('isCompleted', FilterOperator.equals, false),
    Filter('priority', FilterOperator.greaterThan, 2),
  ],
  sorting: [SortDescriptor('modifiedAt', descending: true)],
  limit: 100,
);

final stopwatch = Stopwatch()..start();
final results = await manager.query(complexQuery, userId: userId);
stopwatch.stop();
print('Query took: ${stopwatch.elapsed.inMilliseconds}ms');

// 2. Analyze query complexity
print('Filters: ${complexQuery.filters.length}');
print('Sorting: ${complexQuery.sorting.length}');
print('Limit: ${complexQuery.limit}');
```

**Caching Knobs:**
```dart
// The local database is already a fast cache — before adding your own
// layers, tune the real knobs on DatumConfig:
final config = DatumConfig<Task>(
  // Cache local query results (opt-in — cached instances can go stale
  // when data changes via sync/realtime outside the manager)
  enableQueryCache: true,
  maxQueryCacheSize: 200,
  maxRelationshipQueryCacheSize: 200,
  maxEntityExistenceCacheSize: 1000,

  // Skip the O(n) re-hash of the local dataset on idle sync cycles
  // (on by default — disable only if something writes out-of-band)
  enableMetadataHashCache: true,
);
```

### Issue: Remote API rate limiting

**Symptoms:** 429 Too Many Requests errors

**Rate Limiting Solutions:**
```dart
// Retry with exponential backoff
final config = DatumConfig<Task>(
  errorRecoveryStrategy: DatumErrorRecoveryStrategy(
    maxRetries: 5,
    shouldRetry: (error) async =>
        error is NetworkException && error.isRetryable,
    backoffStrategy: const ExponentialBackoff(
      baseDelay: Duration(seconds: 2),
      multiplier: 2.0,
      maxDelay: Duration(minutes: 5),
    ),
  ),
);
```

```dart
// Add request throttling by wrapping your remote adapter
abstract class ThrottledRemoteAdapter extends RemoteAdapter<Task> {
  ThrottledRemoteAdapter(this.inner);

  /// The real adapter being throttled.
  final RemoteAdapter<Task> inner;

  static const _minRequestInterval = Duration(milliseconds: 100);
  DateTime _lastRequestTime = DateTime.now();

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastRequestTime);

    if (timeSinceLastRequest < _minRequestInterval) {
      await Future<void>.delayed(_minRequestInterval - timeSinceLastRequest);
    }

    _lastRequestTime = DateTime.now();
    return inner.readAll(userId: userId, scope: scope);
  }
}
```

## Network Performance

### Issue: High latency sync operations

**Symptoms:** Sync operations delayed by network latency

**Network Optimization:**
```dart
// 1. Check connectivity through the configured checker
final online = await Datum.instance.connectivityChecker.isConnected;
print('Online: $online');

// 2. Measure effective latency against your backend
Future<Duration> measureNetworkLatency() async {
  final sw = Stopwatch()..start();
  await remoteAdapter.isConnected();
  return sw.elapsed;
}

final latency = await measureNetworkLatency();
print('Network latency: ${latency.inMilliseconds}ms');

// 3. Adjust sync strategy based on network quality
final config = DatumConfig<Task>(
  syncExecutionStrategy: latency > const Duration(seconds: 1)
      ? const ParallelStrategy(batchSize: 5) // smaller batches, poor network
      : const ParallelStrategy(batchSize: 25), // larger batches, good network
);
```

### Issue: Large payload transmission failures

**Symptoms:** Sync fails with large datasets due to payload size limits

**Payload Optimization:**
```dart
// Compress data before transmission by wrapping your adapter
abstract class CompressedRemoteAdapter extends RemoteAdapter<Task> {
  CompressedRemoteAdapter(this.inner);

  /// The real adapter being wrapped.
  final RemoteAdapter<Task> inner;

  /// Your compression codec (e.g. gzip from dart:io).
  List<int> compressJson(Map<String, dynamic> json);

  /// Sends the compressed payload to your API.
  Future<void> sendCompressedData(String path, List<int> payload);

  @override
  Future<void> create(Task entity) async {
    final jsonData = entity.toDatumMap(target: MapTarget.remote);
    await sendCompressedData('/tasks', compressJson(jsonData));
  }
}
```

```dart
// Or cap the per-cycle batch size instead of syncing everything at once
await manager.synchronize(
  userId,
  options: const DatumSyncOptions(overrideBatchSize: 10),
);
```

## UI Responsiveness Issues

### Issue: UI freezing during sync

**Symptoms:** App becomes unresponsive during synchronization

**Background Processing Solutions:**
```dart
// Offload the whole sync cycle to a background isolate.
// (Adapters must be sendable / able to re-establish connections.)
final isolateConfig = DatumConfig<Task>(
  useIsolateSync: true,
);

// Or run just the queue processing through an isolate strategy
final strategyConfig = DatumConfig<Task>(
  syncExecutionStrategy: const IsolateStrategy(
    ParallelStrategy(batchSize: 10),
  ),
);
```

```dart
import 'package:flutter/material.dart';

// Show progress indicators driven by manager.onSyncProgress
class SyncProgressWidget extends StatefulWidget {
  const SyncProgressWidget({super.key, required this.manager});

  final DatumManager<Task> manager;

  @override
  State<SyncProgressWidget> createState() => _SyncProgressWidgetState();
}

class _SyncProgressWidgetState extends State<SyncProgressWidget> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.manager.onSyncProgress.listen((event) {
      setState(() => _progress = event.progress);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(value: _progress);
  }
}
```

### Issue: Reactive streams causing UI lag

**Symptoms:** UI updates are slow or choppy

**Stream Optimization:**
```dart
// Skip emissions that would repaint the UI with identical data
final distinctStream = manager
    .watchAll(userId: userId)
    .distinct((prev, next) => prev.length == next.length);

// Rapid-fire remote pushes are already buffered by the engine —
// widen the debounce window instead of debouncing in the UI:
final config = DatumConfig<Task>(
  remoteEventDebounceTime: Duration(milliseconds: 200),
);
```

## Monitoring and Profiling

### Built-in Performance Logging

```dart
// Datum can log any operation that exceeds a duration threshold
final config = DatumConfig<Task>(
  enablePerformanceLogging: true,
  performanceLogThreshold: Duration(milliseconds: 100),
);
```

### Performance Metrics Collection

```dart
class PerformanceMonitor {
  final Map<String, Duration> _operationTimes = {};

  Future<T> measureOperation<T>(
    String operationName,
    Future<T> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      _operationTimes[operationName] = stopwatch.elapsed;
      return result;
    } finally {
      stopwatch.stop();
    }
  }

  void printReport() {
    print('=== Performance Report ===');
    _operationTimes.forEach((name, duration) {
      print('$name: ${duration.inMilliseconds}ms');
    });
  }
}
```



## Best Practices

### 1. Profile Regularly
```dart
// Datum publishes engine-wide metrics as a stream
final sub = Datum.instance.metrics.listen((m) {
  print('Syncs: ${m.totalSyncOperations} '
      '(${m.successfulSyncs} ok / ${m.failedSyncs} failed)');
});
```

### 2. Optimize for Your Use Case
```dart
// For real-time apps: frequent, small syncs
final realTimeConfig = DatumConfig<Task>(
  autoSyncInterval: Duration(minutes: 2),
  syncExecutionStrategy: ParallelStrategy(batchSize: 5),
);

// For batch-processing apps: larger, infrequent syncs
final batchConfig = DatumConfig<Task>(
  autoSyncInterval: Duration(hours: 1),
  syncExecutionStrategy: ParallelStrategy(batchSize: 50),
);
```

### 3. Monitor Resource Usage
```dart
import 'dart:io';

// Local storage footprint per user
final storageBytes = await manager.getStorageSize(userId: userId);
if (storageBytes > 100 * 1024 * 1024) {
  // 100MB
  print('Warning: local store is over 100MB');
}

// Process memory (resident set size)
print('RSS: ${ProcessInfo.currentRss ~/ (1024 * 1024)}MB');
```

---


*For more performance optimization techniques, check the [Advanced Sync Patterns](../guides/advanced_sync) guide.*
