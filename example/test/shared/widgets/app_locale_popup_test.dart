import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:example/core/local_storage/app_storage_pod.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/pods/internet_checker_pod.dart';
import 'package:example/shared/widget/app_locale_popup.dart';
import 'package:example/shared/pods/translation_pod.dart';
import 'package:spot/spot.dart';

import '../../helpers/pump_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('App Locale Popup Test', () {
    late Box appBox;
    setUp(() async {
      appBox = await Hive.openBox('appBox', bytes: Uint8List(0));
    });
    tearDown(() {
      appBox.clear();
    });
    testWidgets(
        'renders Applocalepopup within default English should be selected ',
        (tester) async {
      final translation = AppLocale.en.buildSync();
      final container = ProviderContainer(
        overrides: [
          enableInternetCheckerPod.overrideWith(
            (ref) => false,
          ),
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith(
            (ref) => translation,
          )
        ],
      );

      await tester.pumpApp(
        child: const Scaffold(
          body: AppLocalePopUp(),
        ),
        container: container,
      );
      expect(find.byType(AppLocalePopUp), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text("English"));
        await tester.pump();
      });

      expect(
        find.byIcon(
          Icons.check,
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          SelectedLocaleItem,
          'English',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    });
    testWidgets('renders Applocalepopup within Spanish if selected Spanish ',
        (tester) async {
      tester.view.physicalSize = const Size(1125, 1800);
      final translation = AppLocale.en.buildSync();
      final container = ProviderContainer(
        overrides: [
          enableInternetCheckerPod.overrideWith(
            (ref) => false,
          ),
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith(
            (ref) => translation,
          )
        ],
      );
      await tester.pumpApp(
        child: const Scaffold(
          body: AppLocalePopUp(),
        ),
        container: container,
      );
      await tester.pumpAndSettle();
      spot<AppLocalePopUp>().existsAtLeastOnce();
      await act.tap(spotIcon(Icons.arrow_drop_down));
      spot<SelectedLocaleItem>().spotText("English").existsAtLeastOnce();
      final spanishitem = spot<UnselectedLocaleItem>().spotText("Spanish");
      spanishitem.existsAtLeastOnce();

      await tester.pumpAndSettle();

      await act.tap(spanishitem);

      await tester.pumpAndSettle();

      spotText("Spanish").existsAtLeastOnce();
      spotText("English").doesNotExist();

      await tester.pumpAndSettle();

      await act.tap(spotIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      spot<SelectedLocaleItem>().spotText("Spanish").existsAtLeastOnce();
    });
  });
}
