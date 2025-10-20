// ignore_for_file: deprecated_member_use

import 'package:example/features/counter/controller/counter_state_pod.dart';
import 'package:example/shared/riverpod_ext/riverpod_observer/riverpod_obs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'package:example/core/local_storage/app_storage_pod.dart';
import 'package:example/features/counter/view/counter_page.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/pods/internet_checker_pod.dart';

import 'package:example/shared/pods/translation_pod.dart';

import '../../../helpers/helpers.dart';
import '../pod/counter_pod_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CounterPage', () {
    late Box appBox;
    setUp(() async {
      appBox = await Hive.openBox('appBox', bytes: Uint8List(0));
    });
    tearDown(() {
      appBox.clear();
    });
    testWidgets('renders CounterView', (tester) async {
      final translation = AppLocale.en.buildSync();
      final counterPage = const CounterPage(key: ValueKey("counterPage"));
      await tester.pumpApp(
        child: counterPage,
        container: ProviderContainer(
          overrides: [
            enableInternetCheckerPod.overrideWith((ref) => false),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => translation),
          ],
        ),
      );
      expect(counterPage.key, equals(ValueKey("counterPage")));
      expect(
        counterPage,
        isNot(const CounterPage(key: ValueKey("counterPages"))),
      );
      expect(find.byKey(const ValueKey('counterPage')), findsOneWidget);

      expect(find.byType(CounterPage), findsOneWidget);
      expect(find.byType(CounterView), findsOneWidget);
    });

    testWidgets('CounterPage constructor', (tester) async {
      const CounterPage();
    });

    testWidgets('contains Scaffold with CounterAppBar and CounterView', (
      tester,
    ) async {
      final translation = AppLocale.en.buildSync();
      await tester.pumpApp(
        child: const CounterPage(),
        container: ProviderContainer(
          overrides: [
            enableInternetCheckerPod.overrideWith((ref) => false),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => translation),
          ],
        ),
      );
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(CounterAppBarTitle), findsOneWidget);
      expect(find.byType(CounterView), findsOneWidget);
    });
  });

  group('CounterView', () {
    late Box appBox;
    setUp(() async {
      appBox = await Hive.openBox('appBox', bytes: Uint8List(0));
    });
    tearDown(() async {
      await appBox.clear();
    });
    testWidgets('renders current count', (tester) async {
      const state = 42;
      final translation = AppLocale.en.buildSync();
      final container = ProviderContainer(
        overrides: [
          enableInternetCheckerPod.overrideWith((ref) => false),
          appBoxProvider.overrideWithValue(appBox),
          counterPod.overrideWith(
            () => InitialCounterNotifier(initialValue: state),
          ),
          translationsPod.overrideWith((ref) => translation),
        ],
        observers: [TalkerRiverpodObserver()],
      );
      addTearDown(container.dispose);
      await tester.pumpApp(child: const CounterView(), container: container);
      await tester.pumpAndSettle();

      expect(find.text('$state'), findsOneWidget);
    });

    testWidgets('calls increment when increment button is tapped', (
      tester,
    ) async {
      const state = 42;
      final translation = AppLocale.en.buildSync();
      await tester.pumpApp(
        child: const CounterView(),
        container: ProviderContainer(
          overrides: [
            enableInternetCheckerPod.overrideWith((ref) => false),
            appBoxProvider.overrideWithValue(appBox),
            counterPod.overrideWith(
              () => InitialCounterNotifier(initialValue: state),
            ),
            translationsPod.overrideWith((ref) => translation),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('42'), findsNothing);
      expect(find.text('43'), findsOneWidget);
    });

    testWidgets('calls decrement when decrement button is tapped', (
      tester,
    ) async {
      const state = 42;
      final translation = AppLocale.en.buildSync();
      final container = ProviderContainer(
        overrides: [
          enableInternetCheckerPod.overrideWith((ref) => false),
          appBoxProvider.overrideWithValue(appBox),
          counterPod.overrideWith(
            () => InitialCounterNotifier(initialValue: state),
          ),
          translationsPod.overrideWith((ref) => translation),
        ],
      );

      await tester.pumpApp(child: const CounterView(), container: container);

      await tester.runAsync(() async {
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pumpAndSettle();
        expect(find.text('42'), findsNothing);
        expect(find.text('41'), findsOneWidget);
      });
    });
  });

  group('CounterAppBarTitle', () {
    late Box appBox;
    setUp(() async {
      appBox = await Hive.openBox('appBox', bytes: Uint8List(0));
    });
    tearDown(() {
      appBox.clear();
    });
    testWidgets('renders the correct title', (tester) async {
      final translation = AppLocale.en.buildSync();
      await tester.pumpApp(
        container: ProviderContainer(
          overrides: [
            translationsPod.overrideWith((ref) => translation),
            appBoxProvider.overrideWithValue(appBox),
          ],
        ),
        child: Material(child: const CounterAppBarTitle()),
      );
      expect(find.text(translation.counterAppBarTitle), findsOneWidget);
    });
  });
}
