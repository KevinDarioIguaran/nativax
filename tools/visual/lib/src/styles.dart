import 'dart:math' as math;

import 'model.dart';

/// Per-property weight for the "design" score. Typography and paint carry
/// more weight than overflow flags because they are visually obvious.
const Map<String, double> _propertyWeights = {
  'font-size': 2,
  'font-weight': 1,
  'font-family': 2,
  'font-style': 1,
  'line-height': 1,
  'letter-spacing': 1,
  'text-align': 1,
  'color': 2,
  'background-color': 2,
  'border-top-width': 0.5,
  'border-right-width': 0.5,
  'border-bottom-width': 0.5,
  'border-left-width': 0.5,
  'border-top-style': 0.5,
  'border-top-color': 1,
  'border-top-left-radius': 0.5,
  'border-top-right-radius': 0.5,
  'border-bottom-left-radius': 0.5,
  'border-bottom-right-radius': 0.5,
  'box-shadow': 1,
  'text-decoration-line': 0.5,
  'display': 1.5,
  'position': 1,
  'visibility': 1,
  'opacity': 0.5,
  'overflow-x': 0.25,
  'overflow-y': 0.25,
};

const Map<String, String> _defaults = {
  'font-weight': '400',
  'font-style': 'normal',
  'line-height': 'normal',
  'letter-spacing': '0px',
  'text-align': 'start',
  'background-color': 'rgba(0, 0, 0, 0)',
  'border-top-width': '0px',
  'border-right-width': '0px',
  'border-bottom-width': '0px',
  'border-left-width': '0px',
  'border-top-style': 'none',
  'border-top-left-radius': '0px',
  'border-top-right-radius': '0px',
  'border-bottom-left-radius': '0px',
  'border-bottom-right-radius': '0px',
  'box-shadow': 'none',
  'text-decoration-line': 'none',
  'position': 'static',
  'visibility': 'visible',
  'opacity': '1',
  'overflow-x': 'visible',
  'overflow-y': 'visible',
};

class StyleMismatch {
  const StyleMismatch(this.property, this.chrome, this.nativa, this.weight);
  final String property;
  final String chrome;
  final String nativa;
  final double weight;

  Map<String, Object> toJson() => {
    'property': property,
    'chrome': chrome,
    'nativa': nativa,
    'weight': weight,
  };
}

class StyleComparison {
  const StyleComparison({
    required this.element,
    required this.score,
    required this.mismatches,
    required this.comparedWeight,
  });

  final ElementSnapshot element;
  final double score;
  final List<StyleMismatch> mismatches;
  final double comparedWeight;
}

/// Normalises a probe style map so equivalent computed values compare equal.
///
/// Chromium and NativaX report some values differently (`bold` vs `700`,
/// `currentcolor` vs the resolved colour, `medium` border widths on
/// `border-style: none`); those are contract-level spellings, not visual
/// differences, so they are canonicalised before scoring.
Map<String, String> normalizeStyles(Map<String, String> raw) {
  final color = (raw['color'] ?? '').trim();
  final topStyle = (raw['border-top-style'] ?? 'none').trim().toLowerCase();
  final out = <String, String>{};

  for (final entry in _propertyWeights.keys) {
    var value = (raw[entry] ?? '').trim();
    if (value.isEmpty) value = _defaults[entry] ?? '';
    value = _normalizeValue(entry, value, color, topStyle);
    if (value.isNotEmpty) out[entry] = value;
  }
  if (color.isNotEmpty) out['color'] = _normalizeColor(color, color);
  return out;
}

