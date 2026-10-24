import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativa_css/nativa_css.dart' hide MediaQuery;

import 'css_item.dart';
import 'layout_profile.dart';

/// The CSS box model inputs for one element, derived from its
/// [ComputedStyle]. Percentages stay unresolved until layout, where
/// [RenderCssBox] resolves them against the containing block reported by its
/// parent.
@immutable
class CssBoxSpec {
  const CssBoxSpec({
    this.width,
    this.height,
    this.minWidth = ResolvedLength.zero,
    this.minHeight = ResolvedLength.zero,
    this.maxWidth,
    this.maxHeight,
    this.padding = const [ResolvedLength.zero, ResolvedLength.zero, ResolvedLength.zero, ResolvedLength.zero],
    this.border = const [0, 0, 0, 0],
    this.borderColors = const [Color(0xff000000), Color(0xff000000), Color(0xff000000), Color(0xff000000)],
    this.borderStyles = const ['solid', 'solid', 'solid', 'solid'],
    this.radii = const [ResolvedLength.zero, ResolvedLength.zero, ResolvedLength.zero, ResolvedLength.zero],
    this.borderBox = false,
    this.clip = false,
    this.background,
    this.backgroundImage,
    this.gradient,
    this.shadows = const [],
    this.outlineWidth = 0,
    this.outlineColor = const Color(0xff000000),
    this.outlineOffset = 0,
  });

  final ResolvedLength? width;
  final ResolvedLength? height;
  final ResolvedLength minWidth;
  final ResolvedLength minHeight;
  final ResolvedLength? maxWidth;
  final ResolvedLength? maxHeight;

  /// top, right, bottom, left.
  final List<ResolvedLength> padding;
  final List<double> border;
  final List<Color> borderColors;

  /// `solid`, `dashed`, `dotted` or `double` per side (top, right, bottom,
  /// left).
  final List<String> borderStyles;

  bool get _customBorder => borderStyles.any((s) => s != 'solid');

  /// top-left, top-right, bottom-right, bottom-left.
  final List<ResolvedLength> radii;
  final bool borderBox;

  /// `overflow` other than `visible`: clip to the padding box.
  final bool clip;
  final Color? background;
  final DecorationImage? backgroundImage;

  /// `background-image: *-gradient()`, painted over [background].
  final GradientValue? gradient;
  final List<BoxShadow> shadows;
  final double outlineWidth;
  final Color outlineColor;
  final double outlineOffset;

  bool get hasDecoration =>
      (background != null && background!.a > 0) ||
      backgroundImage != null ||
      gradient != null ||
      shadows.isNotEmpty ||
      border.any((b) => b > 0);

  @override
  bool operator ==(Object other) =>
      other is CssBoxSpec &&
      other.width == width &&
      other.height == height &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      listEquals(other.padding, padding) &&
      listEquals(other.border, border) &&
      listEquals(other.borderColors, borderColors) &&
      listEquals(other.borderStyles, borderStyles) &&
      listEquals(other.radii, radii) &&
      other.borderBox == borderBox &&
      other.clip == clip &&
      other.background == background &&
      other.backgroundImage == backgroundImage &&
      other.gradient == gradient &&
      listEquals(other.shadows, shadows) &&
      other.outlineWidth == outlineWidth &&
      other.outlineColor == outlineColor &&
      other.outlineOffset == outlineOffset;

  @override
  int get hashCode => Object.hash(width, height, minWidth, minHeight, maxWidth, maxHeight,
      Object.hashAll(padding), Object.hashAll(border), Object.hashAll(borderColors), Object.hashAll(borderStyles),
      Object.hashAll(radii), borderBox, clip, background, backgroundImage, gradient,
      Object.hashAll(shadows), outlineWidth, outlineColor, outlineOffset);
}

