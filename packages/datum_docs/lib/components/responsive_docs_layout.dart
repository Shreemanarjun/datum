import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';
import 'page_metadata.dart';
import 'breadcrumb.dart';

/// A more responsive version of DocsLayout that supports bigger screens as well as small screens.
///
/// This layout includes a sidebar and a header with enhanced responsive behavior.
/// It also renders a table of contents when the [TableOfContentsExtension] is applied to the page.
///
/// It supports light and dark mode and custom theme colors.
///
/// The sidebar is usually a [Sidebar] component but may be any custom component.
/// The header is usually a [Header] component but may be any custom component.
///
/// Enhanced responsive features:
/// - Better breakpoints for ultra-wide screens (1440px, 1920px, 2560px)
/// - Improved sidebar behavior on large screens
/// - Optimized content spacing for different screen sizes
/// - Better table of contents positioning on large displays
class ResponsiveDocsLayout extends PageLayoutBase {
  const ResponsiveDocsLayout({this.sidebar, this.header, this.footer});

  /// The sidebar component to render, usually a [Sidebar].
  final Component? sidebar;

  /// The header component to render, usually a [Header].
  final Component? header;

  /// The footer component to render below the content.
  final Component? footer;

  @override
  String get name => 'responsive-docs';

  @override
  Iterable<Component> buildHead(Page page) sync* {
    yield* super.buildHead(page);

    // Add meta description if available
    final seoData = page.data['seo'] as Map<String, dynamic>?;
    final description = seoData?['description'] as String?;
    if (description != null && description.isNotEmpty) {
      yield meta(name: 'description', content: description);
    }

    yield Style(styles: _styles);
  }

  @override
  Component buildBody(Page page, Component child) {
    final pageData = page.data.page;

    return div(classes: 'responsive-docs', [
      if (header case final header?)
        div(classes: 'header-container', attributes: {if (sidebar != null) 'data-has-sidebar': ''}, [header]),
      div(classes: 'main-container', [
        div(classes: 'sidebar-barrier', attributes: {'role': 'button'}, []),
        if (sidebar case final sidebar?) div(classes: 'sidebar-container', [sidebar]),
        main_([
          div([
            div(classes: 'content-container', [
              div(classes: 'content-header', [
                Breadcrumb(),
                if (pageData['title'] case String title) h1([Component.text(title)]),
                if (pageData['description'] case String description) p([Component.text(description)]),
                if (pageData['image'] case String image) img(src: image, alt: pageData['imageAlt'] as String?),
                PageMetadata(),
              ]),
              child,
              if (footer case final footer?) div(classes: 'content-footer', [footer]),
            ]),
            aside(classes: 'toc', [
              if (page.data['toc'] case TableOfContents toc)
                div([
                  h3([Component.text('On this page')]),
                  toc.build(),
                ]),
            ]),
          ]),
        ]),
      ]),
    ]);
  }

