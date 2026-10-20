import 'package:flutter/painting.dart';
import 'package:nativax_css/nativax_css.dart';

import 'layout/css_box.dart';

Color toColor(CssColor c) => Color(c.argb);

const _serifFallback = ['Noto Serif', 'Times New Roman', 'Georgia', 'DejaVu Serif', 'Liberation Serif'];
const _monoFallback = [
  'Roboto Mono', 'Noto Sans Mono', 'Menlo', 'Consolas', 'Courier New', 'DejaVu Sans Mono', 'Liberation Mono', //
];

/// Maps a CSS font-family list to Flutter's family + fallback. Generic
/// `sans-serif`/`system-ui` use the platform default font. Custom families
/// must be bundled by the app (pubspec `fonts:`).
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
  return (primary, fallback.isEmpty ? null : fallback);
}

FontWeight mapFontWeight(int w) {
  final index = ((w / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[index];
}

TextStyle textStyleFor(ComputedStyle s, {bool inlineBackground = false}) {
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
    letterSpacing: s.letterSpacing,
    height: s.lineHeightMultiplier,
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
  );
}

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
  for (final side in sides) {
    final style = s.borderStyleOf(side);
    if (s.borderWidthOf(side) > 0 && style != 'solid') {
      report?.call('border-style: $style is drawn as solid');
    }
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
    radii: [for (final c in corners) s.radiusOf(c)],
    borderBox: s.borderBox,
    clip: s.overflowX != 'visible' || s.overflowY != 'visible',
    background: s.backgroundColor.alpha > 0 ? toColor(s.backgroundColor) : null,
    backgroundImage: backgroundImage,
  );
}

/// Collapses white space per the `white-space` property. Returns the text
/// and whether it ends with a collapsible space (so the next run can drop a
/// leading space).
(String, bool) processWhiteSpace(String text, String mode, {required bool afterSpace}) {
  switch (mode) {
    case 'pre':
    case 'pre-wrap':
      return (text, false);
    case 'pre-line':
      final t = text.replaceAll(RegExp(r'[ \t\r\f]+'), ' ').replaceAll(RegExp(r' ?\n ?'), '\n');
      return (t, t.endsWith(' '));
    default:
      var t = text.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
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
