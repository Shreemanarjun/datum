import 'dart:async';

import 'package:datum/source/utils/signal_stream.dart';
import 'package:signals_core/signals_core.dart';
import 'package:test/test.dart';

/// The engine keeps its state in signals and its events in streams. These
/// are the few bridges and operators it uses between the two.
// Scenarios: state.streams (packages/datum/doc/SYNC_SCENARIOS.md)
void main() {
  test('watchSignal gives every listener the current value, then each change, and ends with the signal', () async {
    final count = signal(1);
    final early = <int>[];
    final late = <int>[];
    var earlyDone = false;
    final stream = watchSignal(count);
    final first = stream.listen(early.add, onDone: () => earlyDone = true);
    count.value = 2;
    await Future<void>.delayed(Duration.zero);
    // The same stream can be listened to again; a late listener starts from
    // the value as it is now.
    final second = stream.listen(late.add);
    count.value = 3;
    count.value = 3; // no change, no event
    await Future<void>.delayed(Duration.zero);
    expect(early, [1, 2, 3]);
    expect(late, [2, 3]);

    await second.cancel();
    count.value = 4;
    await Future<void>.delayed(Duration.zero);
    expect(late, [2, 3], reason: 'a cancelled listener hears nothing more');
    expect(early.last, 4);

    count.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(earlyDone, isTrue);
    expect(await watchSignal(count).toList(), isEmpty, reason: 'a disposed signal has nothing left to say');
    await first.cancel();
  });

  test('batchedEvery emits what each window collected, and nothing for an empty one', () async {
    final source = StreamController<int>.broadcast();
    final batches = <List<int>>[];
    final sub = source.stream.batchedEvery(const Duration(milliseconds: 20)).listen(batches.add);
    source
      ..add(1)
      ..add(2);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    source.add(3);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(batches, [
      [1, 2],
      [3],
    ]);
    // What is still collected when the source ends is not lost.
    source.add(4);
    await source.close();
    await Future<void>.delayed(Duration.zero);
    expect(batches.last, [4]);
    await sub.cancel();
  });

  test('startWith and whereType', () async {
    expect(await Stream.fromIterable([2, 3]).startWith(1).toList(), [1, 2, 3]);
    expect(await Stream<Object>.fromIterable([1, 'a', 2, 'b']).whereType<String>().toList(), ['a', 'b']);
  });
}
