import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// A comparison table component for displaying feature comparisons.
///
/// Usage in markdown:
/// <ComparisonTable>
///   <TableHeader>Feature|Approach1|Approach2|Approach3</TableHeader>
///   <TableRow>Use Case|Value1|Value2|Value3</TableRow>
///   <TableRow>Complexity|Low|High|Medium</TableRow>
/// </ComparisonTable>
class ComparisonTable extends CustomComponentBase {
  ComparisonTable();

  @override
  final Pattern pattern = RegExp(r'ComparisonTable|TableHeader|TableRow');

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    switch (name) {
      case 'ComparisonTable':
        return _ComparisonTableComponent(child: child);
      case 'TableHeader':
        return _TableHeaderComponent(child: child);
      case 'TableRow':
        return _TableRowComponent(child: child);
      default:
        return Component.text('');
    }
  }

  @css
  static List<StyleRule> get styles => [
    css('.comparison-table', [
      css('&').styles(
        width: 100.percent,
        margin: Margin.only(bottom: 1.5.rem),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        radius: BorderRadius.circular(0.75.rem),
        backgroundColor: Color('var(--background)'),
        raw: {
          'overflow': 'hidden',
          'box-shadow': '0 4px 6px color-mix(in srgb, var(--text) 7%, transparent), 0 1px 3px color-mix(in srgb, var(--text) 10%, transparent)',
        },
      ),
      css('& table').styles(
        width: 100.percent,
        raw: {'border-collapse': 'collapse'},
      ),
      css('& thead').styles(
        backgroundColor: Color('color-mix(in srgb, var(--text) 8%, transparent)'),
      ),
      css('& th').styles(
        padding: Padding.symmetric(vertical: 1.rem, horizontal: 1.25.rem),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        color: Color('var(--text)'),
        textAlign: TextAlign.left,
        fontSize: 0.875.rem,
        fontWeight: FontWeight.w600,
        raw: {'text-transform': 'uppercase', 'letter-spacing': '0.05em'},
      ),
      css('& td').styles(
        padding: Padding.symmetric(vertical: 1.rem, horizontal: 1.25.rem),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        color: Color('var(--text)'),
        raw: {'line-height': '1.5'},
      ),
      css('& tbody tr').styles(
        raw: {
          'transition': 'background-color 0.2s ease',
        },
      ),
      css('& tbody tr:nth-child(even)').styles(
        backgroundColor: Color('color-mix(in srgb, var(--text) 4%, transparent)'),
      ),
      css('& tbody tr:hover').styles(
        backgroundColor: Color('color-mix(in srgb, var(--primary) 6%, transparent)'),
      ),
      // Status badges
      css('& .status-success').styles(
        display: Display.inlineBlock,
        padding: Padding.symmetric(horizontal: 0.5.rem, vertical: 0.25.rem),
        border: Border.all(width: 1.px, color: Color('hsl(142 76% 36% / 0.2)')),
        radius: BorderRadius.circular(9999.px),
        color: Color('hsl(142 76% 36%)'),
        fontSize: 0.75.rem,
        fontWeight: FontWeight.w600,
        backgroundColor: Color('hsl(142 76% 36% / 0.1)'),
      ),
      css('& .status-warning').styles(
        display: Display.inlineBlock,
        padding: Padding.symmetric(horizontal: 0.5.rem, vertical: 0.25.rem),
        border: Border.all(width: 1.px, color: Color('hsl(38 92% 50% / 0.2)')),
        radius: BorderRadius.circular(9999.px),
        color: Color('hsl(38 92% 50%)'),
        fontSize: 0.75.rem,
        fontWeight: FontWeight.w600,
        backgroundColor: Color('hsl(38 92% 50% / 0.1)'),
      ),
      css('& .status-info').styles(
        display: Display.inlineBlock,
        padding: Padding.symmetric(horizontal: 0.5.rem, vertical: 0.25.rem),
        border: Border.all(width: 1.px, color: Color('hsl(199 89% 48% / 0.2)')),
        radius: BorderRadius.circular(9999.px),
        color: Color('hsl(199 89% 48%)'),
        fontSize: 0.75.rem,
        fontWeight: FontWeight.w600,
        backgroundColor: Color('hsl(199 89% 48% / 0.1)'),
      ),
      // Icons and symbols
      css('& .icon-check').styles(
        color: Color('hsl(142 76% 36%)'),
        fontWeight: FontWeight.w600,
      ),
      css('& .icon-cross').styles(
        color: Color('hsl(0 84% 60%)'),
        fontWeight: FontWeight.w600,
      ),
      css('& .icon-manual').styles(
        color: Color('hsl(38 92% 50%)'),
        fontWeight: FontWeight.w600,
      ),
      css('& .icon-dot').styles(
        color: Color('var(--content-captions)'),
      ),
      css('& .icon-circle').styles(
        color: Color('var(--content-captions)'),
      ),
      css('& .icon-green').styles(
        color: Color('hsl(142 76% 36%)'),
      ),
      css('& .icon-yellow').styles(
        color: Color('hsl(38 92% 50%)'),
      ),
      css('& .icon-blue').styles(
        color: Color('hsl(199 89% 48%)'),
      ),
    ]),
  ];
}

