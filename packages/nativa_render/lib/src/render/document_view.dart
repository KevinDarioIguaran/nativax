import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:nativa_css/nativa_css.dart' hide MediaQuery;
import 'package:nativa_dom/nativa_dom.dart' as dom;

import 'canvas2d.dart';
import 'node_view.dart';
import 'render_types.dart';
import '../layout/virtualization.dart';
import '../layout/layout_profile.dart';
import 'draw_trace.dart';
import 'widget_cache.dart';

/// Renders a NativaX [dom.Document] with Flutter widgets.
///
/// The view owns the mutation subscription and batches style invalidation in a
/// microtask. Phase 1 rebuilds the whole tree on every batch; the per-owner
/// `ValueNotifier` optimization is deliberately left for the next iteration.
class NativaXDocumentView extends StatefulWidget {
  const NativaXDocumentView({
    super.key,
    required this.document,
    required this.styleEngine,
    this.imageResolver,
    this.onDiagnostic,
    this.onNavigate,
    this.onSubmit,
    this.padding = EdgeInsets.zero,
  });

  final dom.Document document;
  final StyleEngine styleEngine;
  final NativaXImageResolver? imageResolver;

  /// Receives approximations (for example dashed borders drawn solid). The
  /// view de-duplicates messages within one mount.
  final void Function(String message)? onDiagnostic;
  final void Function(String href, dom.Element anchor)? onNavigate;
  final void Function(dom.Element form)? onSubmit;
  final EdgeInsets padding;

  @override
  State<NativaXDocumentView> createState() => _NativaXDocumentViewState();
}

class _NativaXDocumentViewState extends State<NativaXDocumentView> implements dom.LayoutHost {
  final ValueNotifier<int> _revision = ValueNotifier(0);
  final ScrollController _scroll = ScrollController();
  final Set<String> _reported = {};
  bool _scheduled = false;
  bool _disposed = false;
  bool _diagnosedBuild = false;
  TimingsCallback? _drawTimings;
  void Function(String href, dom.Element anchor)? _previousNavigate;
  void Function(dom.Element form)? _previousSubmit;
  void Function(dom.Element? element)? _previousFocusRequest;

  final GlobalKey _rootKey = GlobalKey();
  final CanvasRegistry _canvases = CanvasRegistry();
  final NativaXWidgetCache _widgetCache = NativaXWidgetCache();
  double? _lastBuildWidth;
  double? _lastBuildHeight;
  final FocusNode _keyboard = FocusNode(debugLabel: 'nativax.document');
  double _lastScroll = 0;
  bool _scrollEventScheduled = false;

  @override
  void initState() {
    super.initState();
    // Virtualized subtrees are styled on demand; computing the whole document
    // up front would defeat the display-lock equivalent.
    widget.styleEngine.lazySubtrees = true;
    LayoutProfile.reset();
    if (NativaXDrawTrace.enabled) {
      NativaXDrawTrace.start();
      _drawTimings = _onDrawTimings;
      SchedulerBinding.instance.addTimingsCallback(_drawTimings!);
    }
    widget.document.layoutHost = this;
    widget.document.canvasHost = _canvases;
    _scroll.addListener(_onScroll);
    widget.document.addMutationListener(_onMutation);
    _previousNavigate = widget.document.onNavigate;
    _previousSubmit = widget.document.onSubmit;
    _previousFocusRequest = widget.document.onFocusRequest;
    widget.document.onFocusRequest = _onFocusRequest;
    if (widget.onNavigate != null) widget.document.onNavigate = widget.onNavigate;
    if (widget.onSubmit != null) widget.document.onSubmit = widget.onSubmit;
  }

  /// `element.focus()` from script may target an element that is currently
  /// outside the materialized window. Blink activates the display lock for
  /// script focus; here we materialize the slot and scroll it into view.
  void _onFocusRequest(dom.Element? element) {
    _previousFocusRequest?.call(element);
    if (element == null) return;
    final owner = virtualOwner[element];
    if (owner == null || owner.isMaterialized(element)) return;
    owner.ensureBuilt(element);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollIntoView(element);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widgetCache.clear();
  }

