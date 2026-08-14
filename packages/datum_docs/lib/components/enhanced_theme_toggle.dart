import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

/// A script component that applies theme immediately on page load to prevent flash
class ThemeScript extends StatelessComponent {
  const ThemeScript({super.key});

  @override
  Component build(BuildContext context) {
    return script(
      content: '''
        (function() {
          // Theme initialization
          try {
            var storage = window.localStorage;
            var storageData = storage.getItem('enhanced_theme_toggle_cache');
            var themeValue = 'light'; // default

            if (storageData) {
              var data = JSON.parse(storageData);
              var themeString = data.theme;
              var timestamp = data.timestamp;
              var now = Date.now();

              // Check if cache is not expired (24 hours)
              if (themeString && timestamp && (now - timestamp) < 86400000) {
                if (themeString === 'dark') {
                  themeValue = 'dark';
                } else if (themeString === 'light') {
                  themeValue = 'light';
                } else if (themeString === 'auto') {
                  // Check system preference
                  themeValue = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
                }
              }
            } else {
              // No cached preference, check system preference
              themeValue = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
            }

            // Apply theme immediately
            document.documentElement.setAttribute('data-theme', themeValue);
          } catch (e) {
            // Fallback to system preference
            var prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
            document.documentElement.setAttribute('data-theme', prefersDark ? 'dark' : 'light');
          }


        })();
      ''',
    );
  }
}

/// An enhanced theme toggle button with auto, dark, and light options.
/// Uses caching similar to CacheManager for theme preferences.
@client
class EnhancedThemeToggle extends StatefulComponent {
  const EnhancedThemeToggle({super.key});

  @override
  State<EnhancedThemeToggle> createState() => EnhancedThemeToggleState();
}

