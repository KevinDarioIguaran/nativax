import 'element.dart';

/// Geometry of a rendered element in viewport coordinates (CSS px), plus
/// its scroll metrics. Produced by the renderer for `getBoundingClientRect`,
/// `offset*`, `client*` and `scroll*`.
class ElementBox {
  const ElementBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.offsetX = 0,
    this.offsetY = 0,
    this.clientWidth = 0,
    this.clientHeight = 0,
    this.scrollWidth = 0,
    this.scrollHeight = 0,
    this.scrollTop = 0,
    this.scrollLeft = 0,
    double? offsetWidth,
    double? offsetHeight,
  }) : offsetWidth = offsetWidth ?? width,
       offsetHeight = offsetHeight ?? height;

  /// Bounds of the (possibly transformed) border box relative to the
  /// viewport, as `getBoundingClientRect` reports them.
  final double x;
  final double y;
  final double width;
  final double height;

  /// Position relative to the offset parent (approximated as the document).
  final double offsetX;
  final double offsetY;
  final double clientWidth;
  final double clientHeight;
  final double scrollWidth;
  final double scrollHeight;
  final double scrollTop;
  final double scrollLeft;

  /// Layout size of the border box, ignoring transforms (`offsetWidth`).
  final double offsetWidth;
  final double offsetHeight;

  Map<String, Object?> toJson() => {
    'offsetWidth': offsetWidth,
    'offsetHeight': offsetHeight,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'clientWidth': clientWidth,
    'clientHeight': clientHeight,
    'scrollWidth': scrollWidth,
    'scrollHeight': scrollHeight,
    'scrollTop': scrollTop,
    'scrollLeft': scrollLeft,
  };
}

/// Implemented by a renderer so scripts can query layout and scroll.
abstract interface class LayoutHost {
  /// The element's box, or null when it is not rendered.
  ElementBox? boxOf(Element element);

  void scrollIntoView(
    Element element, {
    bool smooth = false,
    String block = 'start',
  });

  double get scrollX;
  double get scrollY;
  double get viewportWidth;
  double get viewportHeight;
  double get documentHeight;
  void scrollTo(double x, double y, {bool smooth = false});

  /// Converts a global (screen) position to viewport coordinates.
  (double, double) toViewport(double globalX, double globalY);

  /// Innermost rendered element at viewport coordinates.
  Element? elementFromPoint(double x, double y);

  /// Rendered elements under viewport coordinates, innermost first.
  List<Element> elementsFromPoint(double x, double y);

  /// Whether the document is currently being scrolled. Renderers use it to
  /// defer hover hit-testing, which would otherwise restyle large subtrees on
  /// every wheel/drag frame.
  bool get isScrolling;
}

/// Implemented by a renderer to back `<canvas>` 2D contexts. Scripts record
/// drawing commands; the renderer replays them onto the canvas bitmap.
abstract interface class CanvasHost {
  /// Applies [ops] to [canvas]'s bitmap of [width]×[height] device pixels.
  void draw(Element canvas, int width, int height, List<Object?> ops);

  /// Text metrics for `measureText` (`width`, `ascent`, `descent`).
  Map<String, double> measureText(String font, String text);
}

/// The GPU surface a `<canvas>` element shows (WebGL contexts and
/// `transferControlToOffscreen`), set by the bindings and read by the
/// renderer. Surface ids come from the native GL layer (`GlSurfaces`).
final Expando<int> canvasSurfaces = Expando('nativax.canvasSurface');
