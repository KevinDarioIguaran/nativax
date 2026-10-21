import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:nativa_css/nativa_css.dart';

/// Marks the render box that represents one element, so lookups that must
/// stay within the parent element (perspective) know where to stop.
mixin CssElementBoundary on RenderObject {}

/// Establishes `perspective` for the transformed children of an element.
/// Wraps the element's border box; the origin is relative to it.
class CssPerspective extends SingleChildRenderObjectWidget {
  const CssPerspective({super.key, required this.distance, required this.origin, super.child});
  final double distance;
  final (ResolvedLength, ResolvedLength) origin;

  @override
  RenderCssPerspective createRenderObject(BuildContext context) => RenderCssPerspective(distance, origin);

  @override
  void updateRenderObject(BuildContext context, RenderCssPerspective renderObject) {
    renderObject
      ..distance = distance
      ..origin = origin;
  }
}

class RenderCssPerspective extends RenderProxyBox {
  RenderCssPerspective(this._distance, this._origin);

  double _distance;
  set distance(double v) {
    if (v == _distance) return;
    _distance = v;
    markNeedsPaint();
  }

  (ResolvedLength, ResolvedLength) _origin;
  set origin((ResolvedLength, ResolvedLength) v) {
    if (v == _origin) return;
    _origin = v;
    markNeedsPaint();
  }

  /// The projection in this box's coordinates.
  Matrix4 get matrix {
    final ox = _origin.$1.resolve(size.width) ?? size.width / 2;
    final oy = _origin.$2.resolve(size.height) ?? size.height / 2;
    final p = Matrix4.identity()..setEntry(3, 2, -1 / _distance);
    return Matrix4.translationValues(ox, oy, 0)
      ..multiply(p)
      ..multiply(Matrix4.translationValues(-ox, -oy, 0));
  }
}

/// Applies a CSS `transform` around `transform-origin` (default the box
/// centre). Percentages in `translate*()` refer to the box's own size, so the
/// matrix is built at paint time. 3D functions produce a real 4×4 matrix, and
/// the parent's `perspective` (a [CssPerspective] ancestor) projects it.
class CssTransform extends SingleChildRenderObjectWidget {
  const CssTransform({
    super.key,
    required this.transform,
    this.origin = const (ResolvedLength.percent(50), ResolvedLength.percent(50)),
    super.child,
  });
  final TransformValue transform;
  final (ResolvedLength, ResolvedLength) origin;

  @override
  RenderCssTransform createRenderObject(BuildContext context) => RenderCssTransform(transform, origin);

  @override
  void updateRenderObject(BuildContext context, RenderCssTransform renderObject) {
    renderObject
      ..transform = transform
      ..origin = origin;
  }
}

class RenderCssTransform extends RenderProxyBox {
  RenderCssTransform(this._transform, this._origin);

  TransformValue _transform;
  set transform(TransformValue value) {
    if (value == _transform) return;
    _transform = value;
    markNeedsPaint();
  }

  (ResolvedLength, ResolvedLength) _origin;
  set origin((ResolvedLength, ResolvedLength) v) {
    if (v == _origin) return;
    _origin = v;
    markNeedsPaint();
  }

  /// The nearest perspective of the parent element, if any.
  RenderCssPerspective? get _perspective {
    for (var o = parent; o != null; o = o.parent) {
      if (o is RenderCssPerspective) return o;
      if (o is CssElementBoundary) return null;
    }
    return null;
  }

  Matrix4 get _matrix {
    final local = _localMatrix;
    final p = _perspective;
    if (p == null || !p.hasSize || !attached) return local;
    // Express the parent's projection in this box's coordinates.
    final toParent = getTransformTo(p);
    final fromParent = Matrix4.tryInvert(toParent);
    if (fromParent == null) return local;
    return fromParent
      ..multiply(p.matrix)
      ..multiply(toParent)
      ..multiply(local);
  }

