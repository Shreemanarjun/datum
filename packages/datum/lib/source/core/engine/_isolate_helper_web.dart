import 'dart:async';
import 'dart:convert';

/// Helper for offloading work to a background isolate on web platforms.
///
/// On web, isolates are not supported in the same way as on native platforms.
/// This implementation provides a web-compatible version of IsolateHelper
/// where computeJsonEncode runs directly on the main thread.
class IsolateHelper {
  /// Creates an IsolateHelper for web platforms.
  const IsolateHelper();

  /// Spawns a long-lived isolate for complex, two-way communication.
  ///
  /// This operation is not supported on web and will throw an [UnsupportedError].
  Future<void> spawn<T>(void Function(T message) entryPoint, T message) {
    throw UnsupportedError('Isolates cannot be spawned on the web platform.');
  }

  /// Runs a one-off JSON encoding task directly on the main thread for web.
  ///
  /// On web, there are no isolates, so JSON encoding is performed synchronously.
  Future<String> computeJsonEncode(Object? object) async {
    return jsonEncode(object);
  }

  /// Runs [computation] inline: no isolates on this platform.
  Future<R> run<R>(R Function() computation) async => computation();

  /// Initializes any platform-specific resources. (No-op for web)
  Future<void> initialize() async {}

  /// Disposes of any platform-specific resources. (No-op for web)
  void dispose() {}
}
