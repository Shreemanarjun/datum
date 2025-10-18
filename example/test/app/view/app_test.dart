import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:example/core/local_storage/app_storage_pod.dart';
import 'package:example/features/counter/counter.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/pods/internet_checker_pod.dart';
import 'package:example/shared/pods/translation_pod.dart';

import '../../helpers/pump_app.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Box appBox;
  setUp(() async {
    appBox = await Hive.openBox('appBox', bytes: Uint8List(0));
  });
  tearDown(() {
    appBox.clear();
  });
  group('App', () {
    testWidgets('renders CounterPage', (tester) async {
      final language = await AppLocale.en.build();
      final container = ProviderContainer(
        overrides: [
          enableInternetCheckerPod.overrideWith((ref) => false),
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => language),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpApp(child: const CounterPage(), container: container);
      expect(find.byType(CounterPage), findsOneWidget);
    });
  });
}
