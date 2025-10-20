import 'dart:async';

/// A mixin to provide disposable behavior to a class.
///
/// It manages a disposed state, and can automatically handle closing
/// [StreamController]s and cancelling [StreamSubscription]s upon disposal.
mixin Disposable {
  bool _disposed = false;

  /// Returns `true` if the object has been disposed.
  bool get isDisposed => _disposed;

  final List<StreamController> _managedControllers = [];
  final List<StreamSubscription> _managedSubscriptions = [];

  /// Registers a [StreamController] to be automatically closed on dispose.
  void manageController(StreamController controller) {
    _managedControllers.add(controller);
  }

  /// Registers a [StreamSubscription] to be automatically cancelled on dispose.
  void manageSubscription(StreamSubscription subscription) {
    _managedSubscriptions.add(subscription);
  }

  /// Marks the object as disposed and cleans up managed resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      ..._managedControllers.map((c) => c.close()),
      ..._managedSubscriptions.map((s) => s.cancel()),
    ]);
  }

  /// Throws a [StateError] if the object has been disposed.
  ///
  /// This is useful at the beginning of public methods to prevent use after dispose.
  void ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'Cannot use a disposed $runtimeType. This object has been disposed and can no longer be used.',
      );
    }
  }
}