class _ComparisonTableComponent extends StatelessComponent {
  const _ComparisonTableComponent({required this.child});

  final Component? child;

  @override
  Component build(BuildContext context) {
    return div(classes: 'comparison-table', [
      table([child ?? Component.text('')]),
    ]);
  }
}

class _TableHeaderComponent extends StatelessComponent {
  const _TableHeaderComponent({required this.child});

  final Component? child;

  @override
  Component build(BuildContext context) {
    if (child is Text) {
      final textChild = child as Text;
      final columns = textChild.text.split('|');
      return thead([
        tr(columns.map((column) => th([Component.text(column.trim())])).toList()),
      ]);
    }
    return thead([
      tr([
        th([child ?? Component.text('')]),
      ]),
    ]);
  }
}

class _TableRowComponent extends StatelessComponent {
  const _TableRowComponent({required this.child});

  final Component? child;

  @override
  Component build(BuildContext context) {
    if (child is Text) {
      final textChild = child as Text;
      final columns = textChild.text.split('|');
      return tr(columns.map((column) => td([_parseCellContent(column.trim())])).toList());
    }
    return tr([
      td([child ?? Component.text('')]),
    ]);
  }

  Component _parseCellContent(String content) {
    // Handle special status badges
    if (content.contains('<Badge variant="success">')) {
      final match = RegExp(r'<Badge variant="success">(.*?)</Badge>').firstMatch(content);
      if (match != null) {
        return span(classes: 'status-success', [Component.text(match.group(1)!)]);
      }
    }
    if (content.contains('<Badge variant="warning">')) {
      final match = RegExp(r'<Badge variant="warning">(.*?)</Badge>').firstMatch(content);
      if (match != null) {
        return span(classes: 'status-warning', [Component.text(match.group(1)!)]);
      }
    }
    if (content.contains('<Badge variant="info">')) {
      final match = RegExp(r'<Badge variant="info">(.*?)</Badge>').firstMatch(content);
      if (match != null) {
        return span(classes: 'status-info', [Component.text(match.group(1)!)]);
      }
    }

    // Handle icons and symbols
    if (content == '✅') return span(classes: 'icon-check', [Component.text('✓')]);
    if (content == '❌') return span(classes: 'icon-cross', [Component.text('✗')]);
    if (content == '🔧') return span(classes: 'icon-manual', [Component.text('🔧')]);
    if (content == '⚪') return span(classes: 'icon-circle', [Component.text('○')]);
    if (content == '🟡') return span(classes: 'icon-yellow', [Component.text('●')]);
    if (content == '🟢') return span(classes: 'icon-green', [Component.text('●')]);

    // Handle bold text
    if (content.startsWith('<b>') && content.endsWith('</b>')) {
      final textContent = content.substring(3, content.length - 4);
      return b([Component.text(textContent)]);
    }

    return Component.text(content);
  }
}
