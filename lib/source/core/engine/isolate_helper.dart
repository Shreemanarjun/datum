import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

/// Helper for offloading work to a background isolate.
class IsolateHelper {
  const IsolateHelper();

  /// Spawns a long-lived isolate for complex, two-way communication.
  Future<Isolate> spawn<T>(void Function(T message) entryPoint, T message) => Isolate.spawn<T>(entryPoint, message);

  /// Runs a one-off JSON encoding task in a background isolate.
  ///
  /// This is ideal for preventing UI jank when encoding large objects.
  Future<String> computeJsonEncode(Object? object) {
    return Isolate.run(() => jsonEncode(object));
  }

  Future<void> initialize() async {}
  void dispose() {}
}
