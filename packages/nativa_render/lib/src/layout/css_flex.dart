import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativa_css/nativa_css.dart';

import 'css_item.dart';
import 'layout_profile.dart';

/// A flex container implementing the CSS Flexible Box Layout algorithm
/// (§9) for the supported subset: flex-basis/grow/shrink with min-size
/// freezing, `flex-wrap`, `gap`, `justify-content`, `align-items`,
/// `align-self` and auto margins on the main axis. Not implemented:
/// `align-content` (lines are packed at the start), baseline alignment
/// (treated as `flex-start`), `order`, and max-size clamping of items.
class CssFlexLayout extends MultiChildRenderObjectWidget {
  const CssFlexLayout({
    super.key,
    required this.direction,
    this.reverse = false,
    this.wrap = 'nowrap',
    this.justifyContent = 'normal',
    this.alignItems = 'normal',
    this.rowGap = ResolvedLength.zero,
    this.columnGap = ResolvedLength.zero,
    this.textDirection = TextDirection.ltr,
    super.children,
  });

  final Axis direction;
  final bool reverse;
  final String wrap;
  final String justifyContent;
  final String alignItems;
  final ResolvedLength rowGap;
  final ResolvedLength columnGap;
  final TextDirection textDirection;

  @override
  RenderCssFlex createRenderObject(BuildContext context) => RenderCssFlex()
    ..direction = direction
    ..reverse = reverse
    ..wrap = wrap
    ..justifyContent = justifyContent
    ..alignItems = alignItems
    ..rowGap = rowGap
    ..columnGap = columnGap;

  @override
  void updateRenderObject(BuildContext context, RenderCssFlex r) {
    r
      ..direction = direction
      ..reverse = reverse
      ..wrap = wrap
      ..justifyContent = justifyContent
      ..alignItems = alignItems
      ..rowGap = rowGap
      ..columnGap = columnGap;
  }
}

class _Item {
  _Item(this.child, this.pd);
  final RenderBox child;
  final CssItemParentData pd;
  double base = 0;
  double hypothetical = 0;
  double minMain = 0;
  double target = 0;
  bool frozen = false;
  double mainStart = 0; // margins on the main axis
  double mainEnd = 0;
  double crossStart = 0;
  double crossEnd = 0;
  bool autoMainStart = false;
  bool autoMainEnd = false;
  Size size = Size.zero;
  /// A real (non-dry) layout performed while measuring the base size. Column
  /// flex containers reuse it when no flexible length changes the main size,
  /// avoiding a second text/layout pass per item.
  Size? measuredSize;
  BoxConstraints? measuredConstraints;
  double? measuredMain;
  double get outerHypothetical => hypothetical + mainStart + mainEnd;
  double get outerTarget => target + mainStart + mainEnd;
}

