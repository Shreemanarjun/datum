// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:datum_docs/components/badge.dart' as _badge;
import 'package:datum_docs/components/cached_github_button.dart'
    as _cached_github_button;
import 'package:datum_docs/components/card.dart' as _card;
import 'package:datum_docs/components/code_block.dart' as _code_block;
import 'package:datum_docs/components/custom_image.dart' as _custom_image;
import 'package:datum_docs/components/enhanced_theme_toggle.dart'
    as _enhanced_theme_toggle;
import 'package:datum_docs/components/home_layout.dart' as _home_layout;
import 'package:datum_docs/components/steps.dart' as _steps;
import 'package:datum_docs/components/sync_animation.dart' as _sync_animation;
import 'package:datum_docs/components/tip.dart' as _tip;
import 'package:jaspr_content/components/_internal/code_block_copy_button.dart'
    as _code_block_copy_button;
import 'package:jaspr_content/components/_internal/tab_bar.dart' as _tab_bar;
import 'package:jaspr_content/components/_internal/zoomable_image.dart'
    as _zoomable_image;
import 'package:jaspr_content/components/sidebar_toggle_button.dart'
    as _sidebar_toggle_button;
import 'package:jaspr_content/components/tabs.dart' as _tabs;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _cached_github_button.CachedGitHubButton:
        ClientTarget<_cached_github_button.CachedGitHubButton>(
          'cached_github_button',
          params: __cached_github_buttonCachedGitHubButton,
        ),
    _enhanced_theme_toggle.EnhancedThemeToggle:
        ClientTarget<_enhanced_theme_toggle.EnhancedThemeToggle>(
          'enhanced_theme_toggle',
        ),
    _code_block_copy_button.CodeBlockCopyButton:
        ClientTarget<_code_block_copy_button.CodeBlockCopyButton>(
          'jaspr_content:code_block_copy_button',
        ),
    _tab_bar.TabBar: ClientTarget<_tab_bar.TabBar>(
      'jaspr_content:tab_bar',
      params: __tab_barTabBar,
    ),
    _zoomable_image.ZoomableImage: ClientTarget<_zoomable_image.ZoomableImage>(
      'jaspr_content:zoomable_image',
      params: __zoomable_imageZoomableImage,
    ),
    _sidebar_toggle_button.SidebarToggleButton:
        ClientTarget<_sidebar_toggle_button.SidebarToggleButton>(
          'jaspr_content:sidebar_toggle_button',
        ),
  },
  styles: () => [
    ..._badge.Badge.styles,
    ..._cached_github_button.CachedGitHubButton.styles,
    ..._card.Card.styles,
    ..._code_block.CodeBlock.styles,
    ..._custom_image.CustomImage.styles,
    ..._enhanced_theme_toggle.EnhancedThemeToggleState.styles,
    ..._home_layout.HomeLayout.styles,
    ..._steps.Steps.styles,
    ..._sync_animation.SyncAnimation.styles,
    ..._tip.Tip.styles,
    ..._tabs.Tabs.styles,
    ..._tab_bar.TabBar.styles,
    ..._zoomable_image.ZoomableImage.styles,
  ],
);

Map<String, Object?> __cached_github_buttonCachedGitHubButton(
  _cached_github_button.CachedGitHubButton c,
) => {'repo': c.repo, 'cacheDurationMinutes': c.cacheDurationMinutes};
Map<String, Object?> __tab_barTabBar(_tab_bar.TabBar c) => {
  'initialValue': c.initialValue,
  'items': c.items,
};
Map<String, Object?> __zoomable_imageZoomableImage(
  _zoomable_image.ZoomableImage c,
) => {'src': c.src, 'alt': c.alt, 'caption': c.caption};
