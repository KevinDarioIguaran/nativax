/// Property registry: grammar, initial values, inheritance and shorthand
/// expansion for every property NativaX supports. Declarations for anything
/// not listed here are dropped at parse time and reported.
library;

import 'tokenizer.dart';
import 'values.dart';

typedef LonghandParser = CssValue? Function(ValueStream s);

class PropertySpec {
  const PropertySpec(
    this.name,
    this.parse,
    this.initial, {
    this.inherited = false,
  });
  final String name;
  final LonghandParser parse;
  final CssValue initial;
  final bool inherited;
}

const _auto = Keyword('auto');
const _none = Keyword('none');
const _normal = Keyword('normal');

LonghandParser _keywords(Set<String> allowed) => (s) {
  final t = s.next();
  if (t.type != CssTokenType.ident) return null;
  final k = t.value.toLowerCase();
  return allowed.contains(k) ? Keyword(k) : null;
};

LonghandParser _length({
  Set<String> keywords = const {},
  bool percent = true,
  bool negative = true,
}) => (s) {
  final math = parseMathFunction(s);
  if (math != null) return CalcLength(math);
  final t = s.next();
  if (t.type == CssTokenType.ident) {
    final k = t.value.toLowerCase();
    return keywords.contains(k) ? Keyword(k) : null;
  }
  return lengthFromToken(t, allowPercent: percent, allowNegative: negative);
};

CssValue? _color(ValueStream s) => parseColor(s);

LonghandParser _number({
  bool negative = false,
  bool integer = false,
  Set<String> keywords = const {},
}) => (s) {
  final t = s.next();
  if (t.type == CssTokenType.ident) {
    final k = t.value.toLowerCase();
    return keywords.contains(k) ? Keyword(k) : null;
  }
  if (t.type != CssTokenType.number) return null;
  if (!negative && t.number < 0) return null;
  if (integer && t.number != t.number.truncateToDouble()) return null;
  return NumberValue(t.number);
};

CssValue? _opacity(ValueStream s) {
  final t = s.next();
  final v = switch (t.type) {
    CssTokenType.number => t.number,
    CssTokenType.percentage => t.number / 100,
    _ => null,
  };
  return v == null ? null : NumberValue(v.clamp(0, 1).toDouble());
}

CssValue? _borderWidth(ValueStream s) {
  final t = s.next();
  if (t.type == CssTokenType.ident) {
    return switch (t.value.toLowerCase()) {
      'thin' => const Length.px(1),
      'medium' => const Length.px(3),
      'thick' => const Length.px(5),
      _ => null,
    };
  }
  return lengthFromToken(t, allowPercent: false, allowNegative: false);
}

const _borderStyles = {
  'none',
  'hidden',
  'solid',
  'dashed',
  'dotted',
  'double',
  'groove',
  'ridge',
  'inset',
  'outset',
};

CssValue? _fontSize(ValueStream s) {
  final t = s.next();
  if (t.type == CssTokenType.ident) {
    const sizes = {
      'xx-small': 9.0, 'x-small': 10.0, 'small': 13.0, 'medium': 16.0,
      'large': 18.0, 'x-large': 24.0, 'xx-large': 32.0, //
    };
    final k = t.value.toLowerCase();
    if (sizes.containsKey(k)) return Length.px(sizes[k]!);
    if (k == 'smaller') return const Length(0.833, LengthUnit.em);
    if (k == 'larger') return const Length(1.2, LengthUnit.em);
    return null;
  }
  return lengthFromToken(t, allowNegative: false);
}

CssValue? _fontWeight(ValueStream s) {
  final t = s.next();
  if (t.type == CssTokenType.ident) {
    final k = t.value.toLowerCase();
    return const {'normal', 'bold', 'bolder', 'lighter'}.contains(k)
        ? Keyword(k)
        : null;
  }
  if (t.type == CssTokenType.number && t.number >= 1 && t.number <= 1000) {
    return NumberValue(t.number);
  }
  return null;
}

CssValue? _fontFamily(ValueStream s) {
  final families = <String>[];
  final current = <String>[];
  while (!s.done) {
    final t = s.next();
    if (t.type == CssTokenType.comma) {
      if (current.isEmpty) return null;
      families.add(current.join(' '));
      current.clear();
    } else if (t.type == CssTokenType.string && current.isEmpty) {
      current.add(t.value);
    } else if (t.type == CssTokenType.ident) {
      current.add(t.value);
    } else {
      return null;
    }
  }
  if (current.isEmpty) return null;
  families.add(current.join(' '));
  return FontFamilyValue(families);
}

CssValue? _lineHeight(ValueStream s) {
  final t = s.next();
  if (t.type == CssTokenType.ident) return t.isIdent('normal') ? _normal : null;
  if (t.type == CssTokenType.number)
    return t.number < 0 ? null : NumberValue(t.number);
  return lengthFromToken(t, allowNegative: false);
}

CssValue? _textDecorationLine(ValueStream s) {
  final lines = <String>{};
  while (!s.done) {
    final t = s.next();
    if (t.type != CssTokenType.ident) return null;
    final k = t.value.toLowerCase();
    if (k == 'none' && lines.isEmpty && s.done) return _none;
    if (!const {'underline', 'overline', 'line-through'}.contains(k) ||
        !lines.add(k)) {
      return null;
    }
  }
  return lines.isEmpty ? null : Keyword((lines.toList()..sort()).join(' '));
}

const _repeatKeywords = {'repeat', 'no-repeat', 'space', 'round'};

/// `background-repeat` for the first layer, normalised to one of `repeat`,
/// `no-repeat`, `repeat-x` or `repeat-y` (`space`/`round` tile like
/// `repeat`).
Keyword? _parseBackgroundRepeat(ValueStream s) {
  final t = s.peek;
  if (t == null || t.type != CssTokenType.ident) return null;
  final first = t.value.toLowerCase();
  if (first == 'repeat-x' || first == 'repeat-y') {
    s.next();
    return Keyword(first);
  }
  if (!_repeatKeywords.contains(first)) return null;
  s.next();
  var second = first;
  final n = s.peek;
  if (n != null &&
      n.type == CssTokenType.ident &&
      _repeatKeywords.contains(n.value.toLowerCase())) {
    second = s.next().value.toLowerCase();
  }
  final x = first == 'no-repeat' ? 'no-repeat' : 'repeat';
  final y = second == 'no-repeat' ? 'no-repeat' : 'repeat';
  if (x == y) return Keyword(x);
  return Keyword(x == 'repeat' ? 'repeat-x' : 'repeat-y');
}

const _positionKeywords = {
  'left': 0.0,
  'center': 50.0,
  'right': 100.0,
  'top': 0.0,
  'bottom': 100.0,
};

/// One or two `background-position` components as `[x, y]` (keywords become
/// percentages). Three/four-value offsets are not supported.
ListValue<Length>? _parseBackgroundPosition(ValueStream s) {
  final parts = <(String?, Length?)>[];
  while (parts.length < 2 && !s.done) {
    final t = s.peek!;
    if (t.type == CssTokenType.ident &&
        _positionKeywords.containsKey(t.value.toLowerCase())) {
      parts.add((s.next().value.toLowerCase(), null));
      continue;
    }
    final l = lengthFromToken(t);
    if (l == null || (l.unit != LengthUnit.px && l.unit != LengthUnit.percent)) {
      break;
    }
    s.next();
    parts.add((null, l));
  }
  if (parts.isEmpty) return null;
  Length value((String?, Length?) part) => part.$2 ??
      Length(_positionKeywords[part.$1]!, LengthUnit.percent);
  const center = Length(50, LengthUnit.percent);
  bool vertical((String?, Length?) p) => p.$1 == 'top' || p.$1 == 'bottom';
  bool horizontal((String?, Length?) p) => p.$1 == 'left' || p.$1 == 'right';
  if (parts.length == 1) {
    final only = parts.single;
    return vertical(only)
        ? ListValue([center, value(only)])
        : ListValue([value(only), center]);
  }
  var (x, y) = (parts[0], parts[1]);
  if (vertical(x) || horizontal(y)) (x, y) = (y, x);
  return ListValue([value(x), value(y)]);
}

