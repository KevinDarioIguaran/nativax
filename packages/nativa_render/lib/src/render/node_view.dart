import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:nativa_css/nativa_css.dart' hide MediaQuery;
import 'package:nativa_dom/nativa_dom.dart' as dom;

import '../layout/css_block.dart';
import '../layout/css_box.dart';
import '../layout/css_flex.dart';
import '../layout/css_grid.dart';
import '../layout/css_item.dart';
import '../layout/css_sticky.dart';
import '../layout/preferred_width.dart';
import '../layout/css_transform.dart';
import '../layout/virtualization.dart';
import '../layout/layout_profile.dart';
import '../layout/layout_timed.dart';
import '../style_mapping.dart';
import 'animation.dart';
import 'canvas2d.dart';
import 'control_glyphs.dart';
import 'fieldset.dart';
import 'svg.dart';
import 'render_types.dart';
import 'draw_trace.dart';
import 'widget_cache.dart';

/// Tags that never generate a box. They are excluded before asking the style
/// engine, so scripts/styles in real pages do not pay selector matching.
const Set<String> nativaxNeverRenderedTags = {
  'script',
  'style',
  'head',
  'title',
  'meta',
  'link',
  'noscript',
  'template',
};

/// Renders one DOM element (and its subtree) as a Flutter widget.
///
/// This is the phase 1 renderer: block flow, inline text, flexbox, simple
/// controls and click events. Positioning, tables, list markers, focus
/// traversal and image backgrounds are intentionally deferred and documented
/// in `progress/phases.md`.
class NativeXNodeView extends StatelessWidget {
  const NativeXNodeView({
    super.key,
    required this.element,
    required this.styleEngine,
    this.isRoot = false,
    this.imageResolver,
    this.onDiagnostic,
    this.cache,
  });

  final dom.Element element;
  final StyleEngine styleEngine;
  final bool isRoot;
  final NativaXImageResolver? imageResolver;
  final NativaXDiagnostic? onDiagnostic;
  final NativaXWidgetCache? cache;

  @override
  Widget build(BuildContext context) {
    final builder = _Builder(
      styleEngine: styleEngine,
      context: context,
      imageResolver: imageResolver,
      onDiagnostic: onDiagnostic,
      cache: cache,
    );
    if (isRoot) {
      // The root item needs a real CSS parent for the containing-block
      // percentages and for its margins; a bare SizedBox cannot host
      // CssItemParentData.
      return CssFlexLayout(
        direction: Axis.vertical,
        children: [builder.buildItem(element, parentFlex: true)],
      );
    }
    return builder.buildItem(element, parentFlex: true);
  }
}

/// The render box drawn for each element, for layout queries from script
/// (`getBoundingClientRect`, `offsetWidth`, `scrollIntoView`, observers).
/// Declared in `virtualization.dart` so the virtual window can measure slots.

class _ElementAnchor extends SingleChildRenderObjectWidget {
  const _ElementAnchor({required this.element, super.child});
  final dom.Element element;

  @override
  _RenderElementAnchor createRenderObject(BuildContext context) =>
      _RenderElementAnchor(element);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderElementAnchor renderObject,
  ) {
    renderObject.element = element;
  }
}

class _RenderElementAnchor extends RenderProxyBox with CssElementBoundary {
  _RenderElementAnchor(this._element);
  dom.Element _element;

  set element(dom.Element e) {
    if (identical(e, _element)) return;
    if (identical(elementRenderBoxes[_element], this))
      elementRenderBoxes[_element] = null;
    _element = e;
    if (attached) elementRenderBoxes[e] = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    elementRenderBoxes[_element] = this;
  }

  @override
  void performLayout() {
    final watch = NativaXDrawTrace.enabled ? (Stopwatch()..start()) : null;
    super.performLayout();
    if (NativaXDrawTrace.enabled) {
      final us = watch!.elapsedMicroseconds;
      final ms = us / 1000.0;
      final label =
          'LAYOUT ${NativaXDrawTrace.describe(_element)} '
          'size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
      NativaXDrawTrace.log('$label ms=${ms.toStringAsFixed(2)}');
      NativaXDrawTrace.markSlow(
        'LAYOUT ${NativaXDrawTrace.describe(_element)}',
        us ~/ 1000,
      );
      if (us >= 20000) NativaXDrawTrace.log('SLOW_$label');
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final watch = NativaXDrawTrace.enabled ? (Stopwatch()..start()) : null;
    final label =
        'PAINT ${NativaXDrawTrace.describe(_element)} '
        'offset=${offset.dx.toStringAsFixed(1)},${offset.dy.toStringAsFixed(1)} '
        'size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
    if (NativaXDrawTrace.enabled) {
      NativaXDrawTrace.log('$label');
    }
    super.paint(context, offset);
    if (NativaXDrawTrace.enabled) {
      final us = watch!.elapsedMicroseconds;
      final ms = us / 1000.0;
      NativaXDrawTrace.log('$label ms=${ms.toStringAsFixed(2)}');
      NativaXDrawTrace.markSlow(
        'PAINT ${NativaXDrawTrace.describe(_element)}',
        us ~/ 1000,
      );
      if (us >= 20000) {
        NativaXDrawTrace.log('SLOW_$label');
      }
    }
  }

  @override
  void detach() {
    if (identical(elementRenderBoxes[_element], this))
      elementRenderBoxes[_element] = null;
    super.detach();
  }
}

/// Text range of an inline element (one without its own render box) inside
/// the paragraph that draws it, so layout queries can return the element's
/// own line boxes instead of its container's.
class InlineRange {
  InlineRange(this._state, this.start, this.end);
  final _InlineTextState _state;
  final int start;
  final int end;

  RenderParagraph? get paragraph {
    if (!_state.mounted) return null;
    RenderParagraph? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderParagraph) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final root = _state.context.findRenderObject();
    if (root != null) visit(root);
    return found;
  }
}

final Expando<InlineRange> inlineRanges = Expando('nativax.inlineRange');

/// The rendered elements at [global], innermost first.
List<dom.Element> elementsAtGlobal(BuildContext context, Offset global) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(
    result,
    global,
    View.of(context).viewId,
  );
  final out = <dom.Element>[];
  for (final entry in result.path) {
    final target = entry.target;
    if (target is _RenderElementAnchor && !out.contains(target._element)) {
      out.add(target._element);
    }
  }
  return out;
}

/// The innermost rendered element at [global] (for drag and drop targets).
dom.Element? elementAtGlobal(BuildContext context, Offset global) =>
    elementsAtGlobal(context, global).firstOrNull;

/// Ids of drag-and-drop sessions (shared `dataTransfer` objects in script).
int _nextDragId = 1;

/// The drag session of the element being dragged.
final Expando<int> dragSessionOf = Expando('nativax.drag');

/// An element taken out of normal flow into the viewport layer:
/// `position: fixed` boxes and modal dialogs (the top layer). Must be a
/// direct child of the document view's [Stack].
class NativeXLayerView extends StatelessWidget {
  const NativeXLayerView({
    super.key,
    required this.element,
    required this.styleEngine,
    required this.modal,
    this.imageResolver,
    this.onDiagnostic,
    this.cache,
  });

  final dom.Element element;
  final StyleEngine styleEngine;
  final bool modal;
  final NativaXImageResolver? imageResolver;
  final NativaXDiagnostic? onDiagnostic;
  final NativaXWidgetCache? cache;

