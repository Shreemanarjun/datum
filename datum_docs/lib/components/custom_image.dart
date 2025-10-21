import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/components/_internal/zoomable_image.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// An image component with optional zooming and caption support.

class CustomImage implements CustomComponent {
  const CustomImage({this.zoom = false, this.replaceImg = true});

  static Component from({
    required String src,
    String? alt,
    String? caption,
    bool zoom = false,
    int? width,
    int? height,
    Key? key,
  }) {
    if (zoom) {
      // Assuming ZoomableImage can also accept width and height.
      // If not, you might need to adjust ZoomableImage or omit these properties.
      return ZoomableImage(src: src, alt: alt, caption: caption, key: key);
    }
    return _Image(src: src, alt: alt, caption: caption, width: width, height: height, key: key);
  }

  /// Whether to enable zooming on the image.
  final bool zoom;

  /// Whether to replace the default <img> tag with this component.
  final bool replaceImg;

  @override
  Component? create(Node node, NodesBuilder builder) {
    if (node
        case ElementNode(tag: 'img' || 'Image', :final attributes) ||
            ElementNode(tag: 'p', children: [ElementNode(tag: 'img' || 'Image', :final attributes)])) {
      assert(attributes.containsKey('src'), 'Image must have a "src" argument. Found $attributes');
      return from(
        src: attributes['src']!,
        alt: attributes['alt'],
        caption: attributes['caption'],
        zoom: zoom || attributes['zoom'] != null,
        width: int.tryParse(attributes['width'] ?? ''),
        height: int.tryParse(attributes['height'] ?? ''),
      );
    }
    return null;
  }

  @css
  static List<StyleRule> get styles => [
    css('figure.image', [
      css('&').styles(
        display: Display.flex,
        flexDirection: FlexDirection.column,
        alignItems: AlignItems.center,
      ),
    ]),
  ];
}

/// An image component with an optional caption.
class _Image extends StatelessComponent {
  const _Image({
    required this.src,
    this.alt,
    this.caption,
    this.width,
    this.height,
    super.key,
  });

  /// The image source URL.
  final String src;

  /// The image alt text.
  final String? alt;

  /// The image caption.
  final String? caption;

  /// The image width.
  final int? width;

  /// The image height.
  final int? height;

  @override
  Component build(BuildContext context) {
    return figure(classes: 'image', [
      img(src: src, alt: alt ?? caption, width: width, height: height),
      if (caption != null) figcaption([text(caption!)]),
    ]);
  }
}
