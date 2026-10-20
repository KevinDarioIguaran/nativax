/// Property registry: grammar, initial values, inheritance and shorthand
/// expansion for every property NativaX supports. Declarations for anything
/// not listed here are dropped at parse time and reported.
library;

import 'tokenizer.dart';
import 'values.dart';

typedef LonghandParser = CssValue? Function(ValueStream s);

class PropertySpec {
  const PropertySpec(this.name, this.parse, this.initial, {this.inherited = false});
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
}) =>
    (s) {
      final t = s.next();
      if (t.type == CssTokenType.ident) {
        final k = t.value.toLowerCase();
        return keywords.contains(k) ? Keyword(k) : null;
      }
      return lengthFromToken(t, allowPercent: percent, allowNegative: negative);
    };

CssValue? _color(ValueStream s) => parseColor(s);

LonghandParser _number({bool negative = false, bool integer = false, Set<String> keywords = const {}}) =>
    (s) {
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

const _borderStyles = {'none', 'hidden', 'solid', 'dashed', 'dotted', 'double'};

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
    return const {'normal', 'bold', 'bolder', 'lighter'}.contains(k) ? Keyword(k) : null;
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
  if (t.type == CssTokenType.number) return t.number < 0 ? null : NumberValue(t.number);
  return lengthFromToken(t, allowNegative: false);
}

CssValue? _textDecorationLine(ValueStream s) {
  final lines = <String>{};
  while (!s.done) {
    final t = s.next();
    if (t.type != CssTokenType.ident) return null;
    final k = t.value.toLowerCase();
    if (k == 'none' && lines.isEmpty && s.done) return _none;
    if (!const {'underline', 'overline', 'line-through'}.contains(k) || !lines.add(k)) {
      return null;
    }
  }
  return lines.isEmpty ? null : Keyword((lines.toList()..sort()).join(' '));
}

CssValue? _backgroundImage(ValueStream s) {
  final t = s.next();
  if (t.isIdent('none')) return _none;
  if (t.type == CssTokenType.url) return UrlValue(t.value);
  if (t.type == CssTokenType.function && t.value.toLowerCase() == 'url') {
    final args = s.functionArgs();
    final inner = args?.single.where((x) => x.type != CssTokenType.whitespace).toList();
    if (inner == null || inner.length != 1 || inner.single.type != CssTokenType.string) {
      return null;
    }
    return UrlValue(inner.single.value);
  }
  return null;
}

const _sides = ['top', 'right', 'bottom', 'left'];
const _corners = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];
const _alignKeywords = {
  'stretch', 'flex-start', 'flex-end', 'center', 'baseline', 'start', 'end', 'normal', //
};

