import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// A component for displaying numbered step-by-step instructions.
///
/// Usage in markdown:
/// <Steps>
/// 1. First step content here
/// 2. Second step content here
/// 3. Third step content here
/// </Steps>
class Steps extends CustomComponentBase {
  Steps();

  @override
  final Pattern pattern = 'Steps';

  @override
  Component apply(String name, Map<String, String> attributes, Component? child) {
    return _StepsComponent(child: child);
  }

  @override
  Component? create(Node node, NodesBuilder builder) {
    if (node case ElementNode(tag: 'Steps', :final children)) {
      // Extract raw text content from the element
      final content = children?.map((child) => child.innerText).join('\n') ?? '';
      return _StepsComponent(content: content);
    }
    return null;
  }

  @css
  static List<StyleRule> get styles => [
    css('.steps', [
      css('&').styles(
        padding: Padding.zero,
        margin: Margin.symmetric(vertical: 2.rem),
        raw: {'counter-reset': 'step-counter'},
      ),
      // More specific selectors to override Card component styles
      css('&.steps > li, &.steps li').styles(
        display: Display.flex,
        padding: Padding.symmetric(vertical: 0.75.rem, horizontal: 1.rem),
        margin: Margin.only(bottom: 1.5.rem),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        radius: BorderRadius.circular(0.75.rem),
        alignItems: AlignItems.start,
        gap: Gap(column: 1.rem),
        backgroundColor: Color('var(--background)'),
        raw: {
          'position': 'relative',
          'transition': 'all 0.2s ease-in-out',
          'box-shadow': '0 1px 3px color-mix(in srgb, var(--text) 10%, transparent)',
        },
      ),
      css('&.steps > li:hover, &.steps li:hover').styles(
        backgroundColor: Color('color-mix(in srgb, var(--background) 80%, transparent)'),
        raw: {
          'transform': 'translateY(-1px)',
          'box-shadow': '0 4px 12px color-mix(in srgb, var(--text) 15%, transparent)',
        },
      ),
      css('&.steps > li:last-child, &.steps li:last-child').styles(
        margin: Margin.only(bottom: Unit.zero),
      ),
      css('&.steps > li::before, &.steps li::before').styles(
        raw: {
          'content': 'counter(step-counter)',
          'counter-increment': 'step-counter',
          'position': 'absolute',
          'top': '0.5rem',
          'left': '0.5rem',
          'display': 'flex',
          'align-items': 'center',
          'justify-content': 'center',
          'width': '1.25rem',
          'height': '1.25rem',
          'background-color': 'var(--primary)',
          'color': 'var(--primary-foreground)',
          'border-radius': '50%',
          'font-size': '0.75rem',
          'font-weight': '700',
          'border': '2px solid var(--background)',
          'box-shadow': '0 1px 4px color-mix(in srgb, var(--primary) 30%, transparent)',
          'z-index': '1',
        },
      ),
      css('&.steps > li > .step-content, &.steps li > .step-content').styles(
        margin: Margin.only(left: 2.5.rem),
        flex: Flex(grow: 1),
        color: Color('var(--text)'),
        raw: {'line-height': '1.6'},
      ),
      css('&.steps > li > .step-content p, &.steps li > .step-content p').styles(
        margin: Margin.only(bottom: 0.5.rem),
      ),
      css('&.steps > li > .step-content p:last-child, &.steps li > .step-content p:last-child').styles(
        margin: Margin.only(bottom: Unit.zero),
      ),
      css('&.steps > li > .step-content pre, &.steps li > .step-content pre').styles(
        padding: Padding.all(1.rem),
        margin: Margin.symmetric(vertical: 1.rem),
        border: Border.all(width: 1.px, color: Color('var(--content-hr)')),
        radius: BorderRadius.circular(0.5.rem),
        backgroundColor: Color('color-mix(in srgb, var(--text) 8%, transparent)'),
        raw: {'overflow': 'auto', 'box-shadow': 'inset 0 1px 3px color-mix(in srgb, var(--text) 10%, transparent)'},
      ),
      css('&.steps > li > .step-content code, &.steps li > .step-content code').styles(
        padding: Padding.symmetric(horizontal: 0.25.rem, vertical: 0.125.rem),
        radius: BorderRadius.circular(0.25.rem),
        color: Color('var(--text)'),
        backgroundColor: Color('color-mix(in srgb, var(--text) 8%, transparent)'),
        raw: {'font-size': '0.875em', 'font-family': 'var(--font-mono)'},
      ),
    ]),
  ];
}

class _StepsComponent extends StatelessComponent {
  const _StepsComponent({this.child, this.content});

  final Component? child;
  final String? content;

  @override
  Component build(BuildContext context) {
    final textContent = content ?? (child is Text ? (child as Text).text : null);

    if (textContent == null || textContent.isEmpty) {
      return ol(classes: 'steps', []);
    }

    // Parse the markdown content to extract individual steps
    final steps = _parseSteps(textContent);
    if (steps.isEmpty) {
      return ol(classes: 'steps', []);
    }

    return ol(classes: 'steps', steps);
  }

  List<Component> _parseSteps(String content) {
    final steps = <Component>[];
    final lines = content.split('\n').map((stepLine) => stepLine.trim()).where((stepLine) => stepLine.isNotEmpty);

    for (final stepLine in lines) {
      // Match lines that start with a number followed by a dot and space
      final stepMatch = RegExp(r'^(\d+)\.\s*(.*)$').firstMatch(stepLine);
      if (stepMatch != null) {
        final stepContent = stepMatch.group(2) ?? '';
        steps.add(
          li([
            div(classes: 'step-content', [
              // Parse the step content for markdown formatting
              _parseStepContent(stepContent),
            ]),
          ]),
        );
      }
    }

    return steps;
  }

  Component _parseStepContent(String content) {
    // Simple markdown parsing for bold text
    final parts = <Component>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    var lastIndex = 0;

    for (final match in regex.allMatches(content)) {
      // Add text before the match
      if (match.start > lastIndex) {
        parts.add(Component.text(content.substring(lastIndex, match.start)));
      }

      // Add the bold text
      parts.add(
        span(styles: Styles(fontWeight: FontWeight.w600), [
          Component.text(match.group(1)!),
        ]),
      );

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < content.length) {
      parts.add(Component.text(content.substring(lastIndex)));
    }

    if (parts.isEmpty) {
      return Component.text(content);
    }

    return span(parts);
  }
}
