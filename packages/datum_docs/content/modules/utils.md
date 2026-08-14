# Utils Module




The Utils module in Datum provides a collection of general-purpose utility functions and helpers that support various operations across the Datum ecosystem. These utilities aim to simplify common tasks and enhance code reusability.

## Key Components

### DatumConnectivityChecker

Abstract interface for checking network connectivity. Allows Datum to remain platform-agnostic by requiring users to provide concrete implementations.

**Interface Members:**
- `isConnected`: `Future<bool>` getter — checks if device is connected to network
- `onStatusChange`: `Stream<bool>` getter — emits connectivity status changes

**Example Implementation (Flutter):**
```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class MyConnectivityChecker implements DatumConnectivityChecker {
  final _connectivity = Connectivity();

  @override
  Future<bool> get isConnected async =>
      !(await _connectivity.checkConnectivity()).contains(ConnectivityResult.none);

  @override
  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none));
}
```

### DatumLogger

Enhanced logging utility for Datum's internal operations with structured logging, performance monitoring, and sampling capabilities.

**Configuration:**
- `enabled`: Whether logging is active (default: true)
- `colors`: Whether to use colored output (default: true)
- `minimumLevel`: Minimum log level to output (default: LogLevel.info)
- `samplers`: Map of category-specific sampling strategies
- `enablePerformanceLogging`: Whether to log performance metrics (default: false)
- `performanceThreshold`: Minimum duration to log performance (default: 100ms)
- `sink`: Optional `DatumLogSink` destination for formatted output

**Log Levels:**
- `trace`: Most detailed level, typically disabled in production
- `debug`: Detailed debugging information
- `info`: General information about system operation
- `warn`: Warning about potentially harmful situations
- `error`: Error conditions that don't stop the application
- `fatal`: Severe error conditions that may stop the application
- `off`: Special level for performance-critical operations that should never log

**Structured Logging:**
```dart
final logger = DatumLogger();

// Basic logging
logger.info('Operation completed successfully');
logger.error('Failed to sync data', StackTrace.current);

// Structured logging with metadata
logger.log(LogEntry(
  timestamp: DateTime.now(),
  level: LogLevel.info,
  message: 'User login',
  category: 'auth',
  metadata: {'userId': '123', 'method': 'email'},
));

// Performance logging (only emitted when enablePerformanceLogging is on
// and the duration exceeds performanceThreshold)
logger.logPerformance(
  operation: 'sync_user_data',
  duration: Duration(milliseconds: 250),
  metadata: {'userId': '123', 'items': 50},
);

// Sync-specific logging
logger.logSync(
  level: LogLevel.info,
  message: 'Sync completed',
  userId: '123',
  itemCount: 25,
  metadata: {'conflicts': 2},
);
```

**Sampling Strategies:**
```dart
// Rate limiting sampler
final rateLimiter = RateLimitingSampler(
  window: Duration(minutes: 1),
  maxLogsPerWindow: 10,
);

// Count-based sampler (log every Nth occurrence)
final countSampler = CountBasedSampler(sampleRate: 100);

// Configure logger with samplers
final logger = DatumLogger(
  minimumLevel: LogLevel.debug,
  samplers: {
    'performance': rateLimiter,  // Limit performance logs
    'sync': countSampler,        // Sample sync logs
  },
  enablePerformanceLogging: true,
  performanceThreshold: Duration(milliseconds: 50),
);
```

### formatDuration

Top-level utility for formatting time durations in human-readable form.

```dart
print(formatDuration(const Duration(minutes: 15)));                 // "15m"
print(formatDuration(const Duration(seconds: 5, milliseconds: 50))); // "5s 50ms"
print(formatDuration(const Duration(milliseconds: 120)));            // "120ms"
```

### DatumHashGenerator

Generates consistent SHA-256 hashes for data integrity checks — the same hashing the sync engine uses for metadata comparison.

**Methods:**
- `hashEntities(List<T> entities)`: Order-stable hash of a set of entities (sorts by ID first; O(n log n))
- `hashEntitiesUnordered(List<T> entities)`: Order-independent hash (per-entity digests XOR-combined; no sort)

**Usage:**
```dart
const hashGen = DatumHashGenerator();

final tasks = await manager.readAll(userId: userId);
final hash = hashGen.hashEntities(tasks);
print('Content hash: $hash');
```

### DatumRollingHash

An **incrementally maintainable** set hash for change/drift detection. It keeps a 256-bit XOR accumulator of per-entity digests; because XOR is its own inverse, `add` and `remove` are O(1) — no full re-hash per sync cycle.

```dart
final tasks = await manager.readAll(userId: userId);

final rolling = DatumRollingHash()..addAll(tasks);

// On update: swap the old snapshot for the new one
final updated = task.copyWith(title: 'Renamed');
rolling
  ..remove(task)
  ..add(updated);

print(rolling.value); // 64-character hex digest, comparable to a remote's value
```

`datumEntityDigest(map)` computes the canonical 32-byte digest of a single serialized entity, with map keys sorted recursively so the digest is independent of key insertion order.

### IsolateHelper

Utility for offloading work to a background isolate on native platforms (no-op fallbacks exist for web).

**Key Members:**
- `IsolateHelper()`: `const` constructor
- `computeJsonEncode(Object? object)`: Encodes JSON in a background isolate, returning the encoded string
- `spawn(entryPoint, message)`: Spawns a long-lived isolate for two-way communication
- `initialize()` / `dispose()`: Set up and clean up platform-specific resources

**Usage:**
```dart
const isolateHelper = IsolateHelper();
await isolateHelper.initialize();

// Encode a large payload without blocking the UI
final encoded = await isolateHelper.computeJsonEncode(task.toDatumMap());
print('Encoded ${encoded.length} characters');

isolateHelper.dispose();
```

<Info>
For whole-cycle offloading, set `useIsolateSync: true` in `DatumConfig` — the engine then runs the entire synchronization process in a background isolate (your adapters must be sendable to, or able to re-connect from, another isolate).
</Info>
