import 'dart:typed_data';

import 'package:example/core/theme/theme_controller.dart';
import 'package:example/features/settings/settings_page.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Mirrors App: theme and locale come from the global signals.
Widget _app() => SignalBuilder(
      builder: (_) => ShadApp(
        themeMode: themeMode.value,
        theme: ShadThemeData(
          brightness: Brightness.light,
          colorScheme: const ShadSlateColorScheme.light(),
        ),
        darkTheme: ShadThemeData(
          brightness: Brightness.dark,
          colorScheme: const ShadSlateColorScheme.dark(),
        ),
        locale: translations.value.$meta.locale.flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SettingsPage(),
      ),
    );

Set<ThemeMode> _selected(WidgetTester tester) => tester
    .widget<SegmentedButton<ThemeMode>>(find.byType(SegmentedButton<ThemeMode>))
    .selected;

void main() {
  late Box box;

  setUp(() async {
    box = await Hive.openBox('settings_test', bytes: Uint8List(0));
    translations.value = AppLocale.en.buildSync();
  });

  tearDown(() => box.close());

  test('theme storage falls back to system for missing or unknown values',
      () async {
    bindThemeStorage(box);
    expect(themeMode.value, ThemeMode.system);

    await box.put('theme', 'neon');
    bindThemeStorage(box);
    expect(themeMode.value, ThemeMode.system);

    await box.put('theme', 'light');
    bindThemeStorage(box);
    expect(themeMode.value, ThemeMode.light);
  });

  testWidgets('user switches theme and language; theme persists',
      (tester) async {
    await box.put('theme', 'dark');
    bindThemeStorage(box);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Stored theme is restored and shown.
    expect(find.text('Settings'), findsOneWidget);
    expect(_selected(tester), {ThemeMode.dark});
    expect(ShadTheme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.dark);

    // Light: signal, UI and storage all follow.
    await tester.tap(find.byIcon(Icons.light_mode));
    await tester.pumpAndSettle();
    expect(themeMode.value, ThemeMode.light);
    expect(_selected(tester), {ThemeMode.light});
    expect(box.get('theme'), 'light');
    expect(ShadTheme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.light);

    // System.
    await tester.tap(find.byIcon(Icons.brightness_auto));
    await tester.pumpAndSettle();
    expect(_selected(tester), {ThemeMode.system});
    expect(box.get('theme'), 'system');

    // A fresh bind (app restart) reads the persisted value.
    themeMode.value = ThemeMode.dark;
    bindThemeStorage(box);
    expect(themeMode.value, ThemeMode.system);

    // Locale popup: English is selected; switch to Spanish.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected en')), findsOneWidget);
    expect(find.byKey(const ValueKey('unselected es')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('selected en')),
            matching: find.byIcon(Icons.check)),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unselected es')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(translations.value.$meta.locale, AppLocale.es);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);

    // And back to English.
    await tester.tap(find.text('Spanish'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected es')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unselected en')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(translations.value.$meta.locale, AppLocale.en);
    expect(find.text('Settings'), findsOneWidget);

    // Theme stayed persisted through locale changes.
    expect(box.get('theme'), 'system');
  });
}
