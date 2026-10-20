import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:nativax_css/nativax_css.dart';

import 'css_item.dart';

/// Normal flow for block-level children: stacked vertically, auto-width
/// children fill the line, `margin: auto` centers fixed-width children, and
/// adjacent sibling margins collapse (CSS 2.1 §8.3.1, sibling case only).
class CssBlockFlow extends MultiChildRenderObjectWidget {
  const CssBlockFlow({super.key, super.children});

  @override
  RenderCssBlock createRenderObject(BuildContext context) => RenderCssBlock();
}

double collapseMargins(double a, double b) {
  if (a >= 0 && b >= 0) return math.max(a, b);
  if (a < 0 && b < 0) return math.min(a, b);
  return a + b;
}

class RenderCssBlock extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, CssItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, CssItemParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! CssItemParentData) child.parentData = CssItemParentData();
  }

  Size _run(BoxConstraints constraints, {required bool dry}) {
    final w = constraints.hasBoundedWidth ? constraints.maxWidth : null;
    final cbh = constraints.hasTightHeight ? constraints.maxHeight : null;
    var y = 0.0;
    double? pendingMargin; // bottom margin of the previous child
    var maxWidth = 0.0;
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as CssItemParentData;
      pd.containingWidth = w;
      pd.containingHeight = cbh;
      final basis = w ?? 0;
      final mL = pd.resolveMargin(pd.marginLeft, basis);
      final mR = pd.resolveMargin(pd.marginRight, basis);
      final mT = pd.resolveMargin(pd.marginTop, basis);
      final mB = pd.resolveMargin(pd.marginBottom, basis);
      final BoxConstraints cc;
      if (w != null && pd.autoWidth) {
        cc = BoxConstraints.tightFor(width: math.max(0, w - mL - mR));
      } else if (w != null) {
        cc = BoxConstraints(maxWidth: math.max(0, w - mL - mR));
      } else {
        cc = const BoxConstraints();
      }
      final Size s;
      if (dry) {
        s = child.getDryLayout(cc);
      } else {
        child.layout(cc, parentUsesSize: true);
        s = child.size;
      }
      y += pendingMargin == null ? mT : collapseMargins(pendingMargin, mT);
      if (!dry) {
        double x = mL;
        if (w != null && !pd.autoWidth) {
          final free = w - s.width - mL - mR;
          if (pd.marginLeft == null && pd.marginRight == null) {
            x = (w - s.width) / 2;
          } else if (pd.marginLeft == null) {
            x = mL + math.max(0, free);
          }
        }
        pd.offset = Offset(x, y);
      }
      y += s.height;
      pendingMargin = mB;
      maxWidth = math.max(maxWidth, s.width + mL + mR);
      child = pd.nextSibling;
    }
    y += pendingMargin ?? 0;
    return constraints.constrain(Size(w ?? maxWidth, math.max(0, y)));
  }

  @override
  void performLayout() {
    size = _run(constraints, dry: false);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _run(constraints, dry: true);

  double _fixedMargins(CssItemParentData pd, {required bool horizontal}) {
    double px(ResolvedLength? m) => (m != null && !m.isPercent) ? m.value : 0.0;
    return horizontal ? px(pd.marginLeft) + px(pd.marginRight) : px(pd.marginTop) + px(pd.marginBottom);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var result = 0.0;
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final pd = c.parentData! as CssItemParentData;
      result = math.max(result, c.getMinIntrinsicWidth(double.infinity) + _fixedMargins(pd, horizontal: true));
    }
    return result;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var result = 0.0;
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final pd = c.parentData! as CssItemParentData;
      result = math.max(result, c.getMaxIntrinsicWidth(double.infinity) + _fixedMargins(pd, horizontal: true));
    }
    return result;
  }

  double _height(double width, bool min) {
    var result = 0.0;
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final pd = c.parentData! as CssItemParentData;
      final inner = math.max(0.0, width - _fixedMargins(pd, horizontal: true));
      result += (min ? c.getMinIntrinsicHeight(inner) : c.getMaxIntrinsicHeight(inner)) +
          _fixedMargins(pd, horizontal: false);
    }
    return result;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _height(width, true);

  @override
  double computeMaxIntrinsicHeight(double width) => _height(width, false);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
