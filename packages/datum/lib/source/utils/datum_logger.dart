// ignore_for_file: public_member_api_docs, sort_constructors_first

/// Log levels for structured logging with performance awareness.
enum LogLevel {
  /// Most detailed level, typically disabled in production.
  trace(0),

  /// Detailed debugging information.
  debug(1),

  /// General information about system operation.
  info(2),

  /// Warning about potentially harmful situations.
  warn(3),

  /// Error conditions that don't stop the application.
  error(4),

  /// Severe error conditions that may stop the application.
  fatal(5),

  /// Special level for performance-critical operations that should never log.
  off(99);

  const LogLevel(this.value);
  final int value;
}

/// Structured log entry with metadata for better debugging and monitoring.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? category;
  final Map<String, dynamic>? metadata;
  final Object? error;
  final StackTrace? stackTrace;
  final String? operationId;
  final Duration? duration;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.category,
    this.metadata,
    this.error,
    this.stackTrace,
    this.operationId,
    this.duration,
  });

  /// Creates a performance log entry for operation timing.
  factory LogEntry.performance({
    required String operation,
    required Duration duration,
    Map<String, dynamic>? metadata,
    String? operationId,
  }) {
    return LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      message: 'Performance: $operation completed',
      category: 'performance',
      metadata: {
        'operation': operation,
        'duration_ms': duration.inMilliseconds,
        ...?metadata,
      },
      operationId: operationId,
      duration: duration,
    );
  }

  /// Creates a structured log entry for sync operations.
  factory LogEntry.sync({
    required LogLevel level,
    required String message,
    required String userId,
    String? entityId,
    int? itemCount,
    Map<String, dynamic>? metadata,
  }) {
    return LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      category: 'sync',
      metadata: {
        'user_id': userId,
        'entity_id': entityId,
        'item_count': itemCount,
        ...?metadata,
      },
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}] ');
    buffer.write('[${level.name.toUpperCase()}] ');
    if (category != null) buffer.write('[$category] ');
    buffer.write(message);
    if (operationId != null) buffer.write(' (op:$operationId)');
    if (duration != null) buffer.write(' (${duration!.inMilliseconds}ms)');
    if (metadata != null && metadata!.isNotEmpty) {
      buffer.write(' ${metadata.toString()}');
    }
    return buffer.toString();
  }
}

/// Sampling strategy for high-frequency log operations.
abstract class LogSampler {
  /// Determines if a log entry should be emitted based on sampling rules.
  bool shouldLog(LogEntry entry);

  /// Records that a log entry was processed (for rate limiting).
  void recordLog(LogEntry entry) {}
}

/// Time-based sampler that limits logs to a maximum rate.
class RateLimitingSampler implements LogSampler {
  final Duration window;
  final int maxLogsPerWindow;
  final Map<String, List<DateTime>> _logTimes = {};

  RateLimitingSampler({
    required this.window,
    required this.maxLogsPerWindow,
  });

  @override
  bool shouldLog(LogEntry entry) {
    final key = entry.category ?? 'default';
    final now = entry.timestamp;
    final times = _logTimes[key] ?? [];

    // Remove old entries outside the window
    final cutoff = now.subtract(window);
    times.removeWhere((time) => time.isBefore(cutoff));

    // Check if we're under the limit
    if (times.length < maxLogsPerWindow) {
      return true;
    }

    return false;
  }

  @override
  void recordLog(LogEntry entry) {
    final key = entry.category ?? 'default';
    _logTimes[key] ??= [];
    _logTimes[key]!.add(entry.timestamp);
  }
}

/// Count-based sampler that logs every Nth occurrence.
class CountBasedSampler implements LogSampler {
  final int sampleRate;
  final Map<String, int> _counters = {};

  CountBasedSampler({required this.sampleRate});

  @override
  bool shouldLog(LogEntry entry) {
    final key = entry.category ?? 'default';
    final count = (_counters[key] ?? 0) + 1;
    _counters[key] = count;
    return count % sampleRate == 0;
  }

  @override
  void recordLog(LogEntry entry) {
    // Count-based sampling doesn't need to record logs separately
    // as the decision is made in shouldLog
  }
}

/// A pluggable destination for formatted log output.
///
/// Implement this to redirect Datum's logs to any sink (a file, a crash
/// reporter, `dart:developer`, a test buffer…) without subclassing
/// [DatumLogger]. Pass your sink via `DatumLogger(sink: MySink())`.
///
/// The sink receives both the structured [entry] (for routing/filtering on
/// level, category, metadata) and the [formatted] string the logger produced.
abstract interface class DatumLogSink {
  /// Writes a single, already-formatted log [entry].
  void write(LogEntry entry, String formatted);
}

/// The default [DatumLogSink], printing to stdout via `print`.
class ConsoleLogSink implements DatumLogSink {
  /// Creates a console sink.
  const ConsoleLogSink();

  @override
  void write(LogEntry entry, String formatted) {
    // ignore: avoid_print
    print(formatted);
    if (entry.error != null && entry.stackTrace != null) {
      // ignore: avoid_print
      print(entry.stackTrace.toString());
    }
  }
}

/// A [DatumLogSink] that collects entries in memory. Useful for tests.
class CollectingLogSink implements DatumLogSink {
  /// The entries written so far, in order.
  final List<LogEntry> entries = [];

