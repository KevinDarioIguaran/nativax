import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:nativa_css/nativa_css.dart' hide MediaQuery;
import 'package:nativa_dom/nativa_dom.dart' as dom;

import 'css_item.dart';

/// The render box drawn for each element, for layout queries from script
/// (`getBoundingClientRect`, `offsetWidth`, `scrollIntoView`, observers) and
/// for the virtual window measurements.
final Expando<RenderBox> elementRenderBoxes = Expando('nativax.renderBox');

/// Counters for the profile benchmark and tests. They are plain integers so
/// release builds do not pay for a diagnostic object per element.
class NativeXBuildStats {
  NativeXBuildStats._();

  static int elementBuilds = 0;
  static int virtualBlocks = 0;
  static int virtualItems = 0;
  static int materializedItems = 0;
  static int recycledItems = 0;

  static void reset() {
    elementBuilds = 0;
    virtualBlocks = 0;
    virtualItems = 0;
    materializedItems = 0;
    recycledItems = 0;
  }
}

/// Opt-in renderer diagnostics. Enable at compile time with
/// `--dart-define=NATIVAX_RENDER_PROFILE=true`; release builds otherwise pay
/// only a constant `false` check.
class NativaXRenderProfile {
  NativaXRenderProfile._();

  static const bool enabled =
      bool.fromEnvironment('NATIVAX_RENDER_PROFILE', defaultValue: false);

  static void log(String message) {
    if (enabled) {
      // ignore: avoid_print
      print('RENDER_PROFILE $message');
    }
  }
}

/// The virtual block that owns an element, if any. Layout queries use it to
/// return an estimated box for an element that has not been materialized.
final Expando<CssVirtualBlockState> virtualOwner = Expando('nativax.virtual');

/// Viewport information shared with the virtual blocks below a scroll view.
///
/// The document view creates one for the root scroll; every nested
/// `overflow: auto|scroll` container creates another one with its own
/// controller, so a block always knows which scroll offset moves it.
class NativaXViewportScope extends InheritedWidget {
  const NativaXViewportScope({
    super.key,
    required this.controller,
    required this.viewportHeight,
    required this.viewportWidth,
    this.parent,
    required super.child,
  });

  final ScrollController controller;
  final double viewportHeight;
  final double viewportWidth;

  /// The enclosing scroll viewport, if any. A virtual block walks this chain
  /// to skip a nested scroller that does not actually overflow (for example
  /// `overflow: auto` on an element whose height is its content height).
  final NativaXViewportScope? parent;

  static NativaXViewportScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NativaXViewportScope>();

  /// Reads the scope without registering a build dependency. Safe in
  /// post-frame callbacks.
  static NativaXViewportScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NativaXViewportScope>();

  static NativaXViewportScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'NativaXViewportScope is missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(NativaXViewportScope oldWidget) =>
      controller != oldWidget.controller ||
      parent != oldWidget.parent ||
      viewportHeight != oldWidget.viewportHeight ||
      viewportWidth != oldWidget.viewportWidth;
}

/// A nested CSS scroll container with its own controller and viewport scope.
///
/// This replaces the bare [SingleChildScrollView] used for
/// `overflow: auto|scroll`, so the virtual blocks inside it can react to the
/// container's own scroll offset instead of the document's.
class NativaXVirtualScrollView extends StatefulWidget {
  const NativaXVirtualScrollView({
    super.key,
    required this.child,
    this.vertical = true,
    this.horizontal = false,
  });

  final Widget child;
  final bool vertical;
  final bool horizontal;

  @override
  State<NativaXVirtualScrollView> createState() =>
      _NativaXVirtualScrollViewState();
}