  @override
  Widget build(BuildContext context) {
    final builder = _Builder(
      styleEngine: styleEngine,
      context: context,
      imageResolver: imageResolver,
      onDiagnostic: onDiagnostic,
      cache: cache,
    );
    if (!modal) {
      final mq = MediaQuery.maybeOf(context);
      return builder._absoluteWidget(
        element,
        EdgeInsets.zero,
        mq?.size.width ?? 800,
        mq?.size.height ?? 600,
      );
    }
    final style = styleEngine.styleOf(element);
    final backdrop = styleEngine.pseudoStyleOf(element, 'backdrop');
    final box = builder._interact(
      element,
      style,
      builder.paintEffects(
        element,
        style,
        _ElementAnchor(
          element: element,
          child: builder.buildBox(element, style),
        ),
      ),
    );
    return Positioned.fill(
      key: ObjectKey(element),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: ColoredBox(
                color: backdrop == null
                    ? const Color(0x1a000000)
                    : toColor(backdrop.backgroundColor),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: CssFlexLayout(
                  direction: Axis.vertical,
                  alignItems: 'center',
                  children: [
                    CssItem(
                      margin: const [
                        ResolvedLength.zero,
                        ResolvedLength.zero,
                        ResolvedLength.zero,
                        ResolvedLength.zero,
                      ],
                      autoWidth: false,
                      autoHeight: true,
                      child: box,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Builder {
  _Builder({
    required this.styleEngine,
    required this.context,
    this.imageResolver,
    this.onDiagnostic,
    this.cache,
  });

  final StyleEngine styleEngine;
  final BuildContext context;
  final NativaXImageResolver? imageResolver;
  final NativaXDiagnostic? onDiagnostic;
  final NativaXWidgetCache? cache;

  static const _zeroMargins = [
    ResolvedLength.zero,
    ResolvedLength.zero,
    ResolvedLength.zero,
    ResolvedLength.zero,
  ];

  static const _replaced = {
    'img',
    'input',
    'textarea',
    'select',
    'br',
    'video',
    'audio',
    'canvas',
    'iframe',
    'svg',
  };

  /// `::before`/`::after` of [element] when they generate a box.
  _Pseudo? _pseudo(dom.Element element, String kind) {
    if (_replaced.contains(element.localName)) return null;
    if (!styleEngine.hasPseudoRules(kind)) return null;
    final style = styleEngine.pseudoStyleOf(element, kind);
    if (style == null || style.display == Display.none) return null;
    final content = style.content;
    if (content == null) return null;
    return _Pseudo(element, kind, style, content.resolve(element.getAttribute));
  }

  /// The box tree children of [element]: generated content plus child
  /// nodes, with `display: contents` children replaced by their own
  /// children.
  List<Object> children(dom.Element element) {
    final out = <Object>[];
    final before = _pseudo(element, 'before');
    if (before != null) out.add(before);
    final legend = element.localName == 'fieldset' ? _legendOf(element) : null;
    for (final c in element.childNodes) {
      if (identical(c, legend)) continue;
      if (c is dom.Element && nativaxNeverRenderedTags.contains(c.localName)) {
        continue;
      }
      if (c is dom.Element &&
          styleEngine.styleOf(c).display == Display.contents) {
        out.addAll(children(c));
      } else {
        out.add(c);
      }
    }
    final after = _pseudo(element, 'after');
    if (after != null) out.add(after);
    return out;
  }

  ComputedStyle? styleOfChild(Object c) => switch (c) {
    dom.Element() => styleEngine.styleOf(c),
    _Pseudo() => c.style,
    _ => null,
  };

  bool _skipped(Object c) {
    // Tags that never generate a box are skipped without asking the style
    // engine. Scripts/styles in particular are numerous in real pages and
    // would otherwise pay full selector matching for no visual result.
    if (c is dom.Element && nativaxNeverRenderedTags.contains(c.localName)) {
      return true;
    }
    final s = styleOfChild(c);
    if (s == null) return c is! dom.Text;
    return s.display == Display.none || s.position == 'fixed';
  }

  bool _isAbsolute(Object c) => styleOfChild(c)?.position == 'absolute';
  bool _isFixed(Object c) => styleOfChild(c)?.position == 'fixed';

  bool _isInline(Object c) =>
      c is dom.Text || (styleOfChild(c)?.isInlineLevel ?? false);

  Widget buildItem(
    dom.Element element, {
    required bool parentFlex,
    bool repaintBoundary = false,
  }) {
    final cached = cache?.get(element);
    if (cached != null) return cached;
    NativeXBuildStats.elementBuilds++;
    final buildWatch = NativaXDrawTrace.enabled ? (Stopwatch()..start()) : null;
    final Widget result;
    if (!LayoutProfile.enabled) {
      result = _buildItem(
        element,
        parentFlex: parentFlex,
        repaintBoundary: repaintBoundary,
      );
    } else {
      LayoutProfile.begin('widget.buildItem');
      try {
        result = _buildItem(
          element,
          parentFlex: parentFlex,
          repaintBoundary: repaintBoundary,
        );
      } finally {
        LayoutProfile.end();
      }
    }
    if (NativaXDrawTrace.enabled) {
      final us = buildWatch!.elapsedMicroseconds;
      final label = 'BUILD ${NativaXDrawTrace.describe(element)}';
      NativaXDrawTrace.log('$label ms=${(us / 1000).toStringAsFixed(2)}');
      NativaXDrawTrace.markSlow(label, us ~/ 1000);
    }
    cache?.put(element, result);
    return result;
  }

  Widget _buildItem(
    dom.Element element, {
    required bool parentFlex,
    bool repaintBoundary = false,
  }) {
    final style = styleEngine.styleOf(element);
    // The animated box rebuilds with interpolated styles during CSS
    // transitions and animations; idle, it just builds the box.
    final box = CssAnimatedBox(
      element: element,
      style: style,
      styleEngine: styleEngine,
      builder: (s) {
        var box = buildBox(element, s);
        if (s.display == Display.listItem) box = _withMarker(element, s, box);
        return paintEffects(
          element,
          s,
          _ElementAnchor(element: element, child: box),
        );
      },
    );
    var item = _interact(element, style, box);
    // Sticky boxes are outermost so hit testing follows the shifted box.
    if (style.position == 'sticky' &&
        (style.top != null || style.bottom != null)) {
      item = CssSticky(
        top: _px(style.top),
        bottom: _px(style.bottom),
        child: item,
      );
    }
    if (repaintBoundary) item = RepaintBoundary(child: item);
    return itemFor(
      style,
      item,
      key: ObjectKey(element),
      parentFlex: parentFlex,
      replaced: _replacedElements.contains(element.localName),
    );
  }

  static const _replacedElements = {
    'img',
    'svg',
    'video',
    'canvas',
    'iframe',
    'embed',
    'object',
    'audio',
  };

  /// Wraps [box] in the CSS item parent data for flow, flex and grid parents.
  Widget itemFor(
    ComputedStyle style,
    Widget box, {
    Key? key,
    required bool parentFlex,
    bool replaced = false,
  }) {
    final autoWidth =
        style.width == null && (parentFlex || !style.isInlineLevel);
    return CssItem(
      key: key,
      margin: [
        style.marginOf('top'),
        style.marginOf('right'),
        style.marginOf('bottom'),
        style.marginOf('left'),
      ],
      autoWidth: autoWidth,
      autoHeight: style.height == null,
      maxWidth: style.maxWidth,
      width: style.width,
      flexGrow: style.flexGrow,
      flexShrink: style.flexShrink,
      flexBasis: style.flexBasis,
      alignSelf: style.alignSelf,
      justifySelf: style.justifySelf,
      gridRowStart: style.gridRowStart,
      gridRowEnd: style.gridRowEnd,
      gridColumnStart: style.gridColumnStart,
      gridColumnEnd: style.gridColumnEnd,
      order: style.order,
      zIndex: style.position == 'relative' || style.position == 'sticky'
          ? style.zIndex
          : null,
      replaced: replaced,
      child: box,
    );
  }

  /// `position: relative` offsets, `transform`, `opacity` and
  /// `visibility: hidden` (which keeps the box's space).
  Widget paintEffects(dom.Element? element, ComputedStyle style, Widget box) {
    if (style.position == 'relative') {
      final offset = _relativeOffset(style);
      if (offset != Offset.zero) {
        box = Transform.translate(offset: offset, child: box);
      }
    }
    final backdrop = style.backdropFilter;
    if (backdrop != null) {
      final blur = filterBlur(backdrop);
      if (blur > 0) {
        box = ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: box,
          ),
        );
      }
    }
    final filter = style.filter;
    if (filter != null) {
      final matrix = filterColorMatrix(filter);
      if (matrix != null)
        box = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: box,
        );
      final blur = filterBlur(filter);
      if (blur > 0)
        box = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: box,
        );
      for (final f in filter.functions.where((x) => x.name == 'drop-shadow')) {
        final sh = f.shadow!;
        box = DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: toColor(sh.color.color ?? style.color),
                offset: Offset(sh.x.value, sh.y.value),
                blurRadius: sh.blur.value,
              ),
            ],
          ),
          child: box,
        );
      }
    }
    final transform = style.transform;
    if (transform != null)
      box = CssTransform(
        transform: transform,
        origin: style.transformOrigin,
        child: box,
      );
    if (style.opacity < 1) box = Opacity(opacity: style.opacity, child: box);
    if (style.visibility == 'hidden' || style.visibility == 'collapse') {
      final parent = element?.parentElement;
      final parentHidden =
          parent != null && styleEngine.styleOf(parent).visibility != 'visible';
      if (!parentHidden) {
        box = Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: box,
        );
      }
    }
    if (style.pointerEventsNone) box = IgnorePointer(child: box);
    return box;
  }

  /// A block-level box for generated content.
  Widget buildPseudoBox(_Pseudo p) {
    final style = p.style;
    Widget content = p.text.isEmpty
        ? const SizedBox.shrink()
        : Text(
            applyTextTransform(p.text, style.textTransform),
            style: textStyleFor(style),
            textAlign: textAlignFor(style),
          );
    return paintEffects(
      null,
      style,
      CssBox(
        spec: boxSpecFor(style, report: onDiagnostic),
        child: content,
      ),
    );
  }

  /// Controls drawn by the platform ignore author backgrounds and borders
  /// (as browsers do while `appearance` is `auto`).
  static bool _nativeAppearance(dom.Element e) =>
      e.localName == 'input' &&
      const {'checkbox', 'radio', 'range'}.contains(e.inputType);

  Widget buildBox(dom.Element element, ComputedStyle style) {
    final image = _backgroundImage(element, style);
    var content = buildContent(element, style);
    if (_isScrollable(style)) content = _scrollContainer(style, content);
    // Buttons centre their contents vertically when taller than them.
    if (element.localName == 'button' &&
        !style.isFlexContainer &&
        !style.isGridContainer) {
      content = CenterVertically(child: content);
    }
    var spec = boxSpecFor(style, backgroundImage: image, report: onDiagnostic);
    if (_nativeAppearance(element)) {
      spec = CssBoxSpec(
        width: spec.width,
        height: spec.height,
        minWidth: spec.minWidth,
        minHeight: spec.minHeight,
        maxWidth: spec.maxWidth,
        maxHeight: spec.maxHeight,
        borderBox: spec.borderBox,
        outlineWidth: spec.outlineWidth,
        outlineColor: spec.outlineColor,
        outlineOffset: spec.outlineOffset,
      );
    }
    final legend = element.localName == 'fieldset' ? _legendOf(element) : null;
    final Widget box = legend != null
        ? _fieldset(element, style, spec, legend, content)
        : CssBox(spec: spec, child: content);
    final perspective = style.perspective;
    if (perspective == null) return box;
    return CssPerspective(
      distance: perspective,
      origin: style.perspectiveOrigin,
      child: box,
    );
  }

  dom.Element? _legendOf(dom.Element fieldset) {
    for (final c in fieldset.children) {
      if (c.localName == 'legend') {
        return styleEngine.styleOf(c).display == Display.none ? null : c;
      }
    }
    return null;
  }

  /// A fieldset whose first `<legend>` sits on the top border, which is
  /// interrupted behind it.
  Widget _fieldset(
    dom.Element element,
    ComputedStyle style,
    CssBoxSpec spec,
    dom.Element legend,
    Widget content,
  ) {
    final top = spec.border[0];
    final color = spec.borderColors[0];
    final radius = spec.radii[0].isPercent ? 0.0 : spec.radii[0].value;
    final rRadius = spec.radii[1].isPercent ? 0.0 : spec.radii[1].value;
    final side = BorderSide(width: top, color: color);
    // Horizontal sizing belongs to an outer box around the legend band and
    // the lower part, so both share the fieldset's border-box width.
    final lower = CssBoxSpec(
      height: spec.height,
      minHeight: spec.minHeight,
      maxHeight: spec.maxHeight,
      padding: spec.padding,
      border: [0, spec.border[1], spec.border[2], spec.border[3]],
      borderColors: spec.borderColors,
      radii: [
        ResolvedLength.zero,
        ResolvedLength.zero,
        spec.radii[2],
        spec.radii[3],
      ],
      borderBox: spec.borderBox,
      clip: spec.clip,
      background: spec.background,
      gradient: spec.gradient,
      shadows: spec.shadows,
    );
    final legendStyle = styleEngine.styleOf(legend);
    final legendBox = _interact(
      legend,
      legendStyle,
      paintEffects(
        legend,
        legendStyle,
        _ElementAnchor(element: legend, child: buildBox(legend, legendStyle)),
      ),
    );
    final legendPad = spec.padding[3].isPercent ? 8.0 : spec.padding[3].value;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldsetLegendBar(
          inset: legendPad + spec.border[3],
          top: side,
          left: BorderSide(width: spec.border[3], color: spec.borderColors[3]),
          right: BorderSide(width: spec.border[1], color: spec.borderColors[1]),
          topLeftRadius: radius,
          topRightRadius: rRadius,
          legend: legendBox,
        ),
        CssBox(spec: lower, child: content),
      ],
    );
    if (spec.width == null &&
        spec.maxWidth == null &&
        spec.minWidth.value == 0 &&
        !spec.minWidth.isPercent) {
      return column;
    }
    // Content-box lengths grow by the horizontal padding and borders.
    double extra = spec.border[1] + spec.border[3];
    for (final p in [spec.padding[1], spec.padding[3]]) {
      if (!p.isPercent) extra += p.value;
    }
    ResolvedLength? outer(ResolvedLength? l) =>
        l == null || l.isPercent || spec.borderBox
        ? l
        : ResolvedLength.px(l.value + extra);
    return CssBox(
      spec: CssBoxSpec(
        width: outer(spec.width),
        minWidth: outer(spec.minWidth)!,
        maxWidth: outer(spec.maxWidth),
        borderBox: true,
      ),
      child: column,
    );
  }

  Widget buildContent(dom.Element element, ComputedStyle style) {
    if (style.display == Display.none) {
      return const SizedBox.shrink();
    }
    switch (element.localName) {
      case 'head':
      case 'script':
      case 'style':
      case 'title':
      case 'meta':
      case 'link':
      case 'noscript':
      case 'template':
      case 'br':
        return const SizedBox.shrink();
      case 'img':
        return _image(element, style);
      case 'input':
        return _input(element, style);
      case 'textarea':
        final child = _TextControl(
          element: element,
          style: style,
          multiline: true,
          builder: this,
        );
        if (style.width != null) return child;
        final cols = int.tryParse(element.getAttribute('cols') ?? '') ?? 20;
        return PreferredWidth(
          width: cols * style.fontSize * 0.6,
          child: child,
        );
      case 'select':
        return _select(element, style);
      case 'svg':
        return SvgView(element: element, styleEngine: styleEngine);
      case 'canvas':
        final host = element.ownerDocument.canvasHost;
        return CanvasView(
          element: element,
          registry: host is CanvasRegistry ? host : null,
          style: style,
        );
      case 'video':
      case 'audio':
      case 'iframe':
        return _placeholder(element, style);
    }
    final virtual = _virtualContent(element, style);
    if (virtual != null) return virtual;
    return _normalContent(element, style);
  }

  Widget _normalContent(dom.Element element, ComputedStyle style) {
    final all = [
      for (final c in children(element))
        if (!_skipped(c) && !_isFixed(c)) c,
    ];
    final absolute = all.where(_isAbsolute).toList();
    final normal = all.where((c) => !_isAbsolute(c)).toList();

    Widget content;
    if (normal.isEmpty || _onlyWhitespace(normal, style)) {
      content = const SizedBox.shrink();
    } else if (style.isGridContainer) {
      content = CssGridLayout(
        columns: style.gridTemplateColumns,
        rows: style.gridTemplateRows,
        autoColumns: [
          for (final e in style.gridAutoColumns.entries) ...e.tracks,
        ],
        autoRows: [for (final e in style.gridAutoRows.entries) ...e.tracks],
        areas: style.gridTemplateAreas,
        autoFlow: style.gridAutoFlow,
        rowGap: style.rowGap,
        columnGap: style.columnGap,
        justifyItems: style.justifyItems,
        alignItems: style.alignItems,
        justifyContent: style.justifyContent,
        alignContent: style.alignContent,
        children: _itemChildren(element, normal, style),
      );
    } else if (style.isFlexContainer) {
      content = CssFlexLayout(
        direction: _isRow(style.flexDirection)
            ? Axis.horizontal
            : Axis.vertical,
        reverse: style.flexDirection.endsWith('reverse'),
        wrap: style.flexWrap,
        justifyContent: _justify(style.justifyContent),
        alignItems: _align(style.alignItems),
        rowGap: style.rowGap,
        columnGap: style.columnGap,
        children: _ordered(_itemChildren(element, normal, style), normal),
      );
    } else if (normal.any((c) => !_isInline(c))) {
      final collapse = !_establishesBfc(element, style);
      content = CssBlockFlow(
        collapseTop: collapse && _noEdge(style, 'top'),
        collapseBottom:
            collapse &&
            _noEdge(style, 'bottom') &&
            style.height == null &&
            !style.minHeight.isPercent &&
            style.minHeight.value == 0,
        children: _flowChildren(element, normal, style),
      );
    } else {
      content = _InlineText(
        parent: element,
        style: style,
        builder: this,
        nodes: normal,
      );
    }
    if (absolute.isEmpty) return content;
    return _positioned(element, content, absolute);
  }

  /// Returns a virtualized layout for a large in-flow container, or null when
  /// the container is small or uses a feature the approximation cannot keep
  /// faithful (generated content, absolute children, inline runs).
  ///
  /// The virtual layer is the NativaX equivalent of Blink's display lock: only
  /// the slots in the viewport (plus overscan) are built, so offscreen DOM
  /// elements have neither a render object nor a computed style.
  Widget? _virtualContent(dom.Element element, ComputedStyle style) {
    final isGrid = style.isGridContainer;
    final isFlex = style.isFlexContainer;
    if (!isGrid &&
        !isFlex &&
        style.display != Display.block &&
        style.display != Display.listItem) {
      return null;
    }
    if (isFlex || isGrid) {
      if (element.localName == 'body' ||
          element.localName == 'html' ||
          element.localName == 'fieldset') {
        return null;
      }
    } else if (element.localName == 'body' ||
        element.localName == 'html' ||
        element.localName == 'fieldset') {
      return null;
    }
    // Overlays, modal layers and fixed HUDs keep their real boxes; estimating
    // them (or a child of them) breaks hit testing and geometry queries.
    if (style.position == 'fixed' || style.position == 'absolute') return null;
    final optOut =
        element.getAttribute('data-nativa-virtual') ??
        element.getAttribute('data-nv-virtual');
    if (optOut == 'off' || optOut == 'false') return null;
    final inline = element.getAttribute('style') ?? '';
    if (inline.contains('content-visibility: visible') ||
        inline.contains('content-visibility:visible')) {
      return null;
    }
    if (_pseudo(element, 'before') != null ||
        _pseudo(element, 'after') != null) {
      return null;
    }
    final slots = <dom.Element>[];
    for (final child in element.children) {
      if (const {
        'script',
        'style',
        'template',
        'noscript',
        'head',
        'link',
        'meta',
      }.contains(child.localName)) {
        continue;
      }
      final s = child.getAttribute('style');
      if (s != null &&
          (s.contains('position:absolute') ||
              s.contains('position: absolute') ||
              s.contains('position:fixed') ||
              s.contains('position: fixed') ||
              s.contains('display:contents') ||
              s.contains('display: contents'))) {
        return null;
      }
      slots.add(child);
    }
    for (final node in element.childNodes) {
      if (node is dom.Text && node.data.trim().isNotEmpty) return null;
    }
    if (slots.length < 24) return null;

    if (style.isGridContainer) {
      final width = _availableWidth(element);
      final gap = _px(style.columnGap) ?? 0;
      final columns = gridColumnCount(style.gridTemplateColumns, width, gap);
      if (columns < 2) return _normalContent(element, style);
      final rows = (slots.length + columns - 1) ~/ columns;
      final rowGap = _px(style.rowGap) ?? 0;
      List<dom.Element> rowElements(int row) {
        final start = row * columns;
        final end = math.min(slots.length, start + columns);
        return start >= end ? const [] : slots.sublist(start, end);
      }

      final owner = <dom.Element, (int, int)>{};
      for (var r = 0; r < rows; r++) {
        final row = rowElements(r);
        for (var c = 0; c < row.length; c++) {
          owner[row[c]] = (r, c);
        }
      }
      NativaXRenderProfile.log(
        'VIRT_CREATE grid <${element.localName} id=${element.id} class=${element.className}> slots=$rows',
      );
      return CssVirtualBlock(
        key: ValueKey('virtual-grid-${identityHashCode(element)}'),
        container: element,
        styleEngine: styleEngine,
        debugName: 'grid',
        count: rows,
        columns: columns,
        columnGap: gap,
        elementsAt: rowElements,
        estimate: (i) => _structuralEstimate(rowElements(i)),
        extraHeight: (_) => rowGap,
        indexOfElement: (e) => owner[e]?.$1,
        rowOfElement: (e) => owner[e]?.$1,
        columnOfElement: (e) => owner[e]?.$2,
        itemBuilder: (context, i) {
          final row = rowElements(i);
          return CssGridLayout(
            key: ValueKey('virtual-grid-row-${identityHashCode(element)}-$i'),
            columns: style.gridTemplateColumns,
            rows: style.gridTemplateRows,
            autoColumns: [
              for (final e in style.gridAutoColumns.entries) ...e.tracks,
            ],
            autoRows: [for (final e in style.gridAutoRows.entries) ...e.tracks],
            areas: style.gridTemplateAreas,
            autoFlow: style.gridAutoFlow,
            rowGap: ResolvedLength.zero,
            columnGap: style.columnGap,
            justifyItems: style.justifyItems,
            alignItems: style.alignItems,
            justifyContent: style.justifyContent,
            alignContent: style.alignContent,
            children: [for (final e in row) buildItem(e, parentFlex: true)],
          );
        },
        layoutBuilder: (context, children) => CssBlockFlow(
          collapseTop: false,
          collapseBottom: false,
          children: children,
        ),
      );
    }

    if (style.isFlexContainer) {
      if (_isRow(style.flexDirection) ||
          style.flexWrap != 'nowrap' ||
          !const {
            'normal',
            'flex-start',
            'start',
            'stretch',
          }.contains(style.justifyContent)) {
        return null;
      }
      NativaXRenderProfile.log(
        'VIRT_CREATE flex <${element.localName} id=${element.id} class=${element.className}> slots=${slots.length}',
      );
      return CssVirtualBlock(
        key: ValueKey('virtual-flex-${identityHashCode(element)}'),
        container: element,
        styleEngine: styleEngine,
        debugName: 'flex',
        count: slots.length,
        elementsAt: (i) => [slots[i]],
        estimate: (i) => _structuralEstimate([slots[i]]),
        indexOfElement: (e) {
          final i = slots.indexOf(e);
          return i < 0 ? null : i;
        },
        itemBuilder: (context, i) =>
            buildItem(slots[i], parentFlex: true, repaintBoundary: true),
        layoutBuilder: (context, children) => CssFlexLayout(
          direction: Axis.vertical,
          reverse: false,
          wrap: 'nowrap',
          justifyContent: _justify(style.justifyContent),
          alignItems: _align(style.alignItems),
          rowGap: style.rowGap,
          columnGap: style.columnGap,
          children: children,
        ),
      );
    }

    final collapse = !_establishesBfc(element, style);
    NativaXRenderProfile.log(
      'VIRT_CREATE block <${element.localName} id=${element.id} class=${element.className}> slots=${slots.length}',
    );
    return CssVirtualBlock(
      key: ValueKey('virtual-block-${identityHashCode(element)}'),
      container: element,
      styleEngine: styleEngine,
      debugName: 'block',
      count: slots.length,
      elementsAt: (i) => [slots[i]],
      estimate: (i) => _structuralEstimate([slots[i]]),
      indexOfElement: (e) {
        final i = slots.indexOf(e);
        return i < 0 ? null : i;
      },
      itemBuilder: (context, i) =>
          buildItem(slots[i], parentFlex: false, repaintBoundary: true),
      layoutBuilder: (context, children) => CssBlockFlow(
        collapseTop: collapse && _noEdge(style, 'top'),
        collapseBottom:
            collapse &&
            _noEdge(style, 'bottom') &&
            style.height == null &&
            !style.minHeight.isPercent &&
            style.minHeight.value == 0,
        children: children,
      ),
    );
  }

  /// Best-effort available width for a virtualized grid. It uses the viewport
  /// width and subtracts fixed ancestor padding/borders and fixed-width
  /// siblings of flex rows. This is only used to choose the grid's column
  /// count before layout; the real layout still constrains every row.
  double _availableWidth(dom.Element element) {
    var width =
        NativaXViewportScope.maybeOf(context)?.viewportWidth ??
        MediaQuery.maybeSizeOf(context)?.width ??
        800;
    for (dom.Element? e = element; e != null; e = e.parentElement) {
      final s = styleEngine.styleOf(e);
      for (final side in const ['left', 'right']) {
        width -= s.borderWidthOf(side);
        final p = s.paddingOf(side);
        if (!p.isPercent) width -= p.value;
        final m = s.marginOf(side);
        if (m != null && !m.isPercent) width -= m.value;
      }
      final declared = _px(s.width);
      if (declared != null) width = math.min(width, declared);
      final parent = e.parentElement;
      if (parent == null) break;
      final ps = styleEngine.styleOf(parent);
      if (ps.isFlexContainer && _isRow(ps.flexDirection)) {
        final gap = _px(ps.columnGap) ?? 0;
        for (final sibling in parent.children) {
          if (identical(sibling, e)) continue;
          final ss = styleEngine.styleOf(sibling);
          final sw = _px(ss.width);
          if (sw != null) width -= sw;
          for (final side in const ['left', 'right']) {
            final m = ss.marginOf(side);
            if (m != null && !m.isPercent) width -= m.value;
          }
        }
        width -= gap;
      }
    }
    return math.max(120, width);
  }

  /// Structural height hint used before a slot is measured. It never asks the
  /// style engine for offscreen elements.
  double _structuralEstimate(List<dom.Element> elements) {
    if (elements.isEmpty) return 40;
    final e = elements.first;
    final text = e.textContent.trim();
    final tag = e.localName;
    final charsPerLine = tag == 'h1' || tag == 'h2' || tag == 'h3'
        ? 48.0
        : 78.0;
    final lines = text.isEmpty
        ? 1
        : (text.length / charsPerLine).ceil().clamp(1, 40);
    final lineHeight = switch (tag) {
      'h1' => 44.0,
      'h2' => 32.0,
      'h3' => 28.0,
      'p' => 26.0,
      _ => 24.0,
    };
    final padding = switch (tag) {
      'p' => 0.0,
      _ => 20.0,
    };
    return lines * lineHeight + padding;
  }

  /// Whether [element] starts a new block formatting context, which keeps
  /// its children's margins from collapsing with its own (CSS 2.1 §9.4.1).
  bool _establishesBfc(dom.Element element, ComputedStyle style) {
    final parent = element.parentElement;
    // The root and its children (body): the root's formatting context keeps
    // the margins that would escape them.
    if (parent == null || parent.parentElement == null) return true;
    final ps = styleEngine.styleOf(parent);
    if (ps.isFlexContainer || ps.isGridContainer) return true;
    if (style.display != Display.block && style.display != Display.listItem)
      return true;
    if (style.overflowX != 'visible' || style.overflowY != 'visible')
      return true;
    final position = style.position;
    if (position == 'absolute' || position == 'fixed') return true;
    return const {
      'fieldset',
      'legend',
      'button',
      'td',
      'th',
      'caption',
      'dialog',
    }.contains(element.localName);
  }

  static bool _noEdge(ComputedStyle style, String side) {
    final p = style.paddingOf(side);
    return style.borderWidthOf(side) == 0 && p.calc == null && p.value == 0;
  }

  /// Flex items sorted by `order` (stable).
  List<Widget> _ordered(List<Widget> items, List<Object> sources) {
    final orders = [
      for (final w in items)
        if (w is CssItem) w.order else 0,
    ];
    if (orders.every((o) => o == 0)) return items;
    final indexed = [
      for (var i = 0; i < items.length; i++) (i, orders[i], items[i]),
    ];
    indexed.sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
    return [for (final e in indexed) e.$3];
  }

  Widget _pseudoItem(_Pseudo p, {required bool parentFlex}) => itemFor(
    p.style,
    buildPseudoBox(p),
    key: ValueKey('${identityHashCode(p.element)}::${p.kind}'),
    parentFlex: parentFlex,
  );

  bool _onlyWhitespace(List<Object> nodes, ComputedStyle style) {
    if (style.whiteSpace == 'pre' || style.whiteSpace == 'pre-wrap') {
      return false;
    }
    return nodes.every((node) => node is dom.Text && node.data.trim().isEmpty);
  }

  List<Widget> _flowChildren(
    dom.Element element,
    List<Object> nodes,
    ComputedStyle style,
  ) {
    final out = <Widget>[];
    var inline = <Object>[];
    void flush() {
      if (inline.isEmpty || _onlyWhitespace(inline, style)) {
        inline = <Object>[];
        return;
      }
      out.add(
        CssItem(
          margin: _zeroMargins,
          autoWidth: true,
          autoHeight: true,
          child: _InlineText(
            parent: element,
            style: style,
            builder: this,
            nodes: inline,
          ),
        ),
      );
      inline = <Object>[];
    }

    for (final child in nodes) {
      if (_isInline(child)) {
        inline.add(child);
      } else if (child is dom.Element) {
        flush();
        out.add(buildItem(child, parentFlex: false));
      } else if (child is _Pseudo) {
        flush();
        out.add(_pseudoItem(child, parentFlex: false));
      }
    }
    flush();
    return out;
  }

  /// Children of a flex or grid container: every element is an item; runs
  /// of text become anonymous items.
  List<Widget> _itemChildren(
    dom.Element element,
    List<Object> nodes,
    ComputedStyle style,
  ) {
    final out = <Widget>[];
    var inline = <Object>[];
    void flush() {
      if (inline.isEmpty || _onlyWhitespace(inline, style)) {
        inline = <Object>[];
        return;
      }
      out.add(
        CssItem(
          margin: _zeroMargins,
          autoWidth: false,
          autoHeight: true,
          child: _InlineText(
            parent: element,
            style: style,
            builder: this,
            nodes: inline,
          ),
        ),
      );
      inline = <Object>[];
    }

    for (final child in nodes) {
      if (child is dom.Text) {
        inline.add(child);
      } else if (child is dom.Element) {
        flush();
        out.add(buildItem(child, parentFlex: true));
      } else if (child is _Pseudo) {
        flush();
        out.add(_pseudoItem(child, parentFlex: true));
      }
    }
    flush();
    return out;
  }

  bool _isScrollable(ComputedStyle style) =>
      style.overflowX == 'auto' ||
      style.overflowX == 'scroll' ||
      style.overflowY == 'auto' ||
      style.overflowY == 'scroll';

  Widget _scrollContainer(ComputedStyle style, Widget child) {
    final vertical = style.overflowY == 'auto' || style.overflowY == 'scroll';
    var horizontal = style.overflowX == 'auto' || style.overflowX == 'scroll';
    // Block content keeps the container's width (text wraps, blocks fill
    // the line) and only intrinsically wide content scrolls sideways, as in
    // browsers; an unbounded horizontal viewport would shrink-wrap blocks.
    final wideContent =
        style.isFlexContainer ||
        style.isGridContainer ||
        style.whiteSpace == 'pre' ||
        style.whiteSpace == 'nowrap';
    if (horizontal && !wideContent) horizontal = false;
    if (vertical && horizontal) {
      return Scrollbar(
        child: SingleChildScrollView(
          child: Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: child,
            ),
          ),
        ),
      );
    }
    if (vertical) return NativaXVirtualScrollView(child: child);
    if (horizontal) {
      return Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: child,
        ),
      );
    }
    return child;
  }

  double? _px(ResolvedLength? length) => length?.resolve(null);

  Offset _relativeOffset(ComputedStyle style) {
    final left = _px(style.left);
    final right = _px(style.right);
    final top = _px(style.top);
    final bottom = _px(style.bottom);
    return Offset(
      left ?? (right == null ? 0 : -right),
      top ?? (bottom == null ? 0 : -bottom),
    );
  }

  Widget _positioned(dom.Element parent, Widget normal, List<Object> absolute) {
    final entries = [
      for (final child in absolute) (child, styleOfChild(child)!.zIndex ?? 0),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    // The Stack is the parent's content box, but offsets are relative to its
    // padding box (CSS 2.1 §10.1).
    final ps = styleEngine.styleOf(parent);
    final containerWidth = _px(ps.width) ?? _availableWidth(parent);
    final containerHeight = _px(ps.height);
    double pad(String side) {
      final p = ps.paddingOf(side);
      return p.isPercent ? 0 : p.value;
    }

    final padding = EdgeInsets.fromLTRB(
      pad('left'),
      pad('top'),
      pad('right'),
      pad('bottom'),
    );
    // Expand the in-flow child only when the containing block has a finite
    // size. A loose `Stack` would otherwise let a flex container shrink to
    // its content and defeat cross-axis centering, while an unconditional
    // expand passes infinite constraints to text in unbounded contexts.
    final normalChild = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: normal,
          );
        }
        return normal;
      },
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final entry in entries)
          if (entry.$2 < 0) _absoluteWidget(entry.$1, padding, containerWidth, containerHeight),
        normalChild,
        for (final entry in entries)
          if (entry.$2 >= 0) _absoluteWidget(entry.$1, padding, containerWidth, containerHeight),
      ],
    );
  }

  Widget _absoluteWidget(
    Object node, [
    EdgeInsets containerPadding = EdgeInsets.zero,
    double? containerWidth,
    double? containerHeight,
  ]) {
    final style = styleOfChild(node)!;
    final element = node is _Pseudo ? node.element : node as dom.Element;
    // Percentage offsets of `position: fixed` are relative to the viewport.
    // For `position: absolute`, percentages are relative to the containing
    // block; use the parent size when it is known and fall back to the
    // viewport otherwise. This keeps `top: 50%; left: 50%` centred instead
    // of being dropped as an unresolvable percentage.
    final isFixed = style.position == 'fixed';
    final mq = isFixed ? MediaQuery.maybeOf(context) : null;
    final basisWidth = isFixed
        ? (mq?.size.width ?? containerWidth ?? 800.0)
        : (containerWidth ?? mq?.size.width ?? 800.0);
    final basisHeight = isFixed
        ? (mq?.size.height ?? containerHeight ?? 600.0)
        : (containerHeight ?? mq?.size.height ?? 600.0);
    double? resolve(ResolvedLength? length, double? basis) {
      if (length == null) return null;
      if (!length.isPercent) return length.value;
      return length.resolve(basis);
    }
    final left = resolve(style.left, basisWidth);
    final right = resolve(style.right, basisWidth);
    final top = resolve(style.top, basisHeight);
    final bottom = resolve(style.bottom, basisHeight);
    final hasWidth = style.width != null;
    final hasHeight = style.height != null;

    var box = node is _Pseudo
        ? buildPseudoBox(node)
        : _interact(
            element,
            style,
            paintEffects(
              element,
              style,
              _ElementAnchor(element: element, child: buildBox(element, style)),
            ),
          );
    final margins = EdgeInsets.only(
      top: _px(style.marginOf('top')) ?? 0,
      right: _px(style.marginOf('right')) ?? 0,
      bottom: _px(style.marginOf('bottom')) ?? 0,
      left: _px(style.marginOf('left')) ?? 0,
    );
    if (margins != EdgeInsets.zero) box = Padding(padding: margins, child: box);

    // A fixed full-viewport layer (`inset: 0` / `width/height: 100%`) must
    // receive the Stack's tight constraints. A plain Positioned with auto
    // width/height gives it loose constraints and a percentage can resolve
    // against the viewport, overflowing by a scrollbar's width.
    final fixedFull =
        style.position == 'fixed' &&
        (style.width == null || style.width!.isPercent) &&
        (style.height == null || style.height!.isPercent) &&
        (left == null || left == 0) &&
        (top == null || top == 0) &&
        right == null &&
        bottom == null;
    if (fixedFull) {
      return Positioned.fill(
        key: node is _Pseudo
            ? ValueKey('${identityHashCode(element)}::${node.kind}')
            : ObjectKey(element),
        child: box,
      );
    }
    // `auto` offsets keep the static position, which is in the content box.
    // With an explicit size, an over-constrained right/bottom is ignored.
    final pad = containerPadding;
    return Positioned(
      key: node is _Pseudo
          ? ValueKey('${identityHashCode(element)}::${node.kind}')
          : ObjectKey(element),
      left: left == null ? null : left - pad.left,
      right: right == null || (hasWidth && left != null)
          ? null
          : right - pad.right,
      top: top == null ? null : top - pad.top,
      bottom: bottom == null || (hasHeight && top != null)
          ? null
          : bottom - pad.bottom,
      child: box,
    );
  }

  Widget _withMarker(dom.Element element, ComputedStyle style, Widget child) {
    final marker = _markerText(element, style);
    if (marker == null) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            marker,
            style: textStyleFor(style),
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  String? _markerText(dom.Element element, ComputedStyle style) {
    final type = style.listStyleType;
    if (type == 'none') return null;
    if (type == 'disc') return '•';
    if (type == 'circle') return '◦';
    if (type == 'square') return '▪';
    if (type != 'decimal') return '•';

    final parent = element.parentElement;
    final siblings =
        parent?.children.where((c) => c.localName == 'li').toList() ?? const [];
    final index = siblings.indexWhere((c) => identical(c, element));
    var number = (index < 0 ? 0 : index) + 1;
    final start = int.tryParse(parent?.getAttribute('start') ?? '');
    if (start != null && parent?.localName == 'ol') {
      number += start - 1;
    }
    final value = int.tryParse(element.getAttribute('value') ?? '');
    if (value != null) number = value;
    return '$number.';
  }

  void _activateLabel(dom.Element label) {
    final forId = label.getAttribute('for');
    final target = forId != null
        ? label.ownerDocument.getElementById(forId)
        : label.querySelector('input, select, textarea, button');
    if (target == null) return;
    target.click(trusted: true);
    final isTextInput =
        target.localName == 'input' &&
        !const {
          'checkbox',
          'radio',
          'submit',
          'button',
          'reset',
          'image',
        }.contains(target.inputType);
    if (isTextInput || target.localName == 'textarea') {
      target.ownerDocument.requestFocus(target);
    }
  }

  Widget _interact(dom.Element element, ComputedStyle style, Widget child) {
    final isControl =
        element.localName == 'input' ||
        element.localName == 'textarea' ||
        element.localName == 'select';
    final isLink =
        element.localName == 'a' && element.getAttribute('href') != null;
    final isButton =
        element.localName == 'button' ||
        (element.localName == 'input' &&
            const {'submit', 'button', 'reset'}.contains(element.inputType));
    final isLabel = element.localName == 'label';
    final isSummary = element.localName == 'summary';
    final clickable =
        !isControl &&
        (isLink ||
            isButton ||
            isLabel ||
            isSummary ||
            element.hasEventListeners('click'));

    Widget result = child;
    if (clickable) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (isLabel) {
            _activateLabel(element);
            return;
          }
          element.click(
            trusted: true,
            detail: _pointerDetail(element, d.globalPosition, d.localPosition),
          );
        },
        child: result,
      );
    }
    if (element.hasEventListeners('contextmenu')) {
      void fire(Offset global) {
        element.dispatchEvent(
          dom.Event(
            'contextmenu',
            bubbles: true,
            cancelable: true,
            detail: {..._pointerDetail(element, global, null), 'button': 2},
          )..isTrusted = true,
        );
      }

      result = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => fire(d.globalPosition),
        onLongPressStart: (d) => fire(d.globalPosition),
        onDoubleTapDown: element.hasEventListeners('dblclick')
            ? (d) => element.dispatchEvent(
                dom.Event(
                  'dblclick',
                  bubbles: true,
                  cancelable: true,
                  detail: _pointerDetail(
                    element,
                    d.globalPosition,
                    d.localPosition,
                  ),
                )..isTrusted = true,
              )
            : null,
        child: result,
      );
    }
    if (styleEngine.usesActive) {
      final doc = element.ownerDocument;
      result = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          final current = doc.pressedElement;
          // The innermost element receives the event first.
          if (current == null || !element.contains(current))
            doc.pressedElement = element;
        },
        onPointerUp: (_) => doc.pressedElement = null,
        onPointerCancel: (_) => doc.pressedElement = null,
        child: result,
      );
    }
    final draggableAttr = element.getAttribute('draggable');
    final draggable =
        draggableAttr == 'true' ||
        (draggableAttr == null &&
            (element.localName == 'img' ||
                (isLink && element.hasEventListeners('dragstart'))));
    if (draggable) {
      final feedback = Opacity(
        opacity: 0.7,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child,
          ),
        ),
      );
      void started() {
        final id = _nextDragId++;
        dragSessionOf[element.ownerDocument] = id;
        element.dispatchEvent(
          dom.Event(
            'dragstart',
            bubbles: true,
            cancelable: true,
            detail: {'__drag': id},
          )..isTrusted = true,
        );
      }

      void ended() {
        final id = dragSessionOf[element.ownerDocument];
        element.dispatchEvent(
          dom.Event('dragend', bubbles: true, detail: {'__drag': ?id})
            ..isTrusted = true,
        );
      }

      final touch =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      result = touch
          ? LongPressDraggable<dom.Element>(
              data: element,
              feedback: feedback,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              childWhenDragging: Opacity(opacity: 0.4, child: result),
              onDragStarted: started,
              onDragEnd: (_) => ended(),
              child: result,
            )
          : Draggable<dom.Element>(
              data: element,
              feedback: feedback,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              childWhenDragging: Opacity(opacity: 0.4, child: result),
              onDragStarted: started,
              onDragEnd: (_) => ended(),
              child: result,
            );
    }
    final pointer = style.cursor == 'pointer' || clickable;
    if (styleEngine.mayHover(element) || pointer || style.cursor != 'auto') {
      final doc = element.ownerDocument;
      result = MouseRegion(
        cursor: _cursor(style.cursor, clickable),
        opaque: false,
        onEnter: styleEngine.usesHover
            ? (_) {
                // Scrolling moves content under a stationary pointer. Let
                // hover settle after the scroll instead of restyling the
                // document on every wheel frame.
                if (doc.layoutHost?.isScrolling ?? false) return;
                // Keep a deeper hovered descendant; otherwise this element
                // becomes the hovered one.
                final current = doc.hoverElement;
                if (current == null || !element.contains(current))
                  doc.hoverElement = element;
              }
            : null,
        onExit: styleEngine.usesHover
            ? (_) {
                if (doc.layoutHost?.isScrolling ?? false) return;
                final current = doc.hoverElement;
                if (current != null &&
                    (identical(current, element) ||
                        element.contains(current))) {
                  doc.hoverElement = element.parentElement;
                }
              }
            : null,
        child: result,
      );
    }

    final aria = element.getAttribute('aria-label');
    final heading = RegExp(r'^h[1-6]$').hasMatch(element.localName);
    final label =
        aria ??
        (element.localName == 'img' ? element.getAttribute('alt') : null);
    if (label != null || heading || isLink || isButton) {
      result = Semantics(
        container: false,
        label: label,
        header: heading,
        link: isLink,
        button: isButton,
        child: result,
      );
    }
    return result;
  }

  /// `clientX/Y` (viewport), `pageX/Y`, `offsetX/Y` and `screenX/Y` for
  /// pointer events.
  static Map<String, Object?> _pointerDetail(
    dom.Element element,
    Offset global,
    Offset? local,
  ) {
    final host = element.ownerDocument.layoutHost;
    final (cx, cy) =
        host?.toViewport(global.dx, global.dy) ?? (global.dx, global.dy);
    final box = host?.boxOf(element);
    return {
      'clientX': cx,
      'clientY': cy,
      'pageX': cx + (host?.scrollX ?? 0),
      'pageY': cy + (host?.scrollY ?? 0),
      'screenX': global.dx,
      'screenY': global.dy,
      'offsetX': local?.dx ?? (box == null ? 0 : cx - box.x),
      'offsetY': local?.dy ?? (box == null ? 0 : cy - box.y),
      'button': 0,
      'buttons': 0,
      'detail': 1,
      'pointerType': 'mouse',
    };
  }

  static MouseCursor _cursor(String cursor, bool clickable) => switch (cursor) {
    'pointer' => SystemMouseCursors.click,
    'text' => SystemMouseCursors.text,
    'move' => SystemMouseCursors.move,
    'not-allowed' => SystemMouseCursors.forbidden,
    'wait' => SystemMouseCursors.wait,
    'help' => SystemMouseCursors.help,
    'crosshair' => SystemMouseCursors.precise,
    'grab' => SystemMouseCursors.grab,
    'grabbing' => SystemMouseCursors.grabbing,
    'default' => SystemMouseCursors.basic,
    'progress' => SystemMouseCursors.progress,
    'zoom-in' => SystemMouseCursors.zoomIn,
    'zoom-out' => SystemMouseCursors.zoomOut,
    'copy' => SystemMouseCursors.copy,
    'none' => SystemMouseCursors.none,
    _ => clickable ? SystemMouseCursors.click : MouseCursor.defer,
  };

  /// Media and embedded content NativaX does not render: a sized box with
  /// the element's fallback text, so layout keeps its space.
  Widget _placeholder(dom.Element element, ComputedStyle style) {
    final w = double.tryParse(element.getAttribute('width') ?? '');
    final h = double.tryParse(element.getAttribute('height') ?? '');
    final (dw, dh) = switch (element.localName) {
      'audio' => (300.0, 54.0),
      'canvas' => (300.0, 150.0),
      'svg' => (300.0, 150.0),
      _ => (300.0, 150.0),
    };
    final label = switch (element.localName) {
      'video' => '▶ video',
      'audio' => '♪ audio',
      'canvas' => '',
      'svg' => '',
      _ => element.localName,
    };
    final textStyle = textStyleFor(
      style,
    ).copyWith(color: toColor(style.color).withValues(alpha: 0.6));
    final aspect = (w != null && h != null && h > 0) ? w / h : dw / dh;
    if (element.localName == 'audio') {
      // Audio controls keep their UA height; only the width shrinks.
      final bar = SizedBox(
        height: style.height == null ? (h ?? dh) : null,
        child: Center(child: Text(label, style: textStyle)),
      );
      return style.width != null
          ? bar
          : PreferredWidth(width: w ?? dw, child: bar);
    }
    Widget box = AspectRatio(
      aspectRatio: aspect,
      child: label.isEmpty
          ? const SizedBox.shrink()
          : Center(child: Text(label, style: textStyle)),
    );
    if (style.height != null) box = SizedBox.expand(child: box);
    // The intrinsic width is the width attribute (or the UA default); the
    // parent's constraints (max-width: 100%) shrink it.
    return style.width != null
        ? box
        : PreferredWidth(width: w ?? dw, child: box);
  }

  Widget _image(dom.Element element, ComputedStyle style) {
    final src = element.getAttribute('src') ?? '';
    final alt = element.getAttribute('alt') ?? '';
    ImageProvider? provider;
    if (src.isNotEmpty && imageResolver != null) {
      try {
        provider = imageResolver!(element, src);
      } catch (error) {
        onDiagnostic?.call('image resolver failed for "$src": $error');
      }
    }
    if (provider == null) {
      return Semantics(
        image: true,
        label: alt,
        child: alt.isEmpty
            ? const SizedBox.shrink()
            : Text(alt, style: textStyleFor(style)),
      );
    }
    Widget image = Image(
      image: provider,
      fit: _fit(style.objectFit),
      errorBuilder: (context, error, stack) => alt.isEmpty
          ? const SizedBox.shrink()
          : Text(alt, style: textStyleFor(style)),
    );
    // `width`/`height` attributes give the box its size and aspect ratio
    // before the image loads (as browsers map them to `aspect-ratio`).
    final w = double.tryParse(element.getAttribute('width') ?? '');
    final h = double.tryParse(element.getAttribute('height') ?? '');
    if (w != null && h != null && w > 0 && h > 0) {
      if (style.height == null)
        image = AspectRatio(aspectRatio: w / h, child: image);
      if (style.width == null) image = PreferredWidth(width: w, child: image);
    }
    return Semantics(image: true, label: alt, child: image);
  }

  Widget _input(dom.Element element, ComputedStyle style) {
    final accent = style.accentColor == null
        ? null
        : toColor(style.accentColor!);
    switch (element.inputType) {
      case 'hidden':
        return const SizedBox.shrink();
      case 'checkbox':
        return Material(
          type: MaterialType.transparency,
          child: Checkbox(
            value: element.checked,
            onChanged: element.disabled
                ? null
                : (_) => element.click(trusted: true),
            activeColor: accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        );
      case 'radio':
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: element.disabled ? null : () => element.click(trusted: true),
          child: CustomPaint(
            size: const Size(20, 20),
            painter: _RadioPainter(
              checked: element.checked,
              color: accent ?? const Color(0xff1a73e8),
              disabled: element.disabled,
            ),
          ),
        );
      case 'range':
        return PreferredWidth(
          width: 129,
          child: _RangeControl(element: element, style: style, accent: accent),
        );
      case 'color':
        return _ColorControl(element: element, style: style);
      case 'file':
        return _FileControl(element: element, style: style);
      case 'date':
      case 'time':
      case 'datetime-local':
      case 'month':
      case 'week':
        return _DateControl(element: element, style: style, builder: this);
      case 'submit':
      case 'button':
      case 'reset':
      case 'image':
        final label = element.hasAttribute('value')
            ? element.value
            : (element.inputType == 'reset'
                  ? 'Reset'
                  : (element.inputType == 'button' ? '' : 'Submit'));
        return Text(
          label,
          style: textStyleFor(style),
          textAlign: TextAlign.center,
        );
      default:
        // Text fields are as wide as `size` average characters (20 by
        // default), like browsers. When CSS sets an explicit width, let the
        // normal box constraints apply instead of forcing the intrinsic size.
        final child = _TextControl(
          element: element,
          style: style,
          multiline: false,
          builder: this,
        );
        if (style.width != null) return child;
        final size = int.tryParse(element.getAttribute('size') ?? '') ?? 20;
        return PreferredWidth(
          width: size * style.fontSize * 0.55,
          child: child,
        );
    }
  }

  /// Placeholder text style (`::placeholder` or the UA default).
  TextStyle placeholderStyle(dom.Element element, ComputedStyle style) {
    final ps = styleEngine.hasPseudoRules('placeholder')
        ? styleEngine.pseudoStyleOf(element, 'placeholder')
        : null;
    if (ps != null) return textStyleFor(ps);
    final base = textStyleFor(style);
    return base.copyWith(color: base.color?.withValues(alpha: 0.55));
  }

  Widget _select(dom.Element element, ComputedStyle style) {
    final options = element.options;
    if (options.isEmpty) {
      return Text(element.textContent, style: textStyleFor(style));
    }
    final size = int.tryParse(element.getAttribute('size') ?? '') ?? 0;
    if (element.hasAttribute('multiple') || size > 1) {
      return _ListBox(
        element: element,
        style: style,
        rows: size > 0 ? size : 4,
        optionStyle: (o) => styleEngine.styleOf(o),
      );
    }
    final values = <String>[];
    for (final option in options) {
      final value = option.optionValue;
      if (!values.contains(value)) values.add(value);
    }
    final selected = element.value;
    final text = textStyleFor(style);
    final color = toColor(style.color);
    final padRight = style.paddingOf('right');
    // Chromium reserves 4px before the text and 16px after it for the arrow,
    // which it centres 8px inside the padding box (ignoring author padding).
    final shift = (padRight.isPercent ? 0.0 : padRight.value);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        t,
        style: text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: DropdownButton<String>(
        value: values.contains(selected) ? selected : values.first,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        icon: ControlGlyph(
          kind: ControlGlyphKind.chevron,
          color: color,
          shift: shift,
        ),
        iconSize: 16,
        dropdownColor: style.backgroundColor.alpha == 255
            ? toColor(style.backgroundColor)
            : null,
        style: text,
        selectedItemBuilder: (context) => [
          for (final option in options)
            Align(
              alignment: Alignment.centerLeft,
              child: label(option.textContent.trim()),
            ),
        ],
        items: [
          for (final option in options)
            DropdownMenuItem<String>(
              value: option.optionValue,
              child: Text(option.textContent.trim(), style: text),
            ),
        ],
        onChanged: element.disabled
            ? null
            : (value) {
                if (value == null) return;
                element.value = value;
                element.userInteracted = true;
                element.dispatchEvent(
                  dom.Event('input', bubbles: true)..isTrusted = true,
                );
                element.dispatchEvent(
                  dom.Event('change', bubbles: true)..isTrusted = true,
                );
              },
      ),
    );
  }

  DecorationImage? _backgroundImage(dom.Element element, ComputedStyle style) {
    final url = style.backgroundImage;
    if (url == null || imageResolver == null) return null;
    try {
      final provider = imageResolver!(element, url);
      if (provider == null) return null;
      return DecorationImage(image: provider, fit: BoxFit.cover);
    } catch (error) {
      onDiagnostic?.call('background image failed for "$url": $error');
      return null;
    }
  }

  static bool _isRow(String direction) =>
      direction == 'row' || direction == 'row-reverse';

  static String _justify(String value) => switch (value) {
    'start' || 'left' => 'flex-start',
    'end' || 'right' => 'flex-end',
    _ => value,
  };

  static String _align(String value) => switch (value) {
    'start' || 'self-start' => 'flex-start',
    'end' || 'self-end' => 'flex-end',
    _ => value,
  };

  static BoxFit _fit(String value) => switch (value) {
    'contain' => BoxFit.contain,
    'cover' => BoxFit.cover,
    'none' => BoxFit.none,
    'scale-down' => BoxFit.scaleDown,
    _ => BoxFit.fill,
  };
}