/// Converts a CSS gradient to a Flutter [Gradient] for a box of [size],
/// following the CSS gradient line geometry (the line passes through the
/// center and its length makes the corners hit the 0%/100% stops).
Gradient cssGradient(GradientValue g, Size size) {
  final colors = [for (final s in g.stops) Color(s.color.color?.argb ?? 0xff000000)];
  final stops = _stopPositions(g.stops);
  final tile = g.repeating ? TileMode.repeated : TileMode.clamp;
  if (g.kind == 'radial') {
    final shortest = math.min(size.width, size.height);
    final farthest = math.sqrt(size.width * size.width + size.height * size.height) / 2;
    return RadialGradient(
      colors: colors,
      stops: stops,
      radius: shortest <= 0 ? 0.5 : farthest / shortest,
      tileMode: tile,
    );
  }
  if (g.kind == 'conic') {
    return SweepGradient(
      colors: colors,
      stops: stops,
      startAngle: 0,
      endAngle: math.pi * 2,
      transform: const GradientRotation(-math.pi / 2),
      tileMode: tile,
    );
  }
  final a = g.angle * math.pi / 180;
  final dx = math.sin(a), dy = -math.cos(a);
  final w = size.width, h = size.height;
  final half = (w * dx.abs() + h * dy.abs()) / 2;
  Alignment at(double sign) {
    final px = sign * dx * half;
    final py = sign * dy * half;
    return Alignment(w == 0 ? 0 : px / (w / 2), h == 0 ? 0 : py / (h / 2));
  }

  return LinearGradient(begin: at(-1), end: at(1), colors: colors, stops: stops, tileMode: tile);
}

/// Fills implicit stop positions per CSS Images §3.5.3.
List<double> _stopPositions(List<GradientStop> stops) {
  final n = stops.length;
  final out = List<double?>.generate(n, (i) => stops[i].position);
  out[0] ??= 0;
  out[n - 1] ??= 1;
  var maxSoFar = 0.0;
  for (var i = 0; i < n; i++) {
    if (out[i] != null) {
      if (out[i]! < maxSoFar) out[i] = maxSoFar;
      maxSoFar = out[i]!;
    }
  }
  var i = 0;
  while (i < n) {
    if (out[i] != null) {
      i++;
      continue;
    }
    final start = i - 1;
    var end = i;
    while (out[end] == null) {
      end++;
    }
    for (var k = i; k < end; k++) {
      out[k] = out[start]! + (out[end]! - out[start]!) * (k - start) / (end - start);
    }
    i = end;
  }
  return [for (final v in out) v!];
}

/// Sizes, pads, borders, decorates and clips one CSS box.
class CssBox extends SingleChildRenderObjectWidget {
  const CssBox({super.key, required this.spec, super.child});
  final CssBoxSpec spec;

  @override
  RenderCssBox createRenderObject(BuildContext context) =>
      RenderCssBox(spec, ImageConfiguration.empty.copyWith(
        textDirection: Directionality.maybeOf(context),
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context),
      ));

  @override
  void updateRenderObject(BuildContext context, RenderCssBox renderObject) {
    renderObject.spec = spec;
  }
}