class _NativaXVirtualScrollViewState extends State<NativaXVirtualScrollView> {
  final ScrollController _controller = ScrollController(debugLabel: 'nativax.css-scroll');
  double _viewportHeight = 0;
  double _viewportWidth = 0;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final position = _controller.hasClients ? _controller.position : null;
    final height = position?.viewportDimension;
    final width = context.size?.width;
    final nextHeight = height != null && height > 0 ? height : _viewportHeight;
    final nextWidth = width != null && width > 0 ? width : _viewportWidth;
    if (!_measured ||
        (nextHeight - _viewportHeight).abs() > 0.5 ||
        (nextWidth - _viewportWidth).abs() > 0.5) {
      _measured = true;
      setState(() {
        _viewportHeight = nextHeight;
        _viewportWidth = nextWidth;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    var scroll = widget.child;
    if (widget.horizontal) {
      scroll = SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: scroll,
      );
    } else {
      scroll = SingleChildScrollView(controller: _controller, child: scroll);
    }
    if (widget.vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      return NativaXViewportScope(
        controller: _controller,
        viewportHeight: _viewportHeight > 0
            ? _viewportHeight
            : media?.size.height ?? 600,
        viewportWidth: _viewportWidth > 0
            ? _viewportWidth
            : media?.size.width ?? 800,
        parent: NativaXViewportScope.maybeOf(context),
        child: scroll,
      );
    }
    return scroll;
  }
}

/// Virtualizes a vertical list of slots (block children, flex children, or
/// grid rows).
///
/// The widget mirrors Blink's display lock: only the slots inside the viewport
/// plus [overscan] are materialized. Omitted slots contribute one spacer at the
/// top and one at the bottom, so the number of live render objects does not
/// grow with the document.
class CssVirtualBlock extends StatefulWidget {
  const CssVirtualBlock({
    super.key,
    required this.container,
    required this.styleEngine,
    required this.count,
    required this.elementsAt,
    required this.itemBuilder,
    required this.layoutBuilder,
    required this.estimate,
    this.extraHeight,
    this.columns = 1,
    this.columnGap = 0,
    this.overscan,
    this.debugName = 'block',
    this.indexOfElement,
    this.rowOfElement,
    this.columnOfElement,
  });

  /// Container element (for keys and diagnostics).
  final dom.Element container;

  /// Used only to read margins of materialized slots; offscreen slots never
  /// call it.
  final StyleEngine styleEngine;

  /// Number of slots. A slot is one block/flex child or one grid row.
  final int count;

  /// Elements belonging to a slot. Used to pin, measure and answer geometry.
  final List<dom.Element> Function(int index) elementsAt;

  /// Builds one visible slot.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Wraps the spacer/item children in the container's real layout.
  final Widget Function(BuildContext context, List<Widget> children) layoutBuilder;

  /// Structural height estimate. It must not call `styleOf` for offscreen
  /// elements; it is only a hint until the slot is measured.
  final double Function(int index) estimate;

  /// Extra space between slots (grid row gap), included in the measured
  /// height but not drawn by the item itself when the layout already applies
  /// it elsewhere.
  final double Function(int index)? extraHeight;

  /// Column count for grid rows (1 for block/flex).
  final int columns;

  /// Gap between grid columns, used only by the estimated geometry.
  final double columnGap;

  /// Distance, in pixels, kept materialized before and after the viewport.
  /// Defaults to one viewport, as Blink's auto display lock margin.
  final double? overscan;

  final String debugName;

  /// Optional O(1) element -> slot mapping (grid rows).
  final int? Function(dom.Element element)? indexOfElement;
  final int? Function(dom.Element element)? rowOfElement;
  final int? Function(dom.Element element)? columnOfElement;

  @override
  State<CssVirtualBlock> createState() => CssVirtualBlockState();
}

class CssVirtualBlockState extends State<CssVirtualBlock> {
  final Map<int, double> _heights = {};
  final Set<int> _pinned = {};
  int _start = 0;
  int _end = -1;
  double _defaultHeight = 80;
  double _viewportHeight = 600;
  double _lastViewportTop = double.nan;
  double _lastBlockTop = double.nan;
  ScrollController? _controller;
  bool _scheduled = false;
  bool _updating = false;
  int _initialWindow = 12;

