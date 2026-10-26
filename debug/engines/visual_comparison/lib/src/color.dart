import 'dart:math' as math;

/// CIE L*a*b* colour with a D65 white point.
class Lab {
  const Lab(this.l, this.a, this.b);
  final double l;
  final double a;
  final double b;

  @override
  String toString() =>
      'Lab(${l.toStringAsFixed(1)}, ${a.toStringAsFixed(1)}, ${b.toStringAsFixed(1)})';
}

class Rgb {
  const Rgb(this.r, this.g, this.b, [this.a = 255]);
  final int r;
  final int g;
  final int b;
  final int a;

  @override
  String toString() => a == 255 ? 'rgb($r, $g, $b)' : 'rgba($r, $g, $b, $a)';
}

double _linearize(int channel) {
  final c = channel / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

Lab rgbToLab(int r, int g, int b) {
  final rl = _linearize(r);
  final gl = _linearize(g);
  final bl = _linearize(b);
  final x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047;
  final y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl;
  final z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883;

  double f(double t) => t > 0.008856451679035631
      ? math.pow(t, 1 / 3).toDouble()
      : 7.787037037037035 * t + 16 / 116;

  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// CIE76 colour difference. Same scale as the classic ΔE thresholds:
/// ≤2 is imperceptible, 5 is noticeable, ≥10 is a different colour.
double deltaE76(Lab a, Lab b) {
  final dl = a.l - b.l;
  final da = a.a - b.a;
  final db = a.b - b.b;
  return math.sqrt(dl * dl + da * da + db * db);
}

double deltaE(int r1, int g1, int b1, int r2, int g2, int b2) =>
    deltaE76(rgbToLab(r1, g1, b1), rgbToLab(r2, g2, b2));

/// Maps a ΔE value to a 0..1 fidelity score: 1 at or below [imperceptible],
/// 0 at or above [clearlyWrong], linear in between.
double deltaEScore(
  double value, {
  double imperceptible = 2,
  double clearlyWrong = 10,
}) {
  if (value <= imperceptible) return 1;
  if (value >= clearlyWrong) return 0;
  return 1 - (value - imperceptible) / (clearlyWrong - imperceptible);
}

/// Parses the CSS colour forms a computed style can report:
/// `rgb()`, `rgba()`, `#rrggbb`, `#rgb`, and the keywords the judge needs.
Rgb? parseCssColor(String input) {
  var text = input.trim().toLowerCase();
  if (text.isEmpty) return null;
  const named = {
    'transparent': Rgb(0, 0, 0, 0),
    'black': Rgb(0, 0, 0),
    'white': Rgb(255, 255, 255),
    'red': Rgb(255, 0, 0),
    'green': Rgb(0, 128, 0),
    'blue': Rgb(0, 0, 255),
    'gray': Rgb(128, 128, 128),
    'grey': Rgb(128, 128, 128),
    'currentcolor': null,
  };
  if (named.containsKey(text)) return named[text];
  if (text.startsWith('rgb')) {
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    if (open < 0 || close <= open) return null;
    final parts = text
        .substring(open + 1, close)
        .split(RegExp(r'[,/\s]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    final channels = <int>[];
    for (var i = 0; i < 3; i++) {
      final part = parts[i];
      if (part.endsWith('%')) {
        final pct = double.tryParse(part.substring(0, part.length - 1));
        if (pct == null) return null;
        channels.add((pct * 255 / 100).round().clamp(0, 255));
      } else {
        final value = double.tryParse(part);
        if (value == null) return null;
        channels.add(value.round().clamp(0, 255));
      }
    }
    var alpha = 255;
    if (parts.length >= 4) {
      final raw = parts[3];
      final value = double.tryParse(
        raw.endsWith('%') ? raw.substring(0, raw.length - 1) : raw,
      );
      if (value == null) return null;
      alpha = raw.endsWith('%')
          ? (value * 255 / 100).round().clamp(0, 255)
          : (value * 255).round().clamp(0, 255);
    }
    return Rgb(channels[0], channels[1], channels[2], alpha);
  }
  if (text.startsWith('#')) {
    text = text.substring(1);
    if (text.length == 3) {
      text = text.split('').map((c) => '$c$c').join();
    }
    if (text.length == 6 || text.length == 8) {
      final value = int.tryParse(text, radix: 16);
      if (value == null) return null;
      if (text.length == 6) {
        return Rgb((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
      }
      return Rgb(
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      );
    }
  }
  return null;
}

/// Canonical textual form used when comparing computed colours. Resolves
/// `currentcolor` against [current] when provided.
String canonicalCssColor(String input, {String? current}) {
  var text = input.trim().toLowerCase();
  if (text == 'currentcolor' && current != null)
    text = current.trim().toLowerCase();
  final parsed = parseCssColor(text);
  if (parsed == null) return text.replaceAll(RegExp(r'\s+'), ' ');
  if (parsed.a == 255) return 'rgb(${parsed.r}, ${parsed.g}, ${parsed.b})';
  final alpha = parsed.a / 255;
  final rounded = alpha == 0 ? '0' : (alpha * 100).round() / 100;
  return 'rgba(${parsed.r}, ${parsed.g}, ${parsed.b}, $rounded)';
}