/// `background-size`: `['cover']`, `['contain']` or `[width, height]` where
/// each is a [Length] or `'auto'`.
ListValue<Object>? _parseBackgroundSize(ValueStream s) {
  final t = s.peek;
  if (t == null) return null;
  if (t.type == CssTokenType.ident) {
    final k = t.value.toLowerCase();
    if (k == 'cover' || k == 'contain') {
      s.next();
      return ListValue([k]);
    }
  }
  final parts = <Object>[];
  while (parts.length < 2 && !s.done) {
    final n = s.peek!;
    if (n.isIdent('auto')) {
      s.next();
      parts.add('auto');
      continue;
    }
    final l = lengthFromToken(n, allowNegative: false);
    if (l == null || (l.unit != LengthUnit.px && l.unit != LengthUnit.percent)) {
      break;
    }
    s.next();
    parts.add(l);
  }
  if (parts.isEmpty) return null;
  if (parts.length == 1) parts.add('auto');
  return ListValue(parts);
}

CssValue? _whole(CssValue? Function(ValueStream) parse, ValueStream s) {
  final v = parse(s);
  return v != null && s.done ? v : null;
}

CssValue? _backgroundImage(ValueStream s) {
  final gradient = parseGradient(s);
  if (gradient != null) return gradient;
  final t = s.next();
  if (t.isIdent('none')) return _none;
  if (t.type == CssTokenType.url) return UrlValue(t.value);
  if (t.type == CssTokenType.function && t.value.toLowerCase() == 'url') {
    final args = s.functionArgs();
    final inner = args?.single
        .where((x) => x.type != CssTokenType.whitespace)
        .toList();
    if (inner == null ||
        inner.length != 1 ||
        inner.single.type != CssTokenType.string) {
      return null;
    }
    return UrlValue(inner.single.value);
  }
  return null;
}

CssValue? _content(ValueStream s) {
  final first = s.peek;
  if (first == null) return null;
  if (s.remaining == 1 && first.type == CssTokenType.ident) {
    final k = first.value.toLowerCase();
    if (k == 'none' || k == 'normal') {
      s.next();
      return Keyword(k);
    }
  }
  final parts = <String>[];
  while (!s.done) {
    final t = s.next();
    if (t.type == CssTokenType.string) {
      parts.add(t.value);
    } else if (t.type == CssTokenType.function &&
        t.value.toLowerCase() == 'attr') {
      final args = s.functionArgs();
      final name = args?.first
          .where((x) => x.type == CssTokenType.ident)
          .firstOrNull;
      if (name == null) return null;
      parts.add('\u0000attr:${name.value.toLowerCase()}');
    } else if (t.type == CssTokenType.ident) {
      switch (t.value.toLowerCase()) {
        case 'open-quote':
          parts.add('\u201c');
        case 'close-quote':
          parts.add('\u201d');
        case 'no-open-quote' || 'no-close-quote':
          break;
        default:
          return null;
      }
    } else if (t.type == CssTokenType.function) {
      // counter(), counters(), url(): unsupported; contribute nothing.
      if (s.functionArgs() == null) return null;
    } else if (t.isDelim('/')) {
      // Alternative text for generated content: ignore the rest.
      while (!s.done) {
        s.next();
      }
    } else {
      return null;
    }
  }
  return ContentValue(parts);
}

CssValue? _boxShadow(ValueStream s) {
  if (s.remaining == 1 && s.peek!.isIdent('none')) {
    s.next();
    return _none;
  }
  // Split the stream on top-level commas.
  final layers = <List<CssToken>>[[]];
  var depth = 0;
  while (!s.done) {
    final t = s.next();
    if (t.type == CssTokenType.function || t.type == CssTokenType.leftParen)
      depth++;
    if (t.type == CssTokenType.rightParen) depth--;
    if (t.type == CssTokenType.comma && depth == 0) {
      layers.add([]);
      continue;
    }
    layers.last.add(t);
  }
  final shadows = <CssShadow>[];
  for (final layer in layers) {
    final ls = ValueStream(layer);
    final lengths = <Length>[];
    ColorValue? color;
    var inset = false;
    while (!ls.done) {
      if (ls.peek!.isIdent('inset')) {
        ls.next();
        inset = true;
        continue;
      }
      final c = parseColor(ls);
      if (c != null) {
        color = c;
        continue;
      }
      final l = lengthFromToken(ls.next(), allowPercent: false);
      if (l == null) return null;
      lengths.add(l);
    }
    if (lengths.length < 2 || lengths.length > 4) return null;
    shadows.add(
      CssShadow(
        lengths[0],
        lengths[1],
        lengths.length > 2 ? lengths[2] : Length.zero,
        lengths.length > 3 ? lengths[3] : Length.zero,
        color ?? const ColorValue(null),
        inset: inset,
      ),
    );
  }
  return ShadowValue(shadows);
}

CssValue? _paint(ValueStream s) {
  final t = s.peek!;
  if (t.isIdent('none')) {
    s.next();
    return _none;
  }
  if (t.type == CssTokenType.url) {
    // Gradient/pattern references: paint the fallback color if any, else none.
    s.next();
    return s.done ? _none : parseColor(s);
  }
  if (t.isIdent('context-fill') || t.isIdent('context-stroke')) {
    s.next();
    return const ColorValue(null);
  }
  return parseColor(s);
}

CssValue? _strokeWidth(ValueStream s) {
  final t = s.next();
  if (t.type == CssTokenType.number && t.number >= 0)
    return Length.px(t.number);
  return lengthFromToken(t, allowNegative: false);
}

CssValue? _dashArray(ValueStream s) {
  if (s.remaining == 1 && s.peek!.isIdent('none')) {
    s.next();
    return _none;
  }
  final out = <double>[];
  while (!s.done) {
    final t = s.next();
    if (t.type == CssTokenType.comma) continue;
    if (t.type == CssTokenType.number && t.number >= 0) {
      out.add(t.number);
    } else {
      final l = lengthFromToken(t, allowPercent: false, allowNegative: false);
      if (l == null || l.unit != LengthUnit.px) return null;
      out.add(l.value);
    }
  }
  return out.isEmpty ? null : ListValue<double>(out);
}

CssValue? _filter(ValueStream s) {
  if (s.remaining == 1 && s.peek!.isIdent('none')) {
    s.next();
    return _none;
  }
  final fns = <FilterFunction>[];
  while (!s.done) {
    final t = s.next();
    if (t.type == CssTokenType.url) continue; // SVG filter references
    if (t.type != CssTokenType.function) return null;
    final name = t.value.toLowerCase();
    final args = s.functionArgs();
    if (args == null) return null;
    final parts = args.first
        .where((x) => x.type != CssTokenType.whitespace)
        .toList();
    double amount(double fallback) {
      if (parts.isEmpty) return fallback;
      final p = parts.first;
      return switch (p.type) {
        CssTokenType.number => p.number,
        CssTokenType.percentage => p.number / 100,
        _ => fallback,
      };
    }

    switch (name) {
      case 'blur':
        final l = parts.isEmpty
            ? Length.zero
            : lengthFromToken(
                parts.first,
                allowPercent: false,
                allowNegative: false,
              );
        if (l == null) return null;
        fns.add(
          FilterFunction(
            name,
            l.unit == LengthUnit.px ? l.value : l.value * 16,
          ),
        );
      case 'brightness' ||
          'contrast' ||
          'grayscale' ||
          'invert' ||
          'opacity' ||
          'saturate' ||
          'sepia':
        final def =
            name == 'brightness' ||
                name == 'contrast' ||
                name == 'saturate' ||
                name == 'opacity'
            ? 1.0
            : 1.0;
        fns.add(FilterFunction(name, amount(def)));
      case 'hue-rotate':
        fns.add(
          FilterFunction(
            name,
            parts.isEmpty ? 0 : (angleFromToken(parts.first) ?? 0),
          ),
        );
      case 'drop-shadow':
        final sh = _boxShadow(ValueStream(args.first));
        if (sh is! ShadowValue) return null;
        fns.add(FilterFunction(name, 0, shadow: sh.shadows.first));
      default:
        return null;
    }
  }
  return fns.isEmpty ? null : FilterValue(fns);
}