String _normalizeValue(
  String property,
  String value,
  String color,
  String topStyle,
) {
  var text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  switch (property) {
    case 'color':
    case 'background-color':
      return _normalizeColor(text, color);
    case 'border-top-color':
      return _normalizeColor(text, color);
    case 'border-top-width':
    case 'border-right-width':
    case 'border-bottom-width':
    case 'border-left-width':
      if (topStyle == 'none' || topStyle == 'hidden') return '0px';
      return _normalizeLength(text);
    case 'border-top-left-radius':
    case 'border-top-right-radius':
    case 'border-bottom-left-radius':
    case 'border-bottom-right-radius':
      if (text.contains('/')) {
        text = text.split('/').first.trim();
      }
      return _normalizeLength(text);
    case 'font-weight':
      final lower = text.toLowerCase();
      if (lower == 'normal') return '400';
      if (lower == 'bold') return '700';
      if (lower == 'bolder') return '700';
      if (lower == 'lighter') return '300';
      return lower;
    case 'font-family':
      return text
          .replaceAll('"', '')
          .replaceAll("'", '')
          .replaceAll(RegExp(r'\s*,\s*'), ', ')
          .toLowerCase();
    case 'letter-spacing':
      if (text == 'normal') return '0px';
      return _normalizeLength(text);
    case 'line-height':
      return _normalizeLength(text);
    case 'box-shadow':
      final lower = text.toLowerCase();
      if (lower == 'none' || lower.isEmpty) return 'none';
      return lower
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAllMapped(
            RegExp(r'(rgba?\([^)]*\))'),
            (m) => _normalizeColor(m.group(1)!, color),
          );
    case 'display':
    case 'position':
    case 'visibility':
    case 'font-style':
    case 'text-align':
    case 'text-decoration-line':
    case 'overflow-x':
    case 'overflow-y':
      return text.toLowerCase();
    case 'opacity':
      final v = double.tryParse(text);
      return v == null ? text : (v * 100).round().toString();
    default:
      return text;
  }
}

String _normalizeColor(String input, String current) {
  final canonical = _canonicalColor(input, current);
  return canonical;
}

String _canonicalColor(String input, String current) {
  final lower = input.trim().toLowerCase();
  if (lower == 'currentcolor' || lower == 'currentcolor;') {
    return _canonicalColor(current, 'rgb(0, 0, 0)');
  }
  final parsed = _parseColor(lower);
  if (parsed == null) return lower;
  if (parsed[3] == 255) return 'rgb(${parsed[0]}, ${parsed[1]}, ${parsed[2]})';
  final alpha = parsed[3] / 255;
  final rounded = alpha == 0 ? '0' : (alpha * 100).round() / 100;
  return 'rgba(${parsed[0]}, ${parsed[1]}, ${parsed[2]}, $rounded)';
}