class RenderCssFlex extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, CssItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, CssItemParentData>,
        CssStackingPaint {
  Axis _direction = Axis.horizontal;
  bool _reverse = false;
  String _wrap = 'nowrap';
  String _justify = 'normal';
  String _alignItems = 'normal';
  ResolvedLength _rowGap = ResolvedLength.zero;
  ResolvedLength _columnGap = ResolvedLength.zero;

  set direction(Axis v) => _set(_direction != v, () => _direction = v);
  set reverse(bool v) => _set(_reverse != v, () => _reverse = v);
  set wrap(String v) => _set(_wrap != v, () => _wrap = v);
  set justifyContent(String v) => _set(_justify != v, () => _justify = v);
  set alignItems(String v) => _set(_alignItems != v, () => _alignItems = v);
  set rowGap(ResolvedLength v) => _set(_rowGap != v, () => _rowGap = v);
  set columnGap(ResolvedLength v) => _set(_columnGap != v, () => _columnGap = v);

  void _set(bool changed, void Function() apply) {
    if (!changed) return;
    apply();
    markNeedsLayout();
  }

  bool get _isRow => _direction == Axis.horizontal;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! CssItemParentData) child.parentData = CssItemParentData();
  }

  double _main(Size s) => _isRow ? s.width : s.height;
  double _cross(Size s) => _isRow ? s.height : s.width;

  BoxConstraints _constraintsFor(double? main, double? minCross, double? maxCross) {
    final crossMin = minCross ?? 0;
    final crossMax = maxCross ?? double.infinity;
    return _isRow
        ? BoxConstraints(
            minWidth: main ?? 0, maxWidth: main ?? double.infinity, minHeight: crossMin, maxHeight: crossMax)
        : BoxConstraints(
            minHeight: main ?? 0, maxHeight: main ?? double.infinity, minWidth: crossMin, maxWidth: crossMax);
  }

  String _alignOf(_Item item) {
    final a = item.pd.alignSelf == 'auto' ? _alignItems : item.pd.alignSelf;
    return a == 'normal' ? 'stretch' : a;
  }

  bool _autoCross(_Item item) => _isRow ? item.pd.autoHeight : item.pd.autoWidth;

  Size _run(BoxConstraints constraints, {required bool dry}) {
    final cbw = constraints.hasBoundedWidth ? constraints.maxWidth : null;
    final cbh = constraints.hasTightHeight ? constraints.maxHeight : null;
    final mainMax = _isRow ? constraints.maxWidth : constraints.maxHeight;
    final mainDefinite = mainMax.isFinite;
    final crossMax = _isRow ? constraints.maxHeight : constraints.maxWidth;
    final crossDefinite = _isRow ? constraints.hasTightHeight : constraints.hasTightWidth;
    final mainGap = (_isRow ? _columnGap : _rowGap).resolve(_isRow ? cbw : cbh) ?? 0;
    final crossGap = (_isRow ? _rowGap : _columnGap).resolve(_isRow ? cbh : cbw) ?? 0;

    Size measure(RenderBox c, BoxConstraints cc) {
      if (dry) return c.getDryLayout(cc);
      c.layout(cc, parentUsesSize: true);
      return c.size;
    }

    Size measureItem(_Item i, double? crossAvail) {
      final measuredMain = i.measuredMain;
      if (!dry &&
          i.measuredSize != null &&
          measuredMain != null &&
          (i.target - measuredMain).abs() < 0.001) {
        return i.measuredSize!;
      }
      return measure(i.child, _constraintsFor(i.target, 0, crossAvail));
    }

    // 1. Collect items and determine hypothetical main sizes.
    final items = <_Item>[];
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final pd = c.parentData! as CssItemParentData;
      pd.containingWidth = cbw;
      pd.containingHeight = cbh;
      final item = _Item(c, pd);
      final basis = cbw ?? 0;
      double m(ResolvedLength? v) => pd.resolveMargin(v, basis);
      if (_isRow) {
        item
          ..mainStart = m(pd.marginLeft)
          ..mainEnd = m(pd.marginRight)
          ..crossStart = m(pd.marginTop)
          ..crossEnd = m(pd.marginBottom)
          ..autoMainStart = pd.marginLeft == null
          ..autoMainEnd = pd.marginRight == null;
      } else {
        item
          ..mainStart = m(pd.marginTop)
          ..mainEnd = m(pd.marginBottom)
          ..crossStart = m(pd.marginLeft)
          ..crossEnd = m(pd.marginRight)
          ..autoMainStart = pd.marginTop == null
          ..autoMainEnd = pd.marginBottom == null;
      }
      final crossAvail = crossMax.isFinite ? math.max(0.0, crossMax - item.crossStart - item.crossEnd) : double.infinity;
      final basisLen = pd.flexBasis?.resolve(mainDefinite ? mainMax : null);
      if (basisLen != null) {
        item.base = basisLen;
      } else if (_isRow) {
        item.base = c.getMaxIntrinsicWidth(crossAvail);
      } else {
        final stretchCross = _alignOf(item) == 'stretch' && _autoCross(item) && crossAvail.isFinite;
        final cc = stretchCross
            ? BoxConstraints.tightFor(width: crossAvail)
            : BoxConstraints(maxWidth: crossAvail);
        if (dry) {
          item.base = c.getDryLayout(cc).height;
        } else {
          // Column flex can measure the real child here. Reusing this layout
          // when no flexible length changes the main size avoids the duplicate
          // dry pass (and its text intrinsic measurement) for the whole page.
          c.layout(cc, parentUsesSize: true);
          item.base = c.size.height;
          item.measuredSize = c.size;
          item.measuredConstraints = cc;
          item.measuredMain = item.base;
        }
      }
      // Automatic minimum size (min-width: auto): the min-content size on
      // the main axis for rows. Columns use 0 (documented simplification).
      item.minMain = _isRow ? c.getMinIntrinsicWidth(crossAvail) : 0;
      item.hypothetical = math.max(item.base, item.minMain);
      items.add(item);
    }

    // 2. Collect lines.
    final lines = <List<_Item>>[];
    if (_wrap == 'nowrap' || !mainDefinite) {
      lines.add(items);
    } else {
      var line = <_Item>[];
      var used = 0.0;
      for (final item in items) {
        final outer = math.max(item.outerHypothetical, item.minMain + item.mainStart + item.mainEnd);
        final next = line.isEmpty ? outer : used + mainGap + outer;
        if (line.isNotEmpty && next > mainMax + 0.001) {
          lines.add(line);
          line = [item];
          used = outer;
        } else {
          line.add(item);
          used = next;
        }
      }
      if (line.isNotEmpty) lines.add(line);
    }

    // 3. Resolve flexible lengths per line (with min-size freezing).
    var containerMain = 0.0;
    for (final line in lines) {
      final gaps = mainGap * math.max(0, line.length - 1);
      final usedHypo = line.fold<double>(0, (s, i) => s + i.outerHypothetical) + gaps;
      final available = mainDefinite ? mainMax : usedHypo;
      final growing = available > usedHypo;
      for (final i in line) {
        i.target = i.hypothetical;
        final factor = growing ? i.pd.flexGrow : i.pd.flexShrink;
        // Inflexible items, and items that would move the wrong way, freeze
        // at their hypothetical size.
        i.frozen = factor == 0 ||
            available == usedHypo ||
            (growing && i.base > i.hypothetical) ||
            (!growing && i.base < i.hypothetical);
      }
      for (var guard = 0; guard < line.length + 1; guard++) {
        final unfrozen = line.where((i) => !i.frozen).toList();
        if (unfrozen.isEmpty) break;
        final frozenSpace = line.where((i) => i.frozen).fold<double>(0, (s, i) => s + i.outerTarget);
        final unfrozenSpace = unfrozen.fold<double>(0, (s, i) => s + i.base + i.mainStart + i.mainEnd);
        var free = available - gaps - frozenSpace - unfrozenSpace;
        if (growing) {
          final sum = unfrozen.fold<double>(0, (s, i) => s + i.pd.flexGrow);
          if (sum < 1) free *= sum;
          for (final i in unfrozen) {
            i.target = i.base + (sum == 0 ? 0 : free * i.pd.flexGrow / sum);
          }
        } else {
          final sum = unfrozen.fold<double>(0, (s, i) => s + i.pd.flexShrink * i.base);
          for (final i in unfrozen) {
            i.target = i.base + (sum == 0 ? 0 : free * i.pd.flexShrink * i.base / sum);
          }
        }
        // Clamp to min sizes; freeze violators.
        var totalViolation = 0.0;
        final clamped = <_Item, double>{};
        for (final i in unfrozen) {
          final v = math.max(i.target, i.minMain);
          totalViolation += v - i.target;
          clamped[i] = v;
        }
        if (totalViolation == 0) {
          for (final i in unfrozen) {
            i.frozen = true;
          }
        } else {
          for (final i in unfrozen) {
            if (clamped[i]! > i.target && totalViolation > 0) {
              i.target = clamped[i]!;
              i.frozen = true;
            }
          }
        }
      }
      for (final i in line) {
        i.target = math.max(0, i.target);
      }
      final lineMain = line.fold<double>(0, (s, i) => s + i.outerTarget) + gaps;
      containerMain = math.max(containerMain, lineMain);
    }

    // 4. Lay out items at their main size; determine line cross sizes.
    final lineCross = <double>[];
    for (final line in lines) {
      var cross = 0.0;
      for (final i in line) {
        final crossAvail = crossMax.isFinite ? math.max(0.0, crossMax - i.crossStart - i.crossEnd) : null;
        i.size = measureItem(i, crossAvail);
        cross = math.max(cross, _cross(i.size) + i.crossStart + i.crossEnd);
      }
      lineCross.add(cross);
    }
    if (lines.length == 1 && crossDefinite) lineCross[0] = crossMax;

    // Stretch.
    for (var l = 0; l < lines.length; l++) {
      for (final i in lines[l]) {
        if (_alignOf(i) != 'stretch' || !_autoCross(i)) continue;
        final c = math.max(0.0, lineCross[l] - i.crossStart - i.crossEnd);
        if ((_cross(i.size) - c).abs() < 0.001) continue;
        i.size = measure(i.child, _constraintsFor(i.target, c, c));
      }
    }

    final totalCross = lineCross.fold<double>(0, (s, c) => s + c) + crossGap * math.max(0, lines.length - 1);
    final mainSize = mainDefinite ? mainMax : containerMain;
    final crossSize = crossDefinite ? crossMax : totalCross;
    final size = constraints.constrain(_isRow ? Size(mainSize, crossSize) : Size(crossSize, mainSize));
    // A single line takes the container's (min/max-clamped) cross size, so
    // `min-height` on a row container centers or stretches its items.
    if (lines.length == 1 && _cross(size) > lineCross[0]) {
      lineCross[0] = _cross(size);
      for (final i in lines[0]) {
        if (_alignOf(i) != 'stretch' || !_autoCross(i)) continue;
        final c = math.max(0.0, lineCross[0] - i.crossStart - i.crossEnd);
        if ((_cross(i.size) - c).abs() < 0.001) continue;
        i.size = measure(i.child, _constraintsFor(i.target, c, c));
      }
    }
    if (dry) return size;

    // 5. Position.
    final finalMain = _main(size);
    final finalCross = _cross(size);
    final wrapReverse = _wrap == 'wrap-reverse';
    var crossCursor = wrapReverse ? finalCross : 0.0;
    for (var l = 0; l < lines.length; l++) {
      final line = lines[l];
      final lc = lineCross[l];
      if (wrapReverse) crossCursor -= lc;
      final gaps = mainGap * math.max(0, line.length - 1);
      final used = line.fold<double>(0, (s, i) => s + _main(i.size) + i.mainStart + i.mainEnd) + gaps;
      var free = finalMain - used;
      final autoCount = line.fold<int>(0, (s, i) => s + (i.autoMainStart ? 1 : 0) + (i.autoMainEnd ? 1 : 0));
      final autoShare = autoCount > 0 && free > 0 ? free / autoCount : 0.0;
      if (autoCount > 0 && free > 0) free = 0;
      double lead = 0, between = mainGap;
      final n = line.length;
      final justify = _justify;
      final flexEnd = (justify == 'flex-end' || justify == 'end') != _reverse;
      if (free > 0) {
        switch (justify) {
          case 'center':
            lead = free / 2;
          case 'space-between':
            between += n > 1 ? free / (n - 1) : 0;
          case 'space-around':
            lead = free / n / 2;
            between += free / n;
          case 'space-evenly':
            lead = free / (n + 1);
            between += free / (n + 1);
          default:
            if (flexEnd) lead = free;
        }
      } else if (free < 0 && (justify == 'center')) {
        lead = free / 2;
      }
      final ordered = _reverse ? line.reversed.toList() : line;
      var cursor = lead;
      for (var k = 0; k < ordered.length; k++) {
        final i = ordered[k];
        cursor += i.mainStart + (i.autoMainStart ? autoShare : 0);
        final itemMain = _main(i.size);
        final mainPos = _reverse ? finalMain - cursor - itemMain : cursor;
        cursor += itemMain + i.mainEnd + (i.autoMainEnd ? autoShare : 0);
        if (k < ordered.length - 1) cursor += between;
        final itemCross = _cross(i.size);
        final space = lc - itemCross - i.crossStart - i.crossEnd;
        final double crossOffset = switch (_alignOf(i)) {
          'center' => i.crossStart + space / 2,
          'flex-end' || 'end' => i.crossStart + space,
          _ => i.crossStart,
        };
        final crossPos = crossCursor + (wrapReverse ? lc - itemCross - crossOffset : crossOffset);
        i.pd.offset = _isRow ? Offset(mainPos, crossPos) : Offset(crossPos, mainPos);
      }
      crossCursor = wrapReverse ? crossCursor - crossGap : crossCursor + lc + crossGap;
    }
    return size;
  }

  @override
  void performLayout() {
    size = LayoutProfile.measure('flex.layout', () => _run(constraints, dry: false));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      LayoutProfile.measure('flex.dry', () => _run(constraints, dry: true));

  double _px(ResolvedLength? m) => m == null || m.isPercent ? 0 : m.value;

  double _gap(bool main) {
    final g = main == _isRow ? _columnGap : _rowGap;
    return g.isPercent ? 0 : g.value;
  }

  double _intrinsicMain(double crossExtent, {required bool min}) {
    var sum = 0.0, max = 0.0, count = 0;
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final pd = c.parentData! as CssItemParentData;
      final margins = _isRow ? _px(pd.marginLeft) + _px(pd.marginRight) : _px(pd.marginTop) + _px(pd.marginBottom);
      final v = (_isRow
              ? (min ? c.getMinIntrinsicWidth(crossExtent) : c.getMaxIntrinsicWidth(crossExtent))
              : (min ? c.getMinIntrinsicHeight(crossExtent) : c.getMaxIntrinsicHeight(crossExtent))) +
          margins;
      sum += v;
      max = math.max(max, v);
      count++;
    }
    if (min && _wrap != 'nowrap') return max;
    return sum + _gap(true) * math.max(0, count - 1);
  }

  double _intrinsicCross(double mainExtent, {required bool min}) {
    var max = 0.0;
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final pd = c.parentData! as CssItemParentData;
      final margins = _isRow ? _px(pd.marginTop) + _px(pd.marginBottom) : _px(pd.marginLeft) + _px(pd.marginRight);
      final v = (_isRow
              ? (min ? c.getMinIntrinsicHeight(double.infinity) : c.getMaxIntrinsicHeight(double.infinity))
              : (min ? c.getMinIntrinsicWidth(double.infinity) : c.getMaxIntrinsicWidth(double.infinity))) +
          margins;
      max = math.max(max, v);
    }
    return max;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _isRow ? _intrinsicMain(height, min: true) : _intrinsicCross(height, min: true);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _isRow ? _intrinsicMain(height, min: false) : _intrinsicCross(height, min: false);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _isRow ? _intrinsicCross(width, min: true) : _intrinsicMain(width, min: true);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _isRow ? _intrinsicCross(width, min: false) : _intrinsicMain(width, min: false);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      LayoutProfile.measure('flex.paint', () => paintStacked(context, offset));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      hitTestStacked(result, position);
}
