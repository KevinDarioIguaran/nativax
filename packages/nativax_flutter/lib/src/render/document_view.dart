import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:nativax_css/nativax_css.dart' hide MediaQuery;
import 'package:nativax_dom/nativax_dom.dart' as dom;

import 'canvas2d.dart';
import 'node_view.dart';
import 'render_types.dart';

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
  void Function(String href, dom.Element anchor)? _previousNavigate;
  void Function(dom.Element form)? _previousSubmit;

  final GlobalKey _rootKey = GlobalKey();
  final CanvasRegistry _canvases = CanvasRegistry();
  final FocusNode _keyboard = FocusNode(debugLabel: 'nativax.document');
  double _lastScroll = 0;
  bool _scrollEventScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.document.layoutHost = this;
    widget.document.canvasHost = _canvases;
    _scroll.addListener(_onScroll);
    widget.document.addMutationListener(_onMutation);
    _previousNavigate = widget.document.onNavigate;
    _previousSubmit = widget.document.onSubmit;
    if (widget.onNavigate != null) widget.document.onNavigate = widget.onNavigate;
    if (widget.onSubmit != null) widget.document.onSubmit = widget.onSubmit;
  }

  @override
  void didUpdateWidget(covariant NativaXDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      oldWidget.document.removeMutationListener(_onMutation);
      if (identical(oldWidget.document.layoutHost, this)) oldWidget.document.layoutHost = null;
      widget.document.addMutationListener(_onMutation);
      widget.document.layoutHost = this;
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
    if (widget.onNavigate != null) {
      widget.document.onNavigate = _previousNavigate;
    }
    if (widget.onSubmit != null) {
      widget.document.onSubmit = _previousSubmit;
    }
    _revision.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMutation(dom.MutationRecord record) {
    widget.styleEngine.handleMutation(record);
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _scheduled = false;
    if (_disposed || !mounted) return;
    widget.styleEngine.recompute();
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
    // Layout may be pending (the script just changed the DOM).
    void run() {
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

  @override
  Widget build(BuildContext context) {
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
              : Padding(
                  padding: widget.padding,
                  child: SizedBox(
                    width: width,
                    child: NativeXNodeView(
                      element: body,
                      isRoot: true,
                      styleEngine: widget.styleEngine,
                      imageResolver: widget.imageResolver,
                      onDiagnostic: _diagnose,
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
              ),
            for (final e in document.modalElements)
              if (e.isConnected && e.hasAttribute('open'))
                NativeXLayerView(
                  element: e,
                  styleEngine: widget.styleEngine,
                  modal: true,
                  imageResolver: widget.imageResolver,
                  onDiagnostic: _diagnose,
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
  List<dom.Element> _fixedElements(dom.Element? body) {
    final out = <dom.Element>[];
    if (body == null) return out;
    final modal = widget.document.modalElements.toSet();
    void walk(dom.Element e) {
      for (final c in e.children) {
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
