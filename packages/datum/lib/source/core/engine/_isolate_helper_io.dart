import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

/// Helper for offloading work to a background isolate on native platforms.
class IsolateHelper {
  /// Creates an IsolateHelper for native platforms.
  const IsolateHelper();

  /// Spawns a long-lived isolate for complex, two-way communication.
  Future<Isolate> spawn<T>(void Function(T message) entryPoint, T message) => Isolate.spawn<T>(entryPoint, message);

  /// Encodes [object] to JSON on the current isolate.
  ///
  /// Spawning an isolate per call costs more than encoding a single entity
  /// payload, and copying the map into the isolate is already O(size).
  Future<String> computeJsonEncode(Object? object) async => jsonEncode(object);

  /// Initializes any platform-specific resources. (No-op for native)
  Future<void> initialize() async {}

  /// Disposes of any platform-specific resources. (No-op for native)
  void dispose() {}
}