class _InlineText extends StatefulWidget {
  const _InlineText({
    required this.parent,
    required this.style,
    required this.builder,
    required this.nodes,
  });

  final dom.Element parent;
  final ComputedStyle style;
  final _Builder builder;

  /// [dom.Node]s and [_Pseudo] boxes.
  final List<Object> nodes;

  @override
  State<_InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<_InlineText> {
  List<TapGestureRecognizer> _live = const [];

  /// Characters emitted so far in this build (placeholders count as one).
  int _offset = 0;

  void _add(List<InlineSpan> spans, InlineSpan span) {
    spans.add(span);
    _offset += span is TextSpan ? (span.text?.length ?? 0) : 1;
  }

  @override
  void dispose() {
    for (final recognizer in _live) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recognizers = <TapGestureRecognizer>[];
    final spans = <InlineSpan>[];
    final whitespace = _Whitespace(false);
    _offset = 0;
    for (final node in widget.nodes) {
      _visit(node, widget.style, spans, whitespace, recognizers);
    }
    // A line break that ends the block does not open an empty last line.
    _dropTrailingBreak(spans);

    final previous = _live;
    _live = recognizers;
    if (previous.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final recognizer in previous) {
          recognizer.dispose();
        }
      });
    }

    final ellipsis =
        widget.style.textOverflow == 'ellipsis' &&
        widget.style.overflowX != 'visible';
    final noWrap =
        widget.style.whiteSpace == 'pre' || widget.style.whiteSpace == 'nowrap';
    final text = Text.rich(
      TextSpan(children: spans),
      style: textStyleFor(widget.style),
      textAlign: textAlignFor(widget.style),
      softWrap: !noWrap,
      maxLines: ellipsis && noWrap ? 1 : null,
      overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.clip,
    );
    return LayoutProfile.enabled
        ? LayoutTimed(kind: 'text', child: text)
        : text;
  }

  void _visit(
    Object node,
    ComputedStyle style,
    List<InlineSpan> spans,
    _Whitespace whitespace,
    List<TapGestureRecognizer> recognizers,
  ) {
    if (node is _Pseudo) {
      final ps = node.style;
      if (ps.display == Display.inlineBlock ||
          ps.display == Display.inlineFlex ||
          ps.display == Display.inlineGrid) {
        _add(
          spans,
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: widget.builder.buildPseudoBox(node),
          ),
        );
        whitespace.afterSpace = false;
        return;
      }
      final (text, afterSpace) = processWhiteSpace(
        node.text,
        ps.whiteSpace,
        afterSpace: whitespace.afterSpace,
      );
      whitespace.afterSpace = afterSpace;
      if (text.isEmpty) return;
      _add(
        spans,
        TextSpan(
          text: applyTextTransform(text, ps.textTransform),
          style: textStyleFor(ps, inlineBackground: true),
        ),
      );
      return;
    }
    if (node is dom.Text) {
      final (text, afterSpace) = processWhiteSpace(
        node.data,
        style.whiteSpace,
        afterSpace: whitespace.afterSpace,
      );
      whitespace.afterSpace = afterSpace;
      if (text.isEmpty) return;
      // The block container paints its own background; only inline
      // ancestors contribute a text background.
      _add(
        spans,
        TextSpan(
          text: applyTextTransform(text, style.textTransform),
          style: textStyleFor(
            style,
            inlineBackground: !identical(style, widget.style),
          ),
        ),
      );
      return;
    }
    if (node is! dom.Element) return;
    final childStyle = widget.builder.styleEngine.styleOf(node);
    if (childStyle.display == Display.none || childStyle.position == 'fixed') {
      return;
    }
    switch (node.localName) {
      case 'head':
      case 'script':
      case 'style':
      case 'title':
      case 'meta':
      case 'link':
      case 'noscript':
        return;
      case 'br':
        _add(spans, const TextSpan(text: '\n'));
        whitespace.afterSpace = false;
        return;
      case 'img':
        _add(
          spans,
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: widget.builder._interact(
              node,
              childStyle,
              _ElementAnchor(
                element: node,
                child: widget.builder.buildBox(node, childStyle),
              ),
            ),
          ),
        );
        return;
      case 'input':
      case 'textarea':
      case 'select':
      case 'video':
      case 'audio':
      case 'canvas':
      case 'iframe':
      case 'svg':
        _add(
          spans,
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: widget.builder._interact(
              node,
              childStyle,
              _ElementAnchor(
                element: node,
                child: widget.builder.buildBox(node, childStyle),
              ),
            ),
          ),
        );
        return;
    }

    // vertical-align: super/sub raise or lower the inline run. Flutter has no
    // direct baseline shift on TextSpan, so render these as WidgetSpans with an
    // above/below-baseline placeholder alignment.
    final vaRaw = childStyle['vertical-align'];
    final va = vaRaw is Keyword ? vaRaw.name : vaRaw.toString();
    if (node.localName == 'sup' ||
        node.localName == 'sub' ||
        va == 'super' ||
        va == 'sub') {
      final innerSpans = <InlineSpan>[];
      final before = whitespace.afterSpace;
      whitespace.afterSpace = false;
      final start = _offset;
      for (final child in widget.builder.children(node)) {
        _visit(child, childStyle, innerSpans, whitespace, recognizers);
      }
      inlineRanges[node] = InlineRange(this, start, _offset);
      if (innerSpans.isNotEmpty) {
        final isSub = node.localName == 'sub' || va == 'sub';
        _add(
          spans,
          WidgetSpan(
            alignment: isSub
                ? PlaceholderAlignment.belowBaseline
                : PlaceholderAlignment.aboveBaseline,
            child: Text.rich(
              TextSpan(children: innerSpans),
              style: textStyleFor(childStyle, inlineBackground: true),
            ),
          ),
        );
      } else {
        whitespace.afterSpace = before;
      }
      whitespace.afterSpace = false;
      return;
    }

    if (childStyle.display == Display.inlineBlock ||
        childStyle.display == Display.inlineFlex ||
        childStyle.display == Display.inlineGrid ||
        node.localName == 'button' ||
        node.localName == 'label' ||
        _hasBoxDecoration(childStyle)) {
      _add(
        spans,
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: widget.builder._interact(
            node,
            childStyle,
            widget.builder.paintEffects(
              node,
              childStyle,
              _ElementAnchor(
                element: node,
                child: widget.builder.buildBox(node, childStyle),
              ),
            ),
          ),
        ),
      );
      whitespace.afterSpace = false;
      return;
    }

    final children = <InlineSpan>[];
    final before = whitespace.afterSpace;
    whitespace.afterSpace = false;
    final start = _offset;
    for (final child in widget.builder.children(node)) {
      _visit(child, childStyle, children, whitespace, recognizers);
    }
    inlineRanges[node] = InlineRange(this, start, _offset);
    if (children.isEmpty) {
      whitespace.afterSpace = before;
      return;
    }
    TapGestureRecognizer? recognizer;
    if (_isClickable(node)) {
      recognizer = TapGestureRecognizer()
        ..onTap = node.localName == 'label'
            ? () => widget.builder._activateLabel(node)
            : () => node.click(trusted: true);
      recognizers.add(recognizer);
    }
    spans.add(
      TextSpan(
        style: textStyleFor(childStyle, inlineBackground: true),
        recognizer: recognizer,
        children: children,
      ),
    );
  }

  /// Removes one final `\n` from the last text run, recursing into nested
  /// spans. Returns false when the last run is not text (a placeholder).
  static bool _dropTrailingBreak(List<InlineSpan> spans) {
    for (var i = spans.length - 1; i >= 0; i--) {
      final span = spans[i];
      if (span is! TextSpan) return false;
      final children = span.children;
      if (children != null && children.isNotEmpty) {
        final copy = List<InlineSpan>.of(children);
        if (_dropTrailingBreak(copy)) {
          spans[i] = TextSpan(
            text: span.text,
            style: span.style,
            recognizer: span.recognizer,
            semanticsLabel: span.semanticsLabel,
            children: copy,
          );
          return true;
        }
        if (copy.isNotEmpty && copy.last is! TextSpan) return false;
      }
      final text = span.text;
      if (text == null || text.isEmpty) continue;
      if (!text.endsWith('\n')) return false;
      spans[i] = TextSpan(
        text: text.substring(0, text.length - 1),
        style: span.style,
        recognizer: span.recognizer,
        semanticsLabel: span.semanticsLabel,
        children: span.children,
      );
      return true;
    }
    return false;
  }

  /// Inline elements with padding, borders or rounded backgrounds are drawn
  /// as atomic boxes (an approximation: they do not split across lines).
  static bool _hasBoxDecoration(ComputedStyle s) {
    for (final side in const ['top', 'right', 'bottom', 'left']) {
      if (s.borderWidthOf(side) > 0) return true;
      final p = s.paddingOf(side);
      if (p.value > 0 || p.calc != null) return true;
    }
    return s.boxShadows.isNotEmpty ||
        s.backgroundGradient != null ||
        s.transform != null;
  }

  static bool _isClickable(dom.Element element) =>
      element.hasEventListeners('click') ||
      element.localName == 'label' ||
      (element.localName == 'a' && element.getAttribute('href') != null);
}

