/// Deterministic synthetic image pairs with ground-truth difference regions,
/// used to audit the pixel and region detectors. No randomness except a fixed
/// linear congruential generator, so every run produces identical bytes.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model.dart';
import '../png.dart';

const int datasetWidth = 160;
const int datasetHeight = 120;

class DatasetCase {
  const DatasetCase({
    required this.id,
    required this.description,
    required this.kind,
    required this.reference,
    required this.actual,
    required this.truth,
    required this.expectation,
  });

  final String id;
  final String description;

  /// `identical`, `important` or `unimportant`.
  final String kind;
  final RasterImage reference;
  final RasterImage actual;

  /// Semantic boxes a human reviewer would point at as "different". Empty for
  /// identical pairs and for differences that do not matter.
  final List<BoxRect> truth;

  /// What a correct detector should report, in words.
  final String expectation;

  bool get expectDifferent => truth.isNotEmpty;

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind,
    'description': description,
    'expectation': expectation,
    'expectDifferent': expectDifferent,
    'reference': {'width': reference.width, 'height': reference.height},
    'actual': {'width': actual.width, 'height': actual.height},
    'truth': [
      for (final t in truth)
        [t.x.toInt(), t.y.toInt(), t.width.toInt(), t.height.toInt()],
    ],
  };
}

/// A mutable canvas with the few primitives the dataset needs.
class Canvas {
  Canvas(this.width, this.height, [List<int> background = _white])
    : rgba = Uint8List(width * height * 4) {
    for (var i = 0; i < width * height; i++) {
      rgba[i * 4] = background[0];
      rgba[i * 4 + 1] = background[1];
      rgba[i * 4 + 2] = background[2];
      rgba[i * 4 + 3] = 255;
    }
  }

  final int width;
  final int height;
  final Uint8List rgba;

  /// Source-over fill with straight [opacity]; values are rounded per channel.
  void fill(int x, int y, int w, int h, List<int> color, {double opacity = 1}) {
    for (var yy = math.max(0, y); yy < math.min(height, y + h); yy++) {
      for (var xx = math.max(0, x); xx < math.min(width, x + w); xx++) {
        final i = (yy * width + xx) * 4;
        for (var c = 0; c < 3; c++) {
          rgba[i + c] = (color[c] * opacity + rgba[i + c] * (1 - opacity))
              .round();
        }
      }
    }
  }

  void border(int x, int y, int w, int h, List<int> color) {
    fill(x, y, w, 1, color);
    fill(x, y + h - 1, w, 1, color);
    fill(x, y, 1, h, color);
    fill(x + w - 1, y, 1, h, color);
  }

  /// Draws [text] with the 5×7 bitmap font, 6 px advance at scale 1.
  void text(int x, int y, String text, List<int> color, {int scale = 1}) {
    for (var k = 0; k < text.length; k++) {
      final glyph = _font[text[k]];
      if (glyph == null) {
        throw ArgumentError('no glyph for "${text[k]}"');
      }
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < 5; col++) {
          if (glyph[row][col] != '#') continue;
          fill(x + (k * 6 + col) * scale, y + row * scale, scale, scale, color);
        }
      }
    }
  }

  RasterImage toImage() => RasterImage(width, height, Uint8List.fromList(rgba));
}

const List<int> _white = [255, 255, 255];
const List<int> _black = [0, 0, 0];
const List<int> _header = [30, 41, 59];
const List<int> _button = [37, 99, 235];
const List<int> _buttonShade = [37, 82, 200];
const List<int> _cardFill = [241, 245, 249];
const List<int> _cardBorder = [148, 163, 184];
const List<int> _cardText = [51, 65, 85];
const List<int> _accent = [16, 185, 129];
const List<int> _rule = [226, 232, 240];
const List<int> _badge = [220, 38, 38];

/// Layout of the base page. Every case is a controlled edit of it.
class PageSpec {
  const PageSpec({
    this.background = _white,
    this.showButton = true,
    this.buttonColor = _button,
    this.cardY = 28,
    this.cardOpacity = 1,
    this.total = 'TOTAL 42',
    this.price = 'PRICE 1.50',
    this.badge = false,
    this.block = false,
    this.pixel = false,
  });

  final List<int> background;
  final bool showButton;
  final List<int> buttonColor;
  final int cardY;
  final double cardOpacity;
  final String total;
  final String price;
  final bool badge;
  final bool block;
  final bool pixel;
}

const BoxRect buttonBox = BoxRect(10, 30, 40, 16);
const BoxRect badgeBox = BoxRect(60, 30, 22, 11);
const BoxRect blockBox = BoxRect(132, 64, 6, 6);
const BoxRect pixelBox = BoxRect(120, 100, 1, 1);
BoxRect cardBox(int y) => BoxRect(90, y.toDouble(), 60, 52);

