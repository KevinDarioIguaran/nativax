import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativax_css/nativax_css.dart';

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

  /// `height: auto` — flex parents may stretch such children on the cross
  /// axis.
  bool autoHeight = true;

  double flexGrow = 0;
  double flexShrink = 1;

  /// null = `auto` (use the item's size property or content size).
  ResolvedLength? flexBasis;

  /// `auto` or an align-items keyword.
  String alignSelf = 'auto';

  /// Width/height of the containing block, set by the parent before laying
  /// the child out. null when unknown (indefinite).
  double? containingWidth;
  double? containingHeight;

  double resolveMargin(ResolvedLength? m, double basis) => m?.resolve(basis) ?? 0;
}

/// Attaches CSS item data (margins, flex properties) to a child of a
/// [CssBlockFlow] or [CssFlexLayout].
class CssItem extends ParentDataWidget<CssItemParentData> {
  const CssItem({
    super.key,
    required this.margin,
    required this.autoWidth,
    required this.autoHeight,
    this.flexGrow = 0,
    this.flexShrink = 1,
    this.flexBasis,
    this.alignSelf = 'auto',
    required super.child,
  });

  /// top, right, bottom, left; null entries mean `auto`.
  final List<ResolvedLength?> margin;
  final bool autoWidth;
  final bool autoHeight;
  final double flexGrow;
  final double flexShrink;
  final ResolvedLength? flexBasis;
  final String alignSelf;

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
    set(pd.flexGrow, flexGrow, (v) => pd.flexGrow = v);
    set(pd.flexShrink, flexShrink, (v) => pd.flexShrink = v);
    set(pd.flexBasis, flexBasis, (v) => pd.flexBasis = v);
    set(pd.alignSelf, alignSelf, (v) => pd.alignSelf = v);
    if (changed) renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => CssBlockFlowMarker;
}

/// Only used for [CssItem.debugTypicalAncestorWidgetClass] diagnostics.
abstract class CssBlockFlowMarker extends Widget {
  const CssBlockFlowMarker({super.key});
}
