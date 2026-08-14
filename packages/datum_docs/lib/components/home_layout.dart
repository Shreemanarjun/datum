import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// The landing-page layout: no sidebar, a raw-Jaspr animated hero, and the
/// page's markdown flowing full-width beneath it.
///
/// Selected per page with `layout: home` in frontmatter; docs pages keep
/// [ResponsiveDocsLayout] (the default).
class HomeLayout extends PageLayoutBase {
  const HomeLayout({this.header});

  /// Shared site header (nav parity with the docs pages).
  final Component? header;

  @override
  String get name => 'home';

  @override
  Component buildBody(Page page, Component child) {
    return div(classes: 'home-layout', [
      if (header case final header?) div(classes: 'header-container', [header]),
      _hero(),
      main_(classes: 'home-content', [child]),
    ]);
  }

  Component _hero() {
    return section(classes: 'home-hero', [
      img(classes: 'home-hero-logo', src: '/images/logo.webp', alt: 'Datum logo', width: 180, height: 180),
      h1(classes: 'home-hero-title', [Component.text('Datum')]),
      p(classes: 'home-hero-tagline', [Component.text('Data, Seamlessly Synced')]),
      _syncDiagram(),
      p(classes: 'home-hero-sub', [
        Component.text('The offline-first sync engine for Dart & Flutter — '),
        strong([Component.text('your backend, your database')]),
        Component.text(', one type-safe API.'),
      ]),
      div(classes: 'home-hero-ctas', [
        a(classes: 'cta primary', href: '/getting_started/quick_start', [Component.text('Get started')]),
        a(classes: 'cta', href: 'https://pub.dev/packages/datum', [Component.text('pub.dev')]),
        a(classes: 'cta', href: 'https://github.com/shreemanarjun/datum', [Component.text('GitHub')]),
      ]),
    ]);
  }