class RenderCssBox extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  RenderCssBox(this._spec, this._imageConfiguration);

  CssBoxSpec _spec;
  final ImageConfiguration _imageConfiguration;
  BoxPainter? _painter;
  Decoration? _decoration;
  Size? _decorationSize;
  EdgeInsets _inset = EdgeInsets.zero;

  CssBoxSpec get spec => _spec;
  set spec(CssBoxSpec value) {
    if (value == _spec) return;
    _spec = value;
    _decoration = null;
    _decorationSize = null;
    _painter?.dispose();
    _painter = null;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) child.parentData = BoxParentData();
  }

  @override
  void detach() {
    _painter?.dispose();
    _painter = null;
    super.detach();
  }

  (double?, double?) get _containingBlock {
    final pd = parentData;
    if (pd is CssItemParentData) return (pd.containingWidth, pd.containingHeight);
    return (null, null);
  }

  EdgeInsets _padding(double? cbw) => EdgeInsets.fromLTRB(
        _spec.padding[3].resolve(cbw) ?? 0,
        _spec.padding[0].resolve(cbw) ?? 0,
        _spec.padding[1].resolve(cbw) ?? 0,
        _spec.padding[2].resolve(cbw) ?? 0,
      );

  EdgeInsets get _borderInsets =>
      EdgeInsets.fromLTRB(_spec.border[3], _spec.border[0], _spec.border[1], _spec.border[2]);

  /// The border-box constraints this box wants, intersected with the
  /// incoming [constraints] (which always win).
  BoxConstraints _boxConstraints(BoxConstraints constraints, EdgeInsets inset) {
    final (cbwPd, cbhPd) = _containingBlock;
    final cbw = cbwPd ?? (constraints.hasBoundedWidth ? constraints.maxWidth : null);
    final cbh = cbhPd;
    double? toBorderBox(ResolvedLength? l, double? basis, double extra) {
      final v = l?.resolve(basis);
      if (v == null) return null;
      return _spec.borderBox ? math.max(v, extra) : v + extra;
    }

    final minW = toBorderBox(_spec.minWidth, cbw, inset.horizontal) ?? 0;
    final maxW = toBorderBox(_spec.maxWidth, cbw, inset.horizontal) ?? double.infinity;
    final minH = toBorderBox(_spec.minHeight, cbh, inset.vertical) ?? 0;
    final maxH = toBorderBox(_spec.maxHeight, cbh, inset.vertical) ?? double.infinity;
    final w = toBorderBox(_spec.width, cbw, inset.horizontal);
    final h = toBorderBox(_spec.height, cbh, inset.vertical);
    double clampTo(double v, double lo, double hi) => math.max(lo, math.min(v, hi));
    final wanted = BoxConstraints(
      minWidth: w != null ? clampTo(w, minW, math.max(minW, maxW)) : minW,
      maxWidth: w != null ? clampTo(w, minW, math.max(minW, maxW)) : math.max(minW, maxW),
      minHeight: h != null ? clampTo(h, minH, math.max(minH, maxH)) : minH,
      maxHeight: h != null ? clampTo(h, minH, math.max(minH, maxH)) : math.max(minH, maxH),
    );
    // Minimums from CSS still apply inside loose parent constraints, and the
    // box can never be smaller than its padding and border.
    // When the box has no explicit width but a finite max-width, cap the
    // incoming (possibly tight) constraints to that max-width so max-width
    // is honored instead of being overridden by the parent's tight width.
    BoxConstraints c = constraints;
    if (w == null && maxW.isFinite && constraints.hasBoundedWidth &&
        !constraints.isTight && constraints.maxWidth > maxW) {
      final cap = math.max(minW, maxW);
      c = constraints.copyWith(maxWidth: math.min(constraints.maxWidth, cap));
    }
    return wanted
        .enforce(c)
        .enforce(BoxConstraints(minWidth: math.min(inset.horizontal, constraints.maxWidth),
            minHeight: math.min(inset.vertical, constraints.maxHeight)));
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final (cbwPd, _) = _containingBlock;
    final cbw = cbwPd ?? (constraints.hasBoundedWidth ? constraints.maxWidth : null);
    final inset = _padding(cbw) + _borderInsets;
    final box = _boxConstraints(constraints, inset);
    final inner = box.deflate(inset);
    Size childSize = Size.zero;
    final child = this.child;
    if (child != null) {
      if (dry) {
        childSize = child.getDryLayout(inner);
      } else {
        child.layout(inner, parentUsesSize: true);
        childSize = child.size;
        (child.parentData! as BoxParentData).offset = Offset(inset.left, inset.top);
      }
    }
    if (!dry) _inset = inset;
    return box.constrain(Size(childSize.width + inset.horizontal, childSize.height + inset.vertical));
  }

  @override
  void performLayout() {
    size = LayoutProfile.measure('box.layout', () => _layout(constraints, dry: false));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      LayoutProfile.measure('box.dry', () => _layout(constraints, dry: true));

  double _fixedOr(ResolvedLength? l, double extra, double Function() content) {
    if (l != null && !l.isPercent) return _spec.borderBox ? math.max(l.value, extra) : l.value + extra;
    return content() + extra;
  }

  double _clampW(double v, double extra) {
    final min = _spec.minWidth.isPercent ? 0.0 : (_spec.borderBox ? _spec.minWidth.value : _spec.minWidth.value + extra);
    final maxL = _spec.maxWidth;
    final max = maxL == null || maxL.isPercent ? double.infinity : (_spec.borderBox ? maxL.value : maxL.value + extra);
    return math.max(min, math.min(v, math.max(min, max)));
  }

  EdgeInsets get _intrinsicInset => _padding(null) + _borderInsets;

  @override
  double computeMinIntrinsicWidth(double height) {
    final inset = _intrinsicInset;
    return _clampW(_fixedOr(_spec.width, inset.horizontal, () => child?.getMinIntrinsicWidth(height) ?? 0), inset.horizontal);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final inset = _intrinsicInset;
    return _clampW(_fixedOr(_spec.width, inset.horizontal, () => child?.getMaxIntrinsicWidth(height) ?? 0), inset.horizontal);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final inset = _intrinsicInset;
    return _fixedOr(_spec.height, inset.vertical,
        () => child?.getMinIntrinsicHeight(math.max(0, width - inset.horizontal)) ?? 0);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final inset = _intrinsicInset;
    return _fixedOr(_spec.height, inset.vertical,
        () => child?.getMaxIntrinsicHeight(math.max(0, width - inset.horizontal)) ?? 0);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final child = this.child;
    if (child == null) return null;
    final d = child.getDistanceToActualBaseline(baseline);
    return d == null ? null : d + (child.parentData! as BoxParentData).offset.dy;
  }

  BorderRadius _radius(Size s) {
    Radius r(ResolvedLength l) => l.isPercent
        ? Radius.elliptical(s.width * l.value / 100, s.height * l.value / 100)
        : Radius.circular(l.value);
    return BorderRadius.only(
      topLeft: r(_spec.radii[0]),
      topRight: r(_spec.radii[1]),
      bottomRight: r(_spec.radii[2]),
      bottomLeft: r(_spec.radii[3]),
    );
  }

  bool get _hasRadius => _spec.radii.any((r) => r.value > 0);

  Decoration _decorationFor(Size s) {
    final cached = _decoration;
    if (cached != null && _decorationSize == s) return cached;
    // Percentage border radii depend on the border box size; resize must
    // rebuild the decoration and its painter.
    if (_decorationSize != null && _decorationSize != s) {
      _painter?.dispose();
      _painter = null;
    }
    _decorationSize = s;
    BorderSide side(int i) => _spec.border[i] > 0
        ? BorderSide(width: _spec.border[i], color: _spec.borderColors[i])
        : BorderSide.none;
    var colors = _spec.borderColors;
    // Flutter can only round borders whose visible sides share one color.
    if (_hasRadius) {
      final visible = [for (var i = 0; i < 4; i++) if (_spec.border[i] > 0) colors[i]];
      if (visible.toSet().length > 1) colors = List.filled(4, visible.first);
    }
    BorderSide sideWith(int i) => side(i) == BorderSide.none ? BorderSide.none : side(i).copyWith(color: colors[i]);
    final border = Border(top: sideWith(0), right: sideWith(1), bottom: sideWith(2), left: sideWith(3));
    return _decoration = BoxDecoration(
      color: _spec.background,
      image: _spec.backgroundImage,
      gradient: _spec.gradient == null ? null : cssGradient(_spec.gradient!, s),
      boxShadow: _spec.shadows.isEmpty ? null : _spec.shadows,
      border: _spec.border.every((b) => b == 0) || _spec._customBorder ? null : border,
      borderRadius: _hasRadius ? _radius(s) : null,
    );
  }

  /// Dashed, dotted and double borders (Flutter's [Border] only draws solid
  /// lines). Rounded boxes use the first visible side's width and color.
  void _paintStyledBorder(Canvas canvas, Offset offset) {
    if (!_spec._customBorder || _spec.border.every((b) => b == 0)) return;
    final rect = offset & size;
    Path dashed(Path source, double width, String style) {
      if (style == 'solid' || style == 'double') return source;
      final dash = style == 'dotted' ? width : width * 3;
      final gap = style == 'dotted' ? width : width * 2;
      final out = Path();
      for (final metric in source.computeMetrics()) {
        var d = 0.0;
        while (d < metric.length) {
          out.addPath(metric.extractPath(d, math.min(d + dash, metric.length)), Offset.zero);
          d += dash + gap;
        }
      }
      return out;
    }

    Paint paintFor(int i, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = _spec.borderStyles[i] == 'dotted' ? StrokeCap.round : StrokeCap.butt
      ..color = _spec.borderColors[i];

    if (_hasRadius) {
      final i = [0, 1, 2, 3].firstWhere((k) => _spec.border[k] > 0);
      final w = _spec.border[i];
      final style = _spec.borderStyles[i];
      final r = _radius(size);
      RRect inset(double by) => r.toRRect(rect).deflate(by);
      if (style == 'double') {
        final t = w / 3;
        final p = paintFor(i, t);
        canvas.drawRRect(inset(t / 2), p);
        canvas.drawRRect(inset(w - t / 2), p);
        return;
      }
      final path = Path()..addRRect(inset(w / 2));
      canvas.drawPath(dashed(path, w, style), paintFor(i, style == 'dotted' ? w * 0.9 : w));
      return;
    }
    final t = _spec.border[0], rgt = _spec.border[1], b = _spec.border[2], l = _spec.border[3];
    final sides = [
      (0, Offset(rect.left, rect.top + t / 2), Offset(rect.right, rect.top + t / 2), t),
      (1, Offset(rect.right - rgt / 2, rect.top), Offset(rect.right - rgt / 2, rect.bottom), rgt),
      (2, Offset(rect.right, rect.bottom - b / 2), Offset(rect.left, rect.bottom - b / 2), b),
      (3, Offset(rect.left + l / 2, rect.bottom), Offset(rect.left + l / 2, rect.top), l),
    ];
    for (final (i, a, z, w) in sides) {
      if (w <= 0) continue;
      final style = _spec.borderStyles[i];
      if (style == 'double') {
        final third = w / 3;
        final normal = i == 0 || i == 2 ? const Offset(0, 1) : const Offset(1, 0);
        final sign = i == 0 || i == 3 ? 1.0 : -1.0;
        final shiftOuter = normal * (-(w / 2) + third / 2) * sign;
        final shiftInner = normal * ((w / 2) - third / 2) * sign;
        final p = paintFor(i, third);
        canvas.drawLine(a + shiftOuter, z + shiftOuter, p);
        canvas.drawLine(a + shiftInner, z + shiftInner, p);
        continue;
      }
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(z.dx, z.dy);
      canvas.drawPath(dashed(path, w, style), paintFor(i, w));
    }
  }

  void _paintOutline(Canvas canvas, Offset offset) {
    final w = _spec.outlineWidth;
    if (w <= 0) return;
    final grow = _spec.outlineOffset + w / 2;
    final rect = (offset & size).inflate(grow);
    final paint = Paint()
      ..color = _spec.outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    if (_hasRadius) {
      final r = _radius(size);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect,
            topLeft: r.topLeft + Radius.circular(grow),
            topRight: r.topRight + Radius.circular(grow),
            bottomLeft: r.bottomLeft + Radius.circular(grow),
            bottomRight: r.bottomRight + Radius.circular(grow)),
        paint,
      );
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    LayoutProfile.begin('box.paint');
    try {
    if (_spec.hasDecoration) {
      final decoration = _decorationFor(size);
      _painter ??= decoration.createBoxPainter(markNeedsPaint);
      _painter!.paint(context.canvas, offset, _imageConfiguration.copyWith(size: size));
      _paintStyledBorder(context.canvas, offset);
    }
    final child = this.child;
    if (child == null) {
      _paintOutline(context.canvas, offset);
      return;
    }
    final childOffset = (child.parentData! as BoxParentData).offset;
    if (!_spec.clip) {
      context.paintChild(child, offset + childOffset);
      _paintOutline(context.canvas, offset);
      return;
    }
    final clipRect = Offset(_spec.border[3], _spec.border[0]) &
        Size(size.width - _spec.border[1] - _spec.border[3], size.height - _spec.border[0] - _spec.border[2]);
    if (_hasRadius) {
      _clipLayer.layer = context.pushClipRRect(
        needsCompositing,
        offset,
        clipRect,
        _radius(size).toRRect(clipRect),
        (ctx, o) => ctx.paintChild(child, o + childOffset),
        oldLayer: _clipLayer.layer as ClipRRectLayer?,
      );
    } else {
      _clipLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        clipRect,
        (ctx, o) => ctx.paintChild(child, o + childOffset),
        oldLayer: _clipLayer.layer as ClipRectLayer?,
      );
    }
    _paintOutline(context.canvas, offset);
    } finally {
      LayoutProfile.end();
    }
  }

  final LayerHandle<ContainerLayer> _clipLayer = LayerHandle<ContainerLayer>();

  @override
  void dispose() {
    _clipLayer.layer = null;
    _painter?.dispose();
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => _spec.hasDecoration;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final childOffset = (child.parentData! as BoxParentData).offset;
    return result.addWithPaintOffset(
      offset: childOffset,
      position: position,
      hitTest: (r, p) => child.hitTest(r, position: p),
    );
  }

  /// Insets (padding + border) used in the last layout, for tests.
  EdgeInsets get debugInset => _inset;
}