/// Glyph cell of character [index] of a scale-1 string drawn at ([x], [y]).
BoxRect glyphBox(int x, int y, int index) =>
    BoxRect((x + index * 6).toDouble(), y.toDouble(), 5, 7);

RasterImage renderPage(PageSpec spec) {
  final c = Canvas(datasetWidth, datasetHeight, spec.background);
  c.fill(0, 0, datasetWidth, 18, _header);
  c.text(6, 2, 'PRICE', _white, scale: 2);
  if (spec.showButton) {
    c.fill(
      buttonBox.x.toInt(),
      buttonBox.y.toInt(),
      buttonBox.width.toInt(),
      buttonBox.height.toInt(),
      spec.buttonColor,
    );
    c.text(24, 34, 'OK', _white);
  }
  c.text(10, 56, spec.total, _black);
  c.text(10, 70, spec.price, _black);

  // Card drawn into its own layer so opacity applies to the whole group.
  final card = Canvas(60, 52, _cardFill);
  card.border(0, 0, 60, 52, _cardBorder);
  card.text(14, 12, 'SAVE', _cardText);
  card.fill(10, 28, 40, 4, _accent);
  for (var y = 0; y < 52; y++) {
    for (var x = 0; x < 60; x++) {
      final i = (y * 60 + x) * 4;
      c.fill(90 + x, spec.cardY + y, 1, 1, [
        card.rgba[i],
        card.rgba[i + 1],
        card.rgba[i + 2],
      ], opacity: spec.cardOpacity);
    }
  }

  if (spec.badge) {
    c.fill(
      badgeBox.x.toInt(),
      badgeBox.y.toInt(),
      badgeBox.width.toInt(),
      badgeBox.height.toInt(),
      _badge,
    );
    c.text(62, 32, 'NEW', _white);
  }
  if (spec.block) {
    c.fill(
      blockBox.x.toInt(),
      blockBox.y.toInt(),
      blockBox.width.toInt(),
      blockBox.height.toInt(),
      _badge,
    );
  }
  if (spec.pixel) {
    c.fill(pixelBox.x.toInt(), pixelBox.y.toInt(), 1, 1, _black);
  }
  c.fill(0, 110, datasetWidth, 1, _rule);
  return c.toImage();
}

/// Nearest-neighbour scale around the top-left corner, same canvas size.
RasterImage scaleContent(RasterImage image, double factor) {
  final out = Uint8List(image.width * image.height * 4);
  for (var y = 0; y < image.height; y++) {
    final sy = (y / factor).floor().clamp(0, image.height - 1);
    for (var x = 0; x < image.width; x++) {
      final sx = (x / factor).floor().clamp(0, image.width - 1);
      final s = (sy * image.width + sx) * 4;
      final d = (y * image.width + x) * 4;
      out.setRange(d, d + 4, image.rgba, s);
    }
  }
  return RasterImage(image.width, image.height, out);
}

/// Imitates a different antialiasing rasterizer: every edge pixel (one whose
/// 4-neighbour has another colour) is mixed with that neighbour by a fraction
/// in [0.15, 0.45] drawn from a fixed LCG. Geometry and colours are unchanged.
RasterImage antialiasNoise(RasterImage image, {int seed = 20261026}) {
  final out = Uint8List.fromList(image.rgba);
  var state = seed;
  double next() {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state / 0x7fffffff;
  }

  final w = image.width, h = image.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      int? neighbour;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final j = (ny * w + nx) * 4;
        if (image.rgba[j] != image.rgba[i] ||
            image.rgba[j + 1] != image.rgba[i + 1] ||
            image.rgba[j + 2] != image.rgba[i + 2]) {
          neighbour = j;
          break;
        }
      }
      if (neighbour == null) continue;
      final f = 0.15 + 0.30 * next();
      for (var c = 0; c < 3; c++) {
        out[i +
            c] = (image.rgba[i + c] * (1 - f) + image.rgba[neighbour + c] * f)
            .round();
      }
    }
  }
  return RasterImage(w, h, out);
}

BoxRect _union(BoxRect a, BoxRect b) {
  final x = math.min(a.x, b.x), y = math.min(a.y, b.y);
  return BoxRect(
    x,
    y,
    math.max(a.right, b.right) - x,
    math.max(a.bottom, b.bottom) - y,
  );
}