  Matrix4 get _localMatrix {
    final w = size.width, h = size.height;
    double len(CssValue v, double basis) {
      if (v is Length) return v.unit == LengthUnit.percent ? basis * v.value / 100 : v.value;
      if (v is NumberValue) return v.value;
      return 0;
    }

    double num(CssValue v) => v is NumberValue ? v.value : 0;
    double rad(CssValue v) => num(v) * math.pi / 180;

    final ox = _origin.$1.resolve(w) ?? w / 2;
    final oy = _origin.$2.resolve(h) ?? h / 2;
    final m = Matrix4.identity()..translateByDouble(ox, oy, 0, 1);
    for (final f in _transform.functions) {
      final a = f.args;
      switch (f.name) {
        case 'translate':
          m.translateByDouble(a.isNotEmpty ? len(a[0], w) : 0, a.length > 1 ? len(a[1], h) : 0, 0, 1);
        case 'translatex':
          if (a.isNotEmpty) m.translateByDouble(len(a[0], w), 0, 0, 1);
        case 'translatey':
          if (a.isNotEmpty) m.translateByDouble(0, len(a[0], h), 0, 1);
        case 'translate3d':
          m.translateByDouble(a.isNotEmpty ? len(a[0], w) : 0, a.length > 1 ? len(a[1], h) : 0,
              a.length > 2 ? len(a[2], 0) : 0, 1);
        case 'translatez':
          if (a.isNotEmpty) m.translateByDouble(0, 0, len(a[0], 0), 1);
        case 'scale':
          final x = a.isNotEmpty ? num(a[0]) : 1.0;
          m.scaleByDouble(x, a.length > 1 ? num(a[1]) : x, 1, 1);
        case 'scalex':
          if (a.isNotEmpty) m.scaleByDouble(num(a[0]), 1, 1, 1);
        case 'scaley':
          if (a.isNotEmpty) m.scaleByDouble(1, num(a[0]), 1, 1);
        case 'scale3d':
          m.scaleByDouble(a.isNotEmpty ? num(a[0]) : 1, a.length > 1 ? num(a[1]) : 1, a.length > 2 ? num(a[2]) : 1, 1);
        case 'scalez':
          if (a.isNotEmpty) m.scaleByDouble(1, 1, num(a[0]), 1);
        case 'rotate' || 'rotatez':
          if (a.isNotEmpty) m.rotateZ(rad(a[0]));
        case 'rotatey':
          // CSS rotations are clockwise looking towards the origin with y
          // pointing down, which matches Matrix4 in Flutter's coordinates.
          if (a.isNotEmpty) m.rotateY(rad(a[0]));
        case 'rotatex':
          if (a.isNotEmpty) m.rotateX(rad(a[0]));
        case 'rotate3d':
          if (a.length == 4) {
            final axis = Vector3(num(a[0]), num(a[1]), num(a[2]));
            if (axis.length > 0) m.rotate(axis.normalized(), rad(a[3]));
          }
        case 'perspective':
          if (a.isNotEmpty) {
            final d = len(a[0], 0);
            if (d > 0) m.multiply(Matrix4.identity()..setEntry(3, 2, -1 / d));
          }
        case 'matrix3d':
          if (a.length == 16) {
            // Column-major, like Matrix4's storage.
            final values = [for (var k = 0; k < 16; k++) k == 12 || k == 13 ? len(a[k], k == 12 ? w : h) : num(a[k])];
            m.multiply(Matrix4.fromList(values));
          }
        case 'skew':
          final sx = a.isNotEmpty ? math.tan(rad(a[0])) : 0.0;
          final sy = a.length > 1 ? math.tan(rad(a[1])) : 0.0;
          m.multiply(Matrix4.identity()
            ..setEntry(0, 1, sx)
            ..setEntry(1, 0, sy));
        case 'skewx':
          if (a.isNotEmpty) m.multiply(Matrix4.identity()..setEntry(0, 1, math.tan(rad(a[0]))));
        case 'skewy':
          if (a.isNotEmpty) m.multiply(Matrix4.identity()..setEntry(1, 0, math.tan(rad(a[0]))));
        case 'matrix':
          if (a.length == 6) {
            m.multiply(Matrix4.identity()
              ..setEntry(0, 0, num(a[0]))
              ..setEntry(1, 0, num(a[1]))
              ..setEntry(0, 1, num(a[2]))
              ..setEntry(1, 1, num(a[3]))
              ..setEntry(0, 3, len(a[4], w))
              ..setEntry(1, 3, len(a[5], h)));
          }
      }
    }
    m.translateByDouble(-ox, -oy, 0, 1);
    return m;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _matrix,
      position: position,
      hitTest: (r, p) => super.hitTestChildren(r, position: p),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _matrix,
      (ctx, o) => ctx.paintChild(child, o),
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_matrix);
  }
}