class _Whitespace {
  _Whitespace(this.afterSpace);
  bool afterSpace;
}

class _RadioPainter extends CustomPainter {
  _RadioPainter({
    required this.checked,
    required this.color,
    required this.disabled,
  });
  final bool checked;
  final Color color;
  final bool disabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = disabled
          ? const Color(0x61000000)
          : (checked ? color : const Color(0xff767676));
    canvas.drawCircle(center, r, ring);
    if (checked)
      canvas.drawCircle(
        center,
        r * 0.55,
        Paint()..color = disabled ? const Color(0x61000000) : color,
      );
  }

  @override
  bool shouldRepaint(_RadioPainter old) =>
      old.checked != checked || old.color != color || old.disabled != disabled;
}

/// A generated `::before`/`::after` box.
class _Pseudo {
  _Pseudo(this.element, this.kind, this.style, this.text);
  final dom.Element element;
  final String kind;
  final ComputedStyle style;
  final String text;
}

void _fire(dom.Element element, String type) {
  element.dispatchEvent(dom.Event(type, bubbles: true)..isTrusted = true);
}

/// Sets a control's value from user input and fires `input` (and `change`
/// when [commit]).
void _userInput(dom.Element element, String value, {bool commit = false}) {
  element.userInteracted = true;
  if (element.value != value) {
    element.value = value;
    _fire(element, 'input');
  }
  if (commit) _fire(element, 'change');
}

