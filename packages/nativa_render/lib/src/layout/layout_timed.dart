import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout_profile.dart';

/// Profile-only proxy that attributes a child's layout to [kind]. Disabled
/// builds still create a proxy, so callers must only use it when
/// [LayoutProfile.enabled] is true.
class LayoutTimed extends SingleChildRenderObjectWidget {
  const LayoutTimed({super.key, required this.kind, super.child});
  final String kind;

  @override
  RenderLayoutTimed createRenderObject(BuildContext context) => RenderLayoutTimed(kind);

  @override
  void updateRenderObject(BuildContext context, RenderLayoutTimed renderObject) {
    renderObject.kind = kind;
  }
}

class RenderLayoutTimed extends RenderProxyBox {
  RenderLayoutTimed(this.kind);
  String kind;

  @override
  void performLayout() {
    LayoutProfile.begin('$kind.layout');
    try {
      final child = this.child;
      if (child == null) {
        size = constraints.smallest;
      } else {
        child.layout(constraints, parentUsesSize: true);
        size = child.size;
      }
    } finally {
      LayoutProfile.end();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    LayoutProfile.begin('$kind.paint');
    try {
      super.paint(context, offset);
    } finally {
      LayoutProfile.end();
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      LayoutProfile.measure('$kind.dry', () => child?.getDryLayout(constraints) ?? constraints.smallest);

  @override
  double computeMinIntrinsicWidth(double height) =>
      LayoutProfile.measure('$kind.intrinsic', () => child?.getMinIntrinsicWidth(height) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      LayoutProfile.measure('$kind.intrinsic', () => child?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) =>
      LayoutProfile.measure('$kind.intrinsic', () => child?.getMinIntrinsicHeight(width) ?? 0);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      LayoutProfile.measure('$kind.intrinsic', () => child?.getMaxIntrinsicHeight(width) ?? 0);
}