  Component _syncDiagram() {
    return div(classes: 'home-sync', attributes: {'aria-hidden': 'true'}, [
      div(classes: 'home-node', [
        span(classes: 'home-node-icon', [Component.text('📱')]),
        span(classes: 'home-node-label', [Component.text('device')]),
      ]),
      div(classes: 'home-lane', [
        div(classes: 'home-packet up', []),
        div(classes: 'home-packet down', []),
      ]),
      div(classes: 'home-node cloud', [
        span(classes: 'home-node-icon', [Component.text('☁️')]),
        span(classes: 'home-node-label', [Component.text('your backend')]),
      ]),
      div(classes: 'home-lane', [
        div(classes: 'home-packet up delayed', []),
        div(classes: 'home-packet down delayed', []),
      ]),
      div(classes: 'home-node', [
        span(classes: 'home-node-icon', [Component.text('💻')]),
        span(classes: 'home-node-label', [Component.text('device')]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.home-layout', [
      css('.home-hero').styles(
        display: Display.flex,
        padding: Padding.only(top: 6.rem, bottom: 3.rem, left: 1.5.rem, right: 1.5.rem),
        raw: {
          'flex-direction': 'column',
          'align-items': 'center',
          'text-align': 'center',
          'background':
              'radial-gradient(ellipse 80% 60% at 50% -10%, color-mix(in srgb, hsl(var(--primary)) 18%, transparent), transparent)',
        },
      ),
      css('.home-hero-logo').styles(
        margin: Margin.only(bottom: 0.5.rem),
        raw: {'animation': 'home-float 6s ease-in-out infinite'},
      ),
      css('.home-hero-title').styles(
        margin: Margin.zero,
        fontSize: Unit.expression('clamp(3rem, 10vw, 5rem)'),
        fontWeight: FontWeight.w700,
        raw: {
          'background': 'linear-gradient(90deg, hsl(var(--foreground)), hsl(var(--primary)))',
          '-webkit-background-clip': 'text',
          'background-clip': 'text',
          'color': 'transparent',
        },
      ),
      css('.home-hero-tagline').styles(
        margin: Margin.only(top: 0.5.rem, bottom: 1.5.rem),
        fontSize: Unit.expression('clamp(1.1rem, 4vw, 1.5rem)'),
        fontWeight: FontWeight.w500,
        color: Color('var(--fg-color-2)'),
      ),
      css('.home-hero-sub').styles(
        margin: Margin.only(top: 1.5.rem),
        fontSize: 1.15.rem,
        maxWidth: 40.rem,
        color: Color('var(--fg-color-2)'),
      ),
      css('.home-hero-ctas').styles(
        display: Display.flex,
        margin: Margin.only(top: 1.5.rem),
        raw: {'gap': '0.75rem', 'flex-wrap': 'wrap', 'justify-content': 'center'},
      ),
      css('.cta', [
        css('&').styles(
          padding: Padding.symmetric(vertical: 0.7.rem, horizontal: 1.4.rem),
          radius: BorderRadius.circular(0.6.rem),
          border: Border.all(width: 1.px, color: Color('hsl(var(--border))')),
          fontWeight: FontWeight.w600,
          raw: {'text-decoration': 'none', 'transition': 'all .2s ease'},
        ),
        css('&:hover').styles(raw: {'transform': 'translateY(-2px)', 'box-shadow': '0 6px 18px hsl(var(--foreground) / .12)'}),
        css('&.primary').styles(
          backgroundColor: Color('hsl(var(--primary))'),
          color: Color('hsl(var(--primary-foreground, 0 0% 100%))'),
          border: Border.all(width: 1.px, color: Color('transparent')),
        ),
      ]),
      // --- Animated sync diagram ---
      css('.home-sync').styles(
        display: Display.flex,
        alignItems: AlignItems.center,
        margin: Margin.only(top: 2.rem),
        raw: {'gap': 'clamp(1rem, 6vw, 3rem)', 'user-select': 'none'},
      ),
      css('.home-node', [
        css('&').styles(
          display: Display.flex,
          padding: Padding.all(0.9.rem),
          radius: BorderRadius.circular(1.rem),
          border: Border.all(width: 2.px, color: Color('hsl(var(--border))')),
          backgroundColor: Color('hsl(var(--card, var(--background)))'),
          raw: {'flex-direction': 'column', 'align-items': 'center', 'gap': '.25rem', 'box-shadow': '0 6px 20px hsl(var(--foreground) / .08)'},
        ),
        css('&.cloud').styles(raw: {'animation': 'home-breathe 3.5s ease-in-out infinite'}),
        css('.home-node-icon').styles(fontSize: 1.9.rem),
        css('.home-node-label').styles(fontSize: .75.rem, color: Color('var(--fg-color-2)')),
      ]),
      css('.home-lane').styles(
        position: Position.relative(),
        width: Unit.expression('clamp(70px, 12vw, 130px)'),
        height: 14.px,
      ),
      css('.home-lane::before').styles(
        position: Position.absolute(top: 6.px, left: Unit.zero, right: Unit.zero),
        height: 2.px,
        raw: {'content': '""', 'background': 'hsl(var(--border))'},
      ),
      css('.home-packet', [
        css('&').styles(
          position: Position.absolute(),
          width: 10.px,
          height: 10.px,
          radius: BorderRadius.circular(5.px),
          raw: {'background': 'hsl(var(--primary))', 'box-shadow': '0 0 12px hsl(var(--primary) / .9)'},
        ),
        css('&.up').styles(position: Position.absolute(top: (-2).px), raw: {'animation': 'home-travel 2.2s linear infinite'}),
        css('&.down').styles(position: Position.absolute(top: 8.px), raw: {'animation': 'home-travel 2.2s linear infinite reverse', 'animation-delay': '1.1s', 'opacity': '.75'}),
        css('&.delayed').styles(raw: {'animation-delay': '.55s'}),
        css('&.down.delayed').styles(raw: {'animation-delay': '1.65s'}),
      ]),
      css('.home-content', [
        css('&').styles(
          margin: Margin.symmetric(horizontal: Unit.auto),
          padding: Padding.symmetric(horizontal: 1.5.rem),
          maxWidth: 52.rem,
        ),
      ]),
      css('@media (prefers-reduced-motion: reduce)', [
        css('.home-packet, .home-hero-logo, .home-node.cloud').styles(raw: {'animation': 'none'}),
      ]),
    ]),
    css.keyframes('home-travel', {
      '0%': Styles(raw: {'left': '-5px', 'opacity': '0'}),
      '12%': Styles(raw: {'opacity': '1'}),
      '88%': Styles(raw: {'opacity': '1'}),
      '100%': Styles(raw: {'left': 'calc(100% - 5px)', 'opacity': '0'}),
    }),
    css.keyframes('home-breathe', {
      '0%': Styles(raw: {'transform': 'scale(1)'}),
      '50%': Styles(raw: {'transform': 'scale(1.06)'}),
      '100%': Styles(raw: {'transform': 'scale(1)'}),
    }),
    css.keyframes('home-float', {
      '0%': Styles(raw: {'transform': 'translateY(0)'}),
      '50%': Styles(raw: {'transform': 'translateY(-8px)'}),
      '100%': Styles(raw: {'transform': 'translateY(0)'}),
    }),
  ];
}
