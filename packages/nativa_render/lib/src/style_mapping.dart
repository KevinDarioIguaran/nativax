import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:nativa_css/nativa_css.dart';

import 'layout/css_box.dart';

Color toColor(CssColor c) => Color(c.argb);

const _serifFallback = ['Noto Serif', 'Times New Roman', 'Georgia', 'DejaVu Serif', 'Liberation Serif'];
const _monoFallback = [
  'Roboto Mono', 'Noto Sans Mono', 'Menlo', 'Consolas', 'Courier New', 'DejaVu Sans Mono', 'Liberation Mono', //
];

/// Maps a CSS font-family list to Flutter's family + fallback. Generic
/// `sans-serif`/`system-ui` use the platform default font. Custom families
/// must be bundled by the app (pubspec `fonts:`).
/// Families appended to every text style's fallback list, after the page's
/// own families. Hosts set it when they bundle fonts (for example an emoji
/// font) that the platform's default fallback does not provide.
List<String> nativaxFontFallback = const [];

/// Family used where the page asks for the platform default (`sans-serif`,
/// `system-ui`). null keeps the platform's own default font.
String? nativaxDefaultFontFamily;

(String?, List<String>?) mapFontFamily(List<String> families) {
  String? primary;
  final fallback = <String>[];
  for (final f in families) {
    final lower = f.toLowerCase();
    final List<String> expanded = switch (lower) {
      'sans-serif' || 'system-ui' || '-apple-system' || 'ui-sans-serif' => const [],
      'serif' || 'ui-serif' => _serifFallback,
      'monospace' || 'ui-monospace' => ['monospace', ..._monoFallback],
      _ => [f],
    };
    if (expanded.isEmpty) {
      // Platform default: stop here so later families don't override it.
      if (primary == null) {
        primary = nativaxDefaultFontFamily;
      } else if (nativaxDefaultFontFamily != null) {
        fallback.add(nativaxDefaultFontFamily!);
      }
      break;
    }
    for (final e in expanded) {
      if (primary == null) {
        primary = e;
      } else {
        fallback.add(e);
      }
    }
  }
  fallback.addAll(nativaxFontFallback);
  return (primary, fallback.isEmpty ? null : fallback);
}

