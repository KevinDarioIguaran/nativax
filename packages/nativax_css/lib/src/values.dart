import 'dart:math' as math;

import 'named_colors.dart';
import 'tokenizer.dart';

/// Length units accepted by NativaX. See docs/css-supported.md for how each
/// maps to Flutter logical pixels.
enum LengthUnit { px, percent, em, rem, vw, vh }

/// An sRGB color with alpha, stored as 0xAARRGGBB (the layout Flutter's
/// `Color(int)` constructor expects).
class CssColor {
  const CssColor(this.argb);

  factory CssColor.rgba(num r, num g, num b, [num a = 1]) {
    int c(num v) => v.round().clamp(0, 255);
    return CssColor((c(a * 255) << 24) | (c(r) << 16) | (c(g) << 8) | c(b));
  }

  static const transparent = CssColor(0x00000000);
  static const black = CssColor(0xff000000);

  final int argb;

  int get alpha => (argb >> 24) & 0xff;

  @override
  bool operator ==(Object other) => other is CssColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() => '#${argb.toRadixString(16).padLeft(8, '0')}';
}

sealed class CssValue {
  const CssValue();
}

/// `inherit`, `initial` or `unset`.
class GlobalKeyword extends CssValue {
  const GlobalKeyword(this.name);
  final String name;
  @override
  bool operator ==(Object o) => o is GlobalKeyword && o.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => name;
}

class Keyword extends CssValue {
  const Keyword(this.name);
  final String name;
  @override
  bool operator ==(Object o) => o is Keyword && o.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => name;
}

class Length extends CssValue {
  const Length(this.value, this.unit);
  const Length.px(this.value) : unit = LengthUnit.px;
  static const zero = Length.px(0);

  final double value;
  final LengthUnit unit;

  @override
  bool operator ==(Object o) => o is Length && o.value == value && o.unit == unit;
  @override
  int get hashCode => Object.hash(value, unit);
  @override
  String toString() =>
      '${CssToken(CssTokenType.number, 0, number: value)}${unit == LengthUnit.percent ? '%' : unit.name}';
}

class NumberValue extends CssValue {
  const NumberValue(this.value);
  final double value;
  @override
  bool operator ==(Object o) => o is NumberValue && o.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '$value';
}

class ColorValue extends CssValue {
  const ColorValue(this.color);

  /// null means `currentcolor`.
  final CssColor? color;
  @override
  bool operator ==(Object o) => o is ColorValue && o.color == color;
  @override
  int get hashCode => color.hashCode;
  @override
  String toString() => color?.toString() ?? 'currentcolor';
}

class FontFamilyValue extends CssValue {
  const FontFamilyValue(this.families);
  final List<String> families;
  @override
  bool operator ==(Object o) =>
      o is FontFamilyValue && o.families.join(',') == families.join(',');
  @override
  int get hashCode => families.join(',').hashCode;
  @override
  String toString() => families.join(', ');
}

class UrlValue extends CssValue {
  const UrlValue(this.url);
  final String url;
  @override
  bool operator ==(Object o) => o is UrlValue && o.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'url($url)';
}

/// Component values of one declaration with whitespace removed except where
/// it separates values; helpers below consume them.
class ValueStream {
  ValueStream(List<CssToken> tokens)
      : _tokens = tokens.where((t) => t.type != CssTokenType.whitespace).toList();

  final List<CssToken> _tokens;
  int _i = 0;

  bool get done => _i >= _tokens.length;
  CssToken? get peek => done ? null : _tokens[_i];
  int get remaining => _tokens.length - _i;
  CssToken next() => _tokens[_i++];
  void back() => _i--;

  /// Consumes a function's arguments up to the matching ')' and returns them
  /// split by commas (nested functions are kept intact).
  List<List<CssToken>>? functionArgs() {
    final args = <List<CssToken>>[[]];
    var depth = 0;
    while (!done) {
      final t = next();
      if (t.type == CssTokenType.rightParen) {
        if (depth == 0) return args;
        depth--;
      } else if (t.type == CssTokenType.function || t.type == CssTokenType.leftParen) {
        depth++;
      } else if (t.type == CssTokenType.comma && depth == 0) {
        args.add([]);
        continue;
      }
      args.last.add(t);
    }
    return null; // unterminated
  }
}

Length? lengthFromToken(CssToken t, {bool allowPercent = true, bool allowNegative = true}) {
  if (!allowNegative && t.number < 0) return null;
  switch (t.type) {
    case CssTokenType.number:
      return t.number == 0 ? Length.zero : null; // unitless only for 0
    case CssTokenType.percentage:
      return allowPercent ? Length(t.number, LengthUnit.percent) : null;
    case CssTokenType.dimension:
      final unit = switch (t.unit) {
        'px' => LengthUnit.px,
        'em' => LengthUnit.em,
        'rem' => LengthUnit.rem,
        'vw' => LengthUnit.vw,
        'vh' => LengthUnit.vh,
        _ => null,
      };
      if (unit != null) return Length(t.number, unit);
      // Absolute units convert to px at 96 dpi.
      final factor = switch (t.unit) {
        'pt' => 96 / 72,
        'pc' => 16.0,
        'in' => 96.0,
        'cm' => 96 / 2.54,
        'mm' => 96 / 25.4,
        _ => null,
      };
      return factor == null ? null : Length.px(t.number * factor);
    default:
      return null;
  }
}

