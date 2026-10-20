import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativax_css/nativax_css.dart';

import 'css_item.dart';

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
    this.radii = const [ResolvedLength.zero, ResolvedLength.zero, ResolvedLength.zero, ResolvedLength.zero],
    this.borderBox = false,
    this.clip = false,
    this.background,
    this.backgroundImage,
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

  /// top-left, top-right, bottom-right, bottom-left.
  final List<ResolvedLength> radii;
  final bool borderBox;

  /// `overflow` other than `visible`: clip to the padding box.
  final bool clip;
  final Color? background;
  final DecorationImage? backgroundImage;

  bool get hasDecoration =>
      (background != null && background!.a > 0) ||
      backgroundImage != null ||
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
      listEquals(other.radii, radii) &&
      other.borderBox == borderBox &&
      other.clip == clip &&
      other.background == background &&
      other.backgroundImage == backgroundImage;

  @override
  int get hashCode => Object.hash(width, height, minWidth, minHeight, maxWidth, maxHeight,
      Object.hashAll(padding), Object.hashAll(border), Object.hashAll(borderColors),
      Object.hashAll(radii), borderBox, clip, background, backgroundImage);
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
  EdgeInsets _inset = EdgeInsets.zero;

  CssBoxSpec get spec => _spec;
  set spec(CssBoxSpec value) {
    if (value == _spec) return;
    _spec = value;
    _decoration = null;
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
    return constraints
        .enforce(wanted)
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
    size = _layout(constraints, dry: false);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _layout(constraints, dry: true);

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
    if (cached != null) return cached;
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
      border: _spec.border.every((b) => b == 0) ? null : border,
      borderRadius: _hasRadius ? _radius(s) : null,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_spec.hasDecoration) {
      final decoration = _decorationFor(size);
      _painter ??= decoration.createBoxPainter(markNeedsPaint);
      _painter!.paint(context.canvas, offset, _imageConfiguration.copyWith(size: size));
    }
    final child = this.child;
    if (child == null) return;
    final childOffset = (child.parentData! as BoxParentData).offset;
    if (!_spec.clip) {
      context.paintChild(child, offset + childOffset);
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