CssValue? _transform(ValueStream s) {
  if (s.remaining == 1 && s.peek!.isIdent('none')) {
    s.next();
    return _none;
  }
  return parseTransform(s);
}

CssValue? _trackList(ValueStream s) {
  if (s.remaining == 1 && s.peek!.isIdent('none')) {
    s.next();
    return _none;
  }
  return parseTrackList(s);
}

CssValue? _autoTracks(ValueStream s) => parseTrackList(s, allowRepeat: false);

CssValue? _areas(ValueStream s) {
  if (s.remaining == 1 && s.peek!.isIdent('none')) {
    s.next();
    return _none;
  }
  final rows = <List<String>>[];
  while (!s.done) {
    final t = s.next();
    if (t.type != CssTokenType.string) return null;
    final cells = t.value
        .trim()
        .split(RegExp(r'\s+'))
        .where((c) => c.isNotEmpty)
        .toList();
    if (cells.isEmpty) return null;
    if (rows.isNotEmpty && rows.first.length != cells.length) return null;
    rows.add(cells);
  }
  return rows.isEmpty ? null : GridAreasValue(rows);
}

/// One grid line: `auto`, `<integer>`, `span <integer>`, `<ident>`.
GridLineValue? _gridLine(ValueStream s) {
  if (s.done) return null;
  final t = s.next();
  if (t.isIdent('auto')) return GridLineValue.auto;
  if (t.isIdent('span')) {
    if (s.done) return null;
    final n = s.next();
    if (n.type == CssTokenType.number && n.number >= 1)
      return GridLineValue(span: n.number.toInt());
    if (n.type == CssTokenType.ident)
      return GridLineValue(span: 1, name: n.value);
    return null;
  }
  if (t.type == CssTokenType.number &&
      t.number != 0 &&
      t.number == t.number.truncateToDouble()) {
    return GridLineValue(line: t.number.toInt());
  }
  if (t.type == CssTokenType.ident) return GridLineValue(name: t.value);
  return null;
}

CssValue? _gridLineLonghand(ValueStream s) => _gridLine(s);

/// `a / b` pairs for grid-row / grid-column.
Map<String, CssValue>? _gridPair(ValueStream s, String start, String end) {
  final a = _gridLine(s);
  if (a == null) return null;
  GridLineValue b;
  if (!s.done && s.peek!.isDelim('/')) {
    s.next();
    final v = _gridLine(s);
    if (v == null) return null;
    b = v;
  } else {
    b = a.name != null && a.span == null ? a : GridLineValue.auto;
  }
  return {start: a, end: b};
}

const _sides = ['top', 'right', 'bottom', 'left'];
const _corners = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];
const _alignKeywords = {
  'stretch',
  'flex-start',
  'flex-end',
  'center',
  'baseline',
  'start',
  'end',
  'normal',
  'self-start',
  'self-end', //
};

extension _Let<T> on T {
  R let<R>(R value) => value;
}

/// Accepts any value (for properties NativaX tracks but does not apply).
CssValue? _any(ValueStream s) {
  final b = StringBuffer();
  while (!s.done) {
    b.write(s.next());
    b.write(' ');
  }
  return RawValue(b.toString().trim());
}

CssValue? _display(ValueStream s) {
  final words = <String>[];
  while (!s.done) {
    final t = s.next();
    if (t.type != CssTokenType.ident) return null;
    words.add(t.value.toLowerCase());
  }
  if (words.isEmpty) return null;
  // Two-value syntax (`inline flex`, `block flow-root`).
  if (words.length == 2) {
    final outer = words[0];
    final inner = words[1];
    if (outer == 'inline' && inner == 'flex')
      return const Keyword('inline-flex');
    if (outer == 'inline' && inner == 'grid')
      return const Keyword('inline-grid');
    if (outer == 'inline' && (inner == 'flow-root' || inner == 'flow'))
      return const Keyword('inline-block');
    if (outer == 'block' && const {'flex', 'grid'}.contains(inner))
      return Keyword(inner);
    if (outer == 'block' && (inner == 'flow' || inner == 'flow-root'))
      return const Keyword('block');
    return null;
  }
  if (words.length != 1) return null;
  return switch (words.single) {
    'block' ||
    'inline' ||
    'inline-block' ||
    'flex' ||
    'inline-flex' ||
    'none' ||
    'list-item' ||
    'grid' ||
    'inline-grid' ||
    'contents' => Keyword(words.single),
    // Legacy flexbox display values: treat as flex so old rules still layout.
    '-webkit-box' || '-ms-flexbox' => const Keyword('flex'),
    '-webkit-inline-box' || '-ms-inline-flexbox' => const Keyword('inline-flex'),
    'flow-root' => const Keyword('block'),
    // Tables are laid out as blocks/rows until a table layout exists.
    'table' ||
    'table-row-group' ||
    'table-header-group' ||
    'table-footer-group' ||
    'table-caption' => const Keyword('block'),
    'table-row' => const Keyword('flex'),
    'table-cell' ||
    'table-column' ||
    'table-column-group' => const Keyword('block'),
    'inline-table' => const Keyword('inline-block'),
    'ruby' || 'ruby-text' => const Keyword('inline'),
    _ => null,
  };
}

CssValue? _cursor(ValueStream s) {
  // Skip url(...) fallbacks.
  Keyword? keyword;
  while (!s.done) {
    final t = s.next();
    if (t.type == CssTokenType.url) continue;
    if (t.type == CssTokenType.function) {
      if (s.functionArgs() == null) return null;
      continue;
    }
    if (t.type == CssTokenType.comma || t.type == CssTokenType.number) continue;
    if (t.type == CssTokenType.ident) keyword = Keyword(t.value.toLowerCase());
  }
  return keyword;
}

// --- transition/animation list items ---------------------------------------------

typedef _Item<T> = T? Function(ValueStream s);

/// A comma-separated list of [item] values.
LonghandParser _listOf<T>(_Item<T> item) => (s) {
  final out = <T>[];
  while (!s.done) {
    final v = item(s);
    if (v == null) return null;
    out.add(v);
    if (s.done) break;
    if (s.peek!.type != CssTokenType.comma) return null;
    s.next();
  }
  return out.isEmpty ? null : ListValue<T>(out);
};

double? _time(ValueStream s) => s.done ? null : timeFromToken(s.next());

_Item<String> _kw(Set<String> allowed) => (s) {
  if (s.done) return null;
  final t = s.next();
  if (t.type != CssTokenType.ident) return null;
  final k = t.value.toLowerCase();
  return allowed.contains(k) ? k : null;
};

String? _transitionProperty(ValueStream s) {
  if (s.done) return null;
  final t = s.next();
  if (t.type != CssTokenType.ident) return null;
  return t.value.toLowerCase();
}

String? _animationName(ValueStream s) {
  if (s.done) return null;
  final t = s.next();
  if (t.type == CssTokenType.ident) return t.value;
  if (t.type == CssTokenType.string) return t.value;
  return null;
}

double? _iterationCount(ValueStream s) {
  if (s.done) return null;
  final t = s.next();
  if (t.isIdent('infinite')) return double.infinity;
  if (t.type == CssTokenType.number && t.number >= 0) return t.number;
  return null;
}