/// Parses a color from the stream (consuming its tokens) or returns null
/// and leaves the stream position unchanged.
ColorValue? parseColor(ValueStream s) {
  final t = s.peek;
  if (t == null) return null;
  if (t.type == CssTokenType.ident) {
    final name = t.value.toLowerCase();
    if (name == 'transparent') {
      s.next();
      return const ColorValue(CssColor.transparent);
    }
    if (name == 'currentcolor') {
      s.next();
      return const ColorValue(null);
    }
    final rgb = namedColors[name];
    if (rgb == null) return null;
    s.next();
    return ColorValue(CssColor(0xff000000 | rgb));
  }
  if (t.type == CssTokenType.hash) {
    final c = _hexColor(t.value);
    if (c == null) return null;
    s.next();
    return ColorValue(c);
  }
  if (t.type == CssTokenType.function) {
    final name = t.value.toLowerCase();
    if (!const {'rgb', 'rgba', 'hsl', 'hsla'}.contains(name)) return null;
    final start = s._i;
    s.next();
    final args = s.functionArgs();
    final color = args == null ? null : _functionColor(name, args);
    if (color == null) {
      s._i = start;
      return null;
    }
    return ColorValue(color);
  }
  return null;
}

CssColor? _hexColor(String hex) {
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
  int ch(int i) => int.parse(hex[i] * 2, radix: 16);
  switch (hex.length) {
    case 3:
      return CssColor.rgba(ch(0), ch(1), ch(2));
    case 4:
      return CssColor.rgba(ch(0), ch(1), ch(2), ch(3) / 255);
    case 6:
      return CssColor(0xff000000 | int.parse(hex, radix: 16));
    case 8:
      final v = int.parse(hex, radix: 16);
      return CssColor(((v & 0xff) << 24) | (v >> 8));
  }
  return null;
}

/// Accepts both legacy comma syntax and modern space syntax with `/ alpha`.
CssColor? _functionColor(String name, List<List<CssToken>> args) {
  List<CssToken> parts;
  CssToken? alpha;
  if (args.length == 1) {
    final flat = args.single.where((t) => t.type != CssTokenType.whitespace).toList();
    final slash = flat.indexWhere((t) => t.isDelim('/'));
    if (slash >= 0) {
      if (slash != flat.length - 2) return null;
      alpha = flat.last;
      parts = flat.sublist(0, slash);
    } else {
      parts = flat;
    }
  } else {
    final flat = [
      for (final a in args)
        a.where((t) => t.type != CssTokenType.whitespace).toList(),
    ];
    if (flat.any((a) => a.length != 1)) return null;
    parts = flat.map((a) => a.single).toList();
    if (parts.length == 4) alpha = parts.removeLast();
  }
  if (parts.length != 3) return null;
  double? a = 1;
  if (alpha != null) {
    a = switch (alpha.type) {
      CssTokenType.number => alpha.number,
      CssTokenType.percentage => alpha.number / 100,
      _ => null,
    };
    if (a == null) return null;
    a = a.clamp(0, 1).toDouble();
  }
  if (name.startsWith('rgb')) {
    final v = <double>[];
    for (final p in parts) {
      final x = switch (p.type) {
        CssTokenType.number => p.number,
        CssTokenType.percentage => p.number * 2.55,
        _ => null,
      };
      if (x == null) return null;
      v.add(x);
    }
    return CssColor.rgba(v[0], v[1], v[2], a);
  }
  // hsl
  final hTok = parts[0];
  double? h = switch (hTok.type) {
    CssTokenType.number => hTok.number,
    CssTokenType.dimension when hTok.unit == 'deg' => hTok.number,
    CssTokenType.dimension when hTok.unit == 'turn' => hTok.number * 360,
    CssTokenType.dimension when hTok.unit == 'rad' => hTok.number * 180 / math.pi,
    _ => null,
  };
  if (h == null) return null;
  double? pct(CssToken t) => switch (t.type) {
        CssTokenType.percentage => t.number / 100,
        CssTokenType.number => t.number / 100,
        _ => null,
      };
  final sat = pct(parts[1]);
  final light = pct(parts[2]);
  if (sat == null || light == null) return null;
  h = ((h % 360) + 360) % 360;
  final sClamped = sat.clamp(0.0, 1.0);
  final lClamped = light.clamp(0.0, 1.0);
  double f(double n) {
    final k = (n + h! / 30) % 12;
    final amp = sClamped * math.min(lClamped, 1 - lClamped);
    return lClamped - amp * math.max(-1, math.min(math.min(k - 3, 9 - k), 1));
  }

  return CssColor.rgba(f(0) * 255, f(8) * 255, f(4) * 255, a);
}
