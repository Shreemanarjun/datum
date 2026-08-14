import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

class Tip extends CustomComponentBase {
  Tip();

  @override
  final Pattern pattern = RegExp(r'Tip|Warning|Info');

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    return _TipComponent(type: name, child: child);
  }

  @css
  static List<StyleRule> get styles => [];
}

class _TipComponent extends StatelessComponent {
  const _TipComponent({required this.type, required this.child});

  final String type;
  final Component? child;

  @override
  Component build(BuildContext context) {
    final (borderColor, bgColor, iconColor, iconSvg) = switch (type) {
      'Info' => (
        'hsl(199 89% 48%)', // blue
        'hsl(199 89% 48% / 0.1)',
        'hsl(199 89% 48%)',
        // Info icon
        '''
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"></circle>
          <path d="M12 16v-4"></path>
          <path d="M12 8h.01"></path>
        </svg>
        ''',
      ),
      'Warning' => (
        'hsl(38 92% 50%)', // amber/yellow
        'hsl(38 92% 50% / 0.1)',
        'hsl(38 92% 50%)',
        // Warning icon
        '''
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path>
          <line x1="12" y1="9" x2="12" y2="13"></line>
          <line x1="12" y1="17" x2="12.01" y2="17"></line>
        </svg>
        ''',
      ),
      _ => (
        'hsl(142 76% 36%)', // green
        'hsl(142 76% 36% / 0.1)',
        'hsl(142 76% 36%)',
        // Tip/Lightbulb icon
        '''
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.8 1.2 1.5 1.5 2.5"></path>
          <path d="M9 18h6"></path>
          <path d="M10 22h4"></path>
        </svg>
        ''',
      ),
    };

    return div(
      styles: Styles(
        display: Display.flex,
        padding: Padding.symmetric(vertical: 1.rem, horizontal: 1.25.rem),
        margin: Margin.only(bottom: 1.rem),
        border: Border.all(width: 1.px, color: Color('$borderColor / 0.2')),
        radius: BorderRadius.circular(0.5.rem),
        alignItems: AlignItems.start,
        gap: Gap(column: 0.75.rem),
        backgroundColor: Color(bgColor),
        raw: {'border-left': '4px solid $borderColor'},
      ),
      [
        div(
          styles: Styles(
            width: 1.25.rem,
            height: 1.25.rem,
            flex: Flex(shrink: 0),
            color: Color(iconColor),
            raw: {'margin-top': '0.125rem'},
          ),
          [
            RawText(iconSvg),
          ],
        ),
        div(
          styles: Styles(
            flex: Flex(grow: 1),
            color: Color('var(--text)'),
            raw: {'line-height': '1.6'},
          ),
          [
            _renderContent(child),
          ],
        ),
      ],
    );
  }

  Component _renderContent(Component? component) {
    // The simplest approach: if we have a Text component with markdown,
    // parse it directly. Otherwise, return as-is.

    if (component is Text && component.text.contains('**')) {
      // Parse the markdown directly
      final html = _markdownToHtml(component.text);
      return RawText('<span>$html</span>');
    }

    // For any other case, return the original component
    // The Jaspr system will handle rendering it appropriately
    return component ?? Component.text('');
  }

  String _markdownToHtml(String markdown) {
    // Simple markdown to HTML conversion for bold text
    // Convert **text** to <strong>text</strong>
    final boldRegex = RegExp(r'\*\*(.*?)\*\*');
    return markdown.replaceAllMapped(boldRegex, (match) {
      return '<strong>${match.group(1)}</strong>';
    });
  }
}