class _TextControl extends StatefulWidget {
  const _TextControl({
    required this.element,
    required this.style,
    required this.multiline,
    required this.builder,
  });

  final dom.Element element;
  final ComputedStyle style;
  final bool multiline;
  final _Builder builder;

  @override
  State<_TextControl> createState() => _TextControlState();
}

class _TextControlState extends State<_TextControl> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  String _committed = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.element.value);
    _committed = widget.element.value;
    _focus = FocusNode()..addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant _TextControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.element.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.element.value,
        selection: TextSelection.collapsed(offset: widget.element.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    final element = widget.element;
    if (_focus.hasFocus) {
      element.ownerDocument.setFocusedElement(element);
    } else {
      if (identical(element.ownerDocument.activeElement, element)) {
        element.ownerDocument.setFocusedElement(null);
      }
      if (_committed != element.value) {
        _committed = element.value;
        _fire(element, 'change');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = textStyleFor(widget.style);
    final element = widget.element;
    final maxLength = int.tryParse(element.getAttribute('maxlength') ?? '');
    final rows = int.tryParse(element.getAttribute('rows') ?? '') ?? 2;
    final label =
        element.getAttribute('aria-label') ??
        element.getAttribute('placeholder') ??
        element.getAttribute('name');
    return Semantics(
      textField: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          style: style,
          cursorColor: style.color,
          enabled: !element.disabled,
          readOnly: element.hasAttribute('readonly'),
          autofocus: element.hasAttribute('autofocus'),
          obscureText: !widget.multiline && element.inputType == 'password',
          maxLines: widget.multiline ? null : 1,
          minLines: widget.multiline ? rows : null,
          maxLength: maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          keyboardType: widget.multiline
              ? TextInputType.multiline
              : switch (element.inputType) {
                  'email' => TextInputType.emailAddress,
                  'number' => const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  'tel' => TextInputType.phone,
                  'url' => TextInputType.url,
                  _ => TextInputType.text,
                },
          decoration: InputDecoration.collapsed(
            hintText: element.getAttribute('placeholder'),
            hintStyle: widget.builder.placeholderStyle(element, widget.style),
            border: InputBorder.none,
          ).copyWith(counterText: ''),
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) => null,
          onChanged: (value) => _userInput(element, value),
          onSubmitted: (_) {
            _committed = element.value;
            _fire(element, 'change');
            // Enter in a single-line field submits its form (implicit
            // submission).
            if (!widget.multiline) {
              final form = element.closest('form');
              if (form != null) {
                final submitter = form.querySelector(
                  'button:not([type=button]):not([type=reset]), input[type=submit]',
                );
                if (submitter != null) {
                  submitter.click(trusted: true);
                } else {
                  form.requestSubmit(trusted: true);
                }
              }
            }
          },
        ),
      ),
    );
  }
}

