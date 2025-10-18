import 'dart:async';
import 'dart:typed_data';

import 'package:example/shared/riverpod_ext/riverpod_observer/riverpod_obs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:example/core/local_storage/app_storage_pod.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/pods/internet_checker_pod.dart';
import 'package:example/shared/widget/no_internet_widget.dart';
import 'package:example/shared/pods/translation_pod.dart';
import 'package:spot/spot.dart';
import '../../helpers/pump_app.dart';

class TestInternetStatusNotifier
    extends AutoDisposeStreamNotifier<InternetStatus>
    implements InternetStatusNotifier {
  final Stream<InternetStatus> Function() streamBuild;

  TestInternetStatusNotifier({required this.streamBuild});

  @override
  Stream<InternetStatus> build() {
    return streamBuild.call();
  }

  @override
  void change({required InternetStatus status}) {
    state = AsyncValue.data(status);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('No Internet Widget Test', () {
    late Box appBox;
    setUp(() async {
      appBox = await Hive.openBox('appBox', bytes: Uint8List(0));
    });
    tearDown(() {
      appBox.clear();
    });
    testWidgets('renders the child when internet available ', (tester) async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          enableInternetCheckerPod.overrideWith((ref) => false),
          internetCheckerNotifierPod.overrideWith(
            () => TestInternetStatusNotifier(
              streamBuild: () {
                return Stream.value(InternetStatus.connected);
              },
            ),
          ),
        ],
      );
      await tester.pumpApp(
        child: Scaffold(body: const Text('I am the child').monitorConnection()),
        container: container,
      );
      await tester.pumpAndSettle();
      expect(find.text('I am the child'), findsOneWidget);
      expect(find.text('No Internet Available'), findsNothing);
    });
    testWidgets(
      'renders the no internet widget child when internet is not available ',
      (tester) async {
        final ProviderContainer container = ProviderContainer(
          overrides: [
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
            enableInternetCheckerPod.overrideWith((ref) => false),
            internetCheckerNotifierPod.overrideWith(
              () => TestInternetStatusNotifier(
                streamBuild: () {
                  return Stream.value(InternetStatus.disconnected);
                },
              ),
            ),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: const Text('I am the child').monitorConnection(
              noInternetWidget: const Text('I am no internet child'),
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.text('I am the child'), findsOneWidget);
        expect(find.text('I am no internet child'), findsOneWidget);
      },
    );
    testWidgets(
      'renders the child when internet available without maintaining state ',
      (tester) async {
        final ProviderContainer providerContainer = ProviderContainer(
          overrides: [
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
            enableInternetCheckerPod.overrideWith((ref) => false),
            internetCheckerNotifierPod.overrideWith(
              () => TestInternetStatusNotifier(
                streamBuild: () {
                  return Stream.value(InternetStatus.connected);
                },
              ),
            ),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: const Text('I am the child').monitorConnection(),
          ),
          container: providerContainer,
        );
        await tester.pumpAndSettle();
        expect(find.text('I am the child'), findsOneWidget);
      },
    );
    testWidgets(
      'renders the no internet widget child when internet is not available with no maintained state ',
      (tester) async {
        final ProviderContainer container = ProviderContainer(
          overrides: [
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
            enableInternetCheckerPod.overrideWith((ref) => false),
            internetCheckerNotifierPod.overrideWith(
              () => TestInternetStatusNotifier(
                streamBuild: () {
                  return Stream.value(InternetStatus.disconnected);
                },
              ),
            ),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: const Text('I am the child').monitorConnection(
              noInternetWidget: const Text('I am no internet child'),
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.text('I am the child'), findsOneWidget);
        expect(find.text('I am no internet child'), findsOneWidget);
      },
    );

    testWidgets('renders child on web platform ', (tester) async {
      final ProviderContainer providerContainer = ProviderContainer(
        overrides: [
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          enableInternetCheckerPod.overrideWith((ref) => false),
        ],
      );
      await tester.pumpApp(
        child: Scaffold(
          body: const Text('I am the child', key: ValueKey('child'))
              .monitorConnection(
            noInternetWidget: const Text('I am no internet child'),
          ),
        ),
        container: providerContainer,
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('I am the child'), findsOneWidget);
      expect(find.byKey(const ValueKey('child')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('I am no internet child'), findsNothing);
    });
    testWidgets('renders child only on internet reconnected', (tester) async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          enableInternetCheckerPod.overrideWith((ref) => false),
          internetCheckerNotifierPod.overrideWith(
            () => TestInternetStatusNotifier(
              streamBuild: () async* {
                yield InternetStatus.disconnected;
              },
            ),
          ),
        ],
      );
      await tester.pumpApp(
        child: Scaffold(
          body: const Text('I am the child').monitorConnection(
            noInternetWidget: const Text('I am no internet child'),
          ),
        ),
        container: container,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('I am the child'), findsOneWidget);
      expect(find.text('I am no internet child'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));

      container
          .read(internetCheckerNotifierPod.notifier)
          .change(status: InternetStatus.connected);

      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect(find.text('I am the child'), findsOneWidget);
        expect(find.text('I am no internet child'), findsNothing);
      });
    });

    testWidgets('check no internet pod refreshed on ok clicked on snackbar', (
      tester,
    ) async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          enableInternetCheckerPod.overrideWith((ref) => false),
          internetCheckerNotifierPod.overrideWith(
            () => TestInternetStatusNotifier(
              streamBuild: () async* {
                yield InternetStatus.disconnected;
              },
            ),
          ),
        ],
      );

      await tester.pumpApp(
        child: Material(
          child: const Scaffold(
            body: Text('I am the child'),
          ).monitorConnection(),
        ),
        container: container,
      );

      await tester.pumpAndSettle();

      final childWidget = find.text('I am the child', skipOffstage: false);
      expect(childWidget, findsOneWidget);
      final okButton = find.byKey(
        const ValueKey('OK_BUTTON'),
        skipOffstage: false,
      );
      await tester.ensureVisible(okButton);
      await tester.pumpAndSettle();

      await tester.tap(okButton);
      expect(container.read(internetCheckerNotifierPod).isRefreshing, isTrue);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 500),
      ); // Add a slight delay

      container
          .read(internetCheckerNotifierPod.notifier)
          .change(status: InternetStatus.connected);
      await tester.runAsync(() async {
        await tester.pumpAndSettle(const Duration(milliseconds: 300));

        expect(childWidget, findsOneWidget);
        expect(find.text('No Internet Available'), findsNothing);

        ///  await takeScreenshot();
      });
    });
    testWidgets(
      'check no internet pod refreshed on ok clicked on snackbar when error occurred',
      (tester) async {
        final controller = StreamController<InternetStatus>.broadcast();
        addTearDown(() => controller.close());

        final container = ProviderContainer(
          observers: [TalkerRiverpodObserver()],
          overrides: [
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
            enableInternetCheckerPod.overrideWith((ref) => false),
            internetCheckerNotifierPod.overrideWith(
              () => TestInternetStatusNotifier(
                streamBuild: () => controller.stream,
              ),
            ),
          ],
        );
        addTearDown(() => container.dispose());
        await loadAppFonts();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Material(
                child: const Scaffold(
                  body: Text('I am the child'),
                ).monitorConnection(),
              ),
            ),
          ),
        );

        // Initial pump to build the widget tree
        await tester.pump();

        // Add error to trigger the snackbar
        controller.addError(InternetStatus.disconnected);
        await tester.pumpAndSettle();

        // Find the retry button
        final retryBtn = find.text("Retry");
        expect(retryBtn, findsOneWidget);

        // Add connected status
        controller.add(InternetStatus.connected);
        await tester.pump();

        // Tap the retry button
        await tester.tap(retryBtn);
        await tester.pumpAndSettle();

        // Verify the state
        final provider = container.read(internetCheckerNotifierPod);
        expect(provider.isRefreshing, true);

        await takeScreenshot();
      },
    );
  });
}
