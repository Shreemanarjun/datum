// The entrypoint for the **server** environment.
//
// The [main] method will only be executed on the server during pre-rendering.
// To run code on the client, use the @client annotation.

// Server-specific jaspr import.
import 'package:datum_docs/components/custom_header.dart';
import 'package:datum_docs/components/custom_image.dart';
import 'package:jaspr/server.dart';

import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/code_block.dart';
import 'package:jaspr_content/components/github_button.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'jaspr_options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultJasprOptions,
  );

  // Starts the app.
  //
  // [ContentApp] spins up the content rendering pipeline from jaspr_content to render
  // your markdown files in the content/ directory to a beautiful documentation site.
  runApp(
    ContentApp(
      // Enables mustache templating inside the markdown files.
      templateEngine: MustacheTemplateEngine(),
      dataDirectory: "content",
      debugPrint: true,
      parsers: [
        MarkdownParser(),
        HtmlParser(),
      ],
      extensions: [
        // Adds heading anchors to each heading.
        HeadingAnchorsExtension(),
        // Generates a table of contents for each page.
        TableOfContentsExtension(),
      ],
      components: [
        // The <Info> block and other callouts.
        Callout(),
        // Adds syntax highlighting to code blocks.
        CodeBlock(),
        // Adds a custom Jaspr component to be used as <Clicker/> in markdown.
        // CustomComponent(
        //   pattern: 'Clicker',
        //   builder: (_, __, ___) => Clicker(),
        // ),
        // Adds zooming and caption support to images.
        CustomImage(zoom: false),
      ],

      layouts: [
        // Out-of-the-box layout for documentation sites.
        DocsLayout(
          header: CustomHeader(
            title: 'Datum',
            logo: '/images/datum.png',
            items: [
              // Enables switching between light and dark mode.
              ThemeToggle(),
              // Shows github stats.
              GitHubButton(repo: 'shreemanarjun/datum'),
            ],
          ),
          sidebar: Sidebar(
            groups: [
              // Adds navigation links to the sidebar.
              SidebarGroup(
                links: [
                  SidebarLink(text: "Overview", href: '/'),
                ],
              ),
              SidebarGroup(
                title: 'Getting Started',
                links: [
                  SidebarLink(text: "Quick Start / Installation", href: '/getting_started/quick_start'),
                  SidebarLink(text: "About", href: '/about'),
                ],
              ),
              SidebarGroup(
                title: 'Modules',
                links: [
                  SidebarLink(text: "Core", href: '/modules/core'),
                  SidebarLink(text: "Adapter", href: '/modules/adapter'),
                  SidebarLink(text: "Configuration", href: '/modules/config'),
                  SidebarLink(text: "Utils", href: '/modules/utils'),
                ],
              ),
            ],
          ),
          footer: Builder(
            builder: (context) {
              return div(
                styles: Styles(
                  position: Position.fixed(bottom: 0.px, left: 0.px, right: 0.px),
                  padding: Spacing.only(
                    bottom: 24.px,
                  ),
                ),
                [
                  JasprBadge.lightTwoTone(),
                ],
              );
            },
          ),
        ),
      ],

      theme: ContentTheme(
        // Customizes the default theme colors.
        primary: ThemeColor(ThemeColors.blue.$500, dark: ThemeColors.blue.$300),
        background: ThemeColor(ThemeColors.slate.$50, dark: ThemeColors.zinc.$950),
        colors: [
          ContentColors.quoteBorders.apply(ThemeColors.blue.$400),
        ],
      ),
    ),
  );
}
