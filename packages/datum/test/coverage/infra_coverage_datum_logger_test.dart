import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

/// Extends (not implements) [LogSampler] so the base class's no-op
/// [LogSampler.recordLog] default is inherited and exercised.
class _PassThroughSampler extends LogSampler {
  int shouldLogCalls = 0;

  @override
  bool shouldLog(LogEntry entry) {
    shouldLogCalls++;
    return true;
  }
}

LogEntry _entry({
  LogLevel level = LogLevel.info,
  String message = 'hello',
  String? category,
  Object? error,
  StackTrace? stackTrace,
}) =>
    LogEntry(
      timestamp: DateTime(2024, 1, 1),
      level: level,
      message: message,
      category: category,
      error: error,
      stackTrace: stackTrace,
    );

List<String> _capturePrints(void Function() body) {
  final printed = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

void main() {
  group('LogSampler default recordLog', () {
    test('is a no-op invoked by DatumLogger after a sampled log', () {
      final sampler = _PassThroughSampler();
      final sink = CollectingLogSink();
      final logger = DatumLogger(samplers: {'sync': sampler}, sink: sink);

      logger.info('synced', category: 'sync');

      expect(sampler.shouldLogCalls, 1);
      expect(sink.entries, hasLength(1));
      expect(sink.entries.single.message, 'synced');
    });

    test('can be called directly without side effects', () {
      final sampler = _PassThroughSampler();
      // The inherited default implementation must not throw.
      sampler.recordLog(_entry());
      expect(sampler.shouldLogCalls, 0);
    });
  });

  group('ConsoleLogSink', () {
    test('prints the stack trace when error and stackTrace are present', () {
      final trace = StackTrace.current;
      final entry = _entry(
        level: LogLevel.error,
        message: 'failed',
        error: StateError('bad state'),
        stackTrace: trace,
      );

      final printed = _capturePrints(
        () => const ConsoleLogSink().write(entry, 'formatted-line'),
      );

      expect(printed, hasLength(2));
      expect(printed.first, 'formatted-line');
      expect(printed.last, trace.toString());
    });

    test('prints only the formatted line without an error', () {
      final printed = _capturePrints(
        () => const ConsoleLogSink().write(_entry(), 'just-the-line'),
      );

      expect(printed, ['just-the-line']);
    });
  });

  group('CollectingLogSink', () {
    test('clear empties collected entries and messages', () {
      final sink = CollectingLogSink();
      sink.write(_entry(message: 'first'), 'formatted-first');
      sink.write(_entry(message: 'second'), 'formatted-second');
      expect(sink.entries, hasLength(2));
      expect(sink.messages, hasLength(2));

      sink.clear();

      expect(sink.entries, isEmpty);
      expect(sink.messages, isEmpty);
    });
  });

  group('DatumLogger.getWorkerLogger', () {
    test('returns the same instance by default', () {
      final logger = DatumLogger(sink: CollectingLogSink());
      expect(logger.getWorkerLogger(), same(logger));
    });
  });
}
