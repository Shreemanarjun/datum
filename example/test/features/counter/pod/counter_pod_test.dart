import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/features/counter/counter.dart';
import 'package:mocktail/mocktail.dart';

abstract class MyAbstract {}

class AbstractwithconstConstructor implements MyAbstract {
  const AbstractwithconstConstructor();
}

class NOConstAbstract implements MyAbstract {}

class InitialCounterNotifier extends CounterNotifier implements Mock {
  final int initialValue;
  InitialCounterNotifier({required this.initialValue});
  @override
  int build() {
    return initialValue;
  }
}

void main() {
  group('CounterNotifier', () {
    test('initial state is 0', () {
      final container = ProviderContainer();
      expect(container.read(counterPod), 0);
    });
    test('initial state is 1', () {
      final container = ProviderContainer(
        overrides: [
          counterPod.overrideWith(
            () => InitialCounterNotifier(initialValue: 1),
          ),
        ],
      );
      expect(container.read(counterPod), 1);
    });
    test('emits [0] on start then [1] when increment is called', () {
      final container = ProviderContainer();
      expect(container.read(counterPod), 0);
      container.read(counterPod.notifier).increment();
      expect(container.read(counterPod), 1);
    });
    test('emits [0] on start then [-1] when decrement is called', () {
      final container = ProviderContainer();
      expect(container.read(counterPod), 0);
      container.read(counterPod.notifier).decrement();
      expect(container.read(counterPod), -1);
    });
    test('expect [2] when increment is called twice', () {
      final container = ProviderContainer();
      expect(container.read(counterPod), 0);
      container.read(counterPod.notifier).increment();
      container.read(counterPod.notifier).increment();
      expect(container.read(counterPod), 2);
    });

    test('with const', () {
      expect(
        const AbstractwithconstConstructor(),
        const AbstractwithconstConstructor(),
      );
    });
    test('without const', () {
      expect(NOConstAbstract(), isNot(equals(NOConstAbstract())));
    });
  });
}
