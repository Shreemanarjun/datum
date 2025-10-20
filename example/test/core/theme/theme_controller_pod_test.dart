import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/core/local_storage/app_storage.dart';
import 'package:example/core/local_storage/app_storage_pod.dart';
import 'package:example/core/theme/theme_controller.dart';

void main() {
  group('ThemeModeController Test', () {
    AppStorage appStorage = AppStorage(null);
    setUp(() async {
      await appStorage.init(isTest: true);
    });
    tearDown(() async {
      await appStorage.clearAllData();
    });
    test('expect ThemeMode.system on first time', () {
      final container = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(appStorage)],
      );
      expect(container.read(themecontrollerProvider), ThemeMode.system);
    });

    test(
      'expect ThemeMode.light after change the theme to ThemeMode.light',
      () async {
        final container = ProviderContainer(
          overrides: [appStorageProvider.overrideWithValue(appStorage)],
        );
        expect(container.read(themecontrollerProvider), ThemeMode.system);
        await container
            .read(themecontrollerProvider.notifier)
            .changeTheme(ThemeMode.light);
        expect(container.read(themecontrollerProvider), ThemeMode.light);
      },
    );

    test(
      'expect ThemeMode.dark after change the theme to ThemeMode.light and then ThemeMode.dark',
      () async {
        final container = ProviderContainer(
          overrides: [appStorageProvider.overrideWithValue(appStorage)],
        );
        expect(container.read(themecontrollerProvider), ThemeMode.system);
        await container
            .read(themecontrollerProvider.notifier)
            .changeTheme(ThemeMode.light);
        expect(container.read(themecontrollerProvider), ThemeMode.light);
        await container
            .read(themecontrollerProvider.notifier)
            .changeTheme(ThemeMode.dark);
        expect(container.read(themecontrollerProvider), ThemeMode.dark);
      },
    );

    test('check persistence ThemeMode.light', () async {
      final container = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(appStorage)],
      );
      await appStorage.put(key: 'theme', value: ThemeMode.light.name);
      expect(container.read(themecontrollerProvider), ThemeMode.light);
    });

    test('check persistence ThemeMode.dark', () async {
      final container = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(appStorage)],
      );
      await appStorage.put(key: 'theme', value: ThemeMode.dark.name);
      expect(container.read(themecontrollerProvider), ThemeMode.dark);
    });
    test('check persistence ThemeMode.system', () async {
      final container = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(appStorage)],
      );
      await appStorage.put(key: 'theme', value: ThemeMode.system.name);
      expect(container.read(themecontrollerProvider), ThemeMode.system);
    });
  });
}