class _RangeControl extends StatelessWidget {
  const _RangeControl({
    required this.element,
    required this.style,
    this.accent,
  });
  final dom.Element element;
  final ComputedStyle style;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final min = double.tryParse(element.getAttribute('min') ?? '') ?? 0;
    var max = double.tryParse(element.getAttribute('max') ?? '') ?? 100;
    if (max <= min) max = min + 1;
    final stepAttr = element.getAttribute('step');
    final step = stepAttr == 'any'
        ? null
        : (double.tryParse(stepAttr ?? '') ?? 1);
    final value = (double.tryParse(element.value) ?? (min + max) / 2).clamp(
      min,
      max,
    );
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return SizedBox(
      height: 24,
      child: Material(
        type: MaterialType.transparency,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value.toDouble(),
            min: min,
            max: max,
            divisions: step == null || step <= 0
                ? null
                : ((max - min) / step).round().clamp(1, 10000),
            activeColor: accent,
            onChanged: element.disabled
                ? null
                : (v) => _userInput(element, fmt(v)),
            onChangeEnd: element.disabled
                ? null
                : (v) => _fire(element, 'change'),
          ),
        ),
      ),
    );
  }
}

class _ColorControl extends StatelessWidget {
  const _ColorControl({required this.element, required this.style});
  final dom.Element element;
  final ComputedStyle style;

