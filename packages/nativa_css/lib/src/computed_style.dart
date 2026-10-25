import 'properties.dart';
import 'values.dart';

enum Display {
  block,
  inline,
  inlineBlock,
  flex,
  inlineFlex,
  grid,
  inlineGrid,
  none,
  listItem,
  contents,
}

/// A length after computation: absolute px, a percentage to be resolved by
/// layout against the containing block, or `auto` (represented as null by
/// the accessors below).
class ResolvedLength {
  const ResolvedLength.px(this.value) : isPercent = false, calc = null;
  const ResolvedLength.percent(this.value) : isPercent = true, calc = null;

  /// A `calc()`/`min()`/`max()`/`clamp()` expression mixing `%` and px.
  /// It counts as a percentage ([isPercent]) with [value] 0 for callers that
  /// cannot resolve it.
  const ResolvedLength.calc(CalcNode this.calc) : isPercent = true, value = 0;
  static const zero = ResolvedLength.px(0);

  final double value;
  final bool isPercent;
  final CalcNode? calc;

  /// Resolves against [basis] (the containing block's size on the relevant
  /// axis). Percentages against an unknown (null/infinite) basis yield null,
  /// which callers treat as `auto`.
  double? resolve(double? basis) {
    final c = calc;
    if (c != null) {
      final v = c.evaluate(basis);
      if (v != null) return v;
      // Unknown basis: treat percentages as 0 as for intrinsic sizing.
      return c.evaluate(0);
    }
    if (!isPercent) return value;
    if (basis == null || !basis.isFinite) return null;
    return basis * value / 100;
  }

  @override
  bool operator ==(Object o) =>
      o is ResolvedLength &&
      o.value == value &&
      o.isPercent == isPercent &&
      '${o.calc}' == '$calc';
  @override
  int get hashCode => Object.hash(value, isPercent, '$calc');
  @override
  String toString() =>
      calc != null ? 'calc$calc' : (isPercent ? '$value%' : '${value}px');
}

/// The computed values of every supported longhand for one element.
///
/// Values are stored as [CssValue]s after computation: relative lengths
/// (`em`, `rem`, `vw`, `vh`) are converted to px, `currentcolor` is resolved
/// (except where it must stay relative), and only percentages remain
/// relative. Typed accessors serve the renderer.
class ComputedStyle {
  ComputedStyle(this.values, {this.customProperties = const {}});

  final Map<String, CssValue> values;

  /// Cascaded custom properties (`--name`), inherited like normal properties.
  final Map<String, String> customProperties;

  CssValue operator [](String property) =>
      values[property] ?? longhands[property]!.initial;

  String _kw(String p) => (this[p] as Keyword).name;

  double _px(String p) {
    final v = this[p];
    return v is Length && v.unit == LengthUnit.px ? v.value : 0;
  }

  /// null for `auto` / `none` / `normal` / `content`.
  ResolvedLength? _len(String p) {
    final v = this[p];
    if (v is CalcLength) return ResolvedLength.calc(v.node);
    if (v is! Length) return null;
    return v.unit == LengthUnit.percent
        ? ResolvedLength.percent(v.value)
        : ResolvedLength.px(v.value);
  }

  Display get display => switch (_kw('display')) {
    'block' => Display.block,
    'inline-block' => Display.inlineBlock,
    'flex' => Display.flex,
    'inline-flex' => Display.inlineFlex,
    'none' => Display.none,
    'list-item' => Display.listItem,
    'grid' => Display.grid,
    'inline-grid' => Display.inlineGrid,
    'contents' => Display.contents,
    _ => Display.inline,
  };

  bool get isInlineLevel =>
      display == Display.inline ||
      display == Display.inlineBlock ||
      display == Display.inlineFlex ||
      display == Display.inlineGrid;
  bool get isFlexContainer =>
      display == Display.flex || display == Display.inlineFlex;
  bool get isGridContainer =>
      display == Display.grid || display == Display.inlineGrid;

  String get position => _kw('position');
  ResolvedLength? get top => _len('top');
  ResolvedLength? get right => _len('right');
  ResolvedLength? get bottom => _len('bottom');
  ResolvedLength? get left => _len('left');
  int? get zIndex {
    final v = this['z-index'];
    return v is NumberValue ? v.value.toInt() : null;
  }