  /// The formatted strings written so far, in order.
  final List<String> messages = [];

  @override
  void write(LogEntry entry, String formatted) {
    entries.add(entry);
    messages.add(formatted);
  }

  /// Clears all collected output.
  void clear() {
    entries.clear();
    messages.clear();
  }
}

/// Enhanced logger for the Datum package with structured logging and performance optimizations.
class DatumLogger {
  final bool enabled;
  final bool colors;
  final LogLevel minimumLevel;
  final Map<String, LogSampler> samplers;
  final bool enablePerformanceLogging;
  final Duration performanceThreshold;

  /// The destination for formatted log output. Defaults to [ConsoleLogSink].
  ///
  /// Kept private (with an optional constructor parameter) so that adding sink
  /// support does not break existing `implements DatumLogger` implementations —
  /// a private field is not part of the class interface.
  final DatumLogSink _sink;

  DatumLogger({
    this.enabled = true,
    this.colors = true,
    this.minimumLevel = LogLevel.info,
    this.samplers = const {},
    this.enablePerformanceLogging = false,
    this.performanceThreshold = const Duration(milliseconds: 100),
    DatumLogSink? sink,
  }) : _sink = sink ?? const ConsoleLogSink();

  /// Logs a structured entry with the specified level.
  void log(LogEntry entry) {
    if (!enabled || entry.level.value < minimumLevel.value) {
      return;
    }

    // Check sampling rules
    final sampler = samplers[entry.category];
    if (sampler != null) {
      if (!sampler.shouldLog(entry)) {
        return;
      }
      sampler.recordLog(entry);
    }

    // Format and output the log entry via the configured sink.
    final formatted = _formatEntry(entry);
    _sink.write(entry, formatted);
  }

  /// Logs a performance operation with timing.
  void logPerformance({
    required String operation,
    required Duration duration,
    Map<String, dynamic>? metadata,
    String? operationId,
  }) {
    if (!enablePerformanceLogging) return;

    final entry = LogEntry.performance(
      operation: operation,
      duration: duration,
      metadata: metadata,
      operationId: operationId,
    );

    // Only log if duration exceeds threshold
    if (duration > performanceThreshold) {
      log(entry);
    }
  }

  /// Logs sync-related operations with structured metadata.
  void logSync({
    required LogLevel level,
    required String message,
    required String userId,
    String? entityId,
    int? itemCount,
    Map<String, dynamic>? metadata,
  }) {
    final entry = LogEntry.sync(
      level: level,
      message: message,
      userId: userId,
      entityId: entityId,
      itemCount: itemCount,
      metadata: metadata,
    );
    log(entry);
  }

  /// Convenience method for info level logging.
  void info(String message, {String? category, Map<String, dynamic>? metadata}) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      message: message,
      category: category,
      metadata: metadata,
    ));
  }

  /// Convenience method for debug level logging.
  void debug(String message, {String? category, Map<String, dynamic>? metadata}) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      message: message,
      category: category,
      metadata: metadata,
    ));
  }

  /// Convenience method for error level logging.
  void error(String message, [StackTrace? stackTrace]) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      message: message,
      stackTrace: stackTrace,
    ));
  }

  /// Convenience method for warning level logging.
  void warn(String message, {String? category, Map<String, dynamic>? metadata}) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.warn,
      message: message,
      category: category,
      metadata: metadata,
    ));
  }

  /// Convenience method for trace level logging.
  void trace(String message, {String? category, Map<String, dynamic>? metadata}) {
    log(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.trace,
      message: message,
      category: category,
      metadata: metadata,
    ));
  }

  String _formatEntry(LogEntry entry) {
    final buffer = StringBuffer();
    buffer.write('[Datum ${entry.level.name.toUpperCase()}]');

    if (entry.category != null) {
      buffer.write('[${entry.category}]');
    }

    buffer.write(': ${entry.message}');

    if (entry.operationId != null) {
      buffer.write(' (op:${entry.operationId})');
    }

    if (entry.duration != null) {
      buffer.write(' (${entry.duration!.inMilliseconds}ms)');
    }

    return buffer.toString();
  }

  DatumLogger copyWith({
    bool? enabled,
    bool? colors,
    LogLevel? minimumLevel,
    Map<String, LogSampler>? samplers,
    bool? enablePerformanceLogging,
    Duration? performanceThreshold,
  }) {
    return DatumLogger(
      enabled: enabled ?? this.enabled,
      colors: colors ?? this.colors,
      minimumLevel: minimumLevel ?? this.minimumLevel,
      samplers: samplers ?? this.samplers,
      enablePerformanceLogging: enablePerformanceLogging ?? this.enablePerformanceLogging,
      performanceThreshold: performanceThreshold ?? this.performanceThreshold,
      // Preserve the sink across copies. Note copyWith deliberately does NOT
      // expose a `sink` parameter: keeping its signature unchanged means an
      // `implements DatumLogger` class overriding copyWith stays valid.
      sink: _sink,
    );
  }

  /// Returns a logger instance suitable for use in worker isolates.
  /// Override this if your logger implementation contains unsendable objects (like ReceivePorts).
  DatumLogger getWorkerLogger() => this;
}