  @override
  void initState() {
    super.initState();
    NativeXBuildStats.virtualBlocks++;
    NativeXBuildStats.virtualItems += widget.count;
    _registerOwner();
    _defaultHeight = _initialHeight();
    _end = math.min(widget.count - 1, _initialWindow);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant CssVirtualBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count ||
        !identical(oldWidget.container, widget.container)) {
      _heights.clear();
      _pinned.clear();
      _start = 0;
      _end = math.min(widget.count - 1, _initialWindow);
      _defaultHeight = _initialHeight();
      _registerOwner();
    }
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onScroll);
    _unregisterOwner();
    super.dispose();
  }

  void _registerOwner() {
    for (var i = 0; i < widget.count; i++) {
      for (final e in widget.elementsAt(i)) {
        virtualOwner[e] = this;
      }
    }
  }

  void _unregisterOwner() {
    for (var i = 0; i < widget.count; i++) {
      for (final e in widget.elementsAt(i)) {
        if (identical(virtualOwner[e], this)) virtualOwner[e] = null;
      }
    }
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _update();
    });
  }

  void _onScroll() => _schedule();

  double get _overscan => widget.overscan ?? _viewportHeight;

  double _initialHeight() {
    if (widget.count == 0) return 80;
    final h = widget.estimate(0) + (widget.extraHeight?.call(0) ?? 0);
    return h.isFinite && h > 0 ? h : 80;
  }

  double _heightAt(int i) => _heights[i] ?? _defaultHeight;

  double _sumBefore(int index) {
    var y = index * _defaultHeight;
    for (final entry in _heights.entries) {
      if (entry.key < index) y += entry.value - _defaultHeight;
    }
    return y;
  }

  (int, int) _visibleRange(double localStart, double localEnd) {
    if (widget.count == 0) return (0, -1);
    final limit = localEnd + _overscan;
    var y = 0.0;
    var start = -1;
    var end = -1;
    for (var i = 0; i < widget.count; i++) {
      final h = _heightAt(i);
      if (y + h >= localStart && y <= limit) {
        if (start < 0) start = i;
        end = i;
      }
      if (y > limit && start >= 0) break;
      y += h;
    }
    if (start < 0) {
      // The viewport is above the block (still possible during the first
      // frame): materialize the first window so the initial build is bounded.
      end = math.min(widget.count - 1, _initialWindow);
      return (0, end);
    }
    return (start, end);
  }

  double? _measureSlot(int index) {
    double? result;
    for (final e in widget.elementsAt(index)) {
      final box = elementRenderBoxes[e];
      if (box == null || !box.attached || !box.hasSize) continue;
      final style = widget.styleEngine.styleOf(e);
      var h = box.size.height;
      for (final side in const ['top', 'bottom']) {
        final m = style.marginOf(side);
        if (m != null && !m.isPercent) h += m.value;
      }
      result = result == null ? h : math.max(result, h);
    }
    return result;
  }

  /// The innermost scope whose scroller really overflows. A nested
  /// `overflow: auto` whose height is its content height has no scroll extent;
  /// in that case the document viewport is the one that moves the block.
  NativaXViewportScope? _effectiveScope() {
    var scope = NativaXViewportScope.read(context);
    NativaXViewportScope? fallback;
    while (scope != null) {
      fallback ??= scope;
      final controller = scope.controller;
      if (controller.hasClients) {
        final position = controller.position;
        if (position.hasContentDimensions &&
            position.viewportDimension > 0 &&
            position.maxScrollExtent > 1) {
          return scope;
        }
      }
      scope = scope.parent;
    }
    return fallback;
  }

  void _update() {
    if (!mounted || _updating) return;
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
      _schedule();
      return;
    }
    final scope = _effectiveScope();
    final controller = scope?.controller;
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onScroll);
      _controller = controller;
      _controller?.addListener(_onScroll);
    }
    _viewportHeight = scope?.viewportHeight ?? MediaQuery.maybeSizeOf(context)?.height ?? 600;
    _initialWindow = math.max(6, (_viewportHeight / _defaultHeight).ceil() + 2);
    final blockTop = ro.localToGlobal(Offset.zero).dy;
    double viewportTop = blockTop;
    final position = controller?.hasClients == true ? controller!.position : null;
    final viewportContext = position?.context.notificationContext;
    if (viewportContext != null && viewportContext.mounted) {
      final viewportBox = viewportContext.findRenderObject();
      if (viewportBox is RenderBox && viewportBox.attached) {
        viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
      }
    }
    final localStart = viewportTop - blockTop;
    final localEnd = localStart + _viewportHeight;
    final range = _visibleRange(localStart, localEnd);

    // Measure the current window and pinned slots. Heights are corrected
    // before the next layout, and the scroll offset is adjusted by the delta
    // above the first visible slot (scroll anchoring).
    var changed = false;
    var aboveDelta = 0.0;
    final anchor = _start;
    final measureFrom = range.$1 < _start ? range.$1 : _start;
    final measureTo = range.$2 > _end ? range.$2 : _end;
    for (var i = measureFrom; i <= measureTo; i++) {
      final measured = _measureSlot(i);
      if (measured == null) continue;
      final next = measured + (widget.extraHeight?.call(i) ?? 0);
      final old = _heightAt(i);
      if ((next - old).abs() < 0.5) continue;
      _heights[i] = next;
      changed = true;
      if (i < anchor) aboveDelta += next - old;
    }
    // The rolling default follows the measured slots. Recompute it only when
    // there are measurements, so the initial hint stays stable for a block
    // that is entirely outside the viewport.
    if (_heights.isNotEmpty) {
      var sum = 0.0;
      for (final h in _heights.values) {
        sum += h;
      }
      final mean = sum / _heights.length;
      if ((mean - _defaultHeight).abs() > 0.5) {
        _defaultHeight = mean;
        changed = true;
      }
    }

    final rangeChanged = range.$1 != _start || range.$2 != _end;
    final moved = (_lastBlockTop.isNaN || (blockTop - _lastBlockTop).abs() > 0.5 ||
        _lastViewportTop.isNaN || (viewportTop - _lastViewportTop).abs() > 0.5);
    if (!changed && !rangeChanged && !moved) return;
    NativaXRenderProfile.log(
      'VIRTUAL ${widget.debugName} count=${widget.count} '
      'range=${range.$1}..${range.$2} start=$localStart '
      'viewport=$_viewportHeight default=${_defaultHeight.toStringAsFixed(1)}',
    );

    _updating = true;
    if (aboveDelta.abs() > 0.01 && position != null) {
      final target = (position.pixels + aboveDelta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      controller!.jumpTo(target);
      _lastViewportTop = viewportTop - (target - position.pixels);
    } else {
      _lastViewportTop = viewportTop;
    }
    _lastBlockTop = blockTop - (aboveDelta.abs() > 0.01 ? aboveDelta : 0);
    if (rangeChanged) _evictOutside(range.$1, range.$2);
    setState(() {
      _start = range.$1;
      _end = range.$2;
    });
    _updating = false;
    // The freshly materialized slots are measured on the next frame.
    _schedule();
  }

  /// The slot that owns [element], or null.
  int? indexOf(dom.Element element) {
    final direct = widget.indexOfElement?.call(element);
    if (direct != null) return direct;
    for (var i = 0; i < widget.count; i++) {
      if (widget.elementsAt(i).any((e) => identical(e, element))) return i;
    }
    return null;
  }

  /// Drops computed styles for slots that left the window. Render objects are
  /// already detached by Flutter; this releases the heavier style objects so a
  /// long scroll does not retain the whole document.
  void _evictOutside(int nextStart, int nextEnd) {
    for (var i = _start; i <= _end; i++) {
      if (i >= nextStart && i <= nextEnd) continue;
      if (_pinned.contains(i)) continue;
      for (final e in widget.elementsAt(i)) {
        widget.styleEngine.invalidateDeferred(e);
      }
    }
  }

  /// Force [element] into the materialized window. The real box is available
  /// after the next frame. The window moves to the slot instead of appending
  /// it out of order, so the element's real geometry (and scrollIntoView)
  /// stays correct.
  void ensureBuilt(dom.Element element) {
    final i = indexOf(element);
    if (i == null) return;
    if (i >= _start && i <= _end) {
      if (_pinned.add(i)) setState(() {});
      return;
    }
    _pinned.add(i);
    final span = math.max(6, _end - _start + 1);
    final nextStart = (i - 1).clamp(0, math.max(0, widget.count - 1)).toInt();
    final nextEnd = math.min(widget.count - 1, nextStart + span - 1);
    if (nextStart != _start || nextEnd != _end) {
      setState(() {
        _start = nextStart;
        _end = nextEnd;
      });
    }
    _schedule();
  }

  bool isMaterialized(dom.Element element) {
    final i = indexOf(element);
    if (i == null) return false;
    if (i >= _start && i <= _end) return true;
    final box = elementRenderBoxes[element];
    return box != null && box.attached && box.hasSize;
  }

  /// Whether the element currently has a live, laid-out render box.
  bool hasBox(dom.Element element) {
    final box = elementRenderBoxes[element];
    return box != null && box.attached && box.hasSize;
  }

  /// Estimated viewport box for an element that is not materialized.
  dom.ElementBox? estimatedBoxOf(dom.Element element) {
    final i = indexOf(element);
    if (i == null) return null;
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    final origin = ro.localToGlobal(Offset.zero);
    final elements = widget.elementsAt(i);
    final at = elements.indexWhere((e) => identical(e, element));
    final rowTop = origin.dy + _sumBefore(i);
    final column = widget.columnOfElement?.call(element) ?? (at < 0 ? 0 : at);
    final columns = math.max(1, widget.columns);
    final gap = widget.columnGap;
    final cellWidth = (ro.size.width - gap * (columns - 1)) / columns;
    final left = origin.dx + column * (cellWidth + gap);
    final height = _heightAt(i);
    final scrollY = element.ownerDocument.layoutHost?.scrollY ?? 0;
    return dom.ElementBox(
      x: left,
      y: rowTop,
      width: math.max(0, cellWidth),
      height: math.max(0, height),
      offsetX: left,
      offsetY: rowTop + scrollY,
      clientWidth: math.max(0, cellWidth),
      clientHeight: math.max(0, height),
      scrollWidth: math.max(0, cellWidth),
      scrollHeight: math.max(0, height),
    );
  }

  Widget _spacer(double height) => CssItem(
        margin: const [
          ResolvedLength.zero,
          ResolvedLength.zero,
          ResolvedLength.zero,
          ResolvedLength.zero,
        ],
        autoWidth: true,
        autoHeight: false,
        child: SizedBox(height: math.max(0, height)),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) {
      return widget.layoutBuilder(context, const []);
    }
    final start = _start.clamp(0, widget.count - 1);
    final rawEnd = _end.clamp(-1, widget.count - 1);
    final end = rawEnd < start ? -1 : rawEnd;
    final children = <Widget>[];
    if (start > 0) children.add(_spacer(_sumBefore(start)));
    if (end >= start) {
      for (var i = start; i <= end; i++) {
        NativeXBuildStats.materializedItems++;
        children.add(widget.itemBuilder(context, i));
      }
    }
    for (final i in _pinned.toList()..sort()) {
      if (i < start || i > end) {
        NativeXBuildStats.materializedItems++;
        children.add(widget.itemBuilder(context, i));
      }
    }
    final after = end < 0 ? widget.count : end + 1;
    if (after < widget.count) {
      children.add(_spacer(_sumBefore(widget.count) - _sumBefore(after)));
    }
    return widget.layoutBuilder(context, children);
  }
}
