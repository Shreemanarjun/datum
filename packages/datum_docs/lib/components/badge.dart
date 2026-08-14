import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// A badge component for status indicators, version badges, and labels.
///
/// Usage in markdown:
/// <Badge variant="success">Stable</Badge>
/// <Badge variant="warning">Beta</Badge>
/// <Badge variant="error">Deprecated</Badge>
class Badge extends CustomComponentBase {
  Badge();

  @override
  final Pattern pattern = 'Badge';

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    final variant = attributes['variant'] ?? 'default';
    return _BadgeComponent(variant: variant, child: child);
  }

  @css
  static List<StyleRule> get styles => [
    css('.badge', [
      css('&').styles(
        display: Display.inlineFlex,
        padding: Padding.symmetric(horizontal: 0.625.rem, vertical: 0.25.rem),
        radius: BorderRadius.circular(9999.px),
        justifyContent: JustifyContent.center,
        alignItems: AlignItems.center,
        fontSize: 0.75.rem,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.025.em,
        raw: {
          'line-height': '1',
          'white-space': 'nowrap',
          'transition': 'all 0.2s ease-in-out',
          'box-shadow': '0 1px 2px color-mix(in srgb, var(--text) 10%, transparent)',
          'border': '1px solid transparent',
        },
      ),
      css('&:hover').styles(
        raw: {
          'transform': 'translateY(-1px)',
          'box-shadow': '0 2px 8px color-mix(in srgb, var(--text) 15%, transparent)',
        },
      ),
      // Default variant
      css('&.badge-default').styles(
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        color: Color('var(--content-captions)'),
        backgroundColor: Color('color-mix(in srgb, var(--text) 8%, transparent)'),
      ),
      // Success variant
      css('&.badge-success').styles(
        border: Border.all(width: 1.px, color: Color('hsl(142 76% 36% / 0.2)')),
        color: Color('hsl(142 76% 36%)'),
        backgroundColor: Color('hsl(142 76% 36% / 0.1)'),
        raw: {'box-shadow': '0 1px 2px hsl(142 76% 36% / 0.1)'},
      ),
      // Warning variant
      css('&.badge-warning').styles(
        border: Border.all(width: 1.px, color: Color('hsl(38 92% 50% / 0.2)')),
        color: Color('hsl(38 92% 50%)'),
        backgroundColor: Color('hsl(38 92% 50% / 0.1)'),
        raw: {'box-shadow': '0 1px 2px hsl(38 92% 50% / 0.1)'},
      ),
      // Error variant
      css('&.badge-error').styles(
        border: Border.all(width: 1.px, color: Color('hsl(0 84% 60% / 0.2)')),
        color: Color('hsl(0 84% 60%)'),
        backgroundColor: Color('hsl(0 84% 60% / 0.1)'),
        raw: {'box-shadow': '0 1px 2px hsl(0 84% 60% / 0.1)'},
      ),
      // Info variant
      css('&.badge-info').styles(
        border: Border.all(width: 1.px, color: Color('hsl(199 89% 48% / 0.2)')),
        color: Color('hsl(199 89% 48%)'),
        backgroundColor: Color('hsl(199 89% 48% / 0.1)'),
        raw: {'box-shadow': '0 1px 2px hsl(199 89% 48% / 0.1)'},
      ),
    ]),
  ];
}

class _BadgeComponent extends StatelessComponent {
  const _BadgeComponent({required this.variant, required this.child});

  final String variant;
  final Component? child;

  @override
  Component build(BuildContext context) {
    return span(classes: 'badge badge-$variant', [
      if (child != null) child!,
    ]);
  }
}
