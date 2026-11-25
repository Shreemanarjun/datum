import 'package:flutter/material.dart';
import 'package:example/core/theme/theme_controller.dart';
import 'package:signals_flutter/signals_flutter.dart';

///This class provider segmented button which can be used
///for getting current theme and switching theme
class ThemeSegmentedBtn extends SignalWidget {
  const ThemeSegmentedBtn({super.key});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton(
      segments: const <ButtonSegment<ThemeMode>>[
        ButtonSegment<ThemeMode>(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto),
        ),
      ],
      selected: {themeMode.value},
      onSelectionChanged: (modes) => changeTheme(modes.first),
      style: const ButtonStyle(
          maximumSize: WidgetStatePropertyAll(Size.fromWidth(12))),
    );
  }
}