final Map<String, PropertySpec> longhands = {
  for (final spec in <PropertySpec>[
    PropertySpec('display', _keywords({'block', 'inline', 'inline-block', 'flex', 'inline-flex', 'none', 'list-item'}), const Keyword('inline')),
    PropertySpec('position', _keywords({'static', 'relative', 'absolute'}), const Keyword('static')),
    for (final side in _sides) PropertySpec(side, _length(keywords: {'auto'}), _auto),
    PropertySpec('z-index', _number(negative: true, integer: true, keywords: {'auto'}), _auto),
    PropertySpec('box-sizing', _keywords({'content-box', 'border-box'}), const Keyword('content-box')),
    PropertySpec('width', _length(keywords: {'auto'}, negative: false), _auto),
    PropertySpec('height', _length(keywords: {'auto'}, negative: false), _auto),
    PropertySpec('min-width', _length(keywords: {'auto'}, negative: false), _auto),
    PropertySpec('min-height', _length(keywords: {'auto'}, negative: false), _auto),
    PropertySpec('max-width', _length(keywords: {'none'}, negative: false), _none),
    PropertySpec('max-height', _length(keywords: {'none'}, negative: false), _none),
    for (final side in _sides) ...[
      PropertySpec('margin-$side', _length(keywords: {'auto'}), Length.zero),
      PropertySpec('padding-$side', _length(negative: false), Length.zero),
      PropertySpec('border-$side-width', _borderWidth, const Length.px(3)),
      PropertySpec('border-$side-style', _keywords(_borderStyles), _none),
      PropertySpec('border-$side-color', _color, const ColorValue(null)),
    ],
    for (final corner in _corners)
      PropertySpec('border-$corner-radius', _length(negative: false), Length.zero),
    PropertySpec('background-color', _color, const ColorValue(CssColor.transparent)),
    PropertySpec('background-image', _backgroundImage, _none),
    PropertySpec('color', _color, const ColorValue(CssColor.black), inherited: true),
    PropertySpec('opacity', _opacity, const NumberValue(1)),
    PropertySpec('visibility', _keywords({'visible', 'hidden', 'collapse'}), const Keyword('visible'), inherited: true),
    PropertySpec('font-family', _fontFamily, const FontFamilyValue(['sans-serif']), inherited: true),
    PropertySpec('font-size', _fontSize, const Length.px(16), inherited: true),
    PropertySpec('font-weight', _fontWeight, _normal, inherited: true),
    PropertySpec('font-style', _keywords({'normal', 'italic', 'oblique'}), _normal, inherited: true),
    PropertySpec('text-align', _keywords({'left', 'right', 'center', 'justify', 'start', 'end'}), const Keyword('start'), inherited: true),
    PropertySpec('text-decoration-line', _textDecorationLine, _none),
    PropertySpec('text-decoration-color', _color, const ColorValue(null)),
    PropertySpec('text-decoration-style', _keywords({'solid', 'double', 'dotted', 'dashed', 'wavy'}), const Keyword('solid')),
    PropertySpec('text-transform', _keywords({'none', 'uppercase', 'lowercase', 'capitalize'}), _none, inherited: true),
    PropertySpec('letter-spacing', _length(keywords: {'normal'}, percent: false), _normal, inherited: true),
    PropertySpec('line-height', _lineHeight, _normal, inherited: true),
    PropertySpec('white-space', _keywords({'normal', 'nowrap', 'pre', 'pre-wrap', 'pre-line'}), _normal, inherited: true),
    PropertySpec('overflow-x', _keywords({'visible', 'hidden', 'scroll', 'auto', 'clip'}), const Keyword('visible')),
    PropertySpec('overflow-y', _keywords({'visible', 'hidden', 'scroll', 'auto', 'clip'}), const Keyword('visible')),
    PropertySpec('flex-direction', _keywords({'row', 'row-reverse', 'column', 'column-reverse'}), const Keyword('row')),
    PropertySpec('flex-wrap', _keywords({'nowrap', 'wrap', 'wrap-reverse'}), const Keyword('nowrap')),
    PropertySpec('flex-grow', _number(), const NumberValue(0)),
    PropertySpec('flex-shrink', _number(), const NumberValue(1)),
    PropertySpec('flex-basis', _length(keywords: {'auto', 'content'}, negative: false), _auto),
    PropertySpec('justify-content', _keywords({'flex-start', 'flex-end', 'center', 'space-between', 'space-around', 'space-evenly', 'start', 'end', 'normal'}), _normal),
    PropertySpec('align-items', _keywords(_alignKeywords), _normal),
    PropertySpec('align-self', _keywords({..._alignKeywords, 'auto'}), _auto),
    PropertySpec('row-gap', _length(keywords: {'normal'}, negative: false), _normal),
    PropertySpec('column-gap', _length(keywords: {'normal'}, negative: false), _normal),
    PropertySpec('list-style-type', _keywords({'none', 'disc', 'circle', 'square', 'decimal'}), const Keyword('disc'), inherited: true),
    PropertySpec('object-fit', _keywords({'fill', 'contain', 'cover', 'none', 'scale-down'}), const Keyword('fill')),
    PropertySpec('cursor', _keywords({'auto', 'default', 'pointer', 'text', 'move', 'not-allowed', 'wait', 'help', 'crosshair', 'grab'}), _auto, inherited: true),
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
      final targets = longhands.containsKey(name) ? [name] : _shorthandTargets[name];
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
Map<String, CssValue>? _box(ValueStream s, String Function(String side) key, LonghandParser p) {
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
    if (style == null && t.type == CssTokenType.ident && _borderStyles.contains(t.value.toLowerCase())) {
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
  'padding': (s) => _box(s, (x) => 'padding-$x', longhands['padding-top']!.parse),
  'border-width': (s) => _box(s, (x) => 'border-$x-width', _borderWidth),
  'border-style': (s) => _box(s, (x) => 'border-$x-style', _keywords(_borderStyles)),
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
  'background': (s) {
    CssValue? color, image;
    while (!s.done) {
      if (color == null) {
        final c = parseColor(s);
        if (c != null) {
          color = c;
          continue;
        }
      }
      if (image == null) {
        final i = _backgroundImage(s);
        if (i != null) {
          image = i;
          continue;
        }
        s.back();
      }
      // Position, size, repeat and attachment are not supported.
      return null;
    }
    return {
      'background-color': color ?? const ColorValue(CssColor.transparent),
      'background-image': image ?? _none,
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
        'none' => {'flex-grow': const NumberValue(0), 'flex-shrink': const NumberValue(0), 'flex-basis': _auto},
        'auto' => {'flex-grow': const NumberValue(1), 'flex-shrink': const NumberValue(1), 'flex-basis': _auto},
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
      if (dir == null && const {'row', 'row-reverse', 'column', 'column-reverse'}.contains(k)) {
        dir = Keyword(k);
      } else if (wrap == null && const {'nowrap', 'wrap', 'wrap-reverse'}.contains(k)) {
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
      } else if (style == null && const {'solid', 'double', 'dotted', 'dashed', 'wavy'}.contains(k)) {
        s.next();
        style = Keyword(k);
      } else if (color == null && (color = parseColor(s)) != null) {
        continue;
      } else {
        return null;
      }
    }
    final line = lineTokens.isEmpty ? _none : _textDecorationLine(ValueStream(lineTokens));
    if (line == null) return null;
    return {
      'text-decoration-line': line,
      'text-decoration-color': color ?? const ColorValue(null),
      'text-decoration-style': style ?? const Keyword('solid'),
    };
  },
  'list-style': (s) {
    final v = longhands['list-style-type']!.parse(s);
    return v == null ? null : {'list-style-type': v};
  },
};

final Map<String, List<String>> _shorthandTargets = {
  'margin': [for (final x in _sides) 'margin-$x'],
  'padding': [for (final x in _sides) 'padding-$x'],
  'border-width': [for (final x in _sides) 'border-$x-width'],
  'border-style': [for (final x in _sides) 'border-$x-style'],
  'border-color': [for (final x in _sides) 'border-$x-color'],
  'border': [
    for (final x in _sides) ...['border-$x-width', 'border-$x-style', 'border-$x-color'],
  ],
  for (final x in _sides)
    'border-$x': ['border-$x-width', 'border-$x-style', 'border-$x-color'],
  'border-radius': [for (final c in _corners) 'border-$c-radius'],
  'background': ['background-color', 'background-image'],
  'overflow': ['overflow-x', 'overflow-y'],
  'gap': ['row-gap', 'column-gap'],
  'flex': ['flex-grow', 'flex-shrink', 'flex-basis'],
  'flex-flow': ['flex-direction', 'flex-wrap'],
  'text-decoration': ['text-decoration-line', 'text-decoration-color', 'text-decoration-style'],
  'list-style': ['list-style-type'],
};
