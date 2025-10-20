import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:example/features/counter/counter.dart';

/// This provider holds CounternNotifier
final counterPod = NotifierProvider<CounterNotifier, int>(
  CounterNotifier.new,
  name: 'counterPod',
);
