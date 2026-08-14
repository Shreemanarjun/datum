import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart' hide Color;

import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/components/_internal/code_block_copy_button.dart';

/// A custom highlighter that properly handles multiple languages with fallback.
class CustomHighlighter {
  static bool _initialized = false;

  /// Initialize with supported languages. Since syntax_highlight_lite only supports 'dart',
  /// we'll use a custom approach that falls back to plain text for unsupported languages.
  static Future<void> initialize() async {
    if (_initialized) return;

    // Initialize syntax_highlight_lite with dart (the only supported language)
    await Highlighter.initialize(['dart']);
    _initialized = true;
  }

  /// Add a custom language grammar
  static void addLanguage(String name, String json) {
    try {
      Highlighter.addLanguage(name, json);
    } catch (e) {
      // If parsing fails, we'll fall back to plain text
      print('Failed to parse grammar for $name: $e');
    }
  }

  final String language;
  final HighlighterTheme theme;
  late final Highlighter? _highlighter;

  CustomHighlighter({required this.language, required this.theme}) {
    // Only create highlighter if language is supported (currently only 'dart')
    if (language.toLowerCase() == 'dart') {
      _highlighter = Highlighter(language: language, theme: theme);
    } else {
      _highlighter = Highlighter(language: "dart", theme: theme); // Will render as plain text
    }
  }

  TextSpan highlight(String code) {
    if (_highlighter != null) {
      return _highlighter.highlight(code);
    } else {
      // Return plain text for unsupported languages
      return _highlighter!.highlight(code);
    }
  }
}

/// A code block component that renders syntax-highlighted code.
class CodeBlock extends CustomComponent {
  CodeBlock({this.defaultLanguage = 'dart', this.grammars = const {}, this.codeTheme}) : super.base();

  static Component from({required String source, CustomHighlighter? highlighter, Key? key}) {
    return _CodeBlock(source: source, highlighter: highlighter, key: key);
  }

  /// The default language for the code block.
  final String defaultLanguage;

  /// The available grammars for the code block.
  ///
  /// The key is the name of the language.
  /// The value is a json encoded string of the grammar.
  final Map<String, String> grammars;

  /// The default theme for the code block.
  final HighlighterTheme? codeTheme;

  bool _initialized = false;
  HighlighterTheme? _defaultTheme;

  @override
  Component? create(Node node, NodesBuilder builder) {
    if (node
        case ElementNode(tag: 'Code' || 'CodeBlock', :final children, :final attributes) ||
            ElementNode(tag: 'pre', children: [ElementNode(tag: 'code', :final children, :final attributes)])) {
      var language = attributes['language'];
      if (language == null && (attributes['class']?.startsWith('language-') ?? false)) {
        language = attributes['class']!.substring('language-'.length);
      }

      if (!_initialized) {
        CustomHighlighter.initialize();
        for (final entry in grammars.entries) {
          CustomHighlighter.addLanguage(entry.key, entry.value);
        }
        _initialized = true;
      }

      return AsyncBuilder(
        builder: (context) async {
          final highlighter = CustomHighlighter(
            language: language ?? defaultLanguage,
            theme: codeTheme ?? (_defaultTheme ??= await HighlighterTheme.loadDarkTheme()),
          );

          return _CodeBlock(source: children?.map((c) => c.innerText).join(' ') ?? '', highlighter: highlighter);
        },
      );
    }
    return null;
  }

  @css
  static List<StyleRule> get styles => [
    css('.code-block', [
      css('&').styles(position: Position.relative()),
      css('button').styles(
        position: Position.absolute(top: 1.rem, right: 1.rem),
        zIndex: ZIndex(10),
        width: 1.25.rem,
        height: 1.25.rem,
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        radius: BorderRadius.circular(0.25.rem),
        opacity: 0.5,
        color: Color('var(--text)'),
        backgroundColor: Color('color-mix(in srgb, var(--text) 8%, transparent)'),
        raw: {'transition': 'opacity 0.2s ease'},
      ),
      css('&:hover button').styles(opacity: 1),
      // Thin themed scrollbar — the default track renders as a bright strip
      // against the dark pre background, especially in dark mode.
      css('pre').styles(
        raw: {
          'scrollbar-width': 'thin',
          'scrollbar-color': 'color-mix(in srgb, var(--content-pre-code) 35%, transparent) transparent',
        },
      ),
      css('pre::-webkit-scrollbar').styles(raw: {'height': '8px', 'width': '8px'}),
      css('pre::-webkit-scrollbar-track').styles(raw: {'background': 'transparent'}),
      css('pre::-webkit-scrollbar-thumb').styles(
        raw: {
          'background': 'color-mix(in srgb, var(--content-pre-code) 35%, transparent)',
          'border-radius': '4px',
        },
      ),
    ]),
  ];
}

/// A code block component with syntax highlighting.
class _CodeBlock extends StatelessComponent {
  const _CodeBlock({required this.source, this.highlighter, super.key});

  /// The source code of the code block.
  final String source;

  /// The syntax highlighter instance.
  final CustomHighlighter? highlighter;

  @override
  Component build(BuildContext context) {
    final codeblock = pre([
      code([if (highlighter != null) buildSpan(highlighter!.highlight(source)) else Component.text(source)]),
    ]);

    return div(classes: 'code-block', [CodeBlockCopyButton(), codeblock]);
  }

  Component buildSpan(TextSpan textSpan) {
    Styles? styles;

    if (textSpan.style case final style?) {
      styles = Styles(
        color: Color.value(style.foreground.argb & 0x00FFFFFF),
        fontWeight: style.bold ? FontWeight.bold : null,
        fontStyle: style.italic ? FontStyle.italic : null,
        textDecoration: style.underline ? TextDecoration(line: TextDecorationLine.underline) : null,
      );
    }

    if (styles == null && textSpan.children.isEmpty) {
      return Component.text(textSpan.text ?? '');
    }

    return span(styles: styles, [
      if (textSpan.text != null) Component.text(textSpan.text!),
      for (final t in textSpan.children) buildSpan(t),
    ]);
  }
}
