import 'dart:async';

import 'package:signals_core/signals_core.dart';

/// A mixin to provide disposable behavior to a class.
///
/// It manages a disposed state, and can automatically handle closing
/// [StreamController]s, disposing signals and cancelling
/// [StreamSubscription]s upon disposal.
mixin Disposable {
  bool _disposed = false;

  /// Returns `true` if the object has been disposed.
  bool get isDisposed => _disposed;

  final List<StreamController> _managedControllers = [];
  final List<StreamSubscription> _managedSubscriptions = [];
  final List<ReadonlySignal<Object?>> _managedSignals = [];

  /// Registers a signal to be disposed on dispose.
  void manageSignal(ReadonlySignal<Object?> signal) {
    _managedSignals.add(signal);
  }

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
    // First and at once: a disposed signal is how work in flight sees that
    // its owner is gone.
    for (final signal in _managedSignals) {
      signal.dispose();
    }
    await Future.wait([
      ..._managedControllers.map((c) async => await c.close()),
      ..._managedSubscriptions.map((s) async => await s.cancel()),
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
