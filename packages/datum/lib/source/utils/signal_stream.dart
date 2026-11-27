import 'dart:async';

import 'package:signals_core/signals_core.dart';

/// [signal]'s values as a stream, for callers that consume streams. Every
/// listener gets the current value first, then each change, and the stream
/// ends when the signal is disposed.
Stream<T> watchSignal<T>(ReadonlySignal<T> signal) => Stream<T>.multi(
      (listener) {
        if (signal.disposed) {
          listener.close();
          return;
        }
        final stop = signal.subscribe(listener.add);
        final forget = signal.onDispose(listener.close);
        listener.onCancel = () {
          stop();
          forget();
        };
      },
      isBroadcast: true,
    );

/// The few stream operators the engine needs for its events (state itself
/// lives in signals).
extension EventStream<T> on Stream<T> {
  /// Only the events of type [S].
  Stream<S> whereType<S>() => where((event) => event is S).cast<S>();

  /// [first], then this stream's events.
  Stream<T> startWith(T first) => Stream<T>.multi((listener) {
        listener.add(first);
        final events = listen(listener.add, onError: listener.addError, onDone: listener.close);
        listener.onCancel = events.cancel;
      });

  /// The events of each [window] as one list; an empty window emits nothing.
  /// Whatever is collected when this stream ends is emitted before the end.
  Stream<List<T>> batchedEvery(Duration window) => Stream<List<T>>.multi((listener) {
        var batch = <T>[];
        void flush() {
          if (batch.isEmpty) return;
          listener.add(batch);
          batch = <T>[];
        }

        final ticker = Timer.periodic(window, (_) => flush());
        final events = listen(
          // Not a tear-off: `batch` is replaced on every flush.
          (event) => batch.add(event),
          onError: listener.addError,
          onDone: () {
            ticker.cancel();
            flush();
            listener.close();
          },
        );
        listener.onCancel = () {
          ticker.cancel();
          return events.cancel();
        };
      });
}
