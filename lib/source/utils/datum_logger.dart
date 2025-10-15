import 'package:flutter/foundation.dart';

/// A simple logger for the Datum package.
class DatumLogger {
  final bool enabled;

  DatumLogger({this.enabled = true});

  void info(String message) {
    if (enabled) {
      debugPrint('[Datum INFO]: $message');
    }
  }

  void debug(String message) {
    if (enabled) {
      debugPrint('[Datum DEBUG]: $message');
    }
  }

  void error(String message, [StackTrace? stackTrace]) {
    if (enabled) {
      debugPrint('[Datum ERROR]: $message');
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    }
  }

  // warn

  void warn(String message) {
    if (enabled) {
      debugPrint('[Datum WARN]: $message');
    }
  }
}