  @override
  void didUpdateWidget(covariant NativaXDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      oldWidget.document.removeMutationListener(_onMutation);
      if (identical(oldWidget.document.layoutHost, this)) oldWidget.document.layoutHost = null;
      widget.document.addMutationListener(_onMutation);
      widget.document.layoutHost = this;
      widget.styleEngine.lazySubtrees = true;
      widget.document.onFocusRequest = _onFocusRequest;
      _widgetCache.clear();
    }
    if (oldWidget.onNavigate != widget.onNavigate) {
      widget.document.onNavigate = widget.onNavigate ?? _previousNavigate;
    }
    if (oldWidget.onSubmit != widget.onSubmit) {
      widget.document.onSubmit = widget.onSubmit ?? _previousSubmit;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.document.removeMutationListener(_onMutation);
    if (identical(widget.document.layoutHost, this)) widget.document.layoutHost = null;
    if (identical(widget.document.canvasHost, _canvases)) widget.document.canvasHost = null;
    _canvases.dispose();
    _keyboard.dispose();
    _widgetCache.clear();
    if (widget.onNavigate != null) {
      widget.document.onNavigate = _previousNavigate;
    }
    if (widget.onSubmit != null) {
      widget.document.onSubmit = _previousSubmit;
    }
    if (identical(widget.document.onFocusRequest, _onFocusRequest)) {
      widget.document.onFocusRequest = _previousFocusRequest;
    }
    if (_drawTimings != null) {
      SchedulerBinding.instance.removeTimingsCallback(_drawTimings!);
    }
    _revision.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMutation(dom.MutationRecord record) {
    final target = record.target;
    final element = target is dom.Element ? target : target.parentElement;
    if (element != null) {
      switch (record.type) {
        case dom.MutationType.childList:
          _widgetCache.invalidateSubtree(element);
          for (final n in record.removedNodes) {
            _widgetCache.remove(n);
          }
        case dom.MutationType.attributes:
          final name = (record.name ?? '').toLowerCase();
          if (name == 'class' || name == 'id' || name == 'style') {
            _widgetCache.invalidateSubtree(element);
          } else {
            _widgetCache.invalidatePath(element);
          }
        case dom.MutationType.property:
          _widgetCache.invalidateSubtree(element);
        case dom.MutationType.characterData:
          _widgetCache.invalidatePath(element);
      }
    }
    if (NativaXDrawTrace.enabled) {
      final target = record.target;
      final element = target is dom.Element ? target : target.parentElement;
      NativaXDrawTrace.log(
          'MUTATION ${record.type.name} '
          '${element == null ? '?' : NativaXDrawTrace.describe(element)} '
          'name=${record.name ?? ''}');
    }
    if (_shouldDeferMutation(record)) {
      final target = record.target;
      final element = target is dom.Element ? target : target.parentElement;
      if (element != null) widget.styleEngine.invalidateDeferred(element);
    } else {
      widget.styleEngine.handleMutation(record);
    }
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  /// Mutations inside a virtualized, non-materialized element can update only
  /// the DOM and drop the style cache. The element is computed when it enters
  /// the viewport.
  ///
  /// Selectors whose subject can be affected by a sibling (`class`, `id`,
  /// `hidden`, inline `style`, child lists) stay eager: they may change the
  /// container or a sibling that is visible.
  bool _shouldDeferMutation(dom.MutationRecord record) {
    if (record.type == dom.MutationType.childList) return false;
    final target = record.target;
    final element = target is dom.Element ? target : target.parentElement;
    if (element == null) return false;
    final owner = virtualOwner[element];
    if (owner == null || owner.hasBox(element)) return false;
    if (record.type == dom.MutationType.attributes) {
      const eager = {'class', 'id', 'hidden', 'style'};
      if (eager.contains(record.name)) return false;
    }
    return true;
  }

  void _flush() {
    _scheduled = false;
    if (_disposed || !mounted) return;
    final watch = Stopwatch()..start();
    final changed = widget.styleEngine.recompute();
    watch.stop();
    for (final e in changed) {
      _widgetCache.invalidateSubtree(e);
    }
    NativaXRenderProfile.log(
      'FLUSH style=${watch.elapsedMilliseconds}ms changed=${changed.length} '
      'computes=${widget.styleEngine.computeCount} '
      'subtreePasses=${widget.styleEngine.subtreePasses}',
    );
    NativaXDrawTrace.log(
        'FLUSH_STYLE ms=${watch.elapsedMilliseconds} changed=${changed.length} '
        'computes=${widget.styleEngine.computeCount} '
        'subtreePasses=${widget.styleEngine.subtreePasses}');
    if (NativaXDrawTrace.enabled) {
      NativaXDrawTrace.log(
          'FLUSH style=${watch.elapsedMilliseconds}ms changed=${changed.length} '
          'computes=${widget.styleEngine.computeCount} '
          'roots=${widget.styleEngine.dirtyRootCount}');
    }
    setState(() {});
  }

  // --- LayoutHost ---------------------------------------------------------------

  RenderBox? get _root {
    final r = _rootKey.currentContext?.findRenderObject();
    return r is RenderBox && r.attached && r.hasSize ? r : null;
  }

  @override
  dom.ElementBox? boxOf(dom.Element element) {
    final root = _root;
    if (root == null) return null;
    final document = widget.document;
    if (identical(element, document.documentElement)) {
      final w = root.size.width, h = root.size.height;
      return dom.ElementBox(
        x: 0,
        y: -scrollY,
        width: w,
        height: documentHeight,
        clientWidth: w,
        clientHeight: h,
        scrollWidth: w,
        scrollHeight: documentHeight,
        scrollTop: scrollY,
      );
    }
    if (elementRenderBoxes[element] == null) {
      final virtual = virtualOwner[element];
      if (virtual != null) {
        final estimated = virtual.estimatedBoxOf(element);
        if (estimated != null) return estimated;
      }
      final inline = _inlineBox(element, root);
      if (inline != null) return inline;
    }
    RenderBox? box;
    for (dom.Element? e = element; e != null; e = e.parentElement) {
      box = elementRenderBoxes[e];
      if (box != null) break;
      // Inline elements without their own box report their container's.
      final style = widget.styleEngine.styleOf(e);
      if (style.display == Display.none) return null;
    }
    if (box == null || !box.attached || !box.hasSize) return null;
    final Offset origin;
    final Rect bounds;
    try {
      origin = box.localToGlobal(Offset.zero, ancestor: root);
      // getBoundingClientRect reports the transformed border box's bounds.
      bounds = MatrixUtils.transformRect(box.getTransformTo(root), Offset.zero & box.size);
    } catch (_) {
      return null;
    }
    final size = box.size;
    final style = widget.styleEngine.styleOf(element);
    double bw(String side) => style.borderWidthOf(side);
    final clientW = size.width - bw('left') - bw('right');
    final clientH = size.height - bw('top') - bw('bottom');
    return dom.ElementBox(
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
      offsetWidth: size.width,
      offsetHeight: size.height,
      offsetX: origin.dx + scrollX,
      offsetY: origin.dy + scrollY,
      clientWidth: clientW < 0 ? 0 : clientW,
      clientHeight: clientH < 0 ? 0 : clientH,
      scrollWidth: size.width,
      scrollHeight: size.height,
    );
  }

  /// The union of an inline element's line boxes (the content area, as
  /// browsers report it), or a zero-width caret box when it is empty.
  dom.ElementBox? _inlineBox(dom.Element element, RenderBox root) {
    final range = inlineRanges[element];
    final paragraph = range?.paragraph;
    if (range == null || paragraph == null || !paragraph.attached || !paragraph.hasSize) return null;
    if (widget.styleEngine.styleOf(element).display == Display.none) return null;
    final Offset origin;
    try {
      origin = paragraph.localToGlobal(Offset.zero, ancestor: root);
    } catch (_) {
      return null;
    }
    Rect? rect;
    if (range.end > range.start) {
      for (final b in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: ui.BoxHeightStyle.tight,
      )) {
        final r = b.toRect();
        rect = rect == null ? r : rect.expandToInclude(r);
      }
    }
    if (rect == null) {
      final caret = paragraph.getOffsetForCaret(TextPosition(offset: range.start), Rect.zero);
      final height = paragraph.getFullHeightForCaret(TextPosition(offset: range.start));
      rect = Rect.fromLTWH(caret.dx, caret.dy, 0, height);
    }
    final r = rect.shift(origin);
    return dom.ElementBox(
      x: r.left,
      y: r.top,
      width: r.width,
      height: r.height,
      offsetX: r.left + scrollX,
      offsetY: r.top + scrollY,
      clientWidth: 0,
      clientHeight: 0,
      scrollWidth: 0,
      scrollHeight: 0,
    );
  }

  @override
  (double, double) toViewport(double globalX, double globalY) {
    final root = _root;
    if (root == null) return (globalX, globalY);
    final p = root.globalToLocal(Offset(globalX, globalY));
    return (p.dx, p.dy);
  }

  @override
  double get scrollX => 0;

  @override
  double get scrollY => _scroll.hasClients ? _scroll.offset : 0;

  @override
  double get viewportWidth => _root?.size.width ?? 0;

  @override
  double get viewportHeight => _root?.size.height ?? 0;

  @override
  double get documentHeight {
    if (!_scroll.hasClients) return viewportHeight;
    final p = _scroll.position;
    return p.maxScrollExtent + p.viewportDimension;
  }

  @override
  void scrollTo(double x, double y, {bool smooth = false}) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final target = y.clamp(p.minScrollExtent, p.maxScrollExtent).toDouble();
    if (smooth) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  void scrollIntoView(dom.Element element, {bool smooth = false, String block = 'start'}) {
    // Layout may be pending (the script just changed the DOM). A virtualized
    // target is materialized first, like Blink's display-lock activation for
    // scrollIntoView, and the real box is used on the next frame.
    var attempts = 0;
    void run() {
      final owner = virtualOwner[element];
      if (owner != null && !owner.hasBox(element) && attempts++ < 8) {
        owner.ensureBuilt(element);
        WidgetsBinding.instance.addPostFrameCallback((_) => run());
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      final b = boxOf(element);
      if (b == null) return;
      scrollTo(0, b.offsetY - _scrollPaddingTop(), smooth: smooth);
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
      WidgetsBinding.instance.scheduleFrame();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    }
  }

  double _scrollPaddingTop() {
    final root = widget.document.documentElement;
    if (root == null) return 0;
    final v = widget.styleEngine.styleOf(root)['scroll-padding-top'];
    final text = v.toString().trim();
    final m = RegExp(r'^([\d.]+)(px|rem|em)$').firstMatch(text);
    if (m == null) return 0;
    final n = double.parse(m[1]!);
    return m[2] == 'px' ? n : n * widget.styleEngine.styleOf(root).fontSize;
  }

  void _onScroll() {
    if (_scrollEventScheduled || (_scroll.offset - _lastScroll).abs() < 0.5) return;
    _scrollEventScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollEventScheduled = false;
      if (_disposed || !_scroll.hasClients) return;
      _lastScroll = _scroll.offset;
      widget.document.dispatchEvent(dom.Event('scroll', bubbles: true)..isTrusted = true);
    });
  }

