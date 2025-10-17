/// A simple logger for the Datum package.
class DatumLogger {
  final bool enabled;

  DatumLogger({this.enabled = true});

  void info(String message) {
    if (enabled) {
      print('[Datum INFO]: $message');
    }
  }

  void debug(String message) {
    if (enabled) {
      print('[Datum DEBUG]: $message');
    }
  }

  void error(String message, [StackTrace? stackTrace]) {
    if (enabled) {
      print('[Datum ERROR]: $message');
      if (stackTrace != null) {
        print(stackTrace.toString());
      }
    }
  }

  void warn(String message) {
    if (enabled) {
      print('[Datum WARN]: $message');
    }
  }
}