/// Splits a shorthand value on top-level commas.
List<List<CssToken>> _layers(ValueStream s) {
  final layers = <List<CssToken>>[[]];
  var depth = 0;
  while (!s.done) {
    final t = s.next();
    if (t.type == CssTokenType.function || t.type == CssTokenType.leftParen)
      depth++;
    if (t.type == CssTokenType.rightParen) depth--;
    if (t.type == CssTokenType.comma && depth == 0) {
      layers.add([]);
      continue;
    }
    layers.last.add(t);
  }
  return layers;
}

Map<String, CssValue>? _transitionShorthand(ValueStream s) {
  final props = <String>[], durations = <double>[], delays = <double>[];
  final easings = <CssEasing>[];
  for (final layer in _layers(s)) {
    final ls = ValueStream(layer);
    String? prop;
    double? duration, delay;
    CssEasing? easing;
    while (!ls.done) {
      final e = easing == null ? parseEasing(ls) : null;
      if (e != null) {
        easing = e;
        continue;
      }
      final t = ls.next();
      final time = timeFromToken(t);
      if (time != null) {
        if (duration == null) {
          duration = time;
        } else if (delay == null) {
          delay = time;
        } else {
          return null;
        }
        continue;
      }
      if (t.type == CssTokenType.ident && prop == null) {
        final k = t.value.toLowerCase();
        if (k == 'allow-discrete' || k == 'normal') continue;
        prop = k;
        continue;
      }
      return null;
    }
    props.add(prop ?? 'all');
    durations.add(duration ?? 0);
    delays.add(delay ?? 0);
    easings.add(easing ?? CssEasing.ease);
  }
  return {
    'transition-property': ListValue<String>(props),
    'transition-duration': ListValue<double>(durations),
    'transition-delay': ListValue<double>(delays),
    'transition-timing-function': ListValue<CssEasing>(easings),
  };
}

Map<String, CssValue>? _animationShorthand(ValueStream s) {
  final names = <String>[],
      durations = <double>[],
      delays = <double>[],
      counts = <double>[];
  final easings = <CssEasing>[];
  final directions = <String>[], fills = <String>[], states = <String>[];
  for (final layer in _layers(s)) {
    final ls = ValueStream(layer);
    String? name, direction, fill, state;
    double? duration, delay, count;
    CssEasing? easing;
    while (!ls.done) {
      final e = easing == null ? parseEasing(ls) : null;
      if (e != null) {
        easing = e;
        continue;
      }
      final t = ls.next();
      final time = timeFromToken(t);
      if (time != null &&
          !(t.type == CssTokenType.number &&
              count == null &&
              duration != null)) {
        if (duration == null) {
          duration = time;
        } else if (delay == null) {
          delay = time;
        } else {
          return null;
        }
        continue;
      }
      if (t.type == CssTokenType.number && count == null) {
        count = t.number;
        continue;
      }
      if (t.type == CssTokenType.ident) {
        final k = t.value.toLowerCase();
        if (k == 'infinite' && count == null) {
          count = double.infinity;
        } else if (direction == null &&
            const {
              'normal',
              'reverse',
              'alternate',
              'alternate-reverse',
            }.contains(k) &&
            name != null) {
          direction = k;
        } else if (direction == null &&
            const {'reverse', 'alternate', 'alternate-reverse'}.contains(k)) {
          direction = k;
        } else if (fill == null &&
            const {'forwards', 'backwards', 'both'}.contains(k)) {
          fill = k;
        } else if (state == null && const {'running', 'paused'}.contains(k)) {
          state = k;
        } else if (name == null) {
          name = t.value;
        } else {
          return null;
        }
        continue;
      }
      if (t.type == CssTokenType.string && name == null) {
        name = t.value;
        continue;
      }
      return null;
    }
    names.add(name ?? 'none');
    durations.add(duration ?? 0);
    delays.add(delay ?? 0);
    counts.add(count ?? 1);
    easings.add(easing ?? CssEasing.ease);
    directions.add(direction ?? 'normal');
    fills.add(fill ?? 'none');
    states.add(state ?? 'running');
  }
  return {
    'animation-name': ListValue<String>(names),
    'animation-duration': ListValue<double>(durations),
    'animation-delay': ListValue<double>(delays),
    'animation-iteration-count': ListValue<double>(counts),
    'animation-timing-function': ListValue<CssEasing>(easings),
    'animation-direction': ListValue<String>(directions),
    'animation-fill-mode': ListValue<String>(fills),
    'animation-play-state': ListValue<String>(states),
  };
}