  // --- drag and drop ---------------------------------------------------------------

  dom.Element? _dragOver;

  Map<String, Object?> _dragDetail(Offset global) {
    final (x, y) = toViewport(global.dx, global.dy);
    final id = dragSessionOf[widget.document];
    return {'__drag': ?id, 'clientX': x, 'clientY': y, 'pageX': x, 'pageY': y + scrollY};
  }

  /// One target for the whole document: finds the element under the pointer
  /// and dispatches dragenter/dragover/dragleave/drop to it (they bubble, so
  /// delegated listeners work).
  Widget _dropTarget(Widget child) => DragTarget<dom.Element>(
    onWillAcceptWithDetails: (_) => true,
    onMove: (d) {
      final target = elementAtGlobal(context, d.offset);
      if (!identical(target, _dragOver)) {
        _dragOver?.dispatchEvent(
          dom.Event('dragleave', bubbles: true, detail: _dragDetail(d.offset))..isTrusted = true,
        );
        target?.dispatchEvent(
          dom.Event('dragenter', bubbles: true, cancelable: true, detail: _dragDetail(d.offset))..isTrusted = true,
        );
        _dragOver = target;
      }
      target?.dispatchEvent(
        dom.Event('dragover', bubbles: true, cancelable: true, detail: _dragDetail(d.offset))..isTrusted = true,
      );
    },
    onLeave: (_) {
      _dragOver?.dispatchEvent(dom.Event('dragleave', bubbles: true)..isTrusted = true);
      _dragOver = null;
    },
    onAcceptWithDetails: (d) {
      final target = elementAtGlobal(context, d.offset) ?? _dragOver;
      _dragOver = null;
      target?.dispatchEvent(
        dom.Event('drop', bubbles: true, cancelable: true, detail: _dragDetail(d.offset))..isTrusted = true,
      );
    },
    builder: (context, candidates, rejected) => child,
  );

