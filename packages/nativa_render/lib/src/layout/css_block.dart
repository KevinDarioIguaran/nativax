import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:nativa_css/nativa_css.dart';

import 'css_item.dart';

/// Normal flow for block-level children: stacked vertically, auto-width
/// children fill the line, `margin: auto` centers fixed-width children, and
/// vertical margins collapse (CSS 2.1 §8.3.1): between siblings, through
/// empty boxes, and between a parent and its first/last child when the
/// parent has no border or padding on that side and does not establish a
/// block formatting context ([collapseTop]/[collapseBottom]).
class CssBlockFlow extends MultiChildRenderObjectWidget {
  const CssBlockFlow({super.key, this.collapseTop = false, this.collapseBottom = false, super.children});

  /// The first child's top margin escapes to the parent's own margin.
  final bool collapseTop;

  /// The last child's bottom margin escapes to the parent's own margin.
  final bool collapseBottom;

  @override
  RenderCssBlock createRenderObject(BuildContext context) =>
      RenderCssBlock(collapseTop: collapseTop, collapseBottom: collapseBottom);

  @override
  void updateRenderObject(BuildContext context, RenderCssBlock renderObject) {
    renderObject
      ..collapseTop = collapseTop
      ..collapseBottom = collapseBottom;
  }
}

/// The margins that escaped through [box]'s own box from its first and last
/// in-flow children, found through single-child wrappers (box, effects,
/// gestures). Zero when [box] does not draw a collapsing block flow.
(double, double) escapingMarginsOf(RenderBox box) {
  RenderObject? o = box;
  while (o != null) {
    if (o is RenderCssBlock) return (o.escapingTop, o.escapingBottom);
    if (o is RenderObjectWithChildMixin) {
      o = o.child;
      continue;
    }
    break;
  }
  return (0, 0);
}

double collapseMargins(double a, double b) {
  if (a >= 0 && b >= 0) return math.max(a, b);
  if (a < 0 && b < 0) return math.min(a, b);
  return a + b;
}

class RenderCssBlock extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, CssItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, CssItemParentData>,
        CssStackingPaint {
  RenderCssBlock({bool collapseTop = false, bool collapseBottom = false})
      : _collapseTop = collapseTop,
        _collapseBottom = collapseBottom;

  bool _collapseTop;
  set collapseTop(bool v) {
    if (v == _collapseTop) return;
    _collapseTop = v;
    markNeedsLayout();
  }

  bool _collapseBottom;
  set collapseBottom(bool v) {
    if (v == _collapseBottom) return;
    _collapseBottom = v;
    markNeedsLayout();
  }

  /// Margins that collapsed through this flow's top/bottom edge during the
  /// last layout; the parent flow adds them to this box's own margins.
  double escapingTop = 0;
  double escapingBottom = 0;

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
    var placed = false;
    var escTop = 0.0;
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
      // Margins that escaped from the child's own first/last children.
      final (cTop, cBottom) = dry ? (0.0, 0.0) : escapingMarginsOf(child);
      final top = collapseMargins(mT, cTop);
      final bottom = collapseMargins(mB, cBottom);
      if (s.height == 0) {
        // An empty box's top and bottom margins collapse through it and
        // with its neighbors (CSS 2.1 §8.3.1).
        final through = collapseMargins(top, bottom);
        // Its top edge sits where it would with a bottom border: after its
        // own top margin collapsed with the preceding ones.
        final edge = pendingMargin == null ? top : collapseMargins(pendingMargin, top);
        pendingMargin = pendingMargin == null ? through : collapseMargins(pendingMargin, through);
        if (!dry) pd.offset = Offset(mL, (!placed && _collapseTop) ? y : y + edge);
        maxWidth = math.max(maxWidth, s.width + mL + mR);
        child = pd.nextSibling;
        continue;
      }
      final before = pendingMargin == null ? top : collapseMargins(pendingMargin, top);
      if (!placed && _collapseTop) {
        escTop = before;
      } else {
        y += before;
      }
      placed = true;
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
      pendingMargin = bottom;
      maxWidth = math.max(maxWidth, s.width + mL + mR);
      child = pd.nextSibling;
    }
    var escBottom = 0.0;
    if (!placed && _collapseTop && _collapseBottom) {
      // Nothing in flow: every margin collapses through this box.
      escTop = pendingMargin ?? 0;
    } else if (placed && _collapseBottom) {
      escBottom = pendingMargin ?? 0;
    } else {
      y += pendingMargin ?? 0;
    }
    if (!dry) {
      escapingTop = escTop;
      escapingBottom = escBottom;
    }
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
  void paint(PaintingContext context, Offset offset) => paintStacked(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      hitTestStacked(result, position);
}
