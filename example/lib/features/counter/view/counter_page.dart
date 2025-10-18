import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:example/features/counter/controller/counter_state_pod.dart';
import 'package:example/features/theme_segmented_btn/view/theme_segmented_btn.dart';
import 'package:example/shared/widget/app_locale_popup.dart';
import 'package:example/shared/pods/translation_pod.dart';

@RoutePage(deferredLoading: true)
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  @override
  Widget build(BuildContext context) {
    return const CounterView();
  }
}

class CounterView extends StatelessWidget {
  const CounterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const CounterAppBarTitle(),
        actions: const [AppLocalePopUp()],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [CounterText(), ThemeSegmentedBtn()],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Consumer(
            builder: (context, ref, child) {
              return FloatingActionButton(
                heroTag: 'add',
                onPressed: () => ref.read(counterPod.notifier).increment(),
                child: const Icon(Icons.add),
              );
            },
          ),
          const SizedBox(height: 8),
          Consumer(
            builder: (context, ref, child) {
              return FloatingActionButton(
                heroTag: 'subtract',
                onPressed: () => ref.read(counterPod.notifier).decrement(),
                child: const Icon(Icons.remove),
              );
            },
          ),
        ],
      ),
    );
  }
}

class CounterAppBarTitle extends ConsumerWidget {
  const CounterAppBarTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsPod);
    return Text(t.counterAppBarTitle);
  }
}

class CounterText extends ConsumerWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = ref.watch(counterPod);
    return Text('$count', style: theme.textTheme.displayLarge);
  }
}
