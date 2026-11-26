import 'package:example/features/theme_segmented_btn/view/theme_segmented_btn.dart';
import 'package:example/shared/translations.dart';
import 'package:example/shared/widget/app_locale_popup.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Theme and language preferences, and sign-out (the router returns to
/// login on its own).
class SettingsPage extends SignalWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title:
            Text(translations.value.settingsTitle, style: theme.textTheme.h4),
        backgroundColor: theme.colorScheme.background,
        elevation: 0,
        actions: const [AppLocalePopUp(), SizedBox(width: 8)],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 24,
          children: [
            const ThemeSegmentedBtn(),
            ShadButton.destructive(
              leading: const Icon(LucideIcons.logOut, size: 16),
              onPressed: () => Supabase.instance.client.auth.signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
