import 'dart:convert';

class IsolateHelper {
  const IsolateHelper();

  Future<String> computeJsonEncode(Object? object) async {
    // On unsupported platforms, run synchronously on the main thread.
    return jsonEncode(object);
  }

  /// Runs [computation] inline: no isolates on this platform.
  Future<R> run<R>(R Function() computation) async => computation();

  /// Initializes any platform-specific resources. (No-op for unsupported)
  Future<void> initialize() async {}

  /// Disposes of any platform-specific resources. (No-op for unsupported)
  void dispose() {}
}