List<int>? _parseColor(String input) {
  const named = {
    'transparent': [0, 0, 0, 0],
    'black': [0, 0, 0, 255],
    'white': [255, 255, 255, 255],
    'red': [255, 0, 0, 255],
    'green': [0, 128, 0, 255],
    'blue': [0, 0, 255, 255],
    'gray': [128, 128, 128, 255],
    'grey': [128, 128, 128, 255],
  };
  if (named.containsKey(input)) return named[input];
  if (input.startsWith('#')) {
    var hex = input.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    if (hex.length == 6)
      return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff, 255];
    if (hex.length == 8) {
      return [
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];
    }
    return null;
  }
  if (input.startsWith('rgb')) {
    final open = input.indexOf('(');
    final close = input.lastIndexOf(')');
    if (open < 0 || close <= open) return null;
    final parts = input
        .substring(open + 1, close)
        .split(RegExp(r'[,/\s]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    final out = <int>[];
    for (var i = 0; i < 3; i++) {
      final part = parts[i];
      if (part.endsWith('%')) {
        final pct = double.tryParse(part.substring(0, part.length - 1));
        if (pct == null) return null;
        out.add((pct * 255 / 100).round().clamp(0, 255));
      } else {
        final v = double.tryParse(part);
        if (v == null) return null;
        out.add(v.round().clamp(0, 255));
      }
    }
    var alpha = 255;
    if (parts.length >= 4) {
      final raw = parts[3];
      final v = double.tryParse(
        raw.endsWith('%') ? raw.substring(0, raw.length - 1) : raw,
      );
      if (v == null) return null;
      alpha = raw.endsWith('%')
          ? (v * 255 / 100).round().clamp(0, 255)
          : (v * 255).round().clamp(0, 255);
    }
    out.add(alpha);
    return out;
  }
  return null;
}

String _normalizeLength(String input) {
  final text = input.trim().toLowerCase();
  if (text.isEmpty) return text;
  final match = RegExp(
    r'^(-?[0-9.]+)(px|%|em|rem|pt|vh|vw|vmin|vmax)?$',
  ).firstMatch(text);
  if (match == null) return text;
  final number = double.tryParse(match.group(1)!);
  if (number == null) return text;
  final unit = match.group(2) ?? '';
  if (number == 0 && unit != '%') return '0px';
  final rendered = number == number.roundToDouble()
      ? number.toInt().toString()
      : (number * 100).round() / 100;
  return '$rendered$unit';
}

/// Compares the normalized computed styles of two elements.
///
/// `line-height` gets a special case because a unitless line-height and the
/// pixel value Chromium resolves it to are the same visual value.
StyleComparison compareStyles(ElementSnapshot chrome, ElementSnapshot nativa) {
  final a = normalizeStyles(chrome.styles);
  final b = normalizeStyles(nativa.styles);
  final mismatches = <StyleMismatch>[];
  var matched = 0.0;
  var total = 0.0;
  for (final entry in _propertyWeights.entries) {
    final weight = entry.value;
    total += weight;
    final left = a[entry.key];
    final right = b[entry.key];
    if (left == null || right == null) {
      if (left == null && right == null) {
        matched += weight;
      } else {
        mismatches.add(
          StyleMismatch(
            entry.key,
            left ?? '<missing>',
            right ?? '<missing>',
            weight,
          ),
        );
      }
      continue;
    }
    if (_valuesMatch(entry.key, left, right, a, b, chrome, nativa)) {
      matched += weight;
    } else {
      mismatches.add(StyleMismatch(entry.key, left, right, weight));
    }
  }
  mismatches.sort((x, y) => y.weight.compareTo(x.weight));
  return StyleComparison(
    element: chrome,
    score: total == 0 ? 1 : matched / total,
    mismatches: mismatches,
    comparedWeight: total,
  );
}

bool _valuesMatch(
  String property,
  String a,
  String b,
  Map<String, String> sa,
  Map<String, String> sb,
  ElementSnapshot ca,
  ElementSnapshot cb,
) {
  if (a == b) return true;
  if (property == 'line-height') {
    final resolvedA = _resolveLineHeight(a, sa['font-size']);
    final resolvedB = _resolveLineHeight(b, sb['font-size']);
    if (resolvedA != null && resolvedB != null) {
      return (resolvedA - resolvedB).abs() <= 0.5;
    }
  }
  final lengthA = _lengthValue(a);
  final lengthB = _lengthValue(b);
  if (lengthA != null && lengthB != null) {
    return (lengthA - lengthB).abs() <= 0.5;
  }
  return false;
}

double? _resolveLineHeight(String value, String? fontSize) {
  final length = _lengthValue(value);
  if (length != null) return length;
  final multiplier = double.tryParse(value);
  if (multiplier == null) return null;
  final size = fontSize == null ? null : _lengthValue(fontSize);
  if (size == null) return null;
  return multiplier * size;
}

double? _lengthValue(String value) {
  final match = RegExp(r'^(-?[0-9.]+)px$').firstMatch(value);
  return match == null ? null : double.tryParse(match.group(1)!);
}

double elementWeight(BoxRect rect) {
  final area = rect.area;
  return math.sqrt(area <= 1 ? 1 : (area > 3600 ? 3600 : area));
}
