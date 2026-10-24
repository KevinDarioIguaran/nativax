import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';

/// Minimal pure-Dart [LayoutHost] used by the conformance runner.
///
/// The real renderer lives in `nativa_render` and needs Flutter. CSS Selectors
/// tests only need deterministic geometry for `offsetWidth`, `offsetHeight`,
/// `offsetTop`, `offsetLeft` and `getBoundingClientRect`, so this host
/// computes a simplified block/inline box tree from computed styles. It is
/// intentionally conservative: explicit widths/heights win, blocks fill the
/// containing block, and text contributes an approximate intrinsic size.
class HeadlessLayoutHost implements LayoutHost {
  HeadlessLayoutHost({
    required this.document,
    required this.styleEngine,
    double width = 800,
    double height = 600,
  })  : _viewportWidth = width,
        _viewportHeight = height {
    document.layoutHost = this;
    document.addMutationListener((_) => _invalidate());
  }

  final Document document;
  final StyleEngine styleEngine;
  final double _viewportWidth;
  final double _viewportHeight;

  int _revision = 0;
  int _computedRevision = -1;
  final Map<Element, ElementBox> _boxes = <Element, ElementBox>{};

  void _invalidate() {
    _revision++;
  }

  void _ensureLayout() {
    if (_computedRevision == _revision) return;
    _boxes.clear();
    final root = document.documentElement;
    if (root != null) {
      _layoutBlock(root, 0, 0, viewportWidth);
    }
    _computedRevision = _revision;
  }

  @override
  ElementBox? boxOf(Element element) {
    _ensureLayout();
    return _boxes[element];
  }

  @override
  void scrollIntoView(Element element, {bool smooth = false, String block = 'start'}) {}

  @override
  double get scrollX => 0;

  @override
  double get scrollY => 0;

  @override
  double get viewportWidth => _viewportWidth;

  @override
  double get viewportHeight => _viewportHeight;

  @override
  double get documentHeight {
    _ensureLayout();
    final root = document.documentElement;
    if (root == null) return viewportHeight;
    return _boxes[root]?.height ?? viewportHeight;
  }

  @override
  void scrollTo(double x, double y, {bool smooth = false}) {}

  @override
  (double, double) toViewport(double globalX, double globalY) => (globalX, globalY);

  @override
  bool get isScrolling => false;

  (double, double) _layout(Element element, double containingWidth, double x, double y) {
    final style = styleEngine.styleOf(element);
    if (style.display == Display.none) {
      return (0, 0);
    }
    final ml = _resolve(style.marginOf('left'), containingWidth);
    final mr = _resolve(style.marginOf('right'), containingWidth);
    final mt = _resolve(style.marginOf('top'), containingWidth);
    // mb is reserved for future vertical margin collapsing.
    final pl = style.paddingOf('left').resolve(containingWidth) ?? 0;
    final pr = style.paddingOf('right').resolve(containingWidth) ?? 0;
    final pt = style.paddingOf('top').resolve(containingWidth) ?? 0;
    final pb = style.paddingOf('bottom').resolve(containingWidth) ?? 0;
    final bl = style.borderWidthOf('left');
    final br = style.borderWidthOf('right');
    final bt = style.borderWidthOf('top');
    final bb = style.borderWidthOf('bottom');

    final specifiedW = style.width?.resolve(containingWidth);
    final specifiedH = style.height?.resolve(containingWidth);

    final isInline = style.isInlineLevel && !style.isFlexContainer && !style.isGridContainer;
    final contentContaining = (specifiedW != null)
        ? specifiedW
        : (isInline ? double.infinity : (containingWidth - ml - mr - pl - pr - bl - br).clamp(0.0, double.infinity).toDouble());

    // Layout children.
    double childY = 0;
    double maxChildWidth = 0;
    double inlineWidth = 0;
    double inlineHeight = 0;
    for (final child in element.children) {
      if (isInline) {
        final (cw, ch) = _layout(child, contentContaining.isFinite ? contentContaining : containingWidth, 0, 0);
        inlineWidth += cw;
        if (ch > inlineHeight) inlineHeight = ch;
      } else {
        final (cw, ch) = _layout(child, contentContaining, 0, childY);
        if (cw > maxChildWidth) maxChildWidth = cw;
        childY += ch;
      }
    }
    if (isInline && element.children.isEmpty) {
      // Approximate text width for inline elements without explicit size.
      final text = element.textContent;
      inlineWidth = text.length * style.fontSize * 0.5;
      inlineHeight = style.fontSize * 1.2;
    }

    final width = specifiedW != null
        ? specifiedW + pl + pr + bl + br
        : (isInline
            ? (inlineWidth + pl + pr + bl + br)
            : (contentContaining.isFinite ? contentContaining + pl + pr + bl + br : maxChildWidth + pl + pr + bl + br));
    final height = specifiedH != null
        ? specifiedH + pt + pb + bt + bb
        : (isInline
            ? (inlineHeight + pt + pb + bt + bb)
            : (childY + pt + pb + bt + bb));

    final clampedW = width.clamp(style.minWidth.resolve(containingWidth) ?? 0, (style.maxWidth?.resolve(containingWidth)) ?? double.infinity).toDouble();
    final clampedH = height.clamp(style.minHeight.resolve(containingWidth) ?? 0, (style.maxHeight?.resolve(containingWidth)) ?? double.infinity).toDouble();

    final boxX = x + ml + bl; // border box origin (approx: margin then border)
    final boxY = y + mt + bt;
    final box = ElementBox(
      x: boxX,
      y: boxY,
      width: clampedW,
      height: clampedH,
      offsetX: ml + bl,
      offsetY: mt + bt,
      clientWidth: (clampedW - pl - pr - bl - br).clamp(0, double.infinity),
      clientHeight: (clampedH - pt - pb - bt - bb).clamp(0, double.infinity),
      scrollWidth: clampedW,
      scrollHeight: clampedH,
    );
    _boxes[element] = box;
    return (clampedW.toDouble(), clampedH.toDouble());
  }

  double _resolve(ResolvedLength? length, double basis) {
    if (length == null) return 0;
    return length.resolve(basis) ?? 0;
  }

  (double, double) _layoutBlock(Element element, double x, double y, double containingWidth) {
    // Wrapper to keep the public recursive entry simple.
    return _layout(element, containingWidth, x, y);
  }
}
