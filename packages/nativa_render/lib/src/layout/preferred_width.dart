import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'dry_baseline.dart';

/// Reports [width] as its intrinsic width and fills at most that width
/// (replaced elements with a natural size).
class PreferredWidth extends SingleChildRenderObjectWidget {
  const PreferredWidth({required this.width, super.child});
  final double width;

  @override
  RenderPreferredWidth createRenderObject(BuildContext context) => RenderPreferredWidth(width);

  @override
  void updateRenderObject(BuildContext context, RenderPreferredWidth renderObject) {
    renderObject.width = width;
  }
}

class RenderPreferredWidth extends RenderProxyBox {
  RenderPreferredWidth(this._width);
  double _width;
  set width(double v) {
    if (v == _width) return;
    _width = v;
    markNeedsLayout();
  }

  BoxConstraints _inner(BoxConstraints c) {
    final w = c.constrainWidth(_width);
    return c.tighten(width: w);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _width;
  @override
  double computeMaxIntrinsicWidth(double height) => _width;
  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width.isFinite ? width.clamp(0, _width) : _width) ?? 0;
  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width.isFinite ? width.clamp(0, _width) : _width) ?? 0;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      child?.getDryLayout(_inner(constraints)) ?? constraints.constrain(Size(_width, 0));

  @override
  double? computeDryBaseline(covariant BoxConstraints constraints, TextBaseline baseline) =>
      cssDryBaseline(child, _inner(constraints), baseline);

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.constrain(Size(_width, 0));
      return;
    }
    c.layout(_inner(constraints), parentUsesSize: true);
    size = c.size;
  }
}

/// Takes at least the incoming minimum height and centres its child
/// vertically in it (button contents).
class CenterVertically extends SingleChildRenderObjectWidget {
  const CenterVertically({super.key, super.child});

  @override
  RenderCenterVertically createRenderObject(BuildContext context) => RenderCenterVertically();
}

class RenderCenterVertically extends RenderShiftedBox {
  RenderCenterVertically() : super(null);

  BoxConstraints _inner(BoxConstraints c) =>
      BoxConstraints(minWidth: c.minWidth, maxWidth: c.maxWidth, maxHeight: c.maxHeight);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final s = child?.getDryLayout(_inner(constraints)) ?? Size.zero;
    return constraints.constrain(s);
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(_inner(constraints), parentUsesSize: true);
    size = constraints.constrain(c.size);
    (c.parentData! as BoxParentData).offset = Offset(0, (size.height - c.size.height) / 2);
  }

  @override
  double? computeDryBaseline(covariant BoxConstraints constraints, TextBaseline baseline) {
    final c = child;
    if (c == null) return null;
    final d = cssDryBaseline(c, _inner(constraints), baseline);
    if (d == null) return null;
    final s = c.getDryLayout(_inner(constraints));
    return d + (constraints.constrain(s).height - s.height) / 2;
  }
}