  // --- keyboard ------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final document = widget.document;
    final type = event is KeyUpEvent ? 'keyup' : 'keydown';
    final target = document.focusedElement ?? document.body;
    if (target == null) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    var key = event.character ?? event.logicalKey.keyLabel;
    if (event.logicalKey == LogicalKeyboardKey.space) key = ' ';
    final named = _keyNames[event.logicalKey];
    if (named != null) key = named;
    final ev = dom.Event(
      type,
      bubbles: true,
      cancelable: true,
      detail: {
        'key': key,
        'code': event.physicalKey.debugName?.replaceAll(' ', '') ?? '',
        'ctrlKey': keys.isControlPressed,
        'shiftKey': keys.isShiftPressed,
        'altKey': keys.isAltPressed,
        'metaKey': keys.isMetaPressed,
        'repeat': event is KeyRepeatEvent,
        'keyCode': event.logicalKey.keyId < 0x110000 ? event.logicalKey.keyId : 0,
      },
    )..isTrusted = true;
    final notCanceled = target.dispatchEvent(ev);
    if (type == 'keydown' &&
        notCanceled &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        document.modalElements.isNotEmpty) {
      document.modalElements.last.requestCancel();
      return KeyEventResult.handled;
    }
    return notCanceled ? KeyEventResult.ignored : KeyEventResult.handled;
  }

  static final Map<LogicalKeyboardKey, String> _keyNames = {
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.arrowUp: 'ArrowUp',
    LogicalKeyboardKey.arrowDown: 'ArrowDown',
    LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
    LogicalKeyboardKey.arrowRight: 'ArrowRight',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PageUp',
    LogicalKeyboardKey.pageDown: 'PageDown',
    LogicalKeyboardKey.shiftLeft: 'Shift',
    LogicalKeyboardKey.shiftRight: 'Shift',
    LogicalKeyboardKey.controlLeft: 'Control',
    LogicalKeyboardKey.controlRight: 'Control',
    LogicalKeyboardKey.altLeft: 'Alt',
    LogicalKeyboardKey.altRight: 'Alt',
    LogicalKeyboardKey.metaLeft: 'Meta',
    LogicalKeyboardKey.metaRight: 'Meta',
    LogicalKeyboardKey.f10: 'F10',
    LogicalKeyboardKey.contextMenu: 'ContextMenu',
  };

  void _diagnose(String message) {
    if (_reported.add(message)) widget.onDiagnostic?.call(message);
  }

  int _lastBuildCount = 0;
  int _lastComputeCount = 0;
  int _lastStyleUs = 0;

  void _onDrawTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final builds = NativeXBuildStats.elementBuilds;
      final computes = widget.styleEngine.computeCount;
      final styleUs = widget.styleEngine.metricsOwnUs;
      NativaXDrawTrace.log(
          'FRAME total=${t.totalSpan.inMilliseconds}ms '
          'build=${t.buildDuration.inMilliseconds}ms '
          'raster=${t.rasterDuration.inMilliseconds}ms '
          'builds=${builds - _lastBuildCount} '
          'computes=${computes - _lastComputeCount} '
          'styleMs=${((styleUs - _lastStyleUs) / 1000).toStringAsFixed(1)}');
      NativaXDrawTrace.flushSlowest();
      _lastBuildCount = builds;
      _lastComputeCount = computes;
      _lastStyleUs = styleUs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildWatch = Stopwatch()..start();
    NativaXDrawTrace.log(
        'BUILD_START nodes=${widget.document.querySelectorAll('*').length} '
        'cache=${_widgetCache.length} hits=${_widgetCache.hits} '
        'misses=${_widgetCache.misses}');
    final mediaQuery = MediaQuery.maybeOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;

    // CSS text starts from a neutral base: the host's DefaultTextStyle
    // (Material adds tracking and a 1.43 line height) must not leak into the
    // page, where `normal` means the font's own metrics.
    return DefaultTextStyle(
      style: const TextStyle(inherit: false, color: Color(0xff000000), fontSize: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : mediaQuery?.size.width ?? 800;
          final height = constraints.maxHeight.isFinite ? constraints.maxHeight : mediaQuery?.size.height ?? 600;
          if (_lastBuildWidth != width || _lastBuildHeight != height) {
            _lastBuildWidth = width;
            _lastBuildHeight = height;
            _widgetCache.clear();
          }
          final media = MediaContext(
            width: width,
            height: height,
            devicePixelRatio: mediaQuery?.devicePixelRatio ?? 1,
            prefersDark: mediaQuery?.platformBrightness == Brightness.dark,
            prefersReducedMotion: mediaQuery?.disableAnimations ?? false,
          );
          if (widget.styleEngine.media != media) {
            widget.styleEngine.media = media;
            widget.styleEngine.recompute();
          }

          final document = widget.document;
          final body = document.body;
          final root = document.documentElement;
          final canvas = _canvasColor(body, root);

          final content = body == null
              ? const SizedBox.shrink()
              : NativaXViewportScope(
                  controller: _scroll,
                  viewportHeight: height,
                  viewportWidth: width,
                  child: Padding(
                    padding: widget.padding,
                    child: SizedBox(
                      width: width,
                      child: NativeXNodeView(
                        element: body,
                        isRoot: true,
                        styleEngine: widget.styleEngine,
                        imageResolver: widget.imageResolver,
                        onDiagnostic: _diagnose,
                        cache: _widgetCache,
                      ),
                    ),
                  ),
                );

          final layers = <Widget>[
            for (final e in _fixedElements(body))
              NativeXLayerView(
                element: e,
                styleEngine: widget.styleEngine,
                modal: false,
                imageResolver: widget.imageResolver,
                onDiagnostic: _diagnose,
                cache: _widgetCache,
              ),
            for (final e in document.modalElements)
              if (e.isConnected && e.hasAttribute('open'))
                NativeXLayerView(
                  element: e,
                  styleEngine: widget.styleEngine,
                  modal: true,
                  imageResolver: widget.imageResolver,
                  onDiagnostic: _diagnose,
                  cache: _widgetCache,
                ),
          ];

          final scroll0 = SingleChildScrollView(
            controller: _scroll,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: content,
            ),
          );
          final scroll = _dropTarget(scroll0);
          final constructMs = buildWatch.elapsedMilliseconds;
          NativaXDrawTrace.log(
              'BUILD_END construct=${constructMs}ms '
              'nodes=${document.querySelectorAll('*').length} '
              'cache=${_widgetCache.length} hits=${_widgetCache.hits} '
              'misses=${_widgetCache.misses} layers=${layers.length} '
              'viewport=${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)}');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_diagnosedBuild) {
              _diagnosedBuild = true;
              NativaXRenderProfile.log(
                'DOC_BUILD total=${buildWatch.elapsedMilliseconds}ms '
                'construct=${constructMs}ms '
                'fixed=${layers.length} nodes=${document.querySelectorAll('*').length} '
                'builds=${NativeXBuildStats.elementBuilds} '
                'computes=${widget.styleEngine.computeCount} '
                'subtreePasses=${widget.styleEngine.subtreePasses}',
              );
              NativaXRenderProfile.log(LayoutProfile.summary());
            }
          });
          return Directionality(
            textDirection: direction,
            child: Focus(
              focusNode: _keyboard,
              autofocus: true,
              onKeyEvent: _onKey,
              child: ColoredBox(
                key: _rootKey,
                color: canvas,
                child: layers.isEmpty
                    ? scroll
                    : Stack(
                        children: [
                          Positioned.fill(child: scroll),
                          ...layers,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// `position: fixed` elements that are rendered (no `display: none`
  /// ancestor), excluding modal dialogs, which live in the top layer.
  ///
  /// The walk is bounded and does not descend into containers large enough to
  /// be virtualized: styling every node of a 10.000-row list just to find a
  /// fixed header would defeat the display lock. Fixed elements inside a
  /// virtualized list must opt out with `data-nativa-virtual="off"` (a fixed
  /// descendant of a virtually scrolled list is not meaningful anyway).
  List<dom.Element> _fixedElements(dom.Element? body) {
    final out = <dom.Element>[];
    if (body == null) return out;
    final modal = widget.document.modalElements.toSet();
    var visited = 0;
    void walk(dom.Element e) {
      for (final c in e.children) {
        if (++visited > 2000) return;
        if (nativaxNeverRenderedTags.contains(c.localName)) {
          continue;
        }
        if (c.children.length >= 40) continue;
        final style = widget.styleEngine.styleOf(c);
        if (style.display == Display.none) continue;
        if (style.position == 'fixed') {
          if (!modal.contains(c)) out.add(c);
          continue;
        }
        walk(c);
      }
    }

    walk(body);
    return out;
  }

  Color _canvasColor(dom.Element? body, dom.Element? root) {
    Color? color;
    if (body != null) {
      final style = widget.styleEngine.styleOf(body);
      if (style.backgroundColor.alpha > 0) {
        color = Color(style.backgroundColor.argb);
      }
    }
    if (color == null && root != null) {
      final style = widget.styleEngine.styleOf(root);
      if (style.backgroundColor.alpha > 0) {
        color = Color(style.backgroundColor.argb);
      }
    }
    return color ?? const Color(0xffffffff);
  }
}
