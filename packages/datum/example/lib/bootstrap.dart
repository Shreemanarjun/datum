// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:talker_flutter/talker_flutter.dart';
import 'package:example/isolate_logger.dart';
import 'package:datum/source/utils/datum_logger.dart' as datum_logger;

// coverage:ignore-file

/// This `talker` global variable used for logging and accessible
///  to other classed or function
// coverage:ignore-file

final talker = TalkerFlutter.init(
  settings: TalkerSettings(
    // maxHistoryItems: null,
    useConsoleLogs: !kReleaseMode,
    enabled: !kReleaseMode,
  ),
);

/// Isolate logger that wraps the global talker for cross-isolate logging
/// This should be accessed carefully to avoid multiple instances
IsolateLogger? _isolateLogger;

/// Get the global isolate logger, creating it if necessary
IsolateLogger get isolateLogger {
  _isolateLogger ??= IsolateLogger(_TalkerDatumLogger(talker));
  return _isolateLogger!;
}

/// Private class that adapts Talker to DatumLogger interface
class _TalkerDatumLogger implements datum_logger.DatumLogger {
  final Talker _talker;

  _TalkerDatumLogger(this._talker);

  @override
  bool get enabled => _talker.settings.enabled;

  @override
  bool get colors => true; // Talker handles colors

  @override
  datum_logger.LogLevel get minimumLevel =>
      datum_logger.LogLevel.trace; // Talker handles all levels

  @override
  Map<String, datum_logger.LogSampler> get samplers =>
      {}; // Not used with Talker

  @override
  bool get enablePerformanceLogging => false; // Not used with Talker

  @override
  Duration get performanceThreshold => Duration.zero; // Not used with Talker

  @override
  void log(datum_logger.LogEntry entry) {
    final message = _formatEntry(entry);
    switch (entry.level) {
      case datum_logger.LogLevel.trace:
      case datum_logger.LogLevel.debug:
        _talker.debug(message);
        break;
      case datum_logger.LogLevel.info:
        _talker.info(message);
        break;
      case datum_logger.LogLevel.warn:
        _talker.warning(message);
        break;
      case datum_logger.LogLevel.error:
      case datum_logger.LogLevel.fatal:
        _talker.error(message, entry.stackTrace);
        break;
      case datum_logger.LogLevel.off:
        // Don't log
        break;
    }
  }

  @override
  void logPerformance({
    required String operation,
    required Duration duration,
    Map<String, dynamic>? metadata,
    String? operationId,
  }) {
    // Not implemented for Talker
  }

  @override
  void logSync({
    required datum_logger.LogLevel level,
    required String message,
    required String userId,
    String? entityId,
    int? itemCount,
    Map<String, dynamic>? metadata,
  }) {
    final entry = datum_logger.LogEntry.sync(
      level: level,
      message: message,
      userId: userId,
      entityId: entityId,
      itemCount: itemCount,
      metadata: metadata,
    );
    log(entry);
  }

  @override
  void debug(String message,
      {String? category, Map<String, dynamic>? metadata}) {
    _talker.debug(message);
  }

  @override
  void error(String message, [StackTrace? stackTrace]) {
    _talker.error(message, stackTrace);
  }

  @override
  void info(String message,
      {String? category, Map<String, dynamic>? metadata}) {
    _talker.info(message);
  }

  @override
  void warn(String message,
      {String? category, Map<String, dynamic>? metadata}) {
    _talker.warning(message);
  }

  @override
  void trace(String message,
      {String? category, Map<String, dynamic>? metadata}) {
    _talker.debug('TRACE: $message');
  }

  @override
  _TalkerDatumLogger copyWith({
    bool? enabled,
    bool? colors,
    datum_logger.LogLevel? minimumLevel,
    Map<String, datum_logger.LogSampler>? samplers,
    bool? enablePerformanceLogging,
    Duration? performanceThreshold,
  }) {
    return _TalkerDatumLogger(_talker);
  }

  String _formatEntry(datum_logger.LogEntry entry) {
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

  @override
  datum_logger.DatumLogger getWorkerLogger() => this;
}

/// Replaces the splash tree with the app built by [builder].
Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };
  runApp(await builder());
}
