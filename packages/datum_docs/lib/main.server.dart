// The entrypoint for the **server** environment.
//
// The [main] method will only be executed on the server during pre-rendering.
// To run code on the client, use the @client annotation.

// Server-specific jaspr import.
import 'package:datum_docs/components/cached_github_button.dart';
import 'package:datum_docs/components/custom_header.dart';
import 'package:datum_docs/components/custom_image.dart';
import 'package:datum_docs/components/enhanced_theme_toggle.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/tabs.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.server.options.dart';

import 'components/code_block.dart';
import 'components/steps.dart';
import 'components/card.dart';
import 'components/badge.dart';
import 'components/tip.dart';
import 'components/home_layout.dart';
import 'components/responsive_docs_layout.dart';
import 'page_extensions.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // Starts the app.
  //
  // [ContentApp] spins up the content rendering pipeline from jaspr_content to render
  // your markdown files in the content/ directory to a beautiful documentation site.
  runApp(
    ContentApp(
      // Enables mustache templating inside the markdown files.
      templateEngine: MustacheTemplateEngine(),
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
        // Estimates reading time based on word count.
        ReadingTimeExtension(),
        // Adds SEO enhancements like meta tags and structured data.
        SEOEnhancementsExtension(),
        // Adds last modified date based on file modification time.
        LastModifiedExtension(),
        // Generates breadcrumb navigation data.
        BreadcrumbExtension(),
        // Generates previous/next page navigation (basic implementation).
        PageNavigationExtension(),
      ],
      components: [
        // Adds syntax highlighting to code blocks.
        CodeBlock(
          defaultLanguage: 'dart',
          grammars: {},
        ),
        // Step-by-step instructions component
        Steps(),
        // Card component for highlighting content
        Card(),
        // Badge component for status indicators
        Badge(),
        // Custom tip component for helpful information
        Tip(),
        // Comparison table component for feature comparisons
        //// ComparisonTable(),
        // Adds a custom Jaspr component to be used as <Clicker/> in markdown.
        // CustomComponent(
        //   pattern: 'Clicker',
        //   builder: (_, __, ___) => Clicker(),
        // ),
        // Adds zooming and caption support to images.
        CustomImage(zoom: false),
        Tabs(),
      ],

      layouts: [
        // Enhanced responsive layout for documentation sites (default).
        ResponsiveDocsLayout(
          header: CustomHeader(
            title: 'Datum',
            subtitle: "Data, Seamlessly Synced",
            logo: '/images/logo.webp',
            includeSearch: true,
            navigationItems: [
              // Enables switching between light and dark mode.
              EnhancedThemeToggle(),
              // Shows github stats.
              CachedGitHubButton(
                repo: 'shreemanarjun/datum',
              ),
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
                  SidebarLink(text: "Changelog", href: '/changelog'),
                  SidebarLink(text: "Costs and Licensing", href: '/costs_licensing'),
                  SidebarLink(text: "🚀 Coming Soon", href: '/coming_soon'),
                ],
              ),
              SidebarGroup(
                title: 'Troubleshooting',
                links: [
                  SidebarLink(text: "🔧 Common Errors", href: '/troubleshooting/common_errors'),
                  SidebarLink(text: "⚡ Performance Issues", href: '/troubleshooting/performance'),
                  SidebarLink(text: "🔄 Migration Problems", href: '/troubleshooting/migration'),
                  SidebarLink(text: "🔌 Adapter Issues", href: '/troubleshooting/adapters'),
                ],
              ),
              SidebarGroup(
                title: 'Guides',
                links: [
                  SidebarLink(text: "Define Your Entity", href: '/guides/entity_define'),
                  SidebarLink(text: "Code Generation", href: '/guides/code_generation'),
                  SidebarLink(text: "Automated Relationships", href: '/guides/code_generation_relationships'),
                  SidebarLink(text: "Initialization & Global API", href: '/guides/initialization'),
                  SidebarLink(text: "Working with Relationships", href: '/guides/relationships'),
                  SidebarLink(text: "Cascading Delete", href: '/guides/cascading_delete'),
                  SidebarLink(text: "Querying Data", href: '/guides/querying'),
                  SidebarLink(text: "Define Your Local Adapter", href: '/guides/local_adapter_implement'),
                  SidebarLink(text: "Define Your Remote Adapter", href: '/guides/remote_adapter_implement'),
                  SidebarLink(text: "Datum Singleton API", href: '/guides/singleton_api'),
                  SidebarLink(text: "Sync Patterns", href: '/guides/sync_patterns'),
                  SidebarLink(text: "Advanced Sync Patterns", href: '/guides/advanced_sync'),
                  SidebarLink(text: "Schema Migrations", href: '/guides/migrations'),
                  SidebarLink(text: "Typed Schemas & Auto-Migration", href: '/guides/typed_schema'),
                  SidebarLink(text: "Collaborative Editing & CRDTs", href: '/guides/collaborative_editing'),
                  SidebarLink(text: "Testing Your Sync Stack", href: '/guides/testing'),
                ],
              ),
              SidebarGroup(
                title: 'Performance',
                links: [
                  SidebarLink(text: "Incremental Sync", href: '/guides/performance/incremental_sync'),
                  SidebarLink(text: "Performance Tuning", href: '/guides/performance/tuning'),
                ],
              ),
              SidebarGroup(
                title: 'Custom Adapters',
                links: [
                  SidebarLink(text: "Hive Local Adapter", href: '/guides/custom_adapters/hive_adapter'),
                  SidebarLink(text: "SQLite Local Adapter", href: '/guides/custom_adapters/sqlite_adapter'),
                  SidebarLink(text: "Isar Local Adapter", href: '/guides/custom_adapters/isar_adapter'),
                  SidebarLink(text: "REST API Remote Adapter", href: '/guides/custom_adapters/rest_api_adapter'),
                  SidebarLink(text: "Firebase Remote Adapter", href: '/guides/custom_adapters/firebase_adapter'),
                  SidebarLink(text: "Supabase Remote Adapter", href: '/guides/custom_adapters/supabase_adapter'),
                ],
              ),

              SidebarGroup(
                title: 'Modules',
                links: [
                  SidebarLink(text: "Core", href: '/modules/core'),
                  SidebarLink(text: "Query", href: '/modules/query'),
                  SidebarLink(text: "Migration", href: '/modules/migration'),
                  SidebarLink(text: "Health", href: '/modules/health'),
                  SidebarLink(text: "Observers & Middleware", href: '/modules/observers'),
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
                  position: Position.fixed(bottom: 0.px, right: 24.px),
                  padding: Spacing.only(bottom: 24.px),
                  backgroundColor: Color('var(--background)'),
                  raw: {
                    'transition': 'all 0.3s ease-in-out',
                    //'box-shadow': '0 -2px 10px rgba(0, 0, 0, 0.08)',
                  },
                ),
                [
                  div(
                    styles: Styles(
                      display: Display.flex,
                      flexDirection: FlexDirection.column,
                      alignItems: AlignItems.end,
                      gap: Gap(row: 8.px),
                    ),
                    [
                      div(
                        styles: Styles(
                          display: Display.flex,
                          padding: Spacing.symmetric(horizontal: 8.px, vertical: 4.px),
                          radius: BorderRadius.all(Radius.circular(12.px)),
                          alignItems: AlignItems.center,
                          gap: Gap(row: 6.px),
                          backgroundColor: Color('color-mix(in srgb, var(--primary) 10%, transparent)'),
                        ),
                        [
                          span(
                            styles: Styles(
                              color: Color('var(--primary)'),
                              fontSize: 0.6875.rem,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.025.em,
                            ),
                            [Component.text('v1.1.0')],
                          ),
                          div(
                            styles: Styles(
                              width: 6.px,
                              height: 6.px,
                              radius: BorderRadius.circular(50.percent),
                              backgroundColor: Color('var(--primary)'),
                            ),
                            [],
                          ),
                        ],
                      ),
                      JasprBadge.lightTwoTone(),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        // Landing page: raw-Jaspr hero, no sidebar (frontmatter `layout: home`).
        HomeLayout(
          header: CustomHeader(
            title: 'Datum',
            subtitle: "Data, Seamlessly Synced",
            logo: '/images/logo.webp',
            includeSearch: true,
            navigationItems: [
              EnhancedThemeToggle(),
              CachedGitHubButton(repo: 'shreemanarjun/datum'),
            ],
          ),
        ),
      ],

      theme: ContentTheme(
        // Customizes the default theme colors.
        primary: ThemeColor(ThemeColors.blue.$500, dark: ThemeColors.blue.$300),
        background: ThemeColor(ThemeColors.slate.$50, dark: ThemeColors.zinc.$950),
        colors: [
          ContentColors.quoteBorders.apply(ThemeColors.blue.$400),
          ContentColors.preBg.apply(ThemeColor(ThemeColors.slate.$800, dark: ThemeColors.slate.$800)),
        ],
      ),
    ),
  );
}
