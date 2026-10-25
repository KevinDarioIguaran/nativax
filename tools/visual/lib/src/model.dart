/// Data model shared by the visual judge.
library;

class BoxRect {
  const BoxRect(this.x, this.y, this.width, this.height);

  factory BoxRect.fromJson(List<dynamic> json) => BoxRect(
    (json[0] as num).toDouble(),
    (json[1] as num).toDouble(),
    (json[2] as num).toDouble(),
    (json[3] as num).toDouble(),
  );

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;
  double get area => width <= 0 || height <= 0 ? 0 : width * height;
  bool get isEmpty => width <= 0 || height <= 0;

  double maxPositionDelta(BoxRect other) {
    final dx = (x - other.x).abs();
    final dy = (y - other.y).abs();
    return dx > dy ? dx : dy;
  }

  double maxSizeDelta(BoxRect other) {
    final dw = (width - other.width).abs();
    final dh = (height - other.height).abs();
    return dw > dh ? dw : dh;
  }

  double iou(BoxRect other) {
    final left = x > other.x ? x : other.x;
    final top = y > other.y ? y : other.y;
    final rightEdge = right < other.right ? right : other.right;
    final bottomEdge = bottom < other.bottom ? bottom : other.bottom;
    final w = rightEdge - left;
    final h = bottomEdge - top;
    if (area == 0 || other.area == 0) {
      // Degenerate boxes (for example a 0 % progress bar) have no area to
      // intersect; identical boxes are still a perfect match.
      final same =
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height;
      return same ? 1 : 0;
    }
    if (w <= 0 || h <= 0) return 0;
    final intersection = w * h;
    final union = area + other.area - intersection;
    return union <= 0 ? 1 : intersection / union;
  }

  BoxRect intersect(BoxRect other) {
    final left = x > other.x ? x : other.x;
    final top = y > other.y ? y : other.y;
    final rightEdge = right < other.right ? right : other.right;
    final bottomEdge = bottom < other.bottom ? bottom : other.bottom;
    return BoxRect(left, top, rightEdge - left, bottomEdge - top);
  }

  BoxRect inset(double amount) =>
      BoxRect(x + amount, y + amount, width - amount * 2, height - amount * 2);

  bool containsPoint(double px, double py) =>
      px >= x && py >= y && px < right && py < bottom;

  List<double> toJson() => [x, y, width, height];

  @override
  String toString() =>
      '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)} x ${height.toStringAsFixed(1)})';
}

class ElementSnapshot {
  ElementSnapshot({
    required this.path,
    required this.tag,
    required this.rect,
    required this.styles,
    this.text,
  });

  factory ElementSnapshot.fromJson(Map<String, dynamic> json) =>
      ElementSnapshot(
        path: json['path'] as String,
        tag: json['tag'] as String? ?? '',
        rect: BoxRect.fromJson(json['rect'] as List<dynamic>),
        styles:
            (json['styles'] as Map?)?.map(
              (k, v) => MapEntry(k as String, v as String),
            ) ??
            const {},
        text: json['text'] as String?,
      );

  final String path;
  final String tag;
  final BoxRect rect;
  final Map<String, String> styles;
  final String? text;

  String get shortName {
    final id = path.lastIndexOf('#');
    if (id >= 0) return path.substring(id);
    final i = path.lastIndexOf('>');
    return i >= 0 ? path.substring(i + 1) : path;
  }
}

class ProbeSnapshot {
  ProbeSnapshot({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.dpr,
    required this.documentWidth,
    required this.documentHeight,
    required this.elements,
    this.externalResources = 0,
    this.title = '',
  });

  factory ProbeSnapshot.fromJson(Map<String, dynamic> json) {
    final viewport = json['viewport'] as Map<String, dynamic>? ?? const {};
    final document = json['document'] as Map<String, dynamic>? ?? const {};
    final elements = (json['elements'] as List<dynamic>? ?? const [])
        .map((e) => ElementSnapshot.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return ProbeSnapshot(
      viewportWidth: (viewport['width'] as num?)?.round() ?? 0,
      viewportHeight: (viewport['height'] as num?)?.round() ?? 0,
      dpr: (viewport['dpr'] as num?)?.toDouble() ?? 1,
      documentWidth: (document['width'] as num?)?.round() ?? 0,
      documentHeight: (document['height'] as num?)?.round() ?? 0,
      elements: elements,
      externalResources: (json['externalResources'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
    );
  }

  final int viewportWidth;
  final int viewportHeight;
  final double dpr;
  final int documentWidth;
  final int documentHeight;
  final List<ElementSnapshot> elements;
  final int externalResources;
  final String title;

  late final Map<String, ElementSnapshot> byPath = {
    for (final e in elements) e.path: e,
  };
}

class PageSource {
  const PageSource({
    required this.id,
    required this.suite,
    required this.entry,
    required this.directory,
  });

  /// Stable identifier used for artifact folders and reports.
  final String id;
  final String suite;

  /// Absolute path to the HTML entry point.
  final String entry;

  /// Directory that contains the entry point and its relative assets.
  final String directory;
}