final Map<String, PropertySpec> longhands = {
  for (final spec in <PropertySpec>[
    PropertySpec('display', _display, const Keyword('inline')),
    PropertySpec(
      'position',
      _keywords({'static', 'relative', 'absolute', 'fixed', 'sticky'}),
      const Keyword('static'),
    ),
    for (final side in _sides)
      PropertySpec(side, _length(keywords: {'auto'}), _auto),
    PropertySpec(
      'z-index',
      _number(negative: true, integer: true, keywords: {'auto'}),
      _auto,
    ),
    PropertySpec(
      'box-sizing',
      _keywords({'content-box', 'border-box'}),
      const Keyword('content-box'),
    ),
    PropertySpec('width', _length(keywords: {'auto'}, negative: false), _auto),
    PropertySpec('height', _length(keywords: {'auto'}, negative: false), _auto),
    PropertySpec(
      'min-width',
      _length(keywords: {'auto'}, negative: false),
      _auto,
    ),
    PropertySpec(
      'min-height',
      _length(keywords: {'auto'}, negative: false),
      _auto,
    ),
    PropertySpec(
      'max-width',
      _length(keywords: {'none'}, negative: false),
      _none,
    ),
    PropertySpec(
      'max-height',
      _length(keywords: {'none'}, negative: false),
      _none,
    ),
    for (final side in _sides) ...[
      PropertySpec('margin-$side', _length(keywords: {'auto'}), Length.zero),
      PropertySpec('padding-$side', _length(negative: false), Length.zero),
      PropertySpec('border-$side-width', _borderWidth, const Length.px(3)),
      PropertySpec('border-$side-style', _keywords(_borderStyles), _none),
      PropertySpec('border-$side-color', _color, const ColorValue(null)),
    ],
    for (final corner in _corners)
      PropertySpec(
        'border-$corner-radius',
        _length(negative: false),
        Length.zero,
      ),
    PropertySpec(
      'background-color',
      _color,
      const ColorValue(CssColor.transparent),
    ),
    PropertySpec('background-image', _backgroundImage, _none),
    PropertySpec(
      'background-repeat',
      (s) => _whole(_parseBackgroundRepeat, s),
      const Keyword('repeat'),
    ),
    PropertySpec(
      'background-position',
      (s) => _whole(_parseBackgroundPosition, s),
      const ListValue<Length>([
        Length(0, LengthUnit.percent),
        Length(0, LengthUnit.percent),
      ]),
    ),
    PropertySpec(
      'background-size',
      (s) => _whole(_parseBackgroundSize, s),
      const ListValue<Object>(['auto', 'auto']),
    ),
    PropertySpec(
      'color',
      _color,
      const ColorValue(CssColor.black),
      inherited: true,
    ),
    PropertySpec('opacity', _opacity, const NumberValue(1)),
    PropertySpec(
      'visibility',
      _keywords({'visible', 'hidden', 'collapse'}),
      const Keyword('visible'),
      inherited: true,
    ),
    PropertySpec(
      'font-family',
      _fontFamily,
      // Chrome's default standard font.
      const FontFamilyValue(['Times New Roman']),
      inherited: true,
    ),
    PropertySpec('font-size', _fontSize, const Length.px(16), inherited: true),
    PropertySpec('font-weight', _fontWeight, _normal, inherited: true),
    PropertySpec(
      'font-style',
      _keywords({'normal', 'italic', 'oblique'}),
      _normal,
      inherited: true,
    ),
    PropertySpec(
      'text-align',
      _keywords({'left', 'right', 'center', 'justify', 'start', 'end'}),
      const Keyword('start'),
      inherited: true,
    ),
    PropertySpec('text-decoration-line', _textDecorationLine, _none),
    PropertySpec('text-decoration-color', _color, const ColorValue(null)),
    PropertySpec(
      'text-decoration-style',
      _keywords({'solid', 'double', 'dotted', 'dashed', 'wavy'}),
      const Keyword('solid'),
    ),
    PropertySpec(
      'text-transform',
      _keywords({'none', 'uppercase', 'lowercase', 'capitalize'}),
      _none,
      inherited: true,
    ),
    PropertySpec(
      'letter-spacing',
      _length(keywords: {'normal'}, percent: false),
      _normal,
      inherited: true,
    ),
    PropertySpec('line-height', _lineHeight, _normal, inherited: true),
    PropertySpec(
      'white-space',
      _keywords({'normal', 'nowrap', 'pre', 'pre-wrap', 'pre-line'}),
      _normal,
      inherited: true,
    ),
    PropertySpec(
      'overflow-x',
      _keywords({'visible', 'hidden', 'scroll', 'auto', 'clip'}),
      const Keyword('visible'),
    ),
    PropertySpec(
      'overflow-y',
      _keywords({'visible', 'hidden', 'scroll', 'auto', 'clip'}),
      const Keyword('visible'),
    ),
    PropertySpec(
      'flex-direction',
      _keywords({'row', 'row-reverse', 'column', 'column-reverse'}),
      const Keyword('row'),
    ),
    PropertySpec(
      'flex-wrap',
      _keywords({'nowrap', 'wrap', 'wrap-reverse'}),
      const Keyword('nowrap'),
    ),
    PropertySpec('flex-grow', _number(), const NumberValue(0)),
    PropertySpec('flex-shrink', _number(), const NumberValue(1)),
    PropertySpec(
      'flex-basis',
      _length(keywords: {'auto', 'content'}, negative: false),
      _auto,
    ),
    PropertySpec(
      'justify-content',
      _keywords({
        'flex-start',
        'flex-end',
        'center',
        'space-between',
        'space-around',
        'space-evenly',
        'start',
        'end',
        'normal',
        'left',
        'right',
        'stretch',
      }),
      _normal,
    ),
    PropertySpec('align-items', _keywords(_alignKeywords), _normal),
    PropertySpec('align-self', _keywords({..._alignKeywords, 'auto'}), _auto),
    PropertySpec(
      'row-gap',
      _length(keywords: {'normal'}, negative: false),
      _normal,
    ),
    PropertySpec(
      'column-gap',
      _length(keywords: {'normal'}, negative: false),
      _normal,
    ),
    PropertySpec(
      'list-style-type',
      _keywords({'none', 'disc', 'circle', 'square', 'decimal'}),
      const Keyword('disc'),
      inherited: true,
    ),
    PropertySpec(
      'object-fit',
      _keywords({'fill', 'contain', 'cover', 'none', 'scale-down'}),
      const Keyword('fill'),
    ),
    PropertySpec('cursor', _cursor, _auto, inherited: true),
    PropertySpec('content', _content, _normal),
    // SVG painting.
    PropertySpec(
      'fill',
      _paint,
      const ColorValue(CssColor.black),
      inherited: true,
    ),
    PropertySpec('stroke', _paint, _none, inherited: true),
    PropertySpec(
      'stroke-width',
      _strokeWidth,
      const Length.px(1),
      inherited: true,
    ),
    PropertySpec(
      'fill-opacity',
      _opacity,
      const NumberValue(1),
      inherited: true,
    ),
    PropertySpec(
      'stroke-opacity',
      _opacity,
      const NumberValue(1),
      inherited: true,
    ),
    PropertySpec(
      'stroke-linecap',
      _keywords({'butt', 'round', 'square'}),
      const Keyword('butt'),
      inherited: true,
    ),
    PropertySpec(
      'stroke-linejoin',
      _keywords({'miter', 'round', 'bevel', 'miter-clip', 'arcs'}),
      const Keyword('miter'),
      inherited: true,
    ),
    PropertySpec(
      'fill-rule',
      _keywords({'nonzero', 'evenodd'}),
      const Keyword('nonzero'),
      inherited: true,
    ),
    PropertySpec(
      'text-anchor',
      _keywords({'start', 'middle', 'end'}),
      const Keyword('start'),
      inherited: true,
    ),
    PropertySpec(
      'dominant-baseline',
      _keywords({
        'auto',
        'middle',
        'central',
        'hanging',
        'alphabetic',
        'text-top',
        'text-bottom',
        'ideographic',
        'mathematical',
      }),
      _auto,
      inherited: true,
    ),
    PropertySpec('stroke-dasharray', _dashArray, _none, inherited: true),
    PropertySpec('box-shadow', _boxShadow, _none),
    PropertySpec('text-shadow', _boxShadow, _none, inherited: true),
    PropertySpec('filter', _filter, _none),
    PropertySpec('backdrop-filter', _filter, _none),
    PropertySpec('-webkit-backdrop-filter', _filter, _none),
    PropertySpec('transform', _transform, _none),
    PropertySpec(
      'pointer-events',
      _keywords({
        'auto',
        'none',
        'stroke',
        'fill',
        'all',
        'painted',
        'visible',
        'bounding-box',
      }),
      _auto,
      inherited: true,
    ),
    PropertySpec(
      'accent-color',
      (s) => s.peek!.isIdent('auto') ? (s..next()).let(_auto) : parseColor(s),
      _auto,
      inherited: true,
    ),
    PropertySpec('vertical-align', (s) {
      final t = s.next();
      if (t.type == CssTokenType.ident) {
        final k = t.value.toLowerCase();
        return const {
              'baseline',
              'middle',
              'top',
              'bottom',
              'text-top',
              'text-bottom',
              'sub',
              'super',
            }.contains(k)
            ? Keyword(k)
            : null;
      }
      return lengthFromToken(t);
    }, const Keyword('baseline')),
    PropertySpec(
      'text-overflow',
      _keywords({'clip', 'ellipsis'}),
      const Keyword('clip'),
    ),
    PropertySpec(
      'word-break',
      _keywords({'normal', 'break-all', 'keep-all', 'break-word'}),
      _normal,
      inherited: true,
    ),
    PropertySpec(
      'overflow-wrap',
      _keywords({'normal', 'anywhere', 'break-word'}),
      _normal,
      inherited: true,
    ),
    PropertySpec(
      'user-select',
      _keywords({'auto', 'none', 'text', 'all', 'contain'}),
      _auto,
    ),
    PropertySpec(
      'order',
      _number(negative: true, integer: true),
      const NumberValue(0),
    ),
    PropertySpec('aspect-ratio', (s) {
      final t = s.next();
      if (t.isIdent('auto')) return _auto;
      if (t.type != CssTokenType.number || t.number <= 0) return null;
      var ratio = t.number;
      if (!s.done && s.peek!.isDelim('/')) {
        s.next();
        if (s.done) return null;
        final d = s.next();
        if (d.type != CssTokenType.number || d.number <= 0) return null;
        ratio /= d.number;
      }
      return NumberValue(ratio);
    }, _auto),
    PropertySpec('outline-width', _borderWidth, const Length.px(3)),
    PropertySpec('outline-style', _keywords({..._borderStyles, 'auto'}), _none),
    PropertySpec('outline-color', _color, const ColorValue(null)),
    PropertySpec('outline-offset', _length(percent: false), Length.zero),
    // Grid.
    PropertySpec('grid-template-columns', _trackList, _none),
    PropertySpec('grid-template-rows', _trackList, _none),
    PropertySpec('grid-template-areas', _areas, _none),
    PropertySpec(
      'grid-auto-columns',
      _autoTracks,
      const GridTracksValue([
        TrackEntry([TrackSize.auto]),
      ]),
    ),
    PropertySpec(
      'grid-auto-rows',
      _autoTracks,
      const GridTracksValue([
        TrackEntry([TrackSize.auto]),
      ]),
    ),
    PropertySpec('grid-auto-flow', (s) {
      final words = <String>[];
      while (!s.done) {
        final t = s.next();
        if (t.type != CssTokenType.ident) return null;
        words.add(t.value.toLowerCase());
      }
      if (words.isEmpty ||
          words.any((w) => !const {'row', 'column', 'dense'}.contains(w)))
        return null;
      return Keyword(words.contains('column') ? 'column' : 'row');
    }, const Keyword('row')),
    PropertySpec('grid-row-start', _gridLineLonghand, GridLineValue.auto),
    PropertySpec('grid-row-end', _gridLineLonghand, GridLineValue.auto),
    PropertySpec('grid-column-start', _gridLineLonghand, GridLineValue.auto),
    PropertySpec('grid-column-end', _gridLineLonghand, GridLineValue.auto),
    PropertySpec(
      'justify-items',
      _keywords({
        ..._alignKeywords,
        'left',
        'right',
        'legacy',
        'self-start',
        'self-end',
      }),
      _normal,
    ),
    PropertySpec(
      'justify-self',
      _keywords({
        ..._alignKeywords,
        'auto',
        'left',
        'right',
        'self-start',
        'self-end',
      }),
      _auto,
    ),
    PropertySpec(
      'align-content',
      _keywords({
        ..._alignKeywords,
        'space-between',
        'space-around',
        'space-evenly',
      }),
      _normal,
    ),
    // Parsed so that declarations are not reported as invalid; NativaX does
    // not animate yet.
    PropertySpec(
      'transition-property',
      _listOf(_transitionProperty),
      const ListValue<String>(['all']),
    ),
    PropertySpec(
      'transition-duration',
      _listOf(_time),
      const ListValue<double>([0]),
    ),
    PropertySpec(
      'transition-delay',
      _listOf(_time),
      const ListValue<double>([0]),
    ),
    PropertySpec(
      'transition-timing-function',
      _listOf(parseEasing),
      const ListValue<CssEasing>([CssEasing.ease]),
    ),
    PropertySpec(
      'animation-name',
      _listOf(_animationName),
      const ListValue<String>(['none']),
    ),
    PropertySpec(
      'animation-duration',
      _listOf(_time),
      const ListValue<double>([0]),
    ),
    PropertySpec(
      'animation-delay',
      _listOf(_time),
      const ListValue<double>([0]),
    ),
    PropertySpec(
      'animation-timing-function',
      _listOf(parseEasing),
      const ListValue<CssEasing>([CssEasing.ease]),
    ),
    PropertySpec(
      'animation-iteration-count',
      _listOf(_iterationCount),
      const ListValue<double>([1]),
    ),
    PropertySpec(
      'animation-direction',
      _listOf(_kw({'normal', 'reverse', 'alternate', 'alternate-reverse'})),
      const ListValue<String>(['normal']),
    ),
    PropertySpec(
      'animation-fill-mode',
      _listOf(_kw({'none', 'forwards', 'backwards', 'both'})),
      const ListValue<String>(['none']),
    ),
    PropertySpec(
      'animation-play-state',
      _listOf(_kw({'running', 'paused'})),
      const ListValue<String>(['running']),
    ),
    for (final name in const [
      'transition-behavior',
      'animation-composition',
      'animation-timeline',
      'animation-range',
      'will-change',
      'perspective',
      'perspective-origin',
      'transform-origin',
      'transform-style',
      'backface-visibility',
      'color-scheme',
      'scrollbar-width',
      'scrollbar-color',
      'scroll-behavior',
      'scroll-padding-top',
      'scroll-padding',
      'scroll-margin-top',
      'scroll-snap-type',
      'scroll-snap-align',
      'overscroll-behavior',
      'touch-action',
      'appearance',
      '-webkit-appearance',
      '-webkit-tap-highlight-color',
      '-webkit-font-smoothing',
      '-moz-osx-font-smoothing',
      'text-rendering',
      'font-feature-settings',
      'font-variant-numeric',
      'font-display',
      'font-kerning',
      'hyphens',
      'tab-size',
      'caret-color',
      'resize',
      'contain',
      'content-visibility',
      'isolation',
      'mix-blend-mode',
      'image-rendering',
      'text-size-adjust',
      '-webkit-text-size-adjust',
      'speak',
      'print-color-adjust',
      'forced-color-adjust',
      'mask',
      'clip-path',
      'shape-outside',
      'counter-reset',
      'counter-increment',
      'quotes',
      'background-attachment',
      'background-clip',
      'background-origin',
      'text-indent',
      'text-underline-offset',
      'text-decoration-thickness',
      'table-layout',
      'border-collapse',
      'border-spacing',
      'caption-side',
      'empty-cells',
      'list-style-position',
      'list-style-image',
      'object-position',
      'writing-mode',
      'direction',
      'unicode-bidi',
      'float',
      'clear',
      'columns',
      'column-count',
      'column-width',
      'column-rule',
      'break-inside',
      'page-break-inside',
      'widows',
      'orphans',
      'zoom',
      'inset-inline',
      'inset-block',
      'interpolate-size',
      'field-sizing',
      'font-variant-emoji',
      'font-variant',
      'font-stretch',
      'font-optical-sizing',
      'font-synthesis',
      'text-wrap',
      'text-wrap-mode',
      'text-wrap-style',
      'white-space-collapse',
      'line-clamp',
      '-webkit-line-clamp',
      '-webkit-box-orient',
      'text-align-last',
      'text-justify',
      'word-spacing',
      'scrollbar-gutter',
      'overscroll-behavior-x',
      'overscroll-behavior-y',
      'container-type',
      'container-name',
      'container',
      'anchor-name',
      'position-anchor',
      'view-transition-name',
      'offset-path',
      'offset-distance',
    ])
      PropertySpec(name, _any, const RawValue('')),
  ])
    spec.name: spec,
};