  static Color? parse(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xff000000 | v);
  }

  static const _palette = [
    0x000000,
    0x5a6683,
    0xffffff,
    0xb3261e,
    0xff9a92,
    0xe65100,
    0xf5c75a,
    0x8a5a00,
    0x0b7d45,
    0x5be3a0,
    0x00838f,
    0x3366ff,
    0x3b5bff,
    0x7c93ff,
    0x2237c9,
    0x8a4dff,
    0xc2185b,
    0x795548,
  ];

  @override
  Widget build(BuildContext context) {
    final color = parse(element.value) ?? const Color(0xff000000);
    return GestureDetector(
      onTap: element.disabled
          ? null
          : () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (context) => SimpleDialog(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in _palette)
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(c),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Color(0xff000000 | c),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0x33000000),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (picked == null) return;
              _userInput(
                element,
                '#${picked.toRadixString(16).padLeft(6, '0')}',
                commit: true,
              );
            },
      child: Container(height: 24, color: color),
    );
  }
}

class _FileControl extends StatelessWidget {
  const _FileControl({required this.element, required this.style});
  final dom.Element element;
  final ComputedStyle style;

  @override
  Widget build(BuildContext context) {
    final text = textStyleFor(style);
    final multiple = element.hasAttribute('multiple');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xffefefef),
            border: Border.all(color: const Color(0xff767676)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            multiple ? 'Choose Files' : 'Choose File',
            style: text.copyWith(
              color: const Color(0xff000000),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            multiple ? 'No files chosen' : 'No file chosen',
            style: text,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DateControl extends StatelessWidget {
  const _DateControl({
    required this.element,
    required this.style,
    required this.builder,
  });
  final dom.Element element;
  final ComputedStyle style;
  final _Builder builder;

  String get _hint => switch (element.inputType) {
    'date' => 'mm/dd/yyyy',
    'time' => '--:-- --',
    'datetime-local' => 'mm/dd/yyyy, --:-- --',
    'month' => '-------- ----',
    _ => 'Week --, ----',
  };

  String _display(String v) {
    if (v.isEmpty) return '';
    final type = element.inputType;
    String two(int n) => n.toString().padLeft(2, '0');
    String time(String t) {
      final parts = t.split(':');
      final h = int.tryParse(parts.first) ?? 0;
      final m = parts.length > 1 ? parts[1] : '00';
      return '${two(h % 12 == 0 ? 12 : h % 12)}:$m ${h < 12 ? 'AM' : 'PM'}';
    }

    if (type == 'time') return time(v);
    final date = DateTime.tryParse(
      type == 'month' ? '$v-01' : v.split('T').first,
    );
    if (type == 'month') {
      const names = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return date == null ? v : '${names[date.month - 1]} ${date.year}';
    }
    if (date == null) return v;
    final d = '${two(date.month)}/${two(date.day)}/${date.year}';
    if (type == 'datetime-local' && v.contains('T'))
      return '$d, ${time(v.split('T').last)}';
    return d;
  }

  Future<void> _pick(BuildContext context) async {
    final type = element.inputType;
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final current = DateTime.tryParse(element.value.split('T').first) ?? now;
    if (type == 'time') {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now),
      );
      if (t != null)
        _userInput(element, '${two(t.hour)}:${two(t.minute)}', commit: true);
      return;
    }
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDatePickerMode: type == 'month'
          ? DatePickerMode.year
          : DatePickerMode.day,
    );
    if (d == null || !context.mounted) return;
    final date =
        '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
    switch (type) {
      case 'month':
        _userInput(element, date.substring(0, 7), commit: true);
      case 'week':
        final week =
            ((d.difference(DateTime(d.year)).inDays +
                    DateTime(d.year).weekday -
                    1) ~/
                7) +
            1;
        _userInput(element, '${d.year}-W${two(week)}', commit: true);
      case 'datetime-local':
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(now),
        );
        if (t != null)
          _userInput(
            element,
            '${date}T${two(t.hour)}:${two(t.minute)}',
            commit: true,
          );
      default:
        _userInput(element, date, commit: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = textStyleFor(style);
    final value = _display(element.value);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: element.disabled || element.hasAttribute('readonly')
          ? null
          : () => _pick(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value.isEmpty ? _hint : value,
              style: text,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
          ControlGlyph(
            kind: element.inputType == 'time'
                ? ControlGlyphKind.clock
                : ControlGlyphKind.calendar,
            color: text.color ?? const Color(0xff000000),
          ),
        ],
      ),
    );
  }
}

