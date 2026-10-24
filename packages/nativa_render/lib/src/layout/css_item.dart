import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativa_css/nativa_css.dart';

/// Per-child layout inputs for [RenderCssBlock] and [RenderCssFlex], plus the
/// containing block size those parents report back to [RenderCssBox] so it
/// can resolve percentages against the right basis.
class CssItemParentData extends ContainerBoxParentData<RenderBox> {
  /// Margins; null means `auto`.
  ResolvedLength? marginTop = ResolvedLength.zero;
  ResolvedLength? marginRight = ResolvedLength.zero;
  ResolvedLength? marginBottom = ResolvedLength.zero;
  ResolvedLength? marginLeft = ResolvedLength.zero;

  /// `width: auto` — block parents stretch such children to fill the line.
  bool autoWidth = true;

  /// Resolved `max-width` of the item (border-box basis applied later by the
  /// parent). Used to cap the stretched width of auto-width children.
  ResolvedLength? maxWidth;

  /// `height: auto` — flex parents may stretch such children on the cross
  /// axis.
  bool autoHeight = true;

  double flexGrow = 0;
  double flexShrink = 1;

  /// null = `auto` (use the item's size property or content size).
  ResolvedLength? flexBasis;

  /// `auto` or an align-items keyword.
  String alignSelf = 'auto';

  /// `auto` or a justify-items keyword (grid items).
  String justifySelf = 'auto';

  /// Grid placement.
  GridLineValue gridRowStart = GridLineValue.auto;
  GridLineValue gridRowEnd = GridLineValue.auto;
  GridLineValue gridColumnStart = GridLineValue.auto;
  GridLineValue gridColumnEnd = GridLineValue.auto;

  /// `order` (flex and grid items).
  int order = 0;

  /// Replaced element (img, svg, video, canvas…): in grid, `normal`
  /// alignment means `start` instead of `stretch` for these.
  bool replaced = false;

  /// `z-index` of positioned (relative/sticky) items; null paints in tree
  /// order with the rest of the flow.
  int? zIndex;

  /// Width/height of the containing block, set by the parent before laying
  /// the child out. null when unknown (indefinite).
  double? containingWidth;
  double? containingHeight;

  double resolveMargin(ResolvedLength? m, double basis) => m?.resolve(basis) ?? 0;
}

/// Paints CSS items in stacking order: negative `z-index` first, then the
/// flow in tree order, then non-negative `z-index` items; hit tests in
/// reverse.
mixin CssStackingPaint on RenderBox, ContainerRenderObjectMixin<RenderBox, CssItemParentData> {
  List<RenderBox> _paintOrder() {
    final normal = <RenderBox>[];
    final stacked = <(int, int, RenderBox)>[];
    var i = 0;
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final z = (c.parentData! as CssItemParentData).zIndex;
      if (z == null) {
        normal.add(c);
      } else {
        stacked.add((z, i, c));
      }
      i++;
    }
    if (stacked.isEmpty) return normal;
    stacked.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [
      for (final s in stacked)
        if (s.$1 < 0) s.$3,
      ...normal,
      for (final s in stacked)
        if (s.$1 >= 0) s.$3,
    ];
  }

  void paintStacked(PaintingContext context, Offset offset) {
    for (final c in _paintOrder()) {
      context.paintChild(c, (c.parentData! as CssItemParentData).offset + offset);
    }
  }

  bool hitTestStacked(BoxHitTestResult result, Offset position) {
    final order = _paintOrder();
    for (var k = order.length - 1; k >= 0; k--) {
      final c = order[k];
      final pd = c.parentData! as CssItemParentData;
      final hit = result.addWithPaintOffset(
        offset: pd.offset,
        position: position,
        hitTest: (r, p) => c.hitTest(r, position: p),
      );
      if (hit) return true;
    }
    return false;
  }
}

/// Attaches CSS item data (margins, flex properties) to a child of a
/// [CssBlockFlow] or [CssFlexLayout].
class CssItem extends ParentDataWidget<CssItemParentData> {
  const CssItem({
    super.key,
    required this.margin,
    required this.autoWidth,
    required this.autoHeight,
    this.maxWidth,
    this.flexGrow = 0,
    this.flexShrink = 1,
    this.flexBasis,
    this.alignSelf = 'auto',
    this.justifySelf = 'auto',
    this.gridRowStart = GridLineValue.auto,
    this.gridRowEnd = GridLineValue.auto,
    this.gridColumnStart = GridLineValue.auto,
    this.gridColumnEnd = GridLineValue.auto,
    this.order = 0,
    this.zIndex,
    this.replaced = false,
    required super.child,
  });

  /// top, right, bottom, left; null entries mean `auto`.
  final List<ResolvedLength?> margin;
  final bool autoWidth;
  final bool autoHeight;
  final ResolvedLength? maxWidth;
  final double flexGrow;
  final double flexShrink;
  final ResolvedLength? flexBasis;
  final String alignSelf;
  final String justifySelf;
  final GridLineValue gridRowStart;
  final GridLineValue gridRowEnd;
  final GridLineValue gridColumnStart;
  final GridLineValue gridColumnEnd;
  final int order;
  final int? zIndex;
  final bool replaced;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as CssItemParentData;
    var changed = false;
    void set<T>(T current, T next, void Function(T) assign) {
      if (current != next) {
        assign(next);
        changed = true;
      }
    }

    set(pd.marginTop, margin[0], (v) => pd.marginTop = v);
    set(pd.marginRight, margin[1], (v) => pd.marginRight = v);
    set(pd.marginBottom, margin[2], (v) => pd.marginBottom = v);
    set(pd.marginLeft, margin[3], (v) => pd.marginLeft = v);
    set(pd.autoWidth, autoWidth, (v) => pd.autoWidth = v);
    set(pd.autoHeight, autoHeight, (v) => pd.autoHeight = v);
    set(pd.maxWidth, maxWidth, (v) => pd.maxWidth = v);
    set(pd.flexGrow, flexGrow, (v) => pd.flexGrow = v);
    set(pd.flexShrink, flexShrink, (v) => pd.flexShrink = v);
    set(pd.flexBasis, flexBasis, (v) => pd.flexBasis = v);
    set(pd.alignSelf, alignSelf, (v) => pd.alignSelf = v);
    set(pd.justifySelf, justifySelf, (v) => pd.justifySelf = v);
    set(pd.gridRowStart, gridRowStart, (v) => pd.gridRowStart = v);
    set(pd.gridRowEnd, gridRowEnd, (v) => pd.gridRowEnd = v);
    set(pd.gridColumnStart, gridColumnStart, (v) => pd.gridColumnStart = v);
    set(pd.gridColumnEnd, gridColumnEnd, (v) => pd.gridColumnEnd = v);
    set(pd.order, order, (v) => pd.order = v);
    set(pd.replaced, replaced, (v) => pd.replaced = v);
    if (pd.zIndex != zIndex) {
      pd.zIndex = zIndex;
      renderObject.parent?.markNeedsPaint();
    }
    if (changed) renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => CssBlockFlowMarker;
}

/// Only used for [CssItem.debugTypicalAncestorWidgetClass] diagnostics.
abstract class CssBlockFlowMarker extends Widget {
  const CssBlockFlowMarker({super.key});
}
