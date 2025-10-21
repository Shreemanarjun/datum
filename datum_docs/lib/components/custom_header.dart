import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/components/sidebar_toggle_button.dart';

/// A header component with a logo, title, and additional items.
class CustomHeader extends StatelessComponent {
  const CustomHeader({
    required this.logo,
    required this.title,
    this.subtitle,
    this.leading = const [SidebarToggleButton()],
    this.items = const [],
    super.key,
  });

  /// The src href to render as the site logo.
  final String logo;

  /// The name of the site to render alongside the [logo].
  final String title;

  /// An optional subtitle to render below the [title].
  final String? subtitle;

  /// Components to render before the site logo and title.
  ///
  /// If not specified, defaults to a [SidebarToggleButton].
  final List<Component> leading;

  /// Other components to render in the header, such as site section links.
  final List<Component> items;

  @override
  Component build(BuildContext context) {
    return fragment([
      Document.head(children: [Style(styles: _styles)]),
      header(classes: 'header', [
        ...leading,
        a(classes: 'header-title', href: '/', [
          img(src: logo, alt: '$title Logo'),
          div(classes: 'header-title-text', [
            span(classes: 'header-main-title', [text(title)]),
            if (subtitle != null)
              span(classes: 'header-subtitle', [
                text(subtitle!),
              ]),
          ]),
        ]),
        div(classes: 'header-items', items),
      ]),
    ]);
  }

  static List<StyleRule> get _styles => [
    css('.header', [
      css('&').styles(
        display: Display.flex,
        height: 4.rem,
        maxWidth: 90.rem,
        padding: Padding.symmetric(horizontal: 1.rem, vertical: .25.rem),
        margin: Margin.symmetric(horizontal: Unit.auto),
        border: Border.only(
          bottom: BorderSide(color: Color('#0000000d'), width: 1.px),
        ),
        alignItems: AlignItems.center,
        gap: Gap(column: 1.rem),
      ),
      css.media(MediaQuery.all(minWidth: 768.px), [css('&').styles(padding: Padding.symmetric(horizontal: 2.5.rem))]),
      css('.header-title', [
        css('&').styles(
          display: Display.inlineFlex,
          alignItems: AlignItems.center,
          gap: Gap(column: .75.rem),
          flex: Flex(grow: 1),
          textDecoration: TextDecoration.none, // Remove underline from the link
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
        css('.header-main-title').styles(fontWeight: FontWeight.w700),
        css('.header-subtitle').styles(
          fontSize: 0.75.rem,
          fontWeight: FontWeight.w400,
        ),
        css('span').styles(fontWeight: FontWeight.w700),
      ]),
      css('.header-items', [
        css('&').styles(
          display: Display.flex,
          gap: Gap(column: 0.25.rem),
        ),
      ]),
    ]),
  ];
}