/// Expands [name] with [tokens] into longhand values, or returns null when
/// the property is unknown or the value invalid.
Map<String, CssValue>? expandDeclaration(String name, List<CssToken> tokens) {
  final s = ValueStream(tokens);
  if (s.done) return null;

  // Global keywords apply to every longhand of a shorthand.
  if (s.remaining == 1 && s.peek!.type == CssTokenType.ident) {
    final k = s.peek!.value.toLowerCase();
    if (k == 'inherit' || k == 'initial' || k == 'unset') {
      final targets = longhands.containsKey(name)
          ? [name]
          : _shorthandTargets[name];
      if (targets == null) return null;
      return {for (final t in targets) t: GlobalKeyword(k)};
    }
  }

  final spec = longhands[name];
  if (spec != null) {
    final v = spec.parse(s);
    return v != null && s.done ? {name: v} : null;
  }
  final expander = _shorthands[name];
  if (expander == null) return null;
  final result = expander(s);
  return result != null && s.done ? result : null;
}

bool isSupportedProperty(String name) =>
    longhands.containsKey(name) || _shorthands.containsKey(name);

/// 1–4 value box shorthand (top, right, bottom, left).
Map<String, CssValue>? _box(
  ValueStream s,
  String Function(String side) key,
  LonghandParser p,
) {
  final values = <CssValue>[];
  while (!s.done && values.length < 4) {
    final v = p(s);
    if (v == null) return null;
    values.add(v);
  }
  if (values.isEmpty) return null;
  final t = values[0];
  final r = values.length > 1 ? values[1] : t;
  final b = values.length > 2 ? values[2] : t;
  final l = values.length > 3 ? values[3] : r;
  return {key('top'): t, key('right'): r, key('bottom'): b, key('left'): l};
}

