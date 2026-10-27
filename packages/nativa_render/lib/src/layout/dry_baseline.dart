import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../render/fieldset.dart';
import 'css_block.dart';
import 'css_box.dart';
import 'css_flex.dart';
import 'css_grid.dart';
import 'preferred_width.dart';

/// Dry baseline of [box] laid out with [constraints], or null when it has
/// none or its type cannot compute one without layout (many framework
/// render objects assert in `computeDryBaseline`). Inline atomics then sit
/// on their bottom edge during dry sizing only.
double? cssDryBaseline(RenderBox? box, BoxConstraints constraints, TextBaseline baseline) {
  if (box == null) return null;
  if (box is RenderCssBox ||
      box is RenderCssBlock ||
      box is RenderCssFlex ||
      box is RenderCssGrid ||
      box is RenderParagraph ||
      box is RenderPreferredWidth ||
      box is RenderCenterVertically ||
      box is RenderFieldsetLegendBar ||
      box is RenderCssInlineAtomic ||
      box is RenderCssContainingBlock) {
    return box.getDryBaseline(constraints, baseline);
  }
  if (box is RenderPadding) {
    final padding = box.padding.resolve(box.textDirection);
    final d = cssDryBaseline(box.child, constraints.deflate(padding), baseline);
    return d == null ? null : d + padding.top;
  }
  // Proxies that pass their constraints through unchanged.
  if (box is RenderProxyBox &&
      box is! RenderConstrainedBox &&
      box is! RenderLimitedBox &&
      box is! RenderAspectRatio &&
      box is! RenderIntrinsicWidth &&
      box is! RenderIntrinsicHeight) {
    return cssDryBaseline(box.child, constraints, baseline);
  }
  return null;
}

/// Wraps an atomic inline (inline-block, replaced element, control) so a
/// paragraph can ask for its dry baseline safely.
class CssInlineAtomic extends SingleChildRenderObjectWidget {
  const CssInlineAtomic({super.key, super.child});

  @override
  RenderCssInlineAtomic createRenderObject(BuildContext context) => RenderCssInlineAtomic();
}

class RenderCssInlineAtomic extends RenderProxyBox {
  // Never null: an atomic inline without a baseline sits on its bottom
  // margin edge (CSS 2.1 §10.8.1), and the framework's proxies above a
  // placeholder assert when their child reports no dry baseline.
  @override
  double? computeDryBaseline(covariant BoxConstraints constraints, TextBaseline baseline) =>
      cssDryBaseline(child, constraints, baseline) ?? getDryLayout(constraints).height;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      child?.getDistanceToActualBaseline(baseline) ?? size.height;
}