class EnhancedThemeToggleState extends State<EnhancedThemeToggle> {
  ThemeMode _currentMode = ThemeMode.auto;
  bool _isInitialized = false;
  bool _isDropdownOpen = false;

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _isInitialized = true;
      return;
    }

    // Apply theme immediately to prevent flash
    _initializeTheme();
    _isInitialized = true;
  }

  void _initializeTheme() {
    // Load cached theme preference
    final cachedTheme = _loadCachedTheme();
    if (cachedTheme != null) {
      _currentMode = cachedTheme;
    } else {
      // Check system preference for auto mode
      final prefersDark = web.window.matchMedia('(prefers-color-scheme: dark)').matches;
      _currentMode = prefersDark ? ThemeMode.dark : ThemeMode.light;
    }

    // Apply theme synchronously before any rendering
    _applyThemeImmediately();
  }

  void _applyThemeImmediately() {
    if (!kIsWeb) return;

    final themeValue = switch (_currentMode) {
      ThemeMode.auto => web.window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
    };

    // Apply immediately to prevent flash
    web.document.documentElement?.setAttribute('data-theme', themeValue);
  }

  ThemeMode? _loadCachedTheme() {
    try {
      final storage = web.window.localStorage;
      final storageData = storage.getItem(_themeStorageKey);
      if (storageData == null) return null;

      final data = jsonDecode(storageData) as Map<String, dynamic>;
      final themeString = data['theme'] as String?;
      final timestamp = data['timestamp'] as int?;

      if (themeString == null || timestamp == null) return null;

      // Check if cache is expired (24 hours)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > _cacheDuration.inMilliseconds) {
        storage.removeItem(_themeStorageKey);
        return null;
      }

      return ThemeMode.values.firstWhere(
        (mode) => mode.name == themeString,
        orElse: () => ThemeMode.auto,
      );
    } catch (e) {
      print('EnhancedThemeToggle: Error loading cached theme: $e');
      return null;
    }
  }

  void _saveCachedTheme(ThemeMode mode) {
    try {
      final storage = web.window.localStorage;
      final data = {
        'theme': mode.name,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      storage.setItem(_themeStorageKey, jsonEncode(data));
      print('EnhancedThemeToggle: Cached theme preference: ${mode.name}');
    } catch (e) {
      print('EnhancedThemeToggle: Error saving cached theme: $e');
    }
  }

  void _applyTheme() {
    if (!kIsWeb) return;

    final themeValue = switch (_currentMode) {
      ThemeMode.auto => web.window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
    };

    web.document.documentElement!.setAttribute('data-theme', themeValue);
  }

  @override
  Component build(BuildContext context) {
    if (!_isInitialized) {
      return div(classes: 'enhanced-theme-toggle-container', [
        div(classes: 'theme-dropdown', [Component.text('...')]),
      ]);
    }

    final currentIcon = switch (_currentMode) {
      ThemeMode.auto => MonitorIcon(size: 16),
      ThemeMode.dark => MoonIcon(size: 16),
      ThemeMode.light => SunIcon(size: 16),
    };

    final currentLabel = switch (_currentMode) {
      ThemeMode.auto => 'Auto',
      ThemeMode.dark => 'Dark',
      ThemeMode.light => 'Light',
    };

    return div(
      classes: 'enhanced-theme-toggle-container',
      styles: !kIsWeb ? Styles(visibility: Visibility.hidden) : null,
      [
        div(
          classes:
              'theme-dropdown ${_isDropdownOpen ? 'open' : ''} ${ThemeMode.auto == _currentMode
                  ? 'auto'
                  : ThemeMode.dark == _currentMode
                  ? 'dark'
                  : 'light'}',
          [
            // Current selection display
            div(
              classes: 'dropdown-trigger',
              events: events(
                onClick: () => _toggleDropdown(),
              ),
              [
                currentIcon,
                span(classes: 'theme-label', [Component.text(currentLabel)]),
                ChevronDownIcon(size: 14),
              ],
            ),
            // Dropdown options (only shown when open)
            if (_isDropdownOpen) ...[
              // Backdrop blur
              div(
                classes: 'dropdown-backdrop',
                events: events(
                  onClick: () => _closeDropdown(),
                ),
                [],
              ),
              // Options container
              div(classes: 'dropdown-options', [
                // Auto option
                div(
                  classes: 'dropdown-option ${ThemeMode.auto == _currentMode ? 'active' : ''}',
                  events: events(
                    onClick: () => _selectTheme(ThemeMode.auto),
                  ),
                  [
                    MonitorIcon(size: 16),
                    span(classes: 'theme-label', [Component.text('Auto')]),
                  ],
                ),
                // Dark option
                div(
                  classes: 'dropdown-option ${ThemeMode.dark == _currentMode ? 'active' : ''}',
                  events: events(
                    onClick: () => _selectTheme(ThemeMode.dark),
                  ),
                  [
                    MoonIcon(size: 16),
                    span(classes: 'theme-label', [Component.text('Dark')]),
                  ],
                ),
                // Light option
                div(
                  classes: 'dropdown-option ${ThemeMode.light == _currentMode ? 'active' : ''}',
                  events: events(
                    onClick: () => _selectTheme(ThemeMode.light),
                  ),
                  [
                    SunIcon(size: 16),
                    span(classes: 'theme-label', [Component.text('Light')]),
                  ],
                ),
              ]),
            ],
          ],
        ),
      ],
    );
  }

  void _toggleDropdown() {
    setState(() {
      _isDropdownOpen = !_isDropdownOpen;
    });
  }

  void _closeDropdown() {
    setState(() {
      _isDropdownOpen = false;
    });
  }

  void _selectTheme(ThemeMode mode) {
    setState(() {
      _currentMode = mode;
      _isDropdownOpen = false;
    });
    _applyTheme();
    _saveCachedTheme(_currentMode);
  }

  @css
  static List<StyleRule> get styles => [
    css('.enhanced-theme-toggle-container', [
      css('&').styles(
        display: Display.inlineBlock,
        raw: {'position': 'relative'},
      ),
    ]),
    css('.theme-dropdown', [
      css('&').styles(
        raw: {'position': 'relative', 'display': 'inline-block', 'min-width': '120px'},
      ),
    ]),
    css('.dropdown-trigger', [
      css('&').styles(
        display: Display.flex,
        padding: Padding.symmetric(horizontal: 12.px, vertical: 8.px),
        border: Border.all(color: Color('var(--content-hr)'), width: 1.px, style: BorderStyle.solid),
        radius: BorderRadius.circular(8.px),
        cursor: Cursor.pointer,
        transition: Transition('all', duration: 150.ms),
        justifyContent: JustifyContent.spaceBetween,
        alignItems: AlignItems.center,
        color: Color('var(--text)'),
        fontSize: 0.875.rem,
        fontWeight: FontWeight.w500,
        backgroundColor: Color('var(--background)'),
        raw: {'box-shadow': '0 1px 3px color-mix(in srgb, var(--text) 10%, transparent)', 'gap': '8px'},
      ),
      css('&:hover').styles(
        backgroundColor: Color('color-mix(in srgb, var(--primary) 1%, transparent)'),
        raw: {'box-shadow': '0 2px 6px color-mix(in srgb, var(--text) 15%, transparent)'},
      ),
      css('&:focus-visible').styles(
        raw: {'outline': '2px solid var(--primary)'},
      ),
    ]),
    css('.dropdown-backdrop', [
      css('&').styles(
        raw: {
          'position': 'fixed',
          'top': '0',
          'left': '0',
          'right': '0',
          'bottom': '0',
          'z-index': '999',
          'background-color': 'rgba(0, 0, 0, 0.1)',
        },
      ),
    ]),
    css('.dropdown-options', [
      css('&').styles(
        padding: Padding.all(2.px),
        border: Border.all(color: Color('var(--content-hr)'), width: 1.px, style: BorderStyle.solid),
        radius: BorderRadius.circular(8.px),
        backgroundColor: Color('var(--background)'),
        raw: {
          'position': 'absolute',
          'top': '100%',
          'left': '0',
          'right': '0',
          'z-index': '1000',
          'margin-top': '4px',
          'box-shadow': '0 4px 12px color-mix(in srgb, var(--text) 15%, transparent)',
          'gap': '2px',
        },
      ),
    ]),
    css('.dropdown-option', [
      css('&').styles(
        display: Display.flex,
        padding: Padding.symmetric(horizontal: 10.px, vertical: 8.px),
        radius: BorderRadius.circular(6.px),
        cursor: Cursor.pointer,
        transition: Transition('all', duration: 150.ms),
        alignItems: AlignItems.center,
        color: Color('color-mix(in srgb, var(--text) 80%, transparent)'),
        fontSize: 0.875.rem,
        fontWeight: FontWeight.w500,
        backgroundColor: Colors.transparent,
        raw: {'gap': '8px'},
      ),
      css('&:hover').styles(
        color: Color('var(--text)'),
        backgroundColor: Color('color-mix(in srgb, var(--primary) 2%, transparent)'),
      ),
      css('&.active').styles(
        color: Color('var(--text)'),
        fontWeight: FontWeight.w600,
        backgroundColor: Color('color-mix(in srgb, var(--primary) 3%, transparent)'),
      ),
      css('&:focus-visible').styles(
        raw: {'outline': '2px solid var(--primary)'},
      ),
    ]),
    css('.theme-label', [
      css('&').styles(
        transition: Transition('color', duration: 150.ms),
        fontSize: 0.8125.rem,
        fontWeight: FontWeight.w500,
      ),
    ]),
    // Chevron rotation animation
    css('.dropdown-trigger svg:last-child', [
      css('&').styles(
        transition: Transition('transform', duration: 200.ms),
        raw: {'margin-left': 'auto'},
      ),
    ]),
    css('.theme-dropdown.open .dropdown-trigger svg:last-child', [
      css('&').styles(
        raw: {'transform': 'rotate(180deg)'},
      ),
    ]),
    // Icon animations
    css('.dropdown-option svg, .dropdown-trigger svg:not(:last-child)', [
      css('&').styles(
        transition: Transition('transform', duration: 200.ms),
      ),
      css('.dropdown-option:hover &').styles(
        raw: {'transform': 'scale(1.1)'},
      ),
    ]),
    // Responsive design
    css('@media (max-width: 640px)', [
      css('.dropdown-trigger', [
        css('&').styles(
          padding: Padding.symmetric(horizontal: 10.px, vertical: 6.px),
          fontSize: 0.8125.rem,
        ),
      ]),
      css('.dropdown-option', [
        css('&').styles(
          padding: Padding.symmetric(horizontal: 8.px, vertical: 6.px),
          fontSize: 0.8125.rem,
        ),
      ]),
      css('.theme-label', [
        css('&').styles(
          display: Display.none,
        ),
      ]),
    ]),
  ];

  static const String _themeStorageKey = 'enhanced_theme_toggle_cache';
  static const Duration _cacheDuration = Duration(hours: 24);
}

