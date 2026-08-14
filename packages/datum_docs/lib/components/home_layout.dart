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
      div(classes: 'home-hero-badges', [
        span(classes: 'home-badge', [Component.text('v1.1.0')]),
        span(classes: 'home-badge', [Component.text('MIT licensed')]),
        span(classes: 'home-badge', [Component.text('Pure client library')]),
        span(classes: 'home-badge', [Component.text('100% test coverage')]),
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
              'radial-gradient(ellipse 80% 60% at 50% -10%, color-mix(in srgb, var(--primary) 18%, transparent), transparent)',
        },
      ),
      css('.home-hero-logo').styles(
        margin: Margin.only(bottom: 0.5.rem),
        raw: {'animation': 'home-float 6s ease-in-out infinite'},
      ),
      css('.home-hero-title').styles(
        margin: Margin.zero,
        padding: Padding.only(bottom: 0.15.em),
        fontSize: Unit.expression('clamp(3rem, 10vw, 5rem)'),
        fontWeight: FontWeight.w700,
        raw: {
          'line-height': '1.15',
          'background': 'linear-gradient(90deg, var(--content-headings), var(--primary))',
          '-webkit-background-clip': 'text',
          'background-clip': 'text',
          'color': 'transparent',
        },
      ),
      css('.home-hero-tagline').styles(
        margin: Margin.only(top: 0.5.rem, bottom: 1.5.rem),
        fontSize: Unit.expression('clamp(1.1rem, 4vw, 1.5rem)'),
        fontWeight: FontWeight.w500,
        color: Color('var(--content-lead)'),
      ),
      css('.home-hero-sub').styles(
        margin: Margin.only(top: 1.5.rem),
        fontSize: 1.15.rem,
        maxWidth: 40.rem,
        color: Color('var(--content-lead)'),
      ),
      css('.home-hero-badges').styles(
        display: Display.flex,
        margin: Margin.only(top: 1.25.rem),
        raw: {'gap': '0.5rem', 'flex-wrap': 'wrap', 'justify-content': 'center'},
      ),
      css('.home-badge').styles(
        padding: Padding.symmetric(vertical: 0.35.rem, horizontal: 0.8.rem),
        radius: BorderRadius.circular(999.px),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        fontSize: 0.8.rem,
        fontWeight: FontWeight.w500,
        color: Color('var(--content-lead)'),
        backgroundColor: Color('color-mix(in srgb, var(--background) 94%, var(--text) 6%)'),
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
          border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
          fontWeight: FontWeight.w600,
          raw: {'text-decoration': 'none', 'transition': 'all .2s ease'},
        ),
        css('&:hover').styles(raw: {'transform': 'translateY(-2px)', 'box-shadow': '0 6px 18px color-mix(in srgb, var(--text) 12%, transparent)'}),
        css('&.primary').styles(
          backgroundColor: Color('var(--primary)'),
          // Background doubles as the on-primary color: near-white on blue-500
          // in light mode, near-black on blue-300 in dark mode.
          color: Color('var(--background)'),
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
          border: Border.all(width: 2.px, color: Color('var(--content-hr)')),
          backgroundColor: Color('color-mix(in srgb, var(--background) 94%, var(--text) 6%)'),
          raw: {'flex-direction': 'column', 'align-items': 'center', 'gap': '.25rem', 'box-shadow': '0 6px 20px color-mix(in srgb, var(--text) 8%, transparent)'},
        ),
        css('&.cloud').styles(raw: {'animation': 'home-breathe 3.5s ease-in-out infinite'}),
        css('.home-node-icon').styles(fontSize: 1.9.rem),
        css('.home-node-label').styles(fontSize: .75.rem, color: Color('var(--content-lead)')),
      ]),
      css('.home-lane').styles(
        position: Position.relative(),
        width: Unit.expression('clamp(70px, 12vw, 130px)'),
        height: 14.px,
      ),
      css('.home-lane::before').styles(
        position: Position.absolute(top: 6.px, left: Unit.zero, right: Unit.zero),
        height: 2.px,
        raw: {'content': '""', 'background': 'var(--content-hr)'},
      ),
      css('.home-packet', [
        css('&').styles(
          position: Position.absolute(),
          width: 10.px,
          height: 10.px,
          radius: BorderRadius.circular(5.px),
          raw: {'background': 'var(--primary)', 'box-shadow': '0 0 12px color-mix(in srgb, var(--primary) 90%, transparent)'},
        ),
        css('&.up').styles(position: Position.absolute(top: (-2).px), raw: {'animation': 'home-travel 2.2s linear infinite'}),
        css('&.down').styles(position: Position.absolute(top: 8.px), raw: {'animation': 'home-travel 2.2s linear infinite reverse', 'animation-delay': '1.1s', 'opacity': '.75'}),
        css('&.delayed').styles(raw: {'animation-delay': '.55s'}),
        css('&.down.delayed').styles(raw: {'animation-delay': '1.65s'}),
      ]),
      css('.home-content', [
        css('&').styles(
          margin: Margin.symmetric(horizontal: Unit.auto),
          padding: Padding.only(left: 1.5.rem, right: 1.5.rem, bottom: 4.rem),
          maxWidth: 52.rem,
        ),
        // Clear section structure: centered headings with a gradient accent.
        // (Heading-anchor extension renders h2 as a flex row of <span> + <a>,
        // so center with justify-content and hang the accent off the span.)
        css('& h2').styles(
          margin: Margin.only(top: 4.rem, bottom: 1.25.rem),
          textAlign: TextAlign.center,
          fontSize: Unit.expression('clamp(1.6rem, 5vw, 2.2rem)'),
          raw: {'justify-content': 'center'},
        ),
        css('& h2 > span::after').styles(
          display: Display.block,
          width: 3.5.rem,
          height: 3.px,
          margin: Margin.only(top: 0.6.rem, left: Unit.auto, right: Unit.auto),
          radius: BorderRadius.circular(2.px),
          raw: {
            'content': '""',
            'background': 'linear-gradient(90deg, var(--primary), color-mix(in srgb, var(--primary) 40%, transparent))',
          },
        ),
        // Wide, centered breakout for card grids inside the narrow prose column.
        css('.home-features, .home-stats, .home-build ul, .home-links').styles(
          position: Position.relative(left: 50.percent),
          width: Unit.expression('min(70rem, calc(100vw - 3rem))'),
          raw: {'transform': 'translateX(-50%)'},
        ),
        // Feature cards: responsive grid of equal-height cards.
        css('.home-features', [
          css('&').styles(
            display: Display.grid,
            margin: Margin.symmetric(vertical: 2.rem),
            raw: {
              'grid-template-columns': 'repeat(auto-fit, minmax(280px, 1fr))',
              'gap': '1.25rem',
            },
          ),
          css('.card').styles(
            height: 100.percent,
            margin: Margin.only(bottom: Unit.zero),
          ),
        ]),
        // "What you can build" use-case cards.
        css('.home-build ul', [
          css('&').styles(
            display: Display.grid,
            padding: Padding.zero,
            margin: Margin.symmetric(vertical: 2.rem),
            listStyle: ListStyle.none,
            raw: {
              // 2x2 on desktop, single column on narrow screens.
              'grid-template-columns': 'repeat(auto-fit, minmax(380px, 1fr))',
              'gap': '1.25rem',
            },
          ),
          css('& > li', [
            css('&').styles(
              padding: Padding.all(1.25.rem),
              margin: Margin.zero,
              border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
              radius: BorderRadius.circular(0.75.rem),
              backgroundColor: Color('color-mix(in srgb, var(--background) 94%, var(--text) 6%)'),
              raw: {
                'box-shadow': '0 1px 3px color-mix(in srgb, var(--text) 8%, transparent)',
                'transition': 'all .25s ease',
                'line-height': '1.65',
              },
            ),
            css('&:hover').styles(
              raw: {
                'transform': 'translateY(-2px)',
                'box-shadow': '0 8px 22px color-mix(in srgb, var(--text) 12%, transparent)',
              },
            ),
          ]),
        ]),
        // Stat tiles for "The numbers behind the claims".
        css('.home-stats', [
          css('&').styles(
            display: Display.grid,
            margin: Margin.symmetric(vertical: 2.rem),
            raw: {
              'grid-template-columns': 'repeat(auto-fit, minmax(240px, 1fr))',
              'gap': '1.25rem',
            },
          ),
          css('.home-stat').styles(
            display: Display.flex,
            padding: Padding.all(1.5.rem),
            border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
            radius: BorderRadius.circular(0.75.rem),
            textAlign: TextAlign.center,
            backgroundColor: Color('color-mix(in srgb, var(--background) 94%, var(--text) 6%)'),
            raw: {
              'flex-direction': 'column',
              'align-items': 'center',
              'gap': '.5rem',
              'box-shadow': '0 1px 3px color-mix(in srgb, var(--text) 8%, transparent)',
            },
          ),
          css('.home-stat-value').styles(
            fontSize: Unit.expression('clamp(1.6rem, 4vw, 2.2rem)'),
            fontWeight: FontWeight.w700,
            raw: {
              'background': 'linear-gradient(90deg, var(--primary), var(--content-headings))',
              '-webkit-background-clip': 'text',
              'background-clip': 'text',
              'color': 'transparent',
            },
          ),
          css('.home-stat-label').styles(
            fontSize: 0.9.rem,
            color: Color('var(--content-lead)'),
            raw: {'line-height': '1.55'},
          ),
        ]),
        // "Explore the docs" link-group cards.
        css('.home-links', [
          css('&').styles(
            display: Display.grid,
            margin: Margin.symmetric(vertical: 2.rem),
            raw: {
              'grid-template-columns': 'repeat(auto-fit, minmax(300px, 1fr))',
              'gap': '1.25rem',
            },
          ),
          css('& > p').styles(
            padding: Padding.all(1.25.rem),
            margin: Margin.zero,
            border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
            radius: BorderRadius.circular(0.75.rem),
            fontSize: 0.95.rem,
            backgroundColor: Color('color-mix(in srgb, var(--background) 94%, var(--text) 6%)'),
            raw: {'line-height': '1.9', 'box-shadow': '0 1px 3px color-mix(in srgb, var(--text) 8%, transparent)'},
          ),
        ]),
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
