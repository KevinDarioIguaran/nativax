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
/// A declaration value kept as source text until custom properties have been
/// substituted (or because it uses a function NativaX cannot parse yet).
class RawValue extends CssValue {
  const RawValue(this.text);
  final String text;
  @override
  bool operator ==(Object o) => o is RawValue && o.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => text;
}

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
  bool operator ==(Object o) =>
      o is Length && o.value == value && o.unit == unit;
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
      } else if (t.type == CssTokenType.function ||
          t.type == CssTokenType.leftParen) {
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

Length? lengthFromToken(
  CssToken t, {
  bool allowPercent = true,
  bool allowNegative = true,
}) {
  if (!allowNegative && t.number < 0) return null;
  switch (t.type) {
    case CssTokenType.number:
      return t.number == 0 ? Length.zero : null; // unitless only for 0
    case CssTokenType.percentage:
      return allowPercent ? Length(t.number, LengthUnit.percent) : null;
    case CssTokenType.dimension:
      var value = t.number;
      final rawUnit = t.unit.toLowerCase();
      final unit = switch (rawUnit) {
        'px' => LengthUnit.px,
        'em' => LengthUnit.em,
        'rem' => LengthUnit.rem,
        'vw' => LengthUnit.vw,
        'vh' => LengthUnit.vh,
        // `ch` is the advance of "0"; approximate it as 0.5em.
        'ch' => LengthUnit.em,
        _ => null,
      };
      if (rawUnit == 'ch') value *= 0.5;
      if (unit != null) return Length(value, unit);
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
    final flat = args.single
        .where((t) => t.type != CssTokenType.whitespace)
        .toList();
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
    CssTokenType.dimension when hTok.unit == 'rad' =>
      hTok.number * 180 / math.pi,
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

/// A value that contains relative lengths (`em`, `rem`, `vw`, `vh`) the
/// cascade converts to px during computation.
abstract interface class RelativeValue {
  CssValue absolutize(Length Function(Length) toAbsolute);
}

// --- calc(), min(), max(), clamp() -------------------------------------------

/// A math expression tree. After computation only `px`, `%` and plain
/// numbers remain; percentages are resolved by layout.
sealed class CalcNode {
  const CalcNode();

  /// Evaluates the expression; `%` resolves against [basis]. Returns null
  /// when a percentage meets an unknown basis.
  double? evaluate(double? basis);

  bool get hasPercent;
  CalcNode absolutize(Length Function(Length) toAbsolute);
}

class CalcLeaf extends CalcNode {
  const CalcLeaf(this.value, [this.unit]);

  /// Plain number when [unit] is null.
  final double value;
  final LengthUnit? unit;

  @override
  double? evaluate(double? basis) {
    if (unit == LengthUnit.percent) {
      if (basis == null || !basis.isFinite) return null;
      return basis * value / 100;
    }
    return value;
  }

  @override
  bool get hasPercent => unit == LengthUnit.percent;

  @override
  CalcNode absolutize(Length Function(Length) toAbsolute) {
    final u = unit;
    if (u == null || u == LengthUnit.px || u == LengthUnit.percent) return this;
    final l = toAbsolute(Length(value, u));
    return CalcLeaf(l.value, l.unit);
  }

  @override
  String toString() => unit == null
      ? _num(value)
      : '${_num(value)}${unit == LengthUnit.percent ? '%' : unit!.name}';
}

class CalcOp extends CalcNode {
  const CalcOp(this.op, this.a, this.b);
  final String op; // + - * /
  final CalcNode a;
  final CalcNode b;

  @override
  double? evaluate(double? basis) {
    final x = a.evaluate(basis);
    final y = b.evaluate(basis);
    if (x == null || y == null) return null;
    return switch (op) {
      '+' => x + y,
      '-' => x - y,
      '*' => x * y,
      _ => y == 0 ? null : x / y,
    };
  }

  @override
  bool get hasPercent => a.hasPercent || b.hasPercent;

  @override
  CalcNode absolutize(Length Function(Length) toAbsolute) =>
      CalcOp(op, a.absolutize(toAbsolute), b.absolutize(toAbsolute));

  @override
  String toString() => '($a $op $b)';
}

class CalcFn extends CalcNode {
  const CalcFn(this.name, this.args);
  final String name; // min max clamp
  final List<CalcNode> args;

  @override
  double? evaluate(double? basis) {
    final values = <double>[];
    for (final a in args) {
      final v = a.evaluate(basis);
      if (v == null) return null;
      values.add(v);
    }
    switch (name) {
      case 'min':
        return values.reduce(math.min);
      case 'max':
        return values.reduce(math.max);
      default: // clamp(min, val, max)
        return math.max(values[0], math.min(values[1], values[2]));
    }
  }

  @override
  bool get hasPercent => args.any((a) => a.hasPercent);

  @override
  CalcNode absolutize(Length Function(Length) toAbsolute) =>
      CalcFn(name, [for (final a in args) a.absolutize(toAbsolute)]);

  @override
  String toString() => '$name(${args.join(', ')})';
}

String _num(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : '$v';

/// A length given by a math function.
class CalcLength extends CssValue implements RelativeValue {
  const CalcLength(this.node);
  final CalcNode node;

  @override
  CssValue absolutize(Length Function(Length) toAbsolute) {
    final n = node.absolutize(toAbsolute);
    if (!n.hasPercent) {
      final v = n.evaluate(null);
      if (v != null) return Length.px(v);
    }
    return CalcLength(n);
  }

  @override
  bool operator ==(Object o) => o is CalcLength && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() => 'calc$node';
}

/// Parses `calc()`, `min()`, `max()` or `clamp()` when the stream is at one
/// of those functions; otherwise leaves the stream untouched and returns
/// null.
CalcNode? parseMathFunction(ValueStream s) {
  final t = s.peek;
  if (t == null || t.type != CssTokenType.function) return null;
  final name = t.value.toLowerCase();
  if (!const {'calc', 'min', 'max', 'clamp'}.contains(name)) return null;
  final start = s._i;
  s.next();
  final args = s.functionArgs();
  CalcNode? result;
  if (args != null) {
    final nodes = <CalcNode>[];
    for (final a in args) {
      final n = _CalcParser(
        a.where((x) => x.type != CssTokenType.whitespace).toList(),
      ).parse();
      if (n == null) {
        nodes.clear();
        break;
      }
      nodes.add(n);
    }
    if (nodes.isNotEmpty) {
      if (name == 'calc' && nodes.length == 1) {
        result = nodes.single;
      } else if ((name == 'min' || name == 'max') && nodes.isNotEmpty) {
        result = CalcFn(name, nodes);
      } else if (name == 'clamp' && nodes.length == 3) {
        result = CalcFn(name, nodes);
      }
    }
  }
  if (result == null) s._i = start;
  return result;
}

class _CalcParser {
  _CalcParser(this.tokens);
  final List<CssToken> tokens;
  int i = 0;

  CalcNode? parse() {
    final n = _sum();
    return i == tokens.length ? n : null;
  }

  CalcNode? _sum() {
    var left = _product();
    while (left != null &&
        i < tokens.length &&
        (tokens[i].isDelim('+') || tokens[i].isDelim('-'))) {
      final op = tokens[i++].value;
      final right = _product();
      if (right == null) return null;
      left = CalcOp(op, left, right);
    }
    // `a -5px` tokenizes as a signed number; treat it as subtraction.
    while (left != null &&
        i < tokens.length &&
        (tokens[i].type == CssTokenType.number ||
            tokens[i].type == CssTokenType.dimension ||
            tokens[i].type == CssTokenType.percentage) &&
        tokens[i].number < 0) {
      final right = _product();
      if (right == null) return null;
      left = CalcOp('+', left, right);
    }
    return left;
  }

  CalcNode? _product() {
    var left = _unit();
    while (left != null &&
        i < tokens.length &&
        (tokens[i].isDelim('*') || tokens[i].isDelim('/'))) {
      final op = tokens[i++].value;
      final right = _unit();
      if (right == null) return null;
      left = CalcOp(op, left, right);
    }
    return left;
  }

  CalcNode? _unit() {
    if (i >= tokens.length) return null;
    final t = tokens[i];
    switch (t.type) {
      case CssTokenType.number:
        i++;
        return CalcLeaf(t.number);
      case CssTokenType.percentage:
        i++;
        return CalcLeaf(t.number, LengthUnit.percent);
      case CssTokenType.dimension:
        final l = lengthFromToken(t);
        if (l == null) return null;
        i++;
        return CalcLeaf(l.value, l.unit);
      case CssTokenType.leftParen:
        i++;
        final inner = _sum();
        if (inner == null ||
            i >= tokens.length ||
            tokens[i].type != CssTokenType.rightParen) {
          return null;
        }
        i++;
        return inner;
      case CssTokenType.function:
        // Nested math function: collect its tokens up to the matching ')'.
        var depth = 0;
        final start = i;
        for (; i < tokens.length; i++) {
          final k = tokens[i].type;
          if (k == CssTokenType.function || k == CssTokenType.leftParen)
            depth++;
          if (k == CssTokenType.rightParen) {
            depth--;
            if (depth == 0) {
              i++;
              break;
            }
          }
        }
        final sub = ValueStream(tokens.sublist(start, i));
        final n = parseMathFunction(sub);
        return n != null && sub.done ? n : null;
      case CssTokenType.ident:
        final k = t.value.toLowerCase();
        final c = switch (k) {
          'pi' => math.pi,
          'e' => math.e,
          'infinity' => double.infinity,
          _ => null,
        };
        if (c == null) return null;
        i++;
        return CalcLeaf(c);
      default:
        return null;
    }
  }
}

// --- generated content ----------------------------------------------------------

/// `content` for `::before`/`::after`: a list of strings and `attr()`
/// references, or `none`/`normal`.
class ContentValue extends CssValue {
  const ContentValue(this.parts);

  /// Literal strings, or `attr:<name>` for `attr(name)`.
  final List<String> parts;

  String resolve(String? Function(String name) attribute) {
    final b = StringBuffer();
    for (final p in parts) {
      if (p.startsWith('\u0000attr:')) {
        b.write(attribute(p.substring(6)) ?? '');
      } else {
        b.write(p);
      }
    }
    return b.toString();
  }

  @override
  bool operator ==(Object o) =>
      o is ContentValue && o.parts.join('\u0001') == parts.join('\u0001');
  @override
  int get hashCode => parts.join('\u0001').hashCode;
  @override
  String toString() => parts
      .map(
        (p) => p.startsWith('\u0000attr:') ? 'attr(${p.substring(6)})' : '"$p"',
      )
      .join(' ');
}

// --- shadows ---------------------------------------------------------------------

class CssShadow {
  const CssShadow(
    this.x,
    this.y,
    this.blur,
    this.spread,
    this.color, {
    this.inset = false,
  });
  final Length x;
  final Length y;
  final Length blur;
  final Length spread;
  final ColorValue color;
  final bool inset;

  @override
  String toString() => '${inset ? 'inset ' : ''}$x $y $blur $spread $color';
}

class ShadowValue extends CssValue implements RelativeValue {
  const ShadowValue(this.shadows);
  final List<CssShadow> shadows;

  @override
  CssValue absolutize(Length Function(Length) toAbsolute) => ShadowValue([
    for (final s in shadows)
      CssShadow(
        toAbsolute(s.x),
        toAbsolute(s.y),
        toAbsolute(s.blur),
        toAbsolute(s.spread),
        s.color,
        inset: s.inset,
      ),
  ]);

  @override
  bool operator ==(Object o) => o is ShadowValue && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() => shadows.join(', ');
}

// --- gradients -------------------------------------------------------------------

class GradientStop {
  const GradientStop(this.color, this.position);
  final ColorValue color;

  /// Fraction 0..1, or null when the stop position is implicit.
  final double? position;
  @override
  String toString() => '$color ${position ?? ''}';
}

class GradientValue extends CssValue {
  const GradientValue(
    this.kind,
    this.angle,
    this.stops, {
    this.repeating = false,
  });

  /// `linear`, `radial` or `conic`.
  final String kind;

  /// Degrees for linear gradients (CSS: 0deg points up, 90deg right).
  final double angle;
  final List<GradientStop> stops;
  final bool repeating;

  @override
  bool operator ==(Object o) =>
      o is GradientValue && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() =>
      '${repeating ? 'repeating-' : ''}$kind-gradient(${angle}deg, ${stops.join(', ')})';
}

/// Parses a `*-gradient()` function at the stream position.
GradientValue? parseGradient(ValueStream s) {
  final t = s.peek;
  if (t == null || t.type != CssTokenType.function) return null;
  var name = t.value.toLowerCase();
  final repeating = name.startsWith('repeating-');
  if (repeating) name = name.substring(10);
  if (!const {
    'linear-gradient',
    'radial-gradient',
    'conic-gradient',
  }.contains(name))
    return null;
  final start = s._i;
  s.next();
  final args = s.functionArgs();
  if (args == null || args.isEmpty) {
    s._i = start;
    return null;
  }
  final kind = name.substring(0, name.indexOf('-'));
  var angle = 180.0;
  var first = 0;
  final head = args.first
      .where((x) => x.type != CssTokenType.whitespace)
      .toList();
  if (head.isNotEmpty && parseColor(ValueStream(head)) == null) {
    first = 1;
    if (kind == 'linear') {
      final a = head.first;
      if (a.type == CssTokenType.dimension) {
        angle = switch (a.unit) {
          'deg' => a.number,
          'turn' => a.number * 360,
          'rad' => a.number * 180 / math.pi,
          'grad' => a.number * 0.9,
          _ => 180,
        };
      } else if (a.isIdent('to')) {
        final dirs = head.skip(1).map((x) => x.value.toLowerCase()).toSet();
        final dx = dirs.contains('right')
            ? 1
            : (dirs.contains('left') ? -1 : 0);
        final dy = dirs.contains('bottom')
            ? 1
            : (dirs.contains('top') ? -1 : 0);
        angle =
            (math.atan2(dx.toDouble(), -dy.toDouble()) * 180 / math.pi + 360) %
            360;
      }
    }
  }
  final stops = <GradientStop>[];
  for (final part in args.skip(first)) {
    final ps = ValueStream(part);
    final c = parseColor(ps);
    if (c == null) continue; // color hints / interpolation not supported
    double? pos;
    if (!ps.done) {
      final p = ps.next();
      if (p.type == CssTokenType.percentage) pos = p.number / 100;
      if (p.type == CssTokenType.number && p.number == 0) pos = 0;
    }
    stops.add(GradientStop(c, pos));
    // A second position duplicates the stop.
    if (!ps.done) {
      final p = ps.next();
      if (p.type == CssTokenType.percentage)
        stops.add(GradientStop(c, p.number / 100));
    }
  }
  if (stops.isEmpty) {
    s._i = start;
    return null;
  }
  if (stops.length == 1) stops.add(stops.first);
  return GradientValue(kind, angle, stops, repeating: repeating);
}

// --- transforms --------------------------------------------------------------------

class TransformFunction {
  const TransformFunction(this.name, this.args);
  final String name;

  /// Lengths (translate), plain numbers as px-less Length with unit null are
  /// not used: numbers are stored as [NumberValue], angles as degrees in
  /// [NumberValue].
  final List<CssValue> args;
  @override
  String toString() => '$name(${args.join(', ')})';
}

class TransformValue extends CssValue implements RelativeValue {
  const TransformValue(this.functions);
  final List<TransformFunction> functions;

  @override
  CssValue absolutize(Length Function(Length) toAbsolute) => TransformValue([
    for (final f in functions)
      TransformFunction(f.name, [
        for (final a in f.args) a is Length ? toAbsolute(a) : a,
      ]),
  ]);

  @override
  bool operator ==(Object o) =>
      o is TransformValue && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() => functions.join(' ');
}

double? angleFromToken(CssToken t) {
  if (t.type == CssTokenType.number && t.number == 0) return 0;
  if (t.type != CssTokenType.dimension) return null;
  return switch (t.unit) {
    'deg' => t.number,
    'turn' => t.number * 360,
    'rad' => t.number * 180 / math.pi,
    'grad' => t.number * 0.9,
    _ => null,
  };
}

TransformValue? parseTransform(ValueStream s) {
  final functions = <TransformFunction>[];
  while (!s.done) {
    final t = s.next();
    if (t.type != CssTokenType.function) return null;
    final name = t.value.toLowerCase();
    final args = s.functionArgs();
    if (args == null) return null;
    final values = <CssValue>[];
    for (final a in args) {
      final parts = a.where((x) => x.type != CssTokenType.whitespace).toList();
      for (final p in parts) {
        final angle = name.startsWith('rotate') || name.startsWith('skew')
            ? angleFromToken(p)
            : null;
        if (angle != null) {
          values.add(NumberValue(angle));
          continue;
        }
        if (p.type == CssTokenType.number) {
          values.add(NumberValue(p.number));
          continue;
        }
        if (p.type == CssTokenType.percentage && name.startsWith('scale')) {
          values.add(NumberValue(p.number / 100));
          continue;
        }
        final l = lengthFromToken(p);
        if (l == null) return null;
        values.add(l);
      }
    }
    functions.add(TransformFunction(name, values));
  }
  return functions.isEmpty ? null : TransformValue(functions);
}

// --- grid --------------------------------------------------------------------------

/// One side of a track size: a length/percentage/calc, `fr`, `auto`,
/// `min-content`, `max-content` or `fit-content(<length>)`.
class TrackBreadth {
  const TrackBreadth.length(CssValue this.length) : kind = 'length', fr = 0;
  const TrackBreadth.fr(this.fr) : kind = 'fr', length = null;
  const TrackBreadth.keyword(this.kind) : length = null, fr = 0;
  const TrackBreadth.fitContent(CssValue this.length)
    : kind = 'fit-content',
      fr = 0;

  static const auto = TrackBreadth.keyword('auto');

  /// `length`, `fr`, `auto`, `min-content`, `max-content`, `fit-content`.
  final String kind;

  /// [Length] or [CalcLength].
  final CssValue? length;
  final double fr;

  TrackBreadth absolutize(Length Function(Length) toAbsolute) {
    final l = length;
    if (l == null) return this;
    final abs = l is Length
        ? toAbsolute(l)
        : (l as CalcLength).absolutize(toAbsolute);
    return kind == 'fit-content'
        ? TrackBreadth.fitContent(abs)
        : TrackBreadth.length(abs);
  }

  @override
  String toString() => switch (kind) {
    'length' => '$length',
    'fr' => '${_num(fr)}fr',
    'fit-content' => 'fit-content($length)',
    _ => kind,
  };
}

class TrackSize {
  const TrackSize(this.min, this.max);

  /// A single breadth: `1fr` means `minmax(auto, 1fr)`.
  factory TrackSize.single(TrackBreadth b) =>
      TrackSize(b.kind == 'fr' ? TrackBreadth.auto : b, b);
  static const auto = TrackSize(TrackBreadth.auto, TrackBreadth.auto);
  final TrackBreadth min;
  final TrackBreadth max;

  TrackSize absolutize(Length Function(Length) toAbsolute) =>
      TrackSize(min.absolutize(toAbsolute), max.absolutize(toAbsolute));

  @override
  String toString() => '$min' == '$max' ? '$max' : 'minmax($min, $max)';
}

/// An entry of a track list: a single track or `repeat()`.
class TrackEntry {
  const TrackEntry(this.tracks, {this.count = 1, this.auto});

  /// Repeated tracks (one element for a plain track).
  final List<TrackSize> tracks;
  final int count;

  /// `auto-fill` or `auto-fit` for automatic repetition.
  final String? auto;

  TrackEntry absolutize(Length Function(Length) toAbsolute) => TrackEntry(
    [for (final t in tracks) t.absolutize(toAbsolute)],
    count: count,
    auto: auto,
  );

  @override
  String toString() => auto == null && count == 1
      ? tracks.join(' ')
      : 'repeat(${auto ?? count}, ${tracks.join(' ')})';
}

class GridTracksValue extends CssValue implements RelativeValue {
  const GridTracksValue(this.entries);
  final List<TrackEntry> entries;

  @override
  CssValue absolutize(Length Function(Length) toAbsolute) =>
      GridTracksValue([for (final e in entries) e.absolutize(toAbsolute)]);

  @override
  bool operator ==(Object o) =>
      o is GridTracksValue && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() => entries.join(' ');
}

class GridAreasValue extends CssValue {
  const GridAreasValue(this.rows);
  final List<List<String>> rows;
  @override
  bool operator ==(Object o) =>
      o is GridAreasValue && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() => rows.map((r) => '"${r.join(' ')}"').join(' ');
}

/// A grid placement line: `auto`, an integer line, `span n` or a name.
class GridLineValue extends CssValue {
  const GridLineValue({this.line, this.span, this.name});
  static const auto = GridLineValue();
  final int? line;
  final int? span;
  final String? name;

  bool get isAuto => line == null && span == null && name == null;

  @override
  bool operator ==(Object o) =>
      o is GridLineValue && o.line == line && o.span == span && o.name == name;
  @override
  int get hashCode => Object.hash(line, span, name);
  @override
  String toString() =>
      isAuto ? 'auto' : (span != null ? 'span $span' : (name ?? '$line'));
}

TrackBreadth? _breadth(ValueStream s, {bool allowFr = true}) {
  final math = parseMathFunction(s);
  if (math != null) return TrackBreadth.length(CalcLength(math));
  if (s.done) return null;
  final t = s.next();
  if (t.type == CssTokenType.dimension && t.unit == 'fr') {
    if (!allowFr || t.number < 0) return null;
    return TrackBreadth.fr(t.number);
  }
  if (t.type == CssTokenType.ident) {
    final k = t.value.toLowerCase();
    if (const {'auto', 'min-content', 'max-content'}.contains(k))
      return TrackBreadth.keyword(k);
    return null;
  }
  if (t.type == CssTokenType.function &&
      t.value.toLowerCase() == 'fit-content') {
    final args = s.functionArgs();
    if (args == null || args.length != 1) return null;
    final inner = ValueStream(args.single);
    final l = inner.done
        ? null
        : lengthFromToken(inner.next(), allowNegative: false);
    if (l == null || !inner.done) return null;
    return TrackBreadth.fitContent(l);
  }
  final l = lengthFromToken(t, allowNegative: false);
  return l == null ? null : TrackBreadth.length(l);
}

TrackSize? _trackSize(ValueStream s) {
  final t = s.peek;
  if (t == null) return null;
  if (t.type == CssTokenType.function && t.value.toLowerCase() == 'minmax') {
    s.next();
    final args = s.functionArgs();
    if (args == null || args.length != 2) return null;
    final a = ValueStream(args[0]);
    final b = ValueStream(args[1]);
    final min = _breadth(a, allowFr: false);
    final max = _breadth(b);
    if (min == null || max == null || !a.done || !b.done) return null;
    return TrackSize(min, max);
  }
  final b = _breadth(s);
  return b == null ? null : TrackSize.single(b);
}

/// Parses a `grid-template-columns`/`rows` track list (line names are
/// skipped), or a `grid-auto-*` list when [allowRepeat] is false.
GridTracksValue? parseTrackList(ValueStream s, {bool allowRepeat = true}) {
  final entries = <TrackEntry>[];
  while (!s.done) {
    final t = s.peek!;
    if (t.type == CssTokenType.leftBracket) {
      while (!s.done && s.next().type != CssTokenType.rightBracket) {}
      continue;
    }
    if (allowRepeat &&
        t.type == CssTokenType.function &&
        t.value.toLowerCase() == 'repeat') {
      s.next();
      final args = s.functionArgs();
      if (args == null || args.length < 2) return null;
      final countToks = args[0]
          .where((x) => x.type != CssTokenType.whitespace)
          .toList();
      if (countToks.length != 1) return null;
      final c = countToks.single;
      String? auto;
      var count = 1;
      if (c.isIdent('auto-fill') || c.isIdent('auto-fit')) {
        auto = c.value.toLowerCase();
      } else if (c.type == CssTokenType.number && c.number >= 1) {
        count = c.number.toInt();
      } else {
        return null;
      }
      // The track list may itself contain commas inside minmax(); rejoin.
      final rest = <CssToken>[];
      for (var k = 1; k < args.length; k++) {
        if (k > 1) rest.add(const CssToken(CssTokenType.comma, 0));
        rest.addAll(args[k]);
      }
      final inner = ValueStream(rest);
      final tracks = <TrackSize>[];
      while (!inner.done) {
        if (inner.peek!.type == CssTokenType.leftBracket) {
          while (!inner.done &&
              inner.next().type != CssTokenType.rightBracket) {}
          continue;
        }
        final ts = _trackSize(inner);
        if (ts == null) return null;
        tracks.add(ts);
      }
      if (tracks.isEmpty) return null;
      entries.add(TrackEntry(tracks, count: count, auto: auto));
      continue;
    }
    final ts = _trackSize(s);
    if (ts == null) return null;
    entries.add(TrackEntry([ts]));
  }
  return entries.isEmpty ? null : GridTracksValue(entries);
}

// --- filters ------------------------------------------------------------------------

class FilterFunction {
  const FilterFunction(this.name, this.amount, {this.shadow});
  final String name;

  /// px for blur, degrees for hue-rotate, a factor for the rest.
  final double amount;
  final CssShadow? shadow;

  @override
  String toString() => shadow != null ? '$name($shadow)' : '$name($amount)';
}

class FilterValue extends CssValue implements RelativeValue {
  const FilterValue(this.functions);
  final List<FilterFunction> functions;

  @override
  CssValue absolutize(Length Function(Length) toAbsolute) => FilterValue([
    for (final f in functions)
      f.shadow == null
          ? f
          : FilterFunction(
              f.name,
              f.amount,
              shadow: CssShadow(
                toAbsolute(f.shadow!.x),
                toAbsolute(f.shadow!.y),
                toAbsolute(f.shadow!.blur),
                toAbsolute(f.shadow!.spread),
                f.shadow!.color,
              ),
            ),
  ]);

  @override
  bool operator ==(Object o) => o is FilterValue && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() => functions.join(' ');
}

// --- transitions and animations ------------------------------------------------------

/// A timing function: `linear`, `cubic-bezier()` (and its keywords) or
/// `steps()`.
class CssEasing {
  const CssEasing.cubic(this.x1, this.y1, this.x2, this.y2)
    : kind = 'cubic',
      steps = 0,
      jump = '';
  const CssEasing.steps(this.steps, this.jump)
    : kind = 'steps',
      x1 = 0,
      y1 = 0,
      x2 = 0,
      y2 = 0;
  const CssEasing.linear()
    : kind = 'linear',
      x1 = 0,
      y1 = 0,
      x2 = 1,
      y2 = 1,
      steps = 0,
      jump = '';

  static const ease = CssEasing.cubic(0.25, 0.1, 0.25, 1);
  static const easeIn = CssEasing.cubic(0.42, 0, 1, 1);
  static const easeOut = CssEasing.cubic(0, 0, 0.58, 1);
  static const easeInOut = CssEasing.cubic(0.42, 0, 0.58, 1);

  final String kind;
  final double x1, y1, x2, y2;
  final int steps;

  /// `jump-start`, `jump-end`, `jump-none`, `jump-both` (start/end map here).
  final String jump;

  /// Output progress for input progress [t] in 0..1.
  double transform(double t) {
    if (kind == 'linear') return t;
    if (kind == 'steps') {
      final n = steps <= 0 ? 1 : steps;
      var current = (t * n).floor();
      if (jump == 'jump-start' || jump == 'jump-both') current++;
      final jumps = switch (jump) {
        'jump-none' => n - 1,
        'jump-both' => n + 1,
        _ => n,
      };
      if (t >= 1) return 1;
      return (current / (jumps <= 0 ? 1 : jumps)).clamp(0.0, 1.0);
    }
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    // Solve x(s) = t for s with Newton's method, then return y(s).
    double bx(double s) =>
        3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s;
    double by(double s) =>
        3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s;
    double dx(double s) =>
        3 * (1 - s) * (1 - s) * x1 +
        6 * (1 - s) * s * (x2 - x1) +
        3 * s * s * (1 - x2);
    var s = t;
    for (var i = 0; i < 8; i++) {
      final err = bx(s) - t;
      if (err.abs() < 1e-6) break;
      final d = dx(s);
      if (d.abs() < 1e-6) break;
      s -= err / d;
    }
    s = s.clamp(0.0, 1.0);
    return by(s);
  }

  @override
  String toString() => kind == 'steps'
      ? 'steps($steps, $jump)'
      : (kind == 'linear' ? 'linear' : 'cubic-bezier($x1, $y1, $x2, $y2)');
}

/// A comma-separated list value (`animation-*`, `transition-*`).
class ListValue<T> extends CssValue {
  const ListValue(this.items);
  final List<T> items;
  @override
  bool operator ==(Object o) => o is ListValue && o.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
  @override
  String toString() => items.join(', ');
}

/// Parses a time token to milliseconds.
double? timeFromToken(CssToken t) {
  if (t.type == CssTokenType.number && t.number == 0) return 0;
  if (t.type != CssTokenType.dimension) return null;
  return switch (t.unit) {
    's' => t.number * 1000,
    'ms' => t.number,
    _ => null,
  };
}

/// Parses a timing function at the stream position.
CssEasing? parseEasing(ValueStream s) {
  final t = s.peek;
  if (t == null) return null;
  if (t.type == CssTokenType.ident) {
    final e = switch (t.value.toLowerCase()) {
      'linear' => const CssEasing.linear(),
      'ease' => CssEasing.ease,
      'ease-in' => CssEasing.easeIn,
      'ease-out' => CssEasing.easeOut,
      'ease-in-out' => CssEasing.easeInOut,
      'step-start' => const CssEasing.steps(1, 'jump-start'),
      'step-end' => const CssEasing.steps(1, 'jump-end'),
      _ => null,
    };
    if (e != null) s.next();
    return e;
  }
  if (t.type != CssTokenType.function) return null;
  final name = t.value.toLowerCase();
  if (name != 'cubic-bezier' && name != 'steps' && name != 'linear')
    return null;
  final start = s._i;
  s.next();
  final args = s.functionArgs();
  if (args == null) {
    s._i = start;
    return null;
  }
  final flat = [
    for (final a in args)
      a.where((x) => x.type != CssTokenType.whitespace).toList(),
  ];
  if (name == 'cubic-bezier' &&
      flat.length == 4 &&
      flat.every(
        (a) => a.length == 1 && a.single.type == CssTokenType.number,
      )) {
    final v = [for (final a in flat) a.single.number];
    if (v[0] < 0 || v[0] > 1 || v[2] < 0 || v[2] > 1) {
      s._i = start;
      return null;
    }
    return CssEasing.cubic(v[0], v[1], v[2], v[3]);
  }
  if (name == 'steps' &&
      flat.isNotEmpty &&
      flat.first.length == 1 &&
      flat.first.single.type == CssTokenType.number) {
    var jump = 'jump-end';
    if (flat.length > 1 && flat[1].length == 1) {
      jump = switch (flat[1].single.value.toLowerCase()) {
        'start' || 'jump-start' => 'jump-start',
        'jump-none' => 'jump-none',
        'jump-both' => 'jump-both',
        _ => 'jump-end',
      };
    }
    return CssEasing.steps(flat.first.single.number.toInt(), jump);
  }
  if (name == 'linear')
    return const CssEasing.linear(); // linear() stops approximated
  s._i = start;
  return null;
}

/// One resolved `animation` entry.
class CssAnimation {
  const CssAnimation({
    required this.name,
    this.duration = 0,
    this.easing = CssEasing.ease,
    this.delay = 0,
    this.iterations = 1,
    this.direction = 'normal',
    this.fill = 'none',
    this.paused = false,
  });
  final String name;
  final double duration; // ms
  final CssEasing easing;
  final double delay; // ms
  final double iterations; // may be infinity
  final String direction;
  final String fill;
  final bool paused;

  @override
  bool operator ==(Object o) =>
      o is CssAnimation &&
      o.name == name &&
      o.duration == duration &&
      '${o.easing}' == '$easing' &&
      o.delay == delay &&
      o.iterations == iterations &&
      o.direction == direction &&
      o.fill == fill &&
      o.paused == paused;
  @override
  int get hashCode => Object.hash(
    name,
    duration,
    '$easing',
    delay,
    iterations,
    direction,
    fill,
    paused,
  );
}

/// One resolved `transition` entry.
class CssTransition {
  const CssTransition(this.property, this.duration, this.easing, this.delay);
  final String property; // 'all' or a longhand/shorthand name
  final double duration;
  final CssEasing easing;
  final double delay;
}