  static List<StyleRule> get _styles => [
    // Global scroll padding for anchor links - increased for better header clearance
    css('html').styles(raw: {'scroll-padding-top': '7rem'}),
    css('body').styles(raw: {'scroll-padding-top': '7rem', 'margin-top': '0', 'padding-top': '0'}),

    // Enhanced sidebar styling
    css('.sidebar', [
      css('&').styles(
        border: Border.only(
          right: BorderSide(width: 1.px, color: Color('var(--content-hr)')),
        ),
        backgroundColor: Color('var(--background)'),
        raw: {'box-shadow': '0 0 4px rgba(0, 0, 0, 0.05)'},
      ),
      css('.sidebar-group', [
        css('h3').styles(
          padding: Padding.only(left: 0.75.rem, bottom: 0.0.rem),
          margin: Margin.only(bottom: 0.5.rem, top: Unit.zero),
          border: Border.only(
            bottom: BorderSide(width: 1.px, color: Color('var(--content-hr)')),
          ),
          color: ContentColors.headings,
          fontSize: 12.px,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5.px,
          raw: {'text-transform': 'uppercase'},
        ),
        css('li', [
          css('div', [
            css('&').styles(
              margin: Margin.only(bottom: 2.px),
              radius: BorderRadius.circular(6.px),
              transition: Transition('all', duration: 200.ms, curve: Curve.easeInOut),
            ),
            css('&:hover').styles(
              transform: Transform.translate(x: 2.px),
              backgroundColor: Color('color-mix(in srgb, var(--primary) 12%, transparent)'),
            ),
            css('&.active').styles(
              color: Color('var(--primary)'),
              fontWeight: FontWeight.w600,
              backgroundColor: Color('color-mix(in srgb, var(--primary) 15%, transparent)'),
              raw: {'box-shadow': '0 1px 2px color-mix(in srgb, var(--primary) 20%, transparent)'},
            ),
          ]),
          css('a').styles(
            padding: Padding.only(left: 16.px, top: 8.px, bottom: 8.px, right: 8.px),
            transition: Transition('color', duration: 150.ms, curve: Curve.easeInOut),
            color: Color('inherit'),
            textDecoration: TextDecoration.none,
            raw: {'border-radius': '6px'},
          ),
        ]),
      ]),
    ]),

    css('.responsive-docs', [
      css('.header-container', [
        css('&').styles(
          position: Position.fixed(top: Unit.zero, left: Unit.zero, right: Unit.zero),
          zIndex: ZIndex(10),
          border: Border.only(
            bottom: BorderSide(width: 1.px, color: Color('var(--content-hr)')),
          ),
          raw: {'backdrop-filter': 'none', 'background-color': 'var(--background) !important'},
        ),
        // Large screens - add subtle shadow and improve spacing
        css.media(MediaQuery.all(minWidth: 1440.px), [
          css('&').styles(
            raw: {'box-shadow': '0 2px 8px rgba(0, 0, 0, 0.08)'},
          ),
        ]),
        // Ultra-wide screens - enhance shadow and add more padding
        css.media(MediaQuery.all(minWidth: 1920.px), [
          css('&').styles(
            raw: {'box-shadow': '0 4px 16px rgba(0, 0, 0, 0.1)'},
          ),
        ]),
      ]),
      css('.main-container', [
        css('&').styles(
          maxWidth: 90.rem,
          padding: Padding.zero,
          margin: Margin.symmetric(horizontal: Unit.auto),
        ),
        // Extra large screens (1440px+)
        css.media(MediaQuery.all(minWidth: 1440.px), [
          css('&').styles(maxWidth: 120.rem),
        ]),
        // Ultra-wide screens (1920px+)
        css.media(MediaQuery.all(minWidth: 1920.px), [
          css('&').styles(maxWidth: 140.rem),
        ]),
        // 4K screens (2560px+)
        css.media(MediaQuery.all(minWidth: 2560.px), [
          css('&').styles(maxWidth: 160.rem),
        ]),
        css.media(MediaQuery.all(minWidth: 768.px), [
          css('&').styles(padding: Padding.symmetric(horizontal: 1.25.rem)),
        ]),
        css('.sidebar-barrier', [
          css('&').styles(
            position: Position.absolute(),
            zIndex: ZIndex(9),
            opacity: 0,
            pointerEvents: PointerEvents.none,
            backgroundColor: ContentColors.background,
            raw: {'inset': '0'},
          ),
          css('&:has(+ .sidebar-container.open)').styles(opacity: 0.5, pointerEvents: PointerEvents.auto),
        ]),
        css('.sidebar-container', [
          css('&').styles(
            position: Position.fixed(bottom: 1.rem, top: 4.rem),
            zIndex: ZIndex(10),
            width: 17.rem,
            overflow: Overflow.only(y: Overflow.auto),
            transition: Transition('transform', duration: 150.ms, curve: Curve.easeInOut),
            transform: Transform.translate(x: (-100).percent),
            // Modern scrollbar styling
            raw: {
              // Webkit browsers (Chrome, Safari, Edge)
              '&::-webkit-scrollbar': 'width: 8px',
              '&::-webkit-scrollbar-track': 'background: transparent',
              '&::-webkit-scrollbar-thumb': 'background: var(--content-hr)',
              '&::-webkit-scrollbar-thumb:hover': 'background: color-mix(in srgb, var(--content-captions) 60%, transparent)',
              '&::-webkit-scrollbar-thumb:active': 'background: color-mix(in srgb, var(--content-captions) 80%, transparent)',
              '&::-webkit-scrollbar-corner': 'background: transparent',
              // Firefox
              'scrollbar-width': 'thin',
              'scrollbar-color': 'var(--content-hr) transparent',
            },
          ),
          // Tablet and up
          css.media(MediaQuery.all(minWidth: 768.px), [css('&').styles(margin: Margin.only(left: (-1.25).rem))]),
          // Desktop and up
          css.media(MediaQuery.all(minWidth: 1024.px), [
            css('&').styles(
              margin: Margin.only(left: Unit.zero),
              transform: Transform.translate(x: Unit.zero),
            ),
          ]),
          // Large screens - increase sidebar width slightly
          css.media(MediaQuery.all(minWidth: 1440.px), [
            css('&').styles(width: 18.rem),
          ]),
          // Ultra-wide screens - increase sidebar width more
          css.media(MediaQuery.all(minWidth: 1920.px), [
            css('&').styles(width: 20.rem),
          ]),
          // Mobile/tablet styles
          css.media(MediaQuery.all(maxWidth: 1023.px), [
            css('&').styles(
              position: Position.fixed(top: Unit.zero),
              border: Border.only(
                right: BorderSide(width: 1.px, color: Color('#0000000d')),
              ),
              backgroundColor: ContentColors.background,
            ),
          ]),
          css('&.open').styles(transform: Transform.translate(x: Unit.zero)),
        ]),
        css('main', [
          css('&').styles(
            position: Position.relative(),
            padding: Padding.only(top: 7.rem),
          ),
          // Desktop and up
          css.media(MediaQuery.all(minWidth: 1024.px), [css('&').styles(padding: Padding.only(left: 17.rem))]),
          // Large screens - adjust for wider sidebar
          css.media(MediaQuery.all(minWidth: 1440.px), [css('&').styles(padding: Padding.only(left: 18.rem))]),
          // Ultra-wide screens - adjust for even wider sidebar
          css.media(MediaQuery.all(minWidth: 1920.px), [css('&').styles(padding: Padding.only(left: 20.rem))]),
          css('> div', [
            css('&').styles(
              display: Display.flex,
              padding: Padding.only(top: 2.rem, left: 1.rem, right: 1.rem),
            ),
            // Desktop and up
            css.media(MediaQuery.all(minWidth: 1024.px), [css('&').styles(padding: Padding.only(left: 4.rem))]),
            // Large screens - increase left padding
            css.media(MediaQuery.all(minWidth: 1440.px), [css('&').styles(padding: Padding.only(left: 6.rem))]),
            // Ultra-wide screens - increase left padding more
            css.media(MediaQuery.all(minWidth: 1920.px), [css('&').styles(padding: Padding.only(left: 8.rem))]),
            css('.content-container', [
              css('&').styles(
                minWidth: Unit.zero,
                padding: Padding.only(right: Unit.zero),
                flex: Flex(grow: 1, shrink: 1, basis: 0.percent),
              ),
              // Large screens - add right padding for better spacing
              css.media(MediaQuery.all(minWidth: 1280.px), [css('&').styles(padding: Padding.only(right: 3.rem))]),
              // Ultra-wide screens - increase right padding
              css.media(MediaQuery.all(minWidth: 1440.px), [css('&').styles(padding: Padding.only(right: 6.rem))]),
              // 4K screens - even more right padding
              css.media(MediaQuery.all(minWidth: 1920.px), [css('&').styles(padding: Padding.only(right: 8.rem))]),
              css('.content-header', [
                css('&').styles(
                  margin: Margin.only(bottom: 2.rem),
                  color: ContentColors.headings,
                ),
                css('h1').styles(
                  fontSize: 2.rem,
                  lineHeight: 2.25.rem,
                  // Large screens - increase title size
                  raw: {
                    '@media (min-width: 1440px)': 'font-size: 2.5rem; line-height: 2.75rem;',
                    '@media (min-width: 1920px)': 'font-size: 3rem; line-height: 3.25rem;',
                  },
                ),
                css('p').styles(
                  margin: Margin.only(top: .75.rem),
                  fontSize: 1.25.rem,
                  lineHeight: 1.25.rem,
                  // Large screens - increase description size
                  raw: {
                    '@media (min-width: 1440px)': 'font-size: 1.5rem; line-height: 1.5rem;',
                    '@media (min-width: 1920px)': 'font-size: 1.75rem; line-height: 1.75rem;',
                  },
                ),
                css('img').styles(
                  margin: Margin.only(top: 1.rem),
                  radius: BorderRadius.circular(0.375.rem),
                ),
              ]),
              css('.content-footer', [css('&').styles(margin: Margin.only(top: 2.rem))]),
            ]),
            css('aside.toc', [
              css('&').styles(
                display: Display.none,
                position: Position.relative(),
                width: 17.rem,
              ),
              // Large screens - show TOC earlier
              css.media(MediaQuery.all(minWidth: 1200.px), [css('&').styles(display: Display.block)]),
              // Large screens - increase TOC width
              css.media(MediaQuery.all(minWidth: 1440.px), [css('&').styles(width: 18.rem)]),
              // Ultra-wide screens - increase TOC width more
              css.media(MediaQuery.all(minWidth: 1920.px), [css('&').styles(width: 20.rem)]),
              css('> div', [css('&').styles(position: Position.sticky(top: 6.rem))]),
              css('h3').styles(
                margin: Margin.only(bottom: .5.rem),
                opacity: 0.75,
                fontSize: .875.rem,
                fontWeight: FontWeight.w600,
                lineHeight: 1.25.rem,
                // Large screens - increase TOC header size
                raw: {
                  '@media (min-width: 1440px)': 'font-size: 1rem;',
                  '@media (min-width: 1920px)': 'font-size: 1.125rem;',
                },
              ),
              css('ul').styles(margin: Margin.only(top: 1.rem)),
              css('li').styles(
                margin: Margin.only(top: .5.rem),
                fontSize: 14.px,
                // Large screens - increase TOC item size
                raw: {
                  '@media (min-width: 1440px)': 'font-size: 15px;',
                  '@media (min-width: 1920px)': 'font-size: 16px;',
                },
              ),
            ]),
          ]),
        ]),
      ]),
    ]),
  ];
}