/// `border` / `border-<side>`: width, style and color in any order.
Map<String, CssValue>? _borderSide(ValueStream s, List<String> sides) {
  CssValue? width, style, color;
  while (!s.done) {
    final t = s.peek!;
    if (style == null &&
        t.type == CssTokenType.ident &&
        _borderStyles.contains(t.value.toLowerCase())) {
      s.next();
      style = Keyword(t.value.toLowerCase());
      continue;
    }
    if (width == null) {
      final w = _borderWidth(s);
      if (w != null) {
        width = w;
        continue;
      }
      s.back();
    }
    if (color == null) {
      final c = parseColor(s);
      if (c != null) {
        color = c;
        continue;
      }
    }
    return null;
  }
  return {
    for (final side in sides) ...{
      'border-$side-width': width ?? const Length.px(3),
      'border-$side-style': style ?? _none,
      'border-$side-color': color ?? const ColorValue(null),
    },
  };
}

typedef _Expander = Map<String, CssValue>? Function(ValueStream s);

final Map<String, _Expander> _shorthands = {
  'margin': (s) => _box(s, (x) => 'margin-$x', longhands['margin-top']!.parse),
  'padding': (s) =>
      _box(s, (x) => 'padding-$x', longhands['padding-top']!.parse),
  'border-width': (s) => _box(s, (x) => 'border-$x-width', _borderWidth),
  'border-style': (s) =>
      _box(s, (x) => 'border-$x-style', _keywords(_borderStyles)),
  'border-color': (s) => _box(s, (x) => 'border-$x-color', _color),
  'border': (s) => _borderSide(s, _sides),
  for (final side in _sides) 'border-$side': (s) => _borderSide(s, [side]),
  'border-radius': (s) {
    final m = _box(s, (x) => x, _length(negative: false));
    if (m == null) return null;
    // Box order (t, r, b, l) maps to corners (tl, tr, br, bl).
    return {
      'border-top-left-radius': m['top']!,
      'border-top-right-radius': m['right']!,
      'border-bottom-right-radius': m['bottom']!,
      'border-bottom-left-radius': m['left']!,
    };
  },
  'font': (s) {
    CssValue? style, weight;
    while (!s.done) {
      final t = s.peek!;
      if (t.type == CssTokenType.ident) {
        final k = t.value.toLowerCase();
        if (style == null && (k == 'italic' || k == 'oblique')) {
          style = Keyword(k);
          s.next();
          continue;
        }
        if (weight == null &&
            (k == 'bold' || k == 'bolder' || k == 'lighter')) {
          weight = Keyword(k);
          s.next();
          continue;
        }
        if (weight == null && k == 'normal') {
          s.next();
          continue;
        }
      }
      if (weight == null &&
          t.type == CssTokenType.number &&
          t.number >= 1 &&
          t.number <= 1000) {
        weight = NumberValue(t.number);
        s.next();
        continue;
      }
      break;
    }
    final size = _fontSize(s);
    if (size == null) return null;
    CssValue? lineHeight;
    if (!s.done && s.peek!.isDelim('/')) {
      s.next();
      lineHeight = _lineHeight(s);
      if (lineHeight == null) return null;
    }
    final family = _fontFamily(s);
    if (family == null) return null;
    return {
      'font-style': style ?? _normal,
      'font-weight': weight ?? _normal,
      'font-size': size,
      if (lineHeight != null) 'line-height': lineHeight,
      'font-family': family,
    };
  },
  'background': (s) {
    // Only the last layer may carry a color; NativaX paints the first image
    // layer and the color.
    CssValue? color, image, repeat, position, size;
    var depth = 0;
    while (!s.done) {
      final t = s.peek!;
      if (t.type == CssTokenType.comma && depth == 0) {
        // Another layer follows; keep the first image.
        s.next();
        continue;
      }
      if (image == null) {
        final i = _backgroundImage(s);
        if (i != null) {
          image = i;
          continue;
        }
        s.back();
      } else {
        // Later layers' images are skipped.
        final g = parseGradient(s);
        if (g != null) continue;
        if (s.peek!.type == CssTokenType.url) {
          s.next();
          continue;
        }
      }
      if (repeat == null) {
        repeat = _parseBackgroundRepeat(s);
        if (repeat != null) continue;
      }
      if (position == null) {
        position = _parseBackgroundPosition(s);
        if (position != null) {
          if (!s.done && s.peek!.isDelim('/')) {
            s.next();
            size = _parseBackgroundSize(s);
            if (size == null) return null;
          }
          continue;
        }
      }
      final c = parseColor(s);
      if (c != null) {
        color = c;
        continue;
      }
      // Attachment and box keywords (and later layers' position, size and
      // repeat) are accepted and ignored.
      final n = s.next();
      if (n.type == CssTokenType.ident &&
          const {
            'repeat',
            'no-repeat',
            'repeat-x',
            'repeat-y',
            'space',
            'round',
            'center',
            'top',
            'left',
            'right',
            'bottom',
            'cover',
            'contain',
            'auto',
            'fixed',
            'scroll',
            'local',
            'border-box',
            'padding-box',
            'content-box',
            'text',
          }.contains(n.value.toLowerCase())) {
        continue;
      }
      if (n.isDelim('/') ||
          n.type == CssTokenType.percentage ||
          n.type == CssTokenType.dimension ||
          (n.type == CssTokenType.number && n.number == 0)) {
        continue;
      }
      return null;
    }
    return {
      'background-color': color ?? const ColorValue(CssColor.transparent),
      'background-image': image ?? _none,
      'background-repeat': repeat ?? const Keyword('repeat'),
      'background-position': position ??
          const ListValue<Length>([
            Length(0, LengthUnit.percent),
            Length(0, LengthUnit.percent),
          ]),
      'background-size': size ?? const ListValue<Object>(['auto', 'auto']),
    };
  },
  'overflow': (s) {
    final p = longhands['overflow-x']!.parse;
    final x = p(s);
    if (x == null) return null;
    final y = s.done ? x : p(s);
    if (y == null) return null;
    return {'overflow-x': x, 'overflow-y': y};
  },
  'gap': (s) {
    final p = longhands['row-gap']!.parse;
    final row = p(s);
    if (row == null) return null;
    final col = s.done ? row : p(s);
    if (col == null) return null;
    return {'row-gap': row, 'column-gap': col};
  },
  'flex': (s) {
    final first = s.peek!;
    if (s.remaining == 1 && first.type == CssTokenType.ident) {
      s.next();
      return switch (first.value.toLowerCase()) {
        'none' => {
          'flex-grow': const NumberValue(0),
          'flex-shrink': const NumberValue(0),
          'flex-basis': _auto,
        },
        'auto' => {
          'flex-grow': const NumberValue(1),
          'flex-shrink': const NumberValue(1),
          'flex-basis': _auto,
        },
        _ => null,
      };
    }
    NumberValue? grow, shrink;
    CssValue? basis;
    while (!s.done) {
      final t = s.next();
      if (t.type == CssTokenType.number) {
        if (t.number < 0) return null;
        if (grow == null) {
          grow = NumberValue(t.number);
        } else if (shrink == null && basis == null) {
          shrink = NumberValue(t.number);
        } else if (t.number == 0 && basis == null) {
          basis = Length.zero;
        } else {
          return null;
        }
        continue;
      }
      if (basis != null) return null;
      s.back();
      basis = longhands['flex-basis']!.parse(s);
      if (basis == null) return null;
    }
    return {
      'flex-grow': grow ?? const NumberValue(1),
      'flex-shrink': shrink ?? const NumberValue(1),
      // A unitless flex like `flex: 1` means a 0% basis.
      'flex-basis': basis ?? const Length(0, LengthUnit.percent),
    };
  },
  'flex-flow': (s) {
    CssValue? dir, wrap;
    while (!s.done) {
      final t = s.next();
      final k = t.type == CssTokenType.ident ? t.value.toLowerCase() : '';
      if (dir == null &&
          const {
            'row',
            'row-reverse',
            'column',
            'column-reverse',
          }.contains(k)) {
        dir = Keyword(k);
      } else if (wrap == null &&
          const {'nowrap', 'wrap', 'wrap-reverse'}.contains(k)) {
        wrap = Keyword(k);
      } else {
        return null;
      }
    }
    return {
      'flex-direction': dir ?? const Keyword('row'),
      'flex-wrap': wrap ?? const Keyword('nowrap'),
    };
  },
  'text-decoration': (s) {
    final lineTokens = <CssToken>[];
    CssValue? color, style;
    while (!s.done) {
      final t = s.peek!;
      final k = t.type == CssTokenType.ident ? t.value.toLowerCase() : '';
      if (const {'none', 'underline', 'overline', 'line-through'}.contains(k)) {
        lineTokens.add(s.next());
      } else if (style == null &&
          const {'solid', 'double', 'dotted', 'dashed', 'wavy'}.contains(k)) {
        s.next();
        style = Keyword(k);
      } else if (color == null && (color = parseColor(s)) != null) {
        continue;
      } else {
        return null;
      }
    }
    final line = lineTokens.isEmpty
        ? _none
        : _textDecorationLine(ValueStream(lineTokens));
    if (line == null) return null;
    return {
      'text-decoration-line': line,
      'text-decoration-color': color ?? const ColorValue(null),
      'text-decoration-style': style ?? const Keyword('solid'),
    };
  },
  'list-style': (s) {
    CssValue? type;
    while (!s.done) {
      final t = s.peek!;
      if (t.isIdent('inside') ||
          t.isIdent('outside') ||
          t.type == CssTokenType.url) {
        s.next();
        continue;
      }
      if (type != null) return null;
      type = longhands['list-style-type']!.parse(s);
      if (type == null) return null;
    }
    return {'list-style-type': type ?? const Keyword('disc')};
  },
  'inset': (s) => _box(s, (x) => x, longhands['top']!.parse),
  'outline': (s) {
    CssValue? width, style, color;
    while (!s.done) {
      final t = s.peek!;
      if (style == null &&
          t.type == CssTokenType.ident &&
          ({..._borderStyles, 'auto'}).contains(t.value.toLowerCase())) {
        s.next();
        style = Keyword(t.value.toLowerCase());
        continue;
      }
      if (width == null) {
        final w = _borderWidth(s);
        if (w != null) {
          width = w;
          continue;
        }
        s.back();
      }
      if (color == null) {
        final c = parseColor(s);
        if (c != null) {
          color = c;
          continue;
        }
      }
      return null;
    }
    return {
      'outline-width': width ?? const Length.px(3),
      'outline-style': style ?? _none,
      'outline-color': color ?? const ColorValue(null),
    };
  },
  'transition': _transitionShorthand,
  'animation': _animationShorthand,
  '-webkit-animation': _animationShorthand,
  '-webkit-transition': _transitionShorthand,
  'grid-row': (s) => _gridPair(s, 'grid-row-start', 'grid-row-end'),
  'grid-column': (s) => _gridPair(s, 'grid-column-start', 'grid-column-end'),
  'grid-area': (s) {
    final lines = <GridLineValue>[];
    while (!s.done) {
      if (lines.isNotEmpty) {
        if (!s.peek!.isDelim('/')) return null;
        s.next();
      }
      final l = _gridLine(s);
      if (l == null) return null;
      lines.add(l);
    }
    if (lines.isEmpty || lines.length > 4) return null;
    GridLineValue fallback(GridLineValue from) =>
        from.name != null && from.span == null ? from : GridLineValue.auto;
    final rowStart = lines[0];
    final colStart = lines.length > 1 ? lines[1] : fallback(rowStart);
    final rowEnd = lines.length > 2 ? lines[2] : fallback(rowStart);
    final colEnd = lines.length > 3 ? lines[3] : fallback(colStart);
    return {
      'grid-row-start': rowStart,
      'grid-column-start': colStart,
      'grid-row-end': rowEnd,
      'grid-column-end': colEnd,
    };
  },
  'grid-template': (s) {
    // `<rows> / <columns>` only (no inline area strings).
    final rows = <CssToken>[];
    while (!s.done && !s.peek!.isDelim('/')) {
      rows.add(s.next());
    }
    if (s.done) return null;
    s.next();
    final cols = <CssToken>[];
    while (!s.done) {
      cols.add(s.next());
    }
    final r = _trackList(ValueStream(rows));
    final c = _trackList(ValueStream(cols));
    if (r == null || c == null) return null;
    return {
      'grid-template-rows': r,
      'grid-template-columns': c,
      'grid-template-areas': _none,
    };
  },
  'place-items': (s) {
    final a = longhands['align-items']!.parse(s);
    if (a == null) return null;
    final j = s.done ? a : longhands['justify-items']!.parse(s);
    if (j == null) return null;
    return {'align-items': a, 'justify-items': j};
  },
  'place-self': (s) {
    final a = longhands['align-self']!.parse(s);
    if (a == null) return null;
    final j = s.done ? a : longhands['justify-self']!.parse(s);
    if (j == null) return null;
    return {'align-self': a, 'justify-self': j};
  },
  'place-content': (s) {
    final a = longhands['align-content']!.parse(s);
    if (a == null) return null;
    final j = s.done ? a : longhands['justify-content']!.parse(s);
    if (j == null) return null;
    return {'align-content': a, 'justify-content': j};
  },
};

