import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/components/sidebar_toggle_button.dart';
import 'package:datum_docs/components/enhanced_theme_toggle.dart';
import 'package:datum_docs/components/search_component.dart';

/// A header component with a logo, title, and navigation bar below.
class CustomHeader extends StatelessComponent {
  const CustomHeader({
    required this.logo,
    required this.title,
    this.subtitle,
    this.version = '1.1.0',
    this.leading = const [SidebarToggleButton()],
    this.items = const [],
    this.navigationItems = const [],
    this.includeSearch = false,
    super.key,
  });

  /// The src href to render as the site logo.
  final String logo;

  /// The name of the site to render alongside the [logo].
  final String title;

  /// An optional subtitle to render below the [title].
  final String? subtitle;

  /// The current version of the package.
  final String version;

  /// Components to render before the site logo and title.
  ///
  /// If not specified, defaults to a [SidebarToggleButton].
  final List<Component> leading;

  /// Other components to render in the header, such as site section links.
  final List<Component> items;

  /// Components to render in the navigation bar below the header.
  final List<Component> navigationItems;

  /// Whether to include the search component in the navigation bar.
  final bool includeSearch;

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      Document.head(
        children: [
          // Algolia site verification
          meta(
            name: 'algolia-site-verification',
            content: 'A6639029AF6B0912',
          ),
          Style(styles: _styles),
          Style(
            styles: [
              css('body').styles(
                padding: Padding.only(bottom: 80.px),
              ),
            ],
          ),
          ThemeScript(),
        ],
      ),
      // Single row header with everything
      header(classes: 'header', [
        div(classes: 'header-container', [
          // Left side: Logo and title
          div(classes: 'header-left', [
            ...leading,
            a(classes: 'header-title', href: '/', [
              img(src: logo, alt: '$title Logo'),
              div(classes: 'header-title-text', [
                div(classes: 'header-title-row', [
                  span(classes: 'header-main-title', [Component.text(title)]),
                  span(classes: 'header-version', [Component.text('v$version')]),
                ]),
                if (subtitle != null)
                  span(classes: 'header-subtitle', [
                    Component.text(subtitle!),
                  ]),
              ]),
            ]),
          ]),
          // Center: Search (if enabled)
          if (includeSearch)
            div(classes: 'header-center', [
              AlgoliaDocSearch.datum(),
            ]),
          // Right side: Actions and items
          div(classes: 'header-right', [
            div(classes: 'header-items', items),
            if (navigationItems.isNotEmpty) div(classes: 'header-actions', navigationItems),
          ]),
        ]),
      ]),
    ]);
  }

  static List<StyleRule> get _styles => [
    css('.header', [
      css('&').styles(
        display: Display.flex,
        minHeight: 4.rem,
        maxWidth: 90.rem,
        padding: Padding.symmetric(horizontal: 1.rem, vertical: 0.5.rem),
        margin: Margin.symmetric(horizontal: Unit.auto),
        alignItems: AlignItems.center,
        raw: {
          'backdrop-filter': 'none',
          'background-color': 'var(--background) !important',
          'border-bottom': '1px solid #0000000d',
        },
      ),
      css('.header-container', [
        css('&').styles(
          display: Display.flex,
          width: 100.percent,
          justifyContent: JustifyContent.spaceBetween,
          alignItems: AlignItems.center,
          gap: Gap(column: 1.rem),
        ),
      ]),
      css('.header-left', [
        css('&').styles(
          display: Display.flex,
          alignItems: AlignItems.center,
          gap: Gap(column: 0.75.rem),
        ),
      ]),
      css('.header-center', [
        css('&').styles(
          display: Display.flex,
          maxWidth: 20.rem,
          justifyContent: JustifyContent.center,
          flex: Flex(grow: 1),
        ),
      ]),
      css('.search-input-wrapper', [
        css('&').styles(
          width: 100.percent,
          maxWidth: 28.rem,
          raw: {'position': 'relative'},
        ),
      ]),
      css('.search-input', [
        css('&').styles(
          width: 100.percent,
          padding: Padding.symmetric(horizontal: 1.rem, vertical: 0.5.rem),
          radius: BorderRadius.all(Radius.circular(0.5.rem)),
          color: Color('var(--text)'),
          fontSize: 0.875.rem,
          backgroundColor: Color('var(--background)'),
          raw: {
            'outline': 'none',
            'transition': 'all 0.2s ease',
            'box-sizing': 'border-box',
            'border': '1px solid var(--content-hr)',
          },
        ),
        css('&:focus').styles(
          raw: {
            'border-color': 'var(--primary)',
            'box-shadow': '0 0 0 2px color-mix(in srgb, var(--primary) 20%, transparent)',
          },
        ),
        css('&::placeholder').styles(
          raw: {'color': 'var(--content-captions)'},
        ),
      ]),
      css('.header-right', [
        css('&').styles(
          display: Display.flex,
          alignItems: AlignItems.center,
          gap: Gap(column: 0.5.rem),
        ),
      ]),
      css('.header-title', [
        css('&').styles(
          display: Display.inlineFlex,
          alignItems: AlignItems.center,
          gap: Gap(column: .75.rem),
          textDecoration: TextDecoration.none,
          raw: {'position': 'relative'},
        ),
        css('img').styles(
          width: Unit.auto,
          height: 3.rem,
        ),
        css('.header-title-text').styles(
          display: Display.flex,
          flexDirection: FlexDirection.column,
          justifyContent: JustifyContent.center,
          fontWeight: FontWeight.bold,
        ),
        css('.header-title-row').styles(
          display: Display.flex,
          alignItems: AlignItems.center,
          gap: Gap(column: 0.5.rem),
        ),
        css('.header-main-title').styles(fontWeight: FontWeight.w700),
        css('.header-version').styles(
          padding: Padding.symmetric(horizontal: 0.375.rem, vertical: 0.125.rem),
          radius: BorderRadius.all(Radius.circular(0.25.rem)),
          color: Color('color-mix(in srgb, var(--text) 70%, transparent)'),
          fontSize: 0.75.rem,
          fontWeight: FontWeight.w500,
          backgroundColor: Color('color-mix(in srgb, var(--text) 8%, transparent)'),
        ),
        css('.header-subtitle').styles(
          fontSize: 0.75.rem,
          fontWeight: FontWeight.w400,
        ),
        css('span').styles(fontWeight: FontWeight.w700),
      ]),
      css('.header-items', [
        css('&').styles(
          display: Display.flex,
          alignItems: AlignItems.stretch,
          gap: Gap(column: 0.25.rem),
        ),
      ]),
      css('.header-actions', [
        css('&').styles(
          display: Display.flex,
          alignItems: AlignItems.start,
          gap: Gap(column: 0.1.rem),
        ),
        // Style individual action buttons
        css('a, button', [
          css('&').styles(
            display: Display.flex,
            width: 2.5.rem,
            height: 2.5.rem,
            padding: Padding.all(0.5.rem),
            radius: BorderRadius.all(Radius.circular(0.5.rem)),
            justifyContent: JustifyContent.center,
            alignItems: AlignItems.center,
            raw: {
              'transition': 'all 0.2s ease',
              'border': '1px solid var(--content-hr)',
              'background-color': 'var(--background)',
              'color': 'var(--text)',
              'flex-shrink': '0', // Prevent button shrinking
            },
          ),
          css('&:hover').styles(
            raw: {
              'background-color': 'color-mix(in srgb, var(--primary) 12%, transparent)',
              'border-color': 'var(--content-headings)',
            },
          ),
        ]),
        // The GitHub button carries repo text + star/fork counts — size it to
        // its content instead of the square icon-button width above.
        css('a.github-button').styles(
          width: Unit.auto,
          height: 2.5.rem,
          padding: Padding.symmetric(horizontal: 0.7.rem, vertical: 0.25.rem),
        ),
      ]),
    ]),
    // Desktop responsive styles
    css.media(MediaQuery.all(minWidth: 768.px), [
      css('.header').styles(
        minHeight: 5.rem,
        padding: Padding.only(left: 4.rem, right: 6.rem, top: 1.5.rem, bottom: 1.5.rem),
        margin: Spacing.only(right: 4.rem),
      ),
      css('.header-container').styles(
        justifyContent: JustifyContent.spaceBetween,
      ),
      css('.header-center').styles(
        maxWidth: 24.rem,
        margin: Margin.symmetric(horizontal: 1.rem),
        flex: Flex(grow: 1),
      ),
      css('.header-right').styles(
        padding: Padding.only(right: 4.rem),
        gap: Gap(column: 8.rem),
        flex: Flex(shrink: 0),
      ),
      css('.header-items').styles(
        gap: Gap(column: 0.5.rem),
      ),
      css('.search-input').styles(
        padding: Padding.only(top: 0.75.rem, right: 1.rem, bottom: 1.25.rem, left: 1.rem),
      ),
    ]),
    // Mobile responsive design
    css.media(MediaQuery.all(maxWidth: 640.px), [
      css('.header', [
        css('&').styles(
          minHeight: Unit.auto,
          padding: Padding.symmetric(horizontal: 0.75.rem, vertical: 0.5.rem),
        ),
        css('.header-container', [
          css('&').styles(
            flexDirection: FlexDirection.column,
            alignItems: AlignItems.stretch,
            gap: Gap(row: 1.rem),
          ),
        ]),
        css('.header-top-row', [
          css('&').styles(
            display: Display.flex,
            width: 100.percent,
            justifyContent: JustifyContent.spaceBetween,
            alignItems: AlignItems.center,
          ),
        ]),
        css('.header-left', [
          css('&').styles(
            justifyContent: JustifyContent.start,
          ),
          css('.header-title', [
            css('&').styles(
              gap: Gap(column: 0.5.rem),
            ),
            css('img').styles(
              height: 2.5.rem,
            ),
            css('.header-version').styles(
              padding: Padding.symmetric(horizontal: 0.25.rem, vertical: 0.0625.rem),
              fontSize: 0.625.rem,
            ),
            css('.header-subtitle').styles(
              raw: {'display': 'none !important'},
            ),
          ]),
        ]),
        css('.header-center').styles(
          margin: Margin.only(left: Unit.auto),
        ),
        css('.header-right', [
          css('&').styles(
            justifyContent: JustifyContent.center,
            gap: Gap(column: 0.75.rem),
          ),
          css('.header-actions', [
            css('&').styles(
              flexWrap: FlexWrap.wrap, // Tighter spacing on mobile
              justifyContent: JustifyContent.center,
              gap: Gap(column: 0.25.rem),
            ),
          ]),
        ]),
      ]),
    ]),
  ];
}
