// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/jaspr.dart';
import 'package:datum_docs/components/custom_image.dart' as prefix0;
import 'package:jaspr_content/components/_internal/code_block_copy_button.dart'
    as prefix1;
import 'package:jaspr_content/components/_internal/zoomable_image.dart'
    as prefix2;
import 'package:jaspr_content/components/callout.dart' as prefix3;
import 'package:jaspr_content/components/code_block.dart' as prefix4;
import 'package:jaspr_content/components/github_button.dart' as prefix5;
import 'package:jaspr_content/components/image.dart' as prefix6;
import 'package:jaspr_content/components/sidebar_toggle_button.dart' as prefix7;
import 'package:jaspr_content/components/theme_toggle.dart' as prefix8;

/// Default [JasprOptions] for use with your jaspr project.
///
/// Use this to initialize jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'jaspr_options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultJasprOptions,
///   );
///
///   runApp(...);
/// }
/// ```
JasprOptions get defaultJasprOptions => JasprOptions(
  clients: {
    prefix1.CodeBlockCopyButton: ClientTarget<prefix1.CodeBlockCopyButton>(
      'jaspr_content:components/_internal/code_block_copy_button',
    ),

    prefix2.ZoomableImage: ClientTarget<prefix2.ZoomableImage>(
      'jaspr_content:components/_internal/zoomable_image',
      params: _prefix2ZoomableImage,
    ),

    prefix5.GitHubButton: ClientTarget<prefix5.GitHubButton>(
      'jaspr_content:components/github_button',
      params: _prefix5GitHubButton,
    ),

    prefix7.SidebarToggleButton: ClientTarget<prefix7.SidebarToggleButton>(
      'jaspr_content:components/sidebar_toggle_button',
    ),

    prefix8.ThemeToggle: ClientTarget<prefix8.ThemeToggle>(
      'jaspr_content:components/theme_toggle',
    ),
  },
  styles: () => [
    ...prefix0.CustomImage.styles,

    ...prefix2.ZoomableImage.styles,
    ...prefix3.Callout.styles,
    ...prefix4.CodeBlock.styles,

    ...prefix5.GitHubButton.styles,
    ...prefix6.Image.styles,

    ...prefix8.ThemeToggleState.styles,
  ],
);

Map<String, dynamic> _prefix2ZoomableImage(prefix2.ZoomableImage c) => {
  'src': c.src,
  'alt': c.alt,
  'caption': c.caption,
};
Map<String, dynamic> _prefix5GitHubButton(prefix5.GitHubButton c) => {
  'repo': c.repo,
};