final Map<String, List<String>> _shorthandTargets = {
  'margin': [for (final x in _sides) 'margin-$x'],
  'padding': [for (final x in _sides) 'padding-$x'],
  'border-width': [for (final x in _sides) 'border-$x-width'],
  'border-style': [for (final x in _sides) 'border-$x-style'],
  'border-color': [for (final x in _sides) 'border-$x-color'],
  'border': [
    for (final x in _sides) ...[
      'border-$x-width',
      'border-$x-style',
      'border-$x-color',
    ],
  ],
  for (final x in _sides)
    'border-$x': ['border-$x-width', 'border-$x-style', 'border-$x-color'],
  'border-radius': [for (final c in _corners) 'border-$c-radius'],
  'background': [
    'background-color',
    'background-image',
    'background-repeat',
    'background-position',
    'background-size',
  ],
  'overflow': ['overflow-x', 'overflow-y'],
  'gap': ['row-gap', 'column-gap'],
  'flex': ['flex-grow', 'flex-shrink', 'flex-basis'],
  'flex-flow': ['flex-direction', 'flex-wrap'],
  'text-decoration': [
    'text-decoration-line',
    'text-decoration-color',
    'text-decoration-style',
  ],
  'list-style': ['list-style-type'],
  'font': [
    'font-style',
    'font-weight',
    'font-size',
    'line-height',
    'font-family',
  ],
  'transition': [
    'transition-property',
    'transition-duration',
    'transition-delay',
    'transition-timing-function',
  ],
  'animation': [
    'animation-name',
    'animation-duration',
    'animation-delay',
    'animation-iteration-count',
    'animation-timing-function',
    'animation-direction',
    'animation-fill-mode',
    'animation-play-state',
  ],
  'inset': ['top', 'right', 'bottom', 'left'],
  'outline': ['outline-width', 'outline-style', 'outline-color'],
  'grid-row': ['grid-row-start', 'grid-row-end'],
  'grid-column': ['grid-column-start', 'grid-column-end'],
  'grid-area': [
    'grid-row-start',
    'grid-column-start',
    'grid-row-end',
    'grid-column-end',
  ],
  'grid-template': [
    'grid-template-rows',
    'grid-template-columns',
    'grid-template-areas',
  ],
  'place-items': ['align-items', 'justify-items'],
  'place-self': ['align-self', 'justify-self'],
  'place-content': ['align-content', 'justify-content'],
};