enum ThemeMode {
  auto,
  dark,
  light,
}

class MonitorIcon extends StatelessComponent {
  const MonitorIcon({required this.size, super.key});

  final double size;

  @override
  Component build(BuildContext context) {
    return svg(
      viewBox: '0 0 24 24',
      attributes: {'fill': 'currentColor'},
      styles: Styles(width: size.px, height: size.px),
      [
        path(
          d: 'M21 2H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h7v2H8v2h8v-2h-2v-2h7c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H3V4h18v12z',
          [],
        ),
      ],
    );
  }
}

class MoonIcon extends StatelessComponent {
  const MoonIcon({required this.size, super.key});

  final double size;

  @override
  Component build(BuildContext context) {
    return svg(
      viewBox: '0 0 24 24',
      attributes: {'fill': 'currentColor'},
      styles: Styles(width: size.px, height: size.px),
      [
        path(
          d: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.94-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z',
          [],
        ),
      ],
    );
  }
}

class SunIcon extends StatelessComponent {
  const SunIcon({required this.size, super.key});

  final double size;

  @override
  Component build(BuildContext context) {
    return svg(
      viewBox: '0 0 24 24',
      attributes: {'fill': 'currentColor'},
      styles: Styles(width: size.px, height: size.px),
      [
        path(
          d: 'M12 7c-2.76 0-5 2.24-5 5s2.24 5 5 5 5-2.24 5-5-2.24-5-5-5zM2 13h2c.55 0 1-.45 1-1s-.45-1-1-1H2c-.55 0-1 .45-1 1s.45 1 1 1zm18 0h2c.55 0 1-.45 1-1s-.45-1-1-1h-2c-.55 0-1 .45-1 1s.45 1 1 1zM11 2v2c0 .55.45 1 1 1s1-.45 1-1V2c0-.55-.45-1-1-1s-1 .45-1 1zm0 18v2c0 .55.45 1 1 1s1-.45 1-1v-2c0-.55-.45-1-1-1s-1 .45-1 1zM5.99 4.58c-.39-.39-1.03-.39-1.41 0-.39.39-.39 1.03 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0s.39-1.03 0-1.41L5.99 4.58zm12.37 12.37c-.39-.39-1.03-.39-1.41 0-.39.39-.39 1.03 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0 .39-.39.39-1.03 0-1.41l-1.06-1.06zm-12.37 0c.39.39.39 1.03 0 1.41L4.93 19.5c-.39.39-1.03.39-1.41 0-.39-.39-.39-1.03 0-1.41l1.06-1.06c.39-.39 1.03-.39 1.41 0zM18.01 4.58c.39-.39 1.03-.39 1.41 0 .39.39.39 1.03 0 1.41L18.36 7.05c-.39.39-1.03.39-1.41 0-.39-.39-.39-1.03 0-1.41l1.06-1.06z',
          [],
        ),
      ],
    );
  }
}

class ChevronDownIcon extends StatelessComponent {
  const ChevronDownIcon({required this.size, super.key});

  final double size;

  @override
  Component build(BuildContext context) {
    return svg(
      viewBox: '0 0 24 24',
      attributes: {'fill': 'currentColor'},
      styles: Styles(width: size.px, height: size.px),
      [
        path(
          d: 'M7 10l5 5 5-5z',
          [],
        ),
      ],
    );
  }
}

class HomeIcon extends StatelessComponent {
  const HomeIcon({required this.size, super.key});

  final double size;

  @override
  Component build(BuildContext context) {
    return svg(
      viewBox: '0 0 24 24',
      attributes: {'fill': 'none', 'stroke': 'currentColor', 'stroke-width': '2'},
      styles: Styles(width: size.px, height: size.px),
      [
        path(
          d: 'M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
          [],
        ),
        polyline(
          points: '9,22 9,12 15,12 15,22',
          [],
        ),
      ],
    );
  }
}
