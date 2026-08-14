import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// A card component for highlighting features, examples, or important content.
///
/// Usage in markdown:
/// <Card title="Feature Title">
/// Content goes here
/// </Card>
class Card extends CustomComponentBase {
  Card();

  @override
  final Pattern pattern = 'Card';

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    final title = attributes['title'];
    return _CardComponent(title: title, child: child);
  }

  @css
  static List<StyleRule> get styles => [
    css('.card', [
      css('&').styles(
        padding: Padding.all(1.5.rem),
        margin: Margin.only(bottom: 1.5.rem),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        radius: BorderRadius.circular(0.75.rem),
        backgroundColor: Color('color-mix(in srgb, var(--background) 94%, var(--text) 6%)'),
        raw: {
          'position': 'relative',
          'transition': 'all 0.3s ease-in-out',
          'box-shadow': '0 1px 3px color-mix(in srgb, var(--text) 10%, transparent), 0 1px 2px color-mix(in srgb, var(--text) 6%, transparent)',
          'background': 'linear-gradient(135deg, color-mix(in srgb, var(--background) 94%, var(--text) 6%) 0%, color-mix(in srgb, var(--background) 94%, var(--text) 6%) 100%)',
        },
      ),
      css('&:hover').styles(
        raw: {
          'transform': 'translateY(-2px)',
          'box-shadow': '0 8px 25px color-mix(in srgb, var(--text) 15%, transparent), 0 4px 12px color-mix(in srgb, var(--text) 10%, transparent)',
        },
      ),
      css('&::before').styles(
        raw: {
          'content': '""',
          'position': 'absolute',
          'top': '0',
          'left': '0',
          'right': '0',
          'height': '3px',
          'background': 'linear-gradient(90deg, var(--primary), color-mix(in srgb, var(--primary) 80%, transparent))',
          'border-radius': '0.75rem 0.75rem 0 0',
        },
      ),
      css('& > .card-title').styles(
        margin: Margin.only(bottom: 0.75.rem),
        color: Color('var(--content-headings)'),
        fontSize: 1.125.rem,
        fontWeight: FontWeight.w600,
        raw: {
          'background': 'linear-gradient(135deg, var(--content-headings), color-mix(in srgb, var(--content-headings) 90%, transparent))',
          '-webkit-background-clip': 'text',
          '-webkit-text-fill-color': 'transparent',
          'background-clip': 'text',
        },
      ),
      css('& > .card-content').styles(
        color: Color('var(--content-headings)'),
        raw: {'line-height': '1.7'},
      ),
      css('& > .card-content p').styles(
        margin: Margin.only(bottom: 1.rem),
      ),
      css('& > .card-content p:last-child').styles(
        margin: Margin.only(bottom: Unit.zero),
      ),
      css('& > .card-content pre').styles(
        padding: Padding.all(1.rem),
        margin: Margin.symmetric(vertical: 1.rem),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        radius: BorderRadius.circular(0.5.rem),
        backgroundColor: Color('color-mix(in srgb, var(--background) 90%, var(--text) 10%)'),
        raw: {'overflow': 'auto', 'box-shadow': 'inset 0 1px 3px color-mix(in srgb, var(--text) 10%, transparent)'},
      ),
      css('& > .card-content code').styles(
        padding: Padding.symmetric(horizontal: 0.375.rem, vertical: 0.125.rem),
        radius: BorderRadius.circular(0.375.rem),
        color: Color('var(--content-headings)'),
        fontSize: 0.875.em,
        backgroundColor: Color('color-mix(in srgb, var(--background) 90%, var(--text) 10%)'),
        raw: {'font-family': 'var(--font-mono)'},
      ),
      css('& > .card-content ul, & > .card-content ol').styles(
        padding: Padding.only(left: 1.5.rem),
        margin: Margin.symmetric(vertical: 0.5.rem),
      ),
      css('& > .card-content li').styles(
        margin: Margin.only(bottom: 0.25.rem),
      ),
      css('& > .card-content li:last-child').styles(
        margin: Margin.only(bottom: Unit.zero),
      ),
    ]),
  ];
}

class _CardComponent extends StatelessComponent {
  const _CardComponent({this.title, required this.child});

  final String? title;
  final Component? child;

  @override
  Component build(BuildContext context) {
    return div(classes: 'card', [
      if (title != null) div(classes: 'card-title', [Component.text(title!)]),
      if (child != null) div(classes: 'card-content', [child!]),
    ]);
  }
}