/// The committed dataset, in a fixed order.
List<DatasetCase> buildDataset() {
  final base = renderPage(const PageSpec());
  const fullCanvas = BoxRect(0, 0, datasetWidth * 1.0, datasetHeight * 1.0);
  return [
    DatasetCase(
      id: 'identical',
      kind: 'identical',
      description: 'Both images are byte-identical renders of the base page.',
      reference: base,
      actual: renderPage(const PageSpec()),
      truth: const [],
      expectation: 'no mismatched pixels, no regions',
    ),
    DatasetCase(
      id: 'one-pixel',
      kind: 'important',
      description: 'One background pixel at (120,100) turns black.',
      reference: base,
      actual: renderPage(const PageSpec(pixel: true)),
      truth: const [pixelBox],
      expectation: 'one mismatched pixel; one 1x1 region',
    ),
    DatasetCase(
      id: 'small-block',
      kind: 'important',
      description: 'A 6x6 red block appears inside the card at (132,64).',
      reference: base,
      actual: renderPage(const PageSpec(block: true)),
      truth: const [blockBox],
      expectation: 'one region with bbox [132,64,6,6]',
    ),
    DatasetCase(
      id: 'layout-shift',
      kind: 'important',
      description:
          'The 60x52 card moves 24 px down (y 28 -> 52); old and new '
          'positions overlap by 28 px.',
      reference: base,
      actual: renderPage(const PageSpec(cardY: 52)),
      truth: [_union(cardBox(28), cardBox(52))],
      expectation: 'regions covering the union of old and new card boxes',
    ),
    DatasetCase(
      id: 'missing-component',
      kind: 'important',
      description: 'The blue OK button (40x16) is not rendered.',
      reference: base,
      actual: renderPage(const PageSpec(showButton: false)),
      truth: const [buttonBox],
      expectation: 'one region with the button box',
    ),
    DatasetCase(
      id: 'extra-component',
      kind: 'important',
      description:
          'A red NEW badge (22x11) is rendered that the reference '
          'does not have.',
      reference: base,
      actual: renderPage(const PageSpec(badge: true)),
      truth: const [badgeBox],
      expectation: 'one region with the badge box',
    ),
    DatasetCase(
      id: 'text-change',
      kind: 'important',
      description: 'TOTAL 42 becomes TOTAL 47: one glyph changes.',
      reference: base,
      actual: renderPage(const PageSpec(total: 'TOTAL 47')),
      truth: [glyphBox(10, 56, 7)],
      expectation: 'region(s) inside the changed glyph cell',
    ),
    DatasetCase(
      id: 'color-change',
      kind: 'important',
      description: 'Button background rgb(37,99,235) becomes rgb(37,82,200).',
      reference: base,
      actual: renderPage(const PageSpec(buttonColor: _buttonShade)),
      truth: const [buttonBox],
      expectation: 'one region with the button box',
    ),
    DatasetCase(
      id: 'opacity-change',
      kind: 'important',
      description: 'The card is composited at opacity 0.6 over the page.',
      reference: base,
      actual: renderPage(const PageSpec(cardOpacity: 0.6)),
      truth: [cardBox(28)],
      expectation: 'one region with the card box',
    ),
    DatasetCase(
      id: 'scaling',
      kind: 'important',
      description:
          'The whole page is scaled by 1.05 from the top-left corner '
          '(nearest neighbour), as with a wrong zoom or DPR.',
      reference: base,
      actual: scaleContent(base, 1.05),
      truth: const [fullCanvas],
      expectation: 'regions spread over the whole canvas',
    ),
    DatasetCase(
      id: 'viewport-size',
      kind: 'important',
      description:
          'The actual capture is 8 px narrower (152x120) with the same '
          'content: a viewport-size mismatch.',
      reference: base,
      actual: base.crop(datasetWidth - 8, datasetHeight),
      truth: const [BoxRect(152, 0, 8, 120)],
      expectation:
          'the size difference must be reported; the pipeline catches it with '
          'the hard screenshot-size check, not with pixels',
    ),
    DatasetCase(
      id: 'antialias-noise',
      kind: 'unimportant',
      description:
          'Every edge pixel is mixed 15-45 % with its neighbour (fixed LCG), '
          'imitating another rasterizer. Geometry and colours are unchanged.',
      reference: base,
      actual: antialiasNoise(base),
      truth: const [],
      expectation: 'no actionable region (differences are rasterization noise)',
    ),
    DatasetCase(
      id: 'tiny-important',
      kind: 'important',
      description:
          'PRICE 1.50 becomes PRICE 1 50: the 1 px decimal point disappears, '
          'changing the value tenfold.',
      reference: base,
      actual: renderPage(const PageSpec(price: 'PRICE 1 50')),
      truth: [glyphBox(10, 70, 7)],
      expectation: 'one region at the decimal point despite its size',
    ),
    DatasetCase(
      id: 'unimportant-many',
      kind: 'unimportant',
      description:
          'The page background changes from rgb(255,255,255) to '
          'rgb(247,247,247): about 70 % of the pixels change by deltaE ~3.',
      reference: base,
      actual: renderPage(const PageSpec(background: [247, 247, 247])),
      truth: const [],
      expectation: 'no actionable region (an imperceptible tint change)',
    ),
  ];
}

const Map<String, List<String>> _font = {
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  '.': ['.....', '.....', '.....', '.....', '.....', '.....', '..#..'],
  '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  'I': ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  'N': ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
  'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
};
