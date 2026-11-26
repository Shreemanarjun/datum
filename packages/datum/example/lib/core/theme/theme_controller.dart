import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/bootstrap.dart';
import 'package:example/features/settings/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _themeKey = 'theme';
late Box _themeBox;
StreamSubscription<UserSettings?>? _accountTheme;

/// Signed-in account whose settings the theme syncs with; null = local only.
String? _accountUserId;

/// Current app theme: cached in the app's Hive box for instant start-up and
/// synced per account through Datum ([UserSettings]).
final themeMode = signal(ThemeMode.system);

/// Binds [themeMode] to [box] and loads the stored value. Called during init.
void bindThemeStorage(Box box) {
  _themeBox = box;
  themeMode.value =
      ThemeMode.values.asNameMap()[box.get(_themeKey)] ?? ThemeMode.system;
}

/// Follows the signed-in account's [UserSettings], so a theme picked on one
/// device applies on all of them. Call once Datum is initialized.
void syncThemeWithAccount() {
  Supabase.instance.client.auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct()
      .listen((userId) {
    _accountUserId = userId;
    unawaited(_accountTheme?.cancel());
    _accountTheme = userId == null
        ? null
        : Datum.manager<UserSettings>()
            .watchById(userId, userId: userId)
            .listen((settings) {
            if (settings != null) unawaited(_store(settings.themeMode));
          });
  });
}

Future<void> changeTheme(ThemeMode mode) async {
  await _store(mode);
  final userId = _accountUserId;
  if (userId == null) return;
  try {
    final current =
        await Datum.manager<UserSettings>().read(userId, userId: userId);
    await Datum.instance.pushAndSync(
        item: current?.withTheme(mode) ?? UserSettings.of(userId, mode),
        userId: userId);
  } on Object catch (e) {
    // Saved locally and queued; it syncs on the next cycle.
    talker.warning('Theme sync deferred: $e');
  }
}

Future<void> _store(ThemeMode mode) async {
  themeMode.value = mode;
  await _themeBox.put(_themeKey, mode.name);
}