class _ListBox extends StatelessWidget {
  const _ListBox({
    required this.element,
    required this.style,
    required this.rows,
    required this.optionStyle,
  });
  final dom.Element element;
  final ComputedStyle style;
  final int rows;
  final ComputedStyle Function(dom.Element option) optionStyle;

  /// Browsers size list box rows from the font's normal line height plus the
  /// option's padding (UA: `padding: 0 2px 1px`), not from `line-height`.
  static double _normalLineHeight(TextStyle text) {
    final painter = TextPainter(
      text: TextSpan(text: 'Mg', style: text),
      textDirection: TextDirection.ltr,
    )..layout();
    final h = painter.height;
    painter.dispose();
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final options = element.options;
    final multiple = element.hasAttribute('multiple');
    double rowHeight(dom.Element o, TextStyle text) {
      final os = optionStyle(o);
      double px(String side) {
        final p = os.paddingOf(side);
        return p.isPercent ? 0 : p.value;
      }

      return _normalLineHeight(text) + px('top') + px('bottom');
    }

    final base = optionStyle(options.isEmpty ? element : options.first);
    final baseText = textStyleFor(base, normalLineHeight: true);
    final row = rowHeight(options.isEmpty ? element : options.first, baseText);
    return SizedBox(
      height: row * rows,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final o in options)
              Builder(
                builder: (context) {
                  final os = optionStyle(o);
                  final text = textStyleFor(os, normalLineHeight: true);
                  double px(String side) {
                    final p = os.paddingOf(side);
                    return p.isPercent ? 0 : p.value;
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: element.disabled || o.disabled
                        ? null
                        : () {
                            if (multiple) {
                              o.optionSelected = !o.optionSelected;
                            } else {
                              element.value = o.optionValue;
                            }
                            element.userInteracted = true;
                            _fire(element, 'input');
                            _fire(element, 'change');
                          },
                    child: Container(
                      height: rowHeight(o, text),
                      padding: EdgeInsets.fromLTRB(
                        px('left'),
                        px('top'),
                        px('right'),
                        px('bottom'),
                      ),
                      alignment: Alignment.centerLeft,
                      color: o.optionSelected ? const Color(0xffcedbff) : null,
                      child: Text(
                        o.textContent.trim(),
                        style: text,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
