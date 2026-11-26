import 'dart:async';

/// Emits `read()` initially (unless [includeInitialData] is false) and after
/// every event on [changes].
///
/// Reads are coalesced: change events are batched until the next event-loop
/// turn, and events arriving while a read is in flight trigger at most ONE
/// follow-up read, so a burst of N writes (e.g. a pull) costs a few reads
/// instead of N full re-reads. Stream.multi gives every listener its own
/// change subscription and initial snapshot; the subscription attaches before
/// the first read so no write in that window is missed.
Stream<S> rereadingWatch<S>(
  Stream<Object?> changes,
  Future<S> Function() read, {
  bool includeInitialData = true,
}) {
  return Stream<S>.multi((controller) => _attachRereader(controller, changes, read, includeInitialData));
}

void _attachRereader<S>(
  MultiStreamController<S> controller,
  Stream<Object?> changes,
  Future<S> Function() read,
  bool includeInitialData,
) {
  var busy = false; // a read is scheduled or in flight
  var dirty = false;

  Future<void> run() async {
    try {
      do {
        dirty = false;
        final value = await read();
        if (controller.isClosed) return;
        controller.add(value);
      } while (dirty);
    } catch (e, s) {
      if (!controller.isClosed) controller.addError(e, s);
    } finally {
      busy = false;
    }
  }

  void onChange(Object? _) {
    if (busy) {
      dirty = true;
      return;
    }
    busy = true;
    Timer.run(run);
  }

  final sub = changes.listen(onChange);
  if (includeInitialData) {
    busy = true;
    run();
  }
  controller.onCancel = sub.cancel;
}