  bool get borderBox => _kw('box-sizing') == 'border-box';
  ResolvedLength? get width => _len('width');
  ResolvedLength? get height => _len('height');
  ResolvedLength get minWidth => _len('min-width') ?? ResolvedLength.zero;
  ResolvedLength get minHeight => _len('min-height') ?? ResolvedLength.zero;
  ResolvedLength? get maxWidth => _len('max-width');
  ResolvedLength? get maxHeight => _len('max-height');

  /// Margins; null means `auto`.
  ResolvedLength? marginOf(String side) => _len('margin-$side');
  ResolvedLength paddingOf(String side) =>
      _len('padding-$side') ?? ResolvedLength.zero;

  String borderStyleOf(String side) => _kw('border-$side-style');

  /// Used border width: 0 when the style is `none` or `hidden`.
  double borderWidthOf(String side) {
    final style = borderStyleOf(side);
    return style == 'none' || style == 'hidden' ? 0 : _px('border-$side-width');
  }

  CssColor borderColorOf(String side) =>
      (this['border-$side-color'] as ColorValue).color ?? color;

  ResolvedLength radiusOf(String corner) =>
      _len('border-$corner-radius') ?? ResolvedLength.zero;

  CssColor get backgroundColor =>
      (this['background-color'] as ColorValue).color ?? color;
  String? get backgroundImage {
    final v = this['background-image'];
    return v is UrlValue ? v.url : null;
  }

  /// `repeat`, `no-repeat`, `repeat-x` or `repeat-y`.
  String get backgroundRepeat => _kw('background-repeat');

  /// `[x, y]` as px or percentage [Length]s.
  List<Length> get backgroundPosition =>
      (this['background-position'] as ListValue<Length>).items;

  /// `['cover']`, `['contain']` or `[width, height]` with [Length] or
  /// `'auto'` items.
  List<Object> get backgroundSize =>
      (this['background-size'] as ListValue<Object>).items;

  CssColor get color => (this['color'] as ColorValue).color ?? CssColor.black;
  double get opacity => (this['opacity'] as NumberValue).value;
  String get visibility => _kw('visibility');

  List<String> get fontFamily =>
      (this['font-family'] as FontFamilyValue).families;
  double get fontSize => _px('font-size');
  int get fontWeight {
    final v = this['font-weight'];
    if (v is NumberValue) return v.value.round();
    return (v as Keyword).name == 'bold' ? 700 : 400;
  }

  bool get italic => _kw('font-style') != 'normal';
  String get textAlign => _kw('text-align');
  Set<String> get textDecorationLines {
    final k = _kw('text-decoration-line');
    return k == 'none' ? const {} : k.split(' ').toSet();
  }

  CssColor get textDecorationColor =>
      (this['text-decoration-color'] as ColorValue).color ?? color;
  String get textDecorationStyle => _kw('text-decoration-style');
  String get textTransform => _kw('text-transform');
  double? get letterSpacing {
    final v = this['letter-spacing'];
    return v is Length ? v.value : null;
  }

  /// Multiplier of the font size, or null for `normal`.
  double? get lineHeightMultiplier {
    final v = this['line-height'];
    if (v is NumberValue) return v.value;
    if (v is Length && fontSize > 0) return v.value / fontSize;
    return null;
  }

  String get whiteSpace => _kw('white-space');
  String get overflowX => _kw('overflow-x');
  String get overflowY => _kw('overflow-y');

  String get flexDirection => _kw('flex-direction');
  String get flexWrap => _kw('flex-wrap');
  double get flexGrow => (this['flex-grow'] as NumberValue).value;
  double get flexShrink => (this['flex-shrink'] as NumberValue).value;

  /// null for `auto`/`content`.
  ResolvedLength? get flexBasis => _len('flex-basis');
  String get justifyContent => _kw('justify-content');
  String get alignItems => _kw('align-items');
  String get alignSelf => _kw('align-self');
  ResolvedLength get rowGap => _len('row-gap') ?? ResolvedLength.zero;
  ResolvedLength get columnGap => _len('column-gap') ?? ResolvedLength.zero;

  String get listStyleType => _kw('list-style-type');

  /// Generated content for `::before`/`::after`, or null for none/normal.
  ContentValue? get content {
    final v = this['content'];
    return v is ContentValue ? v : null;
  }

  List<CssShadow> get boxShadows {
    final v = this['box-shadow'];
    return v is ShadowValue ? v.shadows : const [];
  }

