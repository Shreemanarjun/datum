import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

const _themeKey = 'theme';
late Box _themeBox;

/// Current app theme, persisted in the app's Hive box.
final themeMode = signal(ThemeMode.system);

/// Binds [themeMode] to [box] and loads the stored value. Called during init.
void bindThemeStorage(Box box) {
  _themeBox = box;
  themeMode.value =
      ThemeMode.values.asNameMap()[box.get(_themeKey)] ?? ThemeMode.system;
}

Future<void> changeTheme(ThemeMode mode) async {
  themeMode.value = mode;
  await _themeBox.put(_themeKey, mode.name);
}
