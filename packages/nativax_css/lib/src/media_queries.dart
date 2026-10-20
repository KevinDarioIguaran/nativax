import 'tokenizer.dart';
import 'values.dart';

/// The environment media queries are evaluated against. In Flutter this
/// comes from the NativaX view's constraints and `MediaQuery`.
class MediaContext {
  const MediaContext({
    required this.width,
    required this.height,
    this.prefersDark = false,
    this.devicePixelRatio = 1,
    this.prefersReducedMotion = false,
    this.rootFontSize = 16,
  });

  /// Viewport size in logical pixels (CSS px).
  final double width;
  final double height;
  final bool prefersDark;
  final double devicePixelRatio;
  final bool prefersReducedMotion;

  /// Used to resolve `em`/`rem` inside media features (16px, as browsers).
  final double rootFontSize;

  bool get portrait => height >= width;

  @override
  bool operator ==(Object o) =>
      o is MediaContext &&
      o.width == width &&
      o.height == height &&
      o.prefersDark == prefersDark &&
      o.devicePixelRatio == devicePixelRatio &&
      o.prefersReducedMotion == prefersReducedMotion &&
      o.rootFontSize == rootFontSize;

  @override
  int get hashCode => Object.hash(
      width, height, prefersDark, devicePixelRatio, prefersReducedMotion, rootFontSize);
}

class MediaFeature {
  const MediaFeature(this.name, this.value);

  /// Lower-cased, e.g. `min-width`.
  final String name;

  /// null for boolean form `(color)`.
  final CssToken? value;

  bool evaluate(MediaContext c) {
    double? px(CssToken? t) {
      if (t == null) return null;
      final l = lengthFromToken(t, allowPercent: false);
      if (l == null) return null;
      return switch (l.unit) {
        LengthUnit.px => l.value,
        LengthUnit.em || LengthUnit.rem => l.value * c.rootFontSize,
        _ => null,
      };
    }

    String? ident() => value?.type == CssTokenType.ident ? value!.value.toLowerCase() : null;

    switch (name) {
      case 'width':
        return value == null ? c.width > 0 : px(value) == c.width;
      case 'min-width':
        final v = px(value);
        return v != null && c.width >= v;
      case 'max-width':
        final v = px(value);
        return v != null && c.width <= v;
      case 'height':
        return value == null ? c.height > 0 : px(value) == c.height;
      case 'min-height':
        final v = px(value);
        return v != null && c.height >= v;
      case 'max-height':
        final v = px(value);
        return v != null && c.height <= v;
      case 'orientation':
        final o = ident();
        return o == 'portrait' ? c.portrait : o == 'landscape' && !c.portrait;
      case 'prefers-color-scheme':
        final s = ident();
        return s == 'dark' ? c.prefersDark : s == 'light' && !c.prefersDark;
      case 'prefers-reduced-motion':
        final s = ident();
        if (value == null) return c.prefersReducedMotion;
        return s == 'reduce' ? c.prefersReducedMotion : s == 'no-preference' && !c.prefersReducedMotion;
      case 'min-resolution':
      case 'max-resolution':
        final t = value;
        if (t == null || t.type != CssTokenType.dimension) return false;
        final dppx = switch (t.unit) {
          'dppx' || 'x' => t.number,
          'dpi' => t.number / 96,
          _ => null,
        };
        if (dppx == null) return false;
        return name == 'min-resolution' ? c.devicePixelRatio >= dppx : c.devicePixelRatio <= dppx;
    }
    // Unknown features make the query false, as in CSS.
    return false;
  }

  @override
  String toString() => value == null ? '($name)' : '($name: $value)';
}

class MediaQuery {
  const MediaQuery({this.negated = false, this.type = 'all', this.features = const []});
  final bool negated;
  final String type;
  final List<MediaFeature> features;

  bool evaluate(MediaContext c) {
    final typeMatches = type == 'all' || type == 'screen';
    final result = typeMatches && features.every((f) => f.evaluate(c));
    return negated ? !result : result;
  }
}

/// A comma-separated media query list; true when any query matches. An
/// invalid query evaluates to false without invalidating the others.
class MediaQueryList {
  const MediaQueryList(this.queries);
  final List<MediaQuery?> queries;

  bool evaluate(MediaContext c) =>
      queries.isEmpty || queries.any((q) => q != null && q.evaluate(c));

  static MediaQueryList parse(List<CssToken> tokens) {
    final queries = <MediaQuery?>[];
    var current = <CssToken>[];
    var depth = 0;
    for (final t in tokens) {
      if (t.type == CssTokenType.leftParen || t.type == CssTokenType.function) depth++;
      if (t.type == CssTokenType.rightParen) depth--;
      if (t.type == CssTokenType.comma && depth == 0) {
        queries.add(_parseOne(current));
        current = [];
      } else {
        current.add(t);
      }
    }
    if (current.any((t) => t.type != CssTokenType.whitespace) || queries.isNotEmpty) {
      queries.add(_parseOne(current));
    }
    return MediaQueryList(queries);
  }

  static MediaQuery? _parseOne(List<CssToken> raw) {
    final ts = raw.where((t) => t.type != CssTokenType.whitespace).toList();
    var i = 0;
    var negated = false;
    var type = 'all';
    if (i < ts.length && ts[i].type == CssTokenType.ident) {
      final k = ts[i].value.toLowerCase();
      if (k == 'not' || k == 'only') {
        negated = k == 'not';
        i++;
      }
      if (i < ts.length && ts[i].type == CssTokenType.ident) {
        type = ts[i].value.toLowerCase();
        if (!const {'all', 'screen', 'print'}.contains(type)) return null;
        i++;
        if (i < ts.length) {
          if (!ts[i].isIdent('and')) return null;
          i++;
        }
      }
    }
    final features = <MediaFeature>[];
    while (i < ts.length) {
      if (ts[i].type != CssTokenType.leftParen) return null;
      i++;
      if (i >= ts.length || ts[i].type != CssTokenType.ident) return null;
      final name = ts[i].value.toLowerCase();
      i++;
      CssToken? value;
      if (i < ts.length && ts[i].type == CssTokenType.colon) {
        i++;
        if (i >= ts.length) return null;
        value = ts[i];
        i++;
      }
      if (i >= ts.length || ts[i].type != CssTokenType.rightParen) return null;
      i++;
      features.add(MediaFeature(name, value));
      if (i < ts.length) {
        if (!ts[i].isIdent('and')) return null;
        i++;
        if (i >= ts.length) return null;
      }
    }
    return MediaQuery(negated: negated, type: type, features: features);
  }
}