  GradientValue? get backgroundGradient {
    final v = this['background-image'];
    return v is GradientValue ? v : null;
  }

  List<CssShadow> get textShadows {
    final v = this['text-shadow'];
    return v is ShadowValue ? v.shadows : const [];
  }

  FilterValue? get filter {
    final v = this['filter'];
    return v is FilterValue ? v : null;
  }

  FilterValue? get backdropFilter {
    final v = this['backdrop-filter'];
    if (v is FilterValue) return v;
    final w = this['-webkit-backdrop-filter'];
    return w is FilterValue ? w : null;
  }

  String _raw(String p) {
    final v = this[p];
    return v is RawValue ? v.text.trim().toLowerCase() : '';
  }

  double? _rawLength(String text) {
    final m = RegExp(r'^(-?[\d.]+)(px|em|rem)?$').firstMatch(text);
    if (m == null) return null;
    final n = double.tryParse(m[1]!);
    if (n == null) return null;
    return switch (m[2]) {
      'em' => n * fontSize,
      'rem' => n * 16,
      _ => n,
    };
  }

  /// A `<position>`-like pair (`transform-origin`, `perspective-origin`);
  /// defaults to the centre. Keywords, percentages and px.
  (ResolvedLength, ResolvedLength) _origin(String p) {
    final parts = _raw(
      p,
    ).split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    ResolvedLength? one(String t, {required bool horizontal}) {
      switch (t) {
        case 'left' || 'top':
          return const ResolvedLength.percent(0);
        case 'center':
          return const ResolvedLength.percent(50);
        case 'right' || 'bottom':
          return const ResolvedLength.percent(100);
      }
      if (t.endsWith('%')) {
        final n = double.tryParse(t.substring(0, t.length - 1));
        return n == null ? null : ResolvedLength.percent(n);
      }
      final l = _rawLength(t);
      return l == null ? null : ResolvedLength.px(l);
    }

    var x = const ResolvedLength.percent(50);
    var y = const ResolvedLength.percent(50);
    if (parts.isEmpty) return (x, y);
    // A single vertical keyword names the y axis.
    if (parts.length == 1 && (parts[0] == 'top' || parts[0] == 'bottom')) {
      return (x, one(parts[0], horizontal: false)!);
    }
    if (parts.length >= 2 &&
        (parts[0] == 'top' ||
            parts[0] == 'bottom' ||
            parts[1] == 'left' ||
            parts[1] == 'right')) {
      parts.insert(0, parts.removeAt(1));
    }
    x = one(parts[0], horizontal: true) ?? x;
    if (parts.length > 1) y = one(parts[1], horizontal: false) ?? y;
    return (x, y);
  }

  /// `perspective` distance in px, or null for `none`.
  double? get perspective {
    final t = _raw('perspective');
    if (t.isEmpty || t == 'none') return null;
    final l = _rawLength(t);
    return l == null || l <= 0 ? null : l;
  }

  (ResolvedLength, ResolvedLength) get perspectiveOrigin =>
      _origin('perspective-origin');
  (ResolvedLength, ResolvedLength) get transformOrigin =>
      _origin('transform-origin');

  TransformValue? get transform {
    final v = this['transform'];
    return v is TransformValue ? v : null;
  }

  List<T> _list<T>(String p) {
    final v = this[p];
    return v is ListValue ? v.items.cast<T>() : <T>[];
  }

  /// `animation-*` lists zipped per `animation-name` (other lists repeat).
  List<CssAnimation> get animations {
    final names = _list<String>('animation-name');
    if (names.isEmpty || names.every((n) => n == 'none')) return const [];
    T at<T>(List<T> l, int i, T d) => l.isEmpty ? d : l[i % l.length];
    final durations = _list<double>('animation-duration');
    final delays = _list<double>('animation-delay');
    final counts = _list<double>('animation-iteration-count');
    final easings = _list<CssEasing>('animation-timing-function');
    final dirs = _list<String>('animation-direction');
    final fills = _list<String>('animation-fill-mode');
    final states = _list<String>('animation-play-state');
    return [
      for (var i = 0; i < names.length; i++)
        if (names[i] != 'none')
          CssAnimation(
            name: names[i],
            duration: at(durations, i, 0.0),
            delay: at(delays, i, 0.0),
            iterations: at(counts, i, 1.0),
            easing: at(easings, i, CssEasing.ease),
            direction: at(dirs, i, 'normal'),
            fill: at(fills, i, 'none'),
            paused: at(states, i, 'running') == 'paused',
          ),
    ];
  }

