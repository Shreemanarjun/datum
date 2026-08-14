import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// The animated hero visual: two devices exchanging data packets with a
/// cloud, pure CSS keyframes (no JS, pre-render friendly).
///
/// Usage in markdown: `<SyncAnimation/>`
class SyncAnimation extends CustomComponentBase {
  SyncAnimation();

  @override
  final Pattern pattern = 'SyncAnimation';

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) => const _SyncAnimation();

  @css
  static List<StyleRule> get styles => [
    css('.sync-hero', [
      css('&').styles(
        display: Display.flex,
        alignItems: AlignItems.center,
        justifyContent: JustifyContent.center,
        margin: Margin.symmetric(vertical: 2.rem),
        raw: {'gap': 'clamp(1.5rem, 8vw, 4rem)', 'user-select': 'none'},
      ),
      css('.sync-node').styles(
        display: Display.flex,
        alignItems: AlignItems.center,
        justifyContent: JustifyContent.center,
        width: 64.px,
        height: 64.px,
        radius: BorderRadius.circular(16.px),
        border: Border.all(width: 2.px, color: Color('hsl(var(--border))')),
        backgroundColor: Color('hsl(var(--card))'),
        fontSize: 1.8.rem,
        raw: {'box-shadow': '0 4px 14px hsl(var(--foreground) / 0.08)'},
      ),
      css('.sync-cloud').styles(
        raw: {'animation': 'sync-breathe 3s ease-in-out infinite'},
      ),
      css('.sync-lane').styles(
        position: Position.relative(),
        width: 96.px,
        height: 4.px,
        radius: BorderRadius.circular(2.px),
        backgroundColor: Color('hsl(var(--border))'),
        raw: {'overflow': 'visible'},
      ),
      css('.sync-packet').styles(
        position: Position.absolute(top: (-4).px),
        width: 12.px,
        height: 12.px,
        radius: BorderRadius.circular(6.px),
        raw: {
          'background': 'hsl(var(--primary))',
          'box-shadow': '0 0 10px hsl(var(--primary) / 0.8)',
          'animation': 'sync-travel 2.4s linear infinite',
        },
      ),
      css('.sync-packet.reverse').styles(
        raw: {'animation': 'sync-travel 2.4s linear infinite reverse', 'animation-delay': '1.2s'},
      ),
      // Respect users who prefer no motion — the layout still reads.
      css('@media (prefers-reduced-motion: reduce)', [
        css('.sync-packet, .sync-cloud').styles(raw: {'animation': 'none'}),
      ]),
    ]),
    css.keyframes('sync-travel', {
      '0%': Styles(raw: {'left': '-6px', 'opacity': '0'}),
      '15%': Styles(raw: {'opacity': '1'}),
      '85%': Styles(raw: {'opacity': '1'}),
      '100%': Styles(raw: {'left': 'calc(100% - 6px)', 'opacity': '0'}),
    }),
    css.keyframes('sync-breathe', {
      '0%': Styles(raw: {'transform': 'scale(1)'}),
      '50%': Styles(raw: {'transform': 'scale(1.07)'}),
      '100%': Styles(raw: {'transform': 'scale(1)'}),
    }),
  ];
}

class _SyncAnimation extends StatelessComponent {
  const _SyncAnimation();

  @override
  Component build(BuildContext context) {
    return div(classes: 'sync-hero', attributes: {'aria-hidden': 'true'}, [
      div(classes: 'sync-node', [Component.text('📱')]),
      div(classes: 'sync-lane', [div(classes: 'sync-packet', [])]),
      div(classes: 'sync-node sync-cloud', [Component.text('☁️')]),
      div(classes: 'sync-lane', [div(classes: 'sync-packet reverse', [])]),
      div(classes: 'sync-node', [Component.text('💻')]),
    ]);
  }
}