FontWeight mapFontWeight(int w) {
  final index = ((w / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[index];
}

TextStyle textStyleFor(ComputedStyle s, {bool inlineBackground = false, bool normalLineHeight = false}) {
  final (family, fallback) = mapFontFamily(s.fontFamily);
  final lines = s.textDecorationLines;
  final decorations = [
    if (lines.contains('underline')) TextDecoration.underline,
    if (lines.contains('overline')) TextDecoration.overline,
    if (lines.contains('line-through')) TextDecoration.lineThrough,
  ];
  final bg = s.backgroundColor;
  return TextStyle(
    color: toColor(s.color),
    fontSize: s.fontSize,
    fontWeight: mapFontWeight(s.fontWeight),
    fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
    fontFamily: family,
    fontFamilyFallback: fallback,
    // Explicit zeros: Material's DefaultTextStyle would otherwise add its
    // own tracking (0.25–0.5px) to every run.
    letterSpacing: s.letterSpacing ?? 0,
    wordSpacing: 0,
    height: normalLineHeight ? null : s.lineHeightMultiplier,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: decorations.isEmpty ? null : TextDecoration.combine(decorations),
    decorationColor: decorations.isEmpty ? null : toColor(s.textDecorationColor),
    decorationStyle: switch (s.textDecorationStyle) {
      'double' => TextDecorationStyle.double,
      'dotted' => TextDecorationStyle.dotted,
      'dashed' => TextDecorationStyle.dashed,
      'wavy' => TextDecorationStyle.wavy,
      _ => TextDecorationStyle.solid,
    },
    backgroundColor: inlineBackground && bg.alpha > 0 ? toColor(bg) : null,
    shadows: s.textShadows.isEmpty
        ? null
        : [
            for (final sh in s.textShadows)
              Shadow(
                color: toColor(sh.color.color ?? s.color),
                offset: Offset(sh.x.value, sh.y.value),
                blurRadius: sh.blur.value,
              ),
          ],
  );
}

/// The 4×5 color matrix for the color-changing CSS filter functions
/// (Filter Effects §13), composed in order. Returns null when [f] only has
/// blur/drop-shadow.
List<double>? filterColorMatrix(FilterValue f) {
  List<double>? acc;
  List<double> mul(List<double> a, List<double> b) {
    // Treat both as 5×5 with an implicit [0 0 0 0 1] last row: result = a·b.
    double at(List<double> m, int r, int c) => r == 4 ? (c == 4 ? 1 : 0) : m[r * 5 + c];
    return [
      for (var r = 0; r < 4; r++)
        for (var c = 0; c < 5; c++)
          at(a, r, 0) * at(b, 0, c) + at(a, r, 1) * at(b, 1, c) + at(a, r, 2) * at(b, 2, c) +
              at(a, r, 3) * at(b, 3, c) + at(a, r, 4) * at(b, 4, c),
    ];
  }

  for (final fn in f.functions) {
    final a = fn.amount;
    List<double>? m;
    switch (fn.name) {
      case 'brightness':
        m = [a, 0, 0, 0, 0, 0, a, 0, 0, 0, 0, 0, a, 0, 0, 0, 0, 0, 1, 0];
      case 'contrast':
        final i = (1 - a) * 0.5 * 255;
        m = [a, 0, 0, 0, i, 0, a, 0, 0, i, 0, 0, a, 0, i, 0, 0, 0, 1, 0];
      case 'opacity':
        m = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, a.clamp(0, 1).toDouble(), 0];
      case 'invert':
        final v = a.clamp(0, 1).toDouble();
        m = [1 - 2 * v, 0, 0, 0, 255 * v, 0, 1 - 2 * v, 0, 0, 255 * v, 0, 0, 1 - 2 * v, 0, 255 * v, 0, 0, 0, 1, 0];
      case 'grayscale':
        final g = 1 - a.clamp(0, 1).toDouble();
        m = [
          0.2126 + 0.7874 * g, 0.7152 - 0.7152 * g, 0.0722 - 0.0722 * g, 0, 0,
          0.2126 - 0.2126 * g, 0.7152 + 0.2848 * g, 0.0722 - 0.0722 * g, 0, 0,
          0.2126 - 0.2126 * g, 0.7152 - 0.7152 * g, 0.0722 + 0.9278 * g, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case 'sepia':
        final g = 1 - a.clamp(0, 1).toDouble();
        m = [
          0.393 + 0.607 * g, 0.769 - 0.769 * g, 0.189 - 0.189 * g, 0, 0,
          0.349 - 0.349 * g, 0.686 + 0.314 * g, 0.168 - 0.168 * g, 0, 0,
          0.272 - 0.272 * g, 0.534 - 0.534 * g, 0.131 + 0.869 * g, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case 'saturate':
        m = [
          0.213 + 0.787 * a, 0.715 - 0.715 * a, 0.072 - 0.072 * a, 0, 0,
          0.213 - 0.213 * a, 0.715 + 0.285 * a, 0.072 - 0.072 * a, 0, 0,
          0.213 - 0.213 * a, 0.715 - 0.715 * a, 0.072 + 0.928 * a, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case 'hue-rotate':
        final r = a * math.pi / 180;
        final c = math.cos(r), sn = math.sin(r);
        m = [
          0.213 + c * 0.787 - sn * 0.213, 0.715 - c * 0.715 - sn * 0.715, 0.072 - c * 0.072 + sn * 0.928, 0, 0,
          0.213 - c * 0.213 + sn * 0.143, 0.715 + c * 0.285 + sn * 0.140, 0.072 - c * 0.072 - sn * 0.283, 0, 0,
          0.213 - c * 0.213 - sn * 0.787, 0.715 - c * 0.715 + sn * 0.715, 0.072 + c * 0.928 + sn * 0.072, 0, 0,
          0, 0, 0, 1, 0,
        ];
    }
    if (m != null) acc = acc == null ? m : mul(m, acc);
  }
  return acc;
}

double filterBlur(FilterValue f) =>
    f.functions.where((x) => x.name == 'blur').fold(0.0, (a, x) => a + x.amount);

TextAlign textAlignFor(ComputedStyle s) => switch (s.textAlign) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      'end' => TextAlign.end,
      _ => TextAlign.start,
    };

const sides = ['top', 'right', 'bottom', 'left'];
const corners = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];

/// Builds the box spec. [report] receives approximations worth surfacing
/// (for example dashed borders drawn solid).
CssBoxSpec boxSpecFor(
  ComputedStyle s, {
  DecorationImage? backgroundImage,
  ResolvedLength? widthHint,
  ResolvedLength? heightHint,
  void Function(String message)? report,
}) {
  String borderStyle(String side) {
    final style = s.borderStyleOf(side);
    return switch (style) {
      'dashed' || 'dotted' || 'double' => style,
      _ => 'solid', // groove/ridge/inset/outset are approximated as solid
    };
  }

  return CssBoxSpec(
    width: s.width ?? widthHint,
    height: s.height ?? heightHint,
    minWidth: s.minWidth,
    minHeight: s.minHeight,
    maxWidth: s.maxWidth,
    maxHeight: s.maxHeight,
    padding: [for (final x in sides) s.paddingOf(x)],
    border: [for (final x in sides) s.borderWidthOf(x)],
    borderColors: [for (final x in sides) toColor(s.borderColorOf(x))],
    borderStyles: [for (final x in sides) borderStyle(x)],
    radii: [for (final c in corners) s.radiusOf(c)],
    borderBox: s.borderBox,
    clip: s.overflowX != 'visible' || s.overflowY != 'visible',
    background: s.backgroundColor.alpha > 0 ? toColor(s.backgroundColor) : null,
    backgroundImage: backgroundImage,
    gradient: s.backgroundGradient,
    shadows: [
      for (final sh in s.boxShadows)
        if (!sh.inset)
          BoxShadow(
            color: toColor(sh.color.color ?? s.color),
            offset: Offset(sh.x.value, sh.y.value),
            // CSS blur radius = 2 × Gaussian sigma; Flutter's blurRadius
            // already follows that convention.
            blurRadius: sh.blur.value,
            spreadRadius: sh.spread.value,
          ),
    ],
    outlineWidth: s.outlineWidth,
    outlineColor: toColor(s.outlineColor),
    outlineOffset: s.outlineOffset,
  );
}

/// Collapses white space per the `white-space` property. Returns the text
/// and whether it ends with a collapsible space (so the next run can drop a
/// leading space).
final RegExp _collapsibleSpace = RegExp(r'[ \t\n\r\f]+');
final RegExp _preLineSpace = RegExp(r'[ \t\r\f]+');
final RegExp _preLineNewline = RegExp(r' ?\n ?');

bool _hasCollapsibleRun(String text, {required bool newlines}) {
  var previousSpace = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    final space = c == 0x20 || c == 0x09 || c == 0x0c || c == 0x0d || (newlines && c == 0x0a);
    if (space && previousSpace) return true;
    previousSpace = space;
  }
  return false;
}

(String, bool) processWhiteSpace(String text, String mode, {required bool afterSpace}) {
  switch (mode) {
    case 'pre':
    case 'pre-wrap':
      return (text, false);
    case 'pre-line':
      if (!text.contains('\n') && !_hasCollapsibleRun(text, newlines: false)) {
        return (text, text.endsWith(' '));
      }
      final t = text.replaceAll(_preLineSpace, ' ').replaceAll(_preLineNewline, '\n');
      return (t, t.endsWith(' '));
    default:
      if (!_hasCollapsibleRun(text, newlines: true) &&
          !text.contains('\t') &&
          !text.contains('\f') &&
          !text.contains('\r')) {
        var t = text;
        if (afterSpace && t.startsWith(' ')) t = t.substring(1);
        return (t, t.isEmpty ? afterSpace : t.endsWith(' '));
      }
      var t = text.replaceAll(_collapsibleSpace, ' ');
      if (afterSpace && t.startsWith(' ')) t = t.substring(1);
      return (t, t.isEmpty ? afterSpace : t.endsWith(' '));
  }
}

String applyTextTransform(String text, String transform) => switch (transform) {
      'uppercase' => text.toUpperCase(),
      'lowercase' => text.toLowerCase(),
      'capitalize' => text.replaceAllMapped(
          RegExp(r'(^|[\s\-])(\p{L})', unicode: true), (m) => '${m[1]}${m[2]!.toUpperCase()}'),
      _ => text,
    };