  /// `transition-*` lists zipped per `transition-property`.
  List<CssTransition> get transitions {
    final props = _list<String>('transition-property');
    final durations = _list<double>('transition-duration');
    if (props.isEmpty ||
        props.every((p) => p == 'none') ||
        durations.every((d) => d <= 0))
      return const [];
    T at<T>(List<T> l, int i, T d) => l.isEmpty ? d : l[i % l.length];
    final delays = _list<double>('transition-delay');
    final easings = _list<CssEasing>('transition-timing-function');
    return [
      for (var i = 0; i < props.length; i++)
        if (props[i] != 'none')
          CssTransition(
            props[i],
            at(durations, i, 0.0),
            at(easings, i, CssEasing.ease),
            at(delays, i, 0.0),
          ),
    ];
  }

  /// SVG fill/stroke paint: a color, or null for `none`.
  CssColor? get fillColor {
    final v = this['fill'];
    return v is ColorValue ? (v.color ?? color) : null;
  }

  CssColor? get strokeColor {
    final v = this['stroke'];
    return v is ColorValue ? (v.color ?? color) : null;
  }

  double get strokeWidth {
    final v = this['stroke-width'];
    return v is Length && v.unit == LengthUnit.px ? v.value : 1;
  }

  List<double> get strokeDashArray {
    final v = this['stroke-dasharray'];
    return v is ListValue ? v.items.cast<double>() : const [];
  }

  bool get pointerEventsNone => _kw('pointer-events') == 'none';

  CssColor? get accentColor {
    final v = this['accent-color'];
    return v is ColorValue ? (v.color ?? color) : null;
  }

  String get textOverflow => _kw('text-overflow');
  String get justifyItems => _kw('justify-items');
  String get justifySelf => _kw('justify-self');
  String get alignContent => _kw('align-content');
  int get order => (this['order'] as NumberValue).value.toInt();

  double? get aspectRatio {
    final v = this['aspect-ratio'];
    return v is NumberValue ? v.value : null;
  }

  String get outlineStyle => _kw('outline-style');
  double get outlineWidth {
    final s = outlineStyle;
    return s == 'none' || s == 'hidden' ? 0 : _px('outline-width');
  }

  CssColor get outlineColor =>
      (this['outline-color'] as ColorValue).color ?? color;
  double get outlineOffset => _px('outline-offset');

  GridTracksValue? get gridTemplateColumns {
    final v = this['grid-template-columns'];
    return v is GridTracksValue ? v : null;
  }

  GridTracksValue? get gridTemplateRows {
    final v = this['grid-template-rows'];
    return v is GridTracksValue ? v : null;
  }

  GridTracksValue get gridAutoColumns =>
      this['grid-auto-columns'] as GridTracksValue;
  GridTracksValue get gridAutoRows => this['grid-auto-rows'] as GridTracksValue;

  GridAreasValue? get gridTemplateAreas {
    final v = this['grid-template-areas'];
    return v is GridAreasValue ? v : null;
  }

  String get gridAutoFlow => _kw('grid-auto-flow');

  /// Author `content-visibility` value (`visible`, `auto`, `hidden`), or an
  /// empty string when the declaration is absent.
  String get contentVisibility =>
      this['content-visibility'].toString().trim().toLowerCase();
  GridLineValue get gridRowStart => this['grid-row-start'] as GridLineValue;
  GridLineValue get gridRowEnd => this['grid-row-end'] as GridLineValue;
  GridLineValue get gridColumnStart =>
      this['grid-column-start'] as GridLineValue;
  GridLineValue get gridColumnEnd => this['grid-column-end'] as GridLineValue;
  String get objectFit => _kw('object-fit');
  String get cursor => _kw('cursor');

  @override
  bool operator ==(Object other) {
    if (other is! ComputedStyle) return false;
    if (other.values.length != values.length) return false;
    for (final e in values.entries) {
      if (other.values[e.key] != e.value) return false;
    }
    if (other.customProperties.length != customProperties.length) return false;
    for (final e in customProperties.entries) {
      if (other.customProperties[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      values.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      customProperties.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
