import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativa_css/nativa_css.dart';

import 'css_item.dart';

/// A grid container implementing the supported subset of CSS Grid Layout:
///
/// * explicit tracks from `grid-template-columns/rows` with lengths,
///   percentages, `calc()`/`min()`/`max()`, `fr`, `auto`, `min-content`,
///   `max-content`, `fit-content()`, `minmax()` and `repeat()` (including
///   `auto-fill` and `auto-fit`, whose empty tracks collapse);
/// * implicit tracks from `grid-auto-rows/columns`;
/// * placement by line numbers (negative included), `span`, named areas
///   from `grid-template-areas`, and row/column auto-placement (sparse);
/// * `gap`, `justify-items`/`align-items`, `justify-self`/`align-self`,
///   `justify-content`/`align-content` (`normal`/`stretch` grow `auto`
///   tracks).
///
/// Track sizing follows the spec's phases (base sizes from content
/// contributions, maximize, expand flexible tracks, stretch auto tracks)
/// with one simplification: items spanning several tracks distribute their
/// extra size equally over the spanned intrinsic tracks.
class CssGridLayout extends MultiChildRenderObjectWidget {
  const CssGridLayout({
    super.key,
    this.columns,
    this.rows,
    this.autoColumns = const [TrackSize.auto],
    this.autoRows = const [TrackSize.auto],
    this.areas,
    this.autoFlow = 'row',
    this.rowGap = ResolvedLength.zero,
    this.columnGap = ResolvedLength.zero,
    this.justifyItems = 'normal',
    this.alignItems = 'normal',
    this.justifyContent = 'normal',
    this.alignContent = 'normal',
    super.children,
  });

  final GridTracksValue? columns;
  final GridTracksValue? rows;
  final List<TrackSize> autoColumns;
  final List<TrackSize> autoRows;
  final GridAreasValue? areas;
  final String autoFlow;
  final ResolvedLength rowGap;
  final ResolvedLength columnGap;
  final String justifyItems;
  final String alignItems;
  final String justifyContent;
  final String alignContent;

  @override
  RenderCssGrid createRenderObject(BuildContext context) => RenderCssGrid()..apply(this);

  @override
  void updateRenderObject(BuildContext context, RenderCssGrid renderObject) => renderObject.apply(this);
}

class _Placement {
  _Placement(this.child, this.pd);
  final RenderBox child;
  final CssItemParentData pd;
  int row = 0, col = 0, rowSpan = 1, colSpan = 1;
  double minW = 0, maxW = 0, height = 0;
  double mL = 0, mR = 0, mT = 0, mB = 0;
}

class _Track {
  _Track(this.size);
  final TrackSize size;
  double base = 0;
  double limit = 0;
  bool collapsed = false;
  bool get isFlex => size.max.kind == 'fr';
}

class RenderCssGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, CssItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, CssItemParentData>,
        CssStackingPaint {
  GridTracksValue? _columns;
  GridTracksValue? _rows;
  List<TrackSize> _autoColumns = const [TrackSize.auto];
  List<TrackSize> _autoRows = const [TrackSize.auto];
  GridAreasValue? _areas;
  String _autoFlow = 'row';
  ResolvedLength _rowGap = ResolvedLength.zero;
  ResolvedLength _columnGap = ResolvedLength.zero;
  String _justifyItems = 'normal';
  String _alignItems = 'normal';
  String _justifyContent = 'normal';
  String _alignContent = 'normal';

  void apply(CssGridLayout w) {
    var changed = false;
    void set<T>(T a, T b, void Function() f) {
      if (a != b) {
        f();
        changed = true;
      }
    }

    set(_columns, w.columns, () => _columns = w.columns);
    set(_rows, w.rows, () => _rows = w.rows);
    set('${_autoColumns.join(' ')}', '${w.autoColumns.join(' ')}', () => _autoColumns = w.autoColumns);
    set('${_autoRows.join(' ')}', '${w.autoRows.join(' ')}', () => _autoRows = w.autoRows);
    set(_areas, w.areas, () => _areas = w.areas);
    set(_autoFlow, w.autoFlow, () => _autoFlow = w.autoFlow);
    set(_rowGap, w.rowGap, () => _rowGap = w.rowGap);
    set(_columnGap, w.columnGap, () => _columnGap = w.columnGap);
    set(_justifyItems, w.justifyItems, () => _justifyItems = w.justifyItems);
    set(_alignItems, w.alignItems, () => _alignItems = w.alignItems);
    set(_justifyContent, w.justifyContent, () => _justifyContent = w.justifyContent);
    set(_alignContent, w.alignContent, () => _alignContent = w.alignContent);
    if (changed) markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! CssItemParentData) child.parentData = CssItemParentData();
  }

  // --- track lists -------------------------------------------------------------

  /// Size a repetition takes for `auto-fill`/`auto-fit` (spec §7.2.3.2).
  double? _fixedSize(TrackSize t, double? basis) {
    double? definite(TrackBreadth b) {
      if (b.kind != 'length') return null;
      final l = b.length!;
      if (l is Length) return l.unit == LengthUnit.percent ? (basis == null ? null : basis * l.value / 100) : l.value;
      if (l is CalcLength) return l.node.evaluate(basis);
      return null;
    }

    final max = definite(t.max);
    final min = definite(t.min);
    if (max != null) return min == null ? max : math.max(min, max);
    return min;
  }

  /// Expands the template into tracks; returns the tracks and, for
  /// `auto-fit`, the indexes of collapsible tracks.
  (List<TrackSize>, Set<int>) _expand(GridTracksValue? template, double? available, double gap) {
    final out = <TrackSize>[];
    final autoFit = <int>{};
    if (template == null) return (out, autoFit);
    for (final e in template.entries) {
      if (e.auto == null) {
        for (var i = 0; i < e.count; i++) {
          out.addAll(e.tracks);
        }
        continue;
      }
      var reps = 1;
      if (available != null) {
        // Space taken by the other (non-repeated) tracks.
        var other = 0.0;
        var otherCount = 0;
        for (final o in template.entries) {
          if (identical(o, e)) continue;
          for (var i = 0; i < o.count; i++) {
            for (final t in o.tracks) {
              other += _fixedSize(t, available) ?? 0;
              otherCount++;
            }
          }
        }
        var rep = 0.0;
        var ok = true;
        for (final t in e.tracks) {
          final f = _fixedSize(t, available);
          if (f == null || f <= 0) ok = false;
          rep += f ?? 0;
        }
        if (ok) {
          final n = e.tracks.length;
          final free = available - other - otherCount * gap;
          // reps * rep + (reps * n - 1) * gap <= free  (when other tracks exist, one more gap)
          final per = rep + n * gap;
          reps = math.max(1, ((free + gap) / per).floor());
        }
      }
      for (var i = 0; i < reps; i++) {
        for (final t in e.tracks) {
          if (e.auto == 'auto-fit') autoFit.add(out.length);
          out.add(t);
        }
      }
    }
    return (out, autoFit);
  }

  // --- placement ---------------------------------------------------------------

  Map<String, (int, int, int, int)> _areaMap() {
    final areas = <String, (int, int, int, int)>{};
    final a = _areas;
    if (a == null) return areas;
    for (var r = 0; r < a.rows.length; r++) {
      for (var c = 0; c < a.rows[r].length; c++) {
        final name = a.rows[r][c];
        if (name == '.' || RegExp(r'^\.+$').hasMatch(name)) continue;
        final cur = areas[name];
        areas[name] = cur == null
            ? (r, c, r + 1, c + 1)
            : (math.min(cur.$1, r), math.min(cur.$2, c), math.max(cur.$3, r + 1), math.max(cur.$4, c + 1));
      }
    }
    return areas;
  }

  /// Resolves start/end lines on one axis to (start index or null, span).
  (int?, int) _resolve(GridLineValue start, GridLineValue end, int explicit, Map<String, (int, int, int, int)> areas,
      {required bool rows}) {
    int? lineOf(GridLineValue v, {required bool isStart}) {
      if (v.line != null) {
        final l = v.line!;
        return l > 0 ? l - 1 : explicit + 1 + l;
      }
      final name = v.name;
      if (name != null && v.span == null) {
        var n = name;
        var startSide = isStart;
        if (n.endsWith('-start')) {
          n = n.substring(0, n.length - 6);
          startSide = true;
        } else if (n.endsWith('-end')) {
          n = n.substring(0, n.length - 4);
          startSide = false;
        }
        final area = areas[n];
        if (area == null) return null;
        return rows ? (startSide ? area.$1 : area.$3) : (startSide ? area.$2 : area.$4);
      }
      return null;
    }

    final s = lineOf(start, isStart: true);
    final e = lineOf(end, isStart: false);
    if (s != null && e != null) {
      if (e == s) return (s, 1);
      return (math.min(s, e), (e - s).abs());
    }
    if (s != null) return (s, end.span ?? 1);
    if (e != null) {
      final span = start.span ?? 1;
      return (math.max(0, e - span), span);
    }
    return (null, start.span ?? end.span ?? 1);
  }

  List<_Placement> _place(int explicitCols, int explicitRows, double? cbw) {
    final areas = _areaMap();
    final items = <_Placement>[];
    for (var c = firstChild; c != null; c = (c.parentData! as CssItemParentData).nextSibling) {
      final pd = c.parentData! as CssItemParentData;
      final p = _Placement(c, pd);
      final basis = cbw ?? 0;
      p
        ..mL = pd.resolveMargin(pd.marginLeft, basis)
        ..mR = pd.resolveMargin(pd.marginRight, basis)
        ..mT = pd.resolveMargin(pd.marginTop, basis)
        ..mB = pd.resolveMargin(pd.marginBottom, basis);
      items.add(p);
    }
    // `order` affects auto-placement and painting order.
    final ordered = List.of(items);
    if (items.any((i) => i.pd.order != 0)) mergeSort(ordered, compare: (a, b) => a.pd.order - b.pd.order);

    final occupied = <int, Set<int>>{}; // row -> columns
    bool free(int r, int c, int rs, int cs) {
      for (var y = r; y < r + rs; y++) {
        final set = occupied[y];
        if (set == null) continue;
        for (var x = c; x < c + cs; x++) {
          if (set.contains(x)) return false;
        }
      }
      return true;
    }

    void mark(_Placement p) {
      for (var y = p.row; y < p.row + p.rowSpan; y++) {
        final set = occupied.putIfAbsent(y, () => {});
        for (var x = p.col; x < p.col + p.colSpan; x++) {
          set.add(x);
        }
      }
    }

    final pending = <(_Placement, int?, int?)>[];
    var colCount = math.max(1, explicitCols);
    for (final p in ordered) {
      final (r, rs) = _resolve(p.pd.gridRowStart, p.pd.gridRowEnd, explicitRows, areas, rows: true);
      final (c, cs) = _resolve(p.pd.gridColumnStart, p.pd.gridColumnEnd, explicitCols, areas, rows: false);
      p
        ..rowSpan = math.max(1, rs)
        ..colSpan = math.max(1, cs);
      if (c != null) colCount = math.max(colCount, c + p.colSpan);
      if (c == null && cs > colCount) colCount = cs;
      if (r != null && c != null) {
        p
          ..row = math.max(0, r)
          ..col = math.max(0, c);
        mark(p);
      } else {
        pending.add((p, r, c));
      }
    }

    final column = _autoFlow == 'column';
    // Items locked to a row (or column in column flow) first.
    for (final (p, r, c) in pending) {
      if (column ? c == null : r == null) continue;
      if (!column) {
        p.row = math.max(0, r!);
        var x = 0;
        while (!free(p.row, x, p.rowSpan, p.colSpan) && x < 10000) {
          x++;
        }
        p.col = x;
      } else {
        p.col = math.max(0, c!);
        var y = 0;
        while (!free(y, p.col, p.rowSpan, p.colSpan) && y < 10000) {
          y++;
        }
        p.row = y;
      }
      colCount = math.max(colCount, p.col + p.colSpan);
      mark(p);
    }
    var curRow = 0, curCol = 0;
    for (final (p, r, c) in pending) {
      if (column ? c != null : r != null) continue;
      if (!column) {
        if (c != null) {
          // Definite column: move the cursor down to a free row.
          if (c < curCol) curRow++;
          curCol = c;
          while (!free(curRow, c, p.rowSpan, p.colSpan) && curRow < 10000) {
            curRow++;
          }
          p
            ..row = curRow
            ..col = c;
        } else {
          final span = math.min(p.colSpan, colCount);
          while (true) {
            if (curCol + span > colCount) {
              curCol = 0;
              curRow++;
            }
            if (free(curRow, curCol, p.rowSpan, span)) break;
            curCol++;
            if (curRow > 10000) break;
          }
          p
            ..row = curRow
            ..col = curCol
            ..colSpan = span;
        }
        curCol = p.col + p.colSpan;
      } else {
        // Column flow: fill rows within the explicit row count.
        final rowCount = math.max(1, explicitRows);
        while (true) {
          if (curRow + p.rowSpan > rowCount) {
            curRow = 0;
            curCol++;
          }
          if (free(curRow, curCol, p.rowSpan, p.colSpan)) break;
          curRow++;
          if (curCol > 10000) break;
        }
        p
          ..row = curRow
          ..col = curCol;
        curRow = p.row + p.rowSpan;
      }
      colCount = math.max(colCount, p.col + p.colSpan);
      mark(p);
    }
    return items;
  }

  // --- track sizing ------------------------------------------------------------

  double? _breadthValue(TrackBreadth b, double? basis) {
    if (b.kind != 'length') return null;
    final l = b.length!;
    if (l is Length) {
      if (l.unit == LengthUnit.percent) return basis == null ? null : basis * l.value / 100;
      return l.value;
    }
    if (l is CalcLength) return l.node.evaluate(basis) ?? l.node.evaluate(0);
    return null;
  }

  /// Sizes [tracks] given item contributions. [available] is the definite
  /// container size (null = intrinsic). [contribution] returns an item's
  /// (min-content, max-content) size on this axis.
  void _sizeTracks(
    List<_Track> tracks,
    List<_Placement> items,
    double? available,
    double gap, {
    required bool columns,
    required (double, double) Function(_Placement) contribution,
    required String justify,
  }) {
    final basis = available;
    for (final t in tracks) {
      final min = _breadthValue(t.size.min, basis);
      final max = _breadthValue(t.size.max, basis);
      t.base = min ?? 0;
      if (t.size.max.kind == 'fit-content') {
        t.limit = double.infinity;
      } else {
        t.limit = max ?? (t.isFlex ? double.infinity : (t.size.max.kind == 'length' ? 0 : double.infinity));
      }
      if (max != null && t.size.max.kind == 'length') t.limit = math.max(max, t.base);
    }

    int start(_Placement p) => columns ? p.col : p.row;
    int span(_Placement p) => columns ? p.colSpan : p.rowSpan;

    // Intrinsic contributions, single-span items first.
    final infiniteLimit = <_Track>{};
    for (final t in tracks) {
      if (t.limit == double.infinity && !t.isFlex) infiniteLimit.add(t);
    }
    final contentMax = List<double>.filled(tracks.length, 0);
    final hasItems = List<bool>.filled(tracks.length, false);
    for (final p in items) {
      final s = start(p);
      if (s >= tracks.length) continue;
      for (var k = s; k < math.min(tracks.length, s + span(p)); k++) {
        hasItems[k] = true;
      }
    }
    for (final p in items.where((p) => span(p) == 1)) {
      final s = start(p);
      if (s >= tracks.length) continue;
      final t = tracks[s];
      final (minC, maxC) = contribution(p);
      final minKind = t.size.min.kind;
      if (minKind == 'auto' || minKind == 'min-content') {
        t.base = math.max(t.base, minC);
      } else if (minKind == 'max-content') {
        t.base = math.max(t.base, maxC);
      }
      contentMax[s] = math.max(contentMax[s], maxC);
    }
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final maxKind = t.size.max.kind;
      if (maxKind == 'auto' || maxKind == 'max-content') {
        t.limit = math.max(t.base, contentMax[i]);
      } else if (maxKind == 'min-content') {
        t.limit = t.base;
      } else if (maxKind == 'fit-content') {
        final cap = _breadthValue(TrackBreadth.length(t.size.max.length!), basis) ?? double.infinity;
        t.limit = math.max(t.base, math.min(contentMax[i], cap));
      }
      if (t.limit < t.base) t.limit = t.base;
    }
    // Spanning items: spread what they still need over intrinsic tracks.
    for (final p in items.where((p) => span(p) > 1)) {
      final s = start(p);
      if (s >= tracks.length) continue;
      final spanned = tracks.sublist(s, math.min(tracks.length, s + span(p)));
      final (minC, maxC) = contribution(p);
      final gaps = gap * (spanned.length - 1);
      final intrinsic = spanned.where((t) => t.size.min.kind != 'length' && !t.isFlex).toList();
      if (intrinsic.isEmpty) continue;
      final haveBase = spanned.fold<double>(0, (a, t) => a + t.base) + gaps;
      if (minC > haveBase) {
        final extra = (minC - haveBase) / intrinsic.length;
        for (final t in intrinsic) {
          t.base += extra;
          if (t.limit < t.base) t.limit = t.base;
        }
      }
      final haveLimit = spanned.fold<double>(0, (a, t) => a + (t.limit.isFinite ? t.limit : t.base)) + gaps;
      if (maxC > haveLimit) {
        final extra = (maxC - haveLimit) / intrinsic.length;
        for (final t in intrinsic) {
          if (t.limit.isFinite) t.limit += extra;
        }
      }
    }

    // auto-fit collapses tracks without items.
    final collapsedCount = tracks.where((t) => t.collapsed).length;
    final visible = tracks.length - collapsedCount;
    final totalGap = gap * math.max(0, visible - 1);

    double sumBase() => tracks.fold<double>(0, (a, t) => a + (t.collapsed ? 0 : t.base));

    // Maximize: grow tracks toward their limits.
    if (available != null) {
      var free = available - sumBase() - totalGap;
      final growable = tracks.where((t) => !t.collapsed && !t.isFlex && t.limit.isFinite && t.limit > t.base).toList();
      while (free > 0.01 && growable.isNotEmpty) {
        final share = free / growable.length;
        for (final t in List.of(growable)) {
          final add = math.min(share, t.limit - t.base);
          t.base += add;
          free -= add;
          if (t.limit - t.base < 0.01) growable.remove(t);
        }
      }
    } else {
      for (final t in tracks) {
        if (!t.collapsed && !t.isFlex && t.limit.isFinite) t.base = t.limit;
      }
    }

    // Expand flexible tracks.
    final flex = tracks.where((t) => t.isFlex && !t.collapsed).toList();
    if (flex.isNotEmpty) {
      double frSize;
      if (available != null) {
        final inflexible = <_Track>{};
        while (true) {
          final leftover = available -
              totalGap -
              tracks.where((t) => !t.collapsed && (!t.isFlex || inflexible.contains(t))).fold<double>(0, (a, t) => a + t.base);
          final active = flex.where((t) => !inflexible.contains(t)).toList();
          final sum = active.fold<double>(0, (a, t) => a + t.size.max.fr);
          // The spec floors the flex factor sum at 1.
          frSize = sum <= 0 ? 0 : math.max(0, leftover) / math.max(sum, 1.0);
          final violators = active.where((t) => t.size.max.fr * frSize < t.base).toList();
          if (violators.isEmpty) break;
          inflexible.addAll(violators);
          if (inflexible.length == flex.length) break;
        }
        for (final t in flex) {
          if (inflexible.contains(t)) continue;
          t.base = math.max(t.base, t.size.max.fr * frSize);
        }
      } else {
        // Intrinsic: the fr size that fits every flex track's max-content.
        frSize = 0;
        for (var i = 0; i < tracks.length; i++) {
          final t = tracks[i];
          if (!t.isFlex || t.collapsed) continue;
          final fr = t.size.max.fr;
          if (fr <= 0) continue;
          frSize = math.max(frSize, math.max(t.base, contentMax[i]) / (fr < 1 ? 1 : fr));
        }
        for (final t in flex) {
          t.base = math.max(t.base, t.size.max.fr * frSize);
        }
      }
    }

    // Stretch auto tracks (justify/align-content normal or stretch).
    if (available != null && flex.isEmpty && (justify == 'normal' || justify == 'stretch')) {
      final autos = tracks.where((t) => !t.collapsed && t.size.max.kind == 'auto').toList();
      final free = available - sumBase() - totalGap;
      if (free > 0 && autos.isNotEmpty) {
        for (final t in autos) {
          t.base += free / autos.length;
        }
      }
    }
  }

  // --- layout ------------------------------------------------------------------

  Size _run(BoxConstraints constraints, {required bool dry}) {
    final cbw = constraints.hasBoundedWidth ? constraints.maxWidth : null;
    final cbh = constraints.hasTightHeight ? constraints.maxHeight : null;
    final colGap = _columnGap.resolve(cbw) ?? 0;
    final rowGap = _rowGap.resolve(cbh) ?? 0;

    final (colTemplate, autoFitCols) = _expand(_columns, cbw, colGap);
    final (rowTemplate, autoFitRows) = _expand(_rows, cbh, rowGap);
    final areaRows = _areas?.rows.length ?? 0;
    final areaCols = _areas?.rows.firstOrNull?.length ?? 0;
    final explicitCols = math.max(colTemplate.length, areaCols);
    final explicitRows = math.max(rowTemplate.length, areaRows);

    final items = _place(explicitCols, explicitRows, cbw);
    var colCount = explicitCols;
    var rowCount = explicitRows;
    for (final p in items) {
      colCount = math.max(colCount, p.col + p.colSpan);
      rowCount = math.max(rowCount, p.row + p.rowSpan);
    }
    colCount = math.max(colCount, 1);

    TrackSize trackAt(List<TrackSize> template, List<TrackSize> auto, int i) {
      if (i < template.length) return template[i];
      if (auto.isEmpty) return TrackSize.auto;
      return auto[(i - template.length) % auto.length];
    }

    final cols = [for (var i = 0; i < colCount; i++) _Track(trackAt(colTemplate, _autoColumns, i))];
    final rows = [for (var i = 0; i < rowCount; i++) _Track(trackAt(rowTemplate, _autoRows, i))];
    bool occupiedCol(int i) => items.any((p) => i >= p.col && i < p.col + p.colSpan);
    bool occupiedRow(int i) => items.any((p) => i >= p.row && i < p.row + p.rowSpan);
    for (final i in autoFitCols) {
      if (i < cols.length && !occupiedCol(i)) cols[i].collapsed = true;
    }
    for (final i in autoFitRows) {
      if (i < rows.length && !occupiedRow(i)) rows[i].collapsed = true;
    }

    for (final p in items) {
      p.minW = p.child.getMinIntrinsicWidth(double.infinity) + p.mL + p.mR;
      p.maxW = p.child.getMaxIntrinsicWidth(double.infinity) + p.mL + p.mR;
    }
    _sizeTracks(cols, items, cbw, colGap,
        columns: true, contribution: (p) => (p.minW, p.maxW), justify: _justifyContent);

    double span(List<_Track> tracks, int start, int count, double gap) {
      var w = 0.0;
      var visible = 0;
      for (var k = start; k < math.min(tracks.length, start + count); k++) {
        if (tracks[k].collapsed) continue;
        w += tracks[k].base;
        visible++;
      }
      return w + gap * math.max(0, visible - 1);
    }

    String justifyOf(_Placement p) {
      final j = p.pd.justifySelf == 'auto' ? _justifyItems : p.pd.justifySelf;
      return j == 'legacy' ? 'normal' : j;
    }

    String alignOf(_Placement p) => p.pd.alignSelf == 'auto' ? _alignItems : p.pd.alignSelf;

    bool stretchesX(_Placement p) {
      final j = justifyOf(p);
      return (j == 'stretch' || (j == 'normal' && !p.pd.replaced)) && p.pd.autoWidth && p.pd.marginLeft != null && p.pd.marginRight != null;
    }

    bool stretchesY(_Placement p) {
      final a = alignOf(p);
      return (a == 'stretch' || (a == 'normal' && !p.pd.replaced)) && p.pd.autoHeight && p.pd.marginTop != null && p.pd.marginBottom != null;
    }

    BoxConstraints widthConstraints(_Placement p, double areaW) {
      final inner = math.max(0.0, areaW - p.mL - p.mR);
      return stretchesX(p) ? BoxConstraints.tightFor(width: inner) : BoxConstraints(maxWidth: inner);
    }

    Size measure(RenderBox c, BoxConstraints cc) {
      if (dry) return c.getDryLayout(cc);
      c.layout(cc, parentUsesSize: true);
      return c.size;
    }

    // Row sizing uses each item's height at its column width.
    for (final p in items) {
      final areaW = span(cols, p.col, p.colSpan, colGap);
      p.pd.containingWidth = areaW;
      p.pd.containingHeight = null;
      final s = p.child.getDryLayout(widthConstraints(p, areaW));
      p.height = s.height + p.mT + p.mB;
    }
    _sizeTracks(rows, items, cbh, rowGap,
        columns: false, contribution: (p) => (p.height, p.height), justify: _alignContent);
    // An auto-height grid still grows to its min-height, and align-content
    // `normal`/`stretch` hands that free space to the auto rows.
    if (cbh == null && (_alignContent == 'normal' || _alignContent == 'stretch')) {
      final free = constraints.minHeight - span(rows, 0, rows.length, rowGap);
      final autos = rows.where((t) => !t.collapsed && t.size.max.kind == 'auto').toList();
      if (free > 0 && autos.isNotEmpty) {
        for (final t in autos) {
          t.base += free / autos.length;
        }
      }
    }

    double offsetOf(List<_Track> tracks, int index, double gap, double lead, double between) {
      var o = lead;
      for (var k = 0; k < index && k < tracks.length; k++) {
        if (tracks[k].collapsed) continue;
        o += tracks[k].base + gap + between;
      }
      return o;
    }

    final gridW = span(cols, 0, cols.length, colGap);
    final gridH = span(rows, 0, rows.length, rowGap);
    final width = cbw ?? gridW;
    final height = constraints.constrainHeight(cbh ?? gridH);
    final size = constraints.constrain(Size(width, height));
    if (dry) return size;

    (double, double) distribute(String mode, double free, int n) {
      if (free <= 0 || n == 0) return (0, 0);
      return switch (mode) {
        'center' => (free / 2, 0),
        'end' || 'flex-end' || 'right' => (free, 0),
        'space-between' => (0, n > 1 ? free / (n - 1) : 0),
        'space-around' => (free / n / 2, free / n),
        'space-evenly' => (free / (n + 1), free / (n + 1)),
        _ => (0, 0),
      };
    }

    final visibleCols = cols.where((t) => !t.collapsed).length;
    final visibleRows = rows.where((t) => !t.collapsed).length;
    final (colLead, colBetween) = distribute(_justifyContent, size.width - gridW, visibleCols);
    final (rowLead, rowBetween) = distribute(_alignContent, size.height - gridH, visibleRows);

    for (final p in items) {
      final x0 = offsetOf(cols, p.col, colGap, colLead, colBetween);
      final y0 = offsetOf(rows, p.row, rowGap, rowLead, rowBetween);
      final areaW = span(cols, p.col, p.colSpan, colGap) + colBetween * (p.colSpan - 1);
      final areaH = span(rows, p.row, p.rowSpan, rowGap) + rowBetween * (p.rowSpan - 1);
      p.pd.containingWidth = areaW;
      p.pd.containingHeight = areaH;
      final innerW = math.max(0.0, areaW - p.mL - p.mR);
      final innerH = math.max(0.0, areaH - p.mT - p.mB);
      final cc = BoxConstraints(
        minWidth: stretchesX(p) ? innerW : 0,
        maxWidth: innerW,
        minHeight: stretchesY(p) ? innerH : 0,
        maxHeight: stretchesY(p) ? innerH : double.infinity,
      );
      final s = measure(p.child, cc);
      double place(String mode, double free, bool autoStart, bool autoEnd) {
        if (autoStart && autoEnd) return free / 2;
        if (autoStart) return free;
        if (autoEnd) return 0;
        return switch (mode) {
          'center' => free / 2,
          'end' || 'flex-end' || 'self-end' || 'right' => free,
          _ => 0,
        };
      }

      final dx = place(justifyOf(p), innerW - s.width, p.pd.marginLeft == null, p.pd.marginRight == null);
      final dy = place(alignOf(p), innerH - s.height, p.pd.marginTop == null, p.pd.marginBottom == null);
      p.pd.offset = Offset(x0 + p.mL + dx, y0 + p.mT + dy);
    }
    return size;
  }

  @override
  void performLayout() {
    size = _run(constraints, dry: false);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _run(constraints, dry: true);

  double _intrinsicWidth({required bool min}) {
    final (colTemplate, _) = _expand(_columns, null, 0);
    final areaCols = _areas?.rows.firstOrNull?.length ?? 0;
    final explicitCols = math.max(colTemplate.length, areaCols);
    final explicitRows = math.max(_expand(_rows, null, 0).$1.length, _areas?.rows.length ?? 0);
    final items = _place(explicitCols, explicitRows, null);
    var colCount = math.max(1, explicitCols);
    for (final p in items) {
      colCount = math.max(colCount, p.col + p.colSpan);
      p.minW = p.child.getMinIntrinsicWidth(double.infinity) + p.mL + p.mR;
      p.maxW = p.child.getMaxIntrinsicWidth(double.infinity) + p.mL + p.mR;
    }
    final gap = _columnGap.isPercent ? 0.0 : _columnGap.value;
    final cols = [
      for (var i = 0; i < colCount; i++)
        _Track(i < colTemplate.length
            ? colTemplate[i]
            : (_autoColumns.isEmpty ? TrackSize.auto : _autoColumns[(i - colTemplate.length) % _autoColumns.length])),
    ];
    _sizeTracks(cols, items, null, gap,
        columns: true, contribution: (p) => min ? (p.minW, p.minW) : (p.minW, p.maxW), justify: 'start');
    return cols.fold<double>(0, (a, t) => a + t.base) + gap * math.max(0, cols.length - 1);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth(min: true);

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth(min: false);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _run(BoxConstraints(maxWidth: width.isFinite ? width : double.infinity), dry: true).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) => paintStacked(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      hitTestStacked(result, position);
}
