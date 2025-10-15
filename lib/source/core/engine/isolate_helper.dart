import 'dart:isolate';

/// Helper for offloading work to a background isolate.
class IsolateHelper {
  const IsolateHelper();

  Future<Isolate> spawn<T>(void Function(T message) entryPoint, T message) =>
      Isolate.spawn<T>(entryPoint, message);
  Future<void> initialize() async {}
  void dispose() {}
}
