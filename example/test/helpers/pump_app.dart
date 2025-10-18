import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/core/theme/app_theme.dart';
import 'package:example/core/theme/theme_controller.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/pods/translation_pod.dart';
import 'package:spot/spot.dart';

extension PumpApp on WidgetTester {
  Future<void> pumpApp({
    required Widget child,
    ProviderContainer? container,
  }) async {
    await loadAppFonts();
    final newContainer = container ?? ProviderContainer();
    addTearDown(newContainer.dispose);
    return await pumpWidget(
      UncontrolledProviderScope(
        container: newContainer,
        child: FakeApp(widget: child, providerContainer: container),
      ),
    );
  }
}

class FakeApp extends ConsumerWidget {
  final ProviderContainer? providerContainer;
  final Widget widget;
  const FakeApp({super.key, required this.widget, this.providerContainer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.read(themecontrollerProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Themes.theme,
      darkTheme: Themes.darkTheme,
      themeMode: currentTheme,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      locale: ref.watch(translationsPod).$meta.locale.flutterLocale,
      home: widget,
    );
  }
}
