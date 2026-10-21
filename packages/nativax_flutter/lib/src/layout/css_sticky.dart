import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// `position: sticky`: the box keeps its place in flow, but while its
/// scroll container scrolls it is shifted to stay [top]/[bottom] px inside
/// the viewport, never leaving its containing block (the parent box).
class CssSticky extends StatefulWidget {
  const CssSticky({super.key, this.top, this.bottom, required this.child});
  final double? top;
  final double? bottom;
  final Widget child;

  @override
  State<CssSticky> createState() => _CssStickyState();
}

class _CssStickyState extends State<CssSticky> {
  ScrollPosition? _position;
  final GlobalKey _key = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (!identical(p, _position)) {
      _position?.removeListener(_onScroll);
      _position = p;
      _position?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final r = _key.currentContext?.findRenderObject();
    if (r is RenderCssSticky && r.attached) r.markNeedsPaint();
  }

  @override
  Widget build(BuildContext context) =>
      _StickyBox(key: _key, top: widget.top, bottom: widget.bottom, child: widget.child);
}

class _StickyBox extends SingleChildRenderObjectWidget {
  const _StickyBox({super.key, this.top, this.bottom, super.child});
  final double? top;
  final double? bottom;

  @override
  RenderCssSticky createRenderObject(BuildContext context) => RenderCssSticky(top, bottom);

  @override
  void updateRenderObject(BuildContext context, RenderCssSticky r) {
    r
      ..top = top
      ..bottom = bottom;
  }
}

class RenderCssSticky extends RenderProxyBox {
  RenderCssSticky(this._top, this._bottom);

  double? _top;
  double? _bottom;
  set top(double? v) {
    if (v == _top) return;
    _top = v;
    markNeedsPaint();
  }

  set bottom(double? v) {
    if (v == _bottom) return;
    _bottom = v;
    markNeedsPaint();
  }

  /// The containing block: the nearest ancestor that lays out CSS children.
  RenderBox? get _container {
    RenderObject? p = parent;
    var depth = 0;
    while (p != null && depth < 12) {
      if (p is RenderBox && p is ContainerRenderObjectMixin) return p;
      p = p.parent;
      depth++;
    }
    return null;
  }

  double _shift() {
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderBox || !hasSize) return 0;
    final vp = viewport as RenderBox;
    if (!vp.hasSize) return 0;
    final double y;
    try {
      y = localToGlobal(Offset.zero, ancestor: vp).dy;
    } catch (_) {
      return 0;
    }
    var shift = 0.0;
    final top = _top, bottom = _bottom;
    if (top != null && y < top) shift = top - y;
    if (bottom != null && y + size.height > vp.size.height - bottom) {
      shift = vp.size.height - bottom - (y + size.height);
    }
    final container = _container;
    if (container != null && container.hasSize) {
      final double cTop;
      try {
        cTop = container.localToGlobal(Offset.zero, ancestor: vp).dy;
      } catch (_) {
        return shift;
      }
      final maxDown = cTop + container.size.height - (y + size.height);
      final maxUp = cTop - y;
      shift = shift.clamp(math.min(0.0, maxUp), math.max(0.0, maxDown));
    }
    return shift;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset + Offset(0, _shift()));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final shift = _shift();
    return result.addWithPaintOffset(
      offset: Offset(0, shift),
      position: position,
      hitTest: (r, p) => super.hitTestChildren(r, position: p),
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final shift = _shift();
    if (position.dx < 0 || position.dx > size.width) return false;
    if (position.dy < shift || position.dy > shift + size.height) return false;
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _shift(), 0, 1);
  }
}
