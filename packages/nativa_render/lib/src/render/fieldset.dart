import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The top band of a `<fieldset>` with a rendered `<legend>`: the legend is
/// shrink-to-fit (it only wraps when it does not fit the fieldset), and the
/// fieldset's top border runs through its vertical centre, interrupted behind
/// the legend's border box, like browsers draw it.
class FieldsetLegendBar extends SingleChildRenderObjectWidget {
  const FieldsetLegendBar({
    super.key,
    required this.inset,
    required this.top,
    required this.left,
    required this.right,
    required this.topLeftRadius,
    required this.topRightRadius,
    required Widget legend,
  }) : super(child: legend);

  /// Distance from the fieldset's outer left edge to the legend.
  final double inset;
  final BorderSide top;
  final BorderSide left;
  final BorderSide right;
  final double topLeftRadius;
  final double topRightRadius;

  @override
  RenderFieldsetLegendBar createRenderObject(BuildContext context) => RenderFieldsetLegendBar(
        inset: inset,
        top: top,
        left: left,
        right: right,
        topLeftRadius: topLeftRadius,
        topRightRadius: topRightRadius,
      );

  @override
  void updateRenderObject(BuildContext context, RenderFieldsetLegendBar renderObject) {
    renderObject
      ..inset = inset
      ..top = top
      ..left = left
      ..right = right
      ..topLeftRadius = topLeftRadius
      ..topRightRadius = topRightRadius;
  }
}

class RenderFieldsetLegendBar extends RenderShiftedBox {
  RenderFieldsetLegendBar({
    required double inset,
    required BorderSide top,
    required BorderSide left,
    required BorderSide right,
    required double topLeftRadius,
    required double topRightRadius,
  })  : _inset = inset,
        _top = top,
        _left = left,
        _right = right,
        _topLeftRadius = topLeftRadius,
        _topRightRadius = topRightRadius,
        super(null);

  double _inset;
  set inset(double v) {
    if (v == _inset) return;
    _inset = v;
    markNeedsLayout();
  }

  BorderSide _top;
  set top(BorderSide v) {
    if (v == _top) return;
    _top = v;
    markNeedsPaint();
  }

  BorderSide _left;
  set left(BorderSide v) {
    if (v == _left) return;
    _left = v;
    markNeedsPaint();
  }

  BorderSide _right;
  set right(BorderSide v) {
    if (v == _right) return;
    _right = v;
    markNeedsPaint();
  }

  double _topLeftRadius;
  set topLeftRadius(double v) {
    if (v == _topLeftRadius) return;
    _topLeftRadius = v;
    markNeedsPaint();
  }

  double _topRightRadius;
  set topRightRadius(double v) {
    if (v == _topRightRadius) return;
    _topRightRadius = v;
    markNeedsPaint();
  }

  double get _reserved => _inset * 2;

  @override
  double computeMinIntrinsicWidth(double height) => _reserved + (child?.getMinIntrinsicWidth(height) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) => _reserved + (child?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(math.max(0, width - _reserved)) ?? _top.width;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(math.max(0, width - _reserved)) ?? _top.width;

  /// Legends are shrink-to-fit: min(max(min-content, available), max-content).
  BoxConstraints _legendConstraints(RenderBox c, double w) {
    final available = math.max(0.0, w - _reserved);
    final preferred = c.getMaxIntrinsicWidth(double.infinity);
    final minimum = c.getMinIntrinsicWidth(double.infinity);
    return BoxConstraints.tightFor(width: math.min(math.max(minimum, available), preferred));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    final w = constraints.hasBoundedWidth ? constraints.maxWidth : computeMaxIntrinsicWidth(double.infinity);
    if (c == null) return constraints.constrain(Size(w, _top.width));
    final s = c.getDryLayout(_legendConstraints(c, w));
    return constraints.constrain(Size(w, s.height));
  }

  @override
  void performLayout() {
    final c = child;
    final w = constraints.hasBoundedWidth ? constraints.maxWidth : computeMaxIntrinsicWidth(double.infinity);
    if (c == null) {
      size = constraints.constrain(Size(w, _top.width));
      return;
    }
    c.layout(_legendConstraints(c, w), parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = Offset(_inset, 0);
    size = constraints.constrain(Size(w, c.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    final legendLeft = _inset;
    final legendRight = _inset + (c?.size.width ?? 0);
    final y = size.height / 2;
    final canvas = context.canvas;
    // Left segment with its corner.
    _corner(canvas, offset, Rect.fromLTRB(0, y, legendLeft, size.height), left: true);
    _corner(canvas, offset, Rect.fromLTRB(legendRight, y, size.width, size.height), left: false);
    super.paint(context, offset);
  }

  void _corner(Canvas canvas, Offset offset, Rect rect, {required bool left}) {
    if (rect.width <= 0 || rect.height < 0) return;
    final r = rect.shift(offset);
    final radius = left ? _topLeftRadius : _topRightRadius;
    final border = Border(
      top: _top,
      left: left ? _left : BorderSide.none,
      right: left ? BorderSide.none : _right,
    );
    // A Border with mixed sides cannot draw a radius, so a rounded corner is
    // painted as a stroked path and only the straight run uses Border.
    if (radius > 0 && _top.width > 0) {
      final side = left ? _left : _right;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _top.width
        ..color = _top.color;
      final half = _top.width / 2;
      final rr = math.min(radius, math.min(r.width, r.height + radius));
      final path = Path();
      if (left) {
        path
          ..moveTo(r.left + side.width / 2, r.bottom)
          ..lineTo(r.left + side.width / 2, r.top + half + rr)
          ..arcToPoint(Offset(r.left + side.width / 2 + rr, r.top + half), radius: Radius.circular(rr))
          ..lineTo(r.right, r.top + half);
      } else {
        path
          ..moveTo(r.left, r.top + half)
          ..lineTo(r.right - side.width / 2 - rr, r.top + half)
          ..arcToPoint(Offset(r.right - side.width / 2, r.top + half + rr), radius: Radius.circular(rr))
          ..lineTo(r.right - side.width / 2, r.bottom);
      }
      canvas.drawPath(path, paint);
      return;
    }
    border.paint(canvas, r);
  }
}
