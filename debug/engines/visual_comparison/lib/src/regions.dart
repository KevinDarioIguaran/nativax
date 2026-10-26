import 'dart:math' as math;
import 'dart:typed_data';

import 'color.dart';
import 'model.dart';
import 'png.dart';

/// ΔE76 above which a pixel belongs to the difference mask. Same value as the
/// mismatch threshold of [comparePixels].
const double defaultMaskThreshold = 2.0;

/// Connected components with fewer pixels than this are dropped from the
/// region list (but still counted in `dropped`). Chosen a priori as the
/// smallest blob that is not a 1–3 px speckle; `metrics-visual.md` shows the
/// measured effect of other values.
const int defaultMinRegionArea = 4;

/// Components whose boxes are at most this many px apart form one region.
/// Measured on the audit dataset (`metrics-visual.md`, merge-gap sweep).
const int defaultMergeGap = 4;

/// A group below [defaultMinRegionArea] is kept when its max ΔE reaches this
/// value: a 1 px black-on-white change is an edit, not speckle.
const double defaultStrongDeltaE = 50;

/// Regions kept in `regions.json`, largest first. Totals stay exact.
const int defaultMaxRegions = 500;

/// Elements listed per region, best IoU first.
const int defaultMaxElementsPerRegion = 8;

/// Per-pixel CIE76 ΔE over the common area of both images, row-major.
class DeltaMap {
  DeltaMap(
    this.width,
    this.height,
    this.values, {
    int? fullWidth,
    int? fullHeight,
  }) : fullWidth = fullWidth ?? width,
       fullHeight = fullHeight ?? height;
  final int width;
  final int height;
  final Float32List values;

  /// Size of the union of both images; larger than the common area when the
  /// captures differ in size.
  final int fullWidth;
  final int fullHeight;
}

DeltaMap deltaMap(RasterImage reference, RasterImage actual) {
  final width = math.min(reference.width, actual.width);
  final height = math.min(reference.height, actual.height);
  final values = Float32List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * reference.width + x) * 4;
      final j = (y * actual.width + x) * 4;
      values[y * width + x] = deltaE(
        reference.rgba[i],
        reference.rgba[i + 1],
        reference.rgba[i + 2],
        actual.rgba[j],
        actual.rgba[j + 1],
        actual.rgba[j + 2],
      );
    }
  }
  return DeltaMap(
    width,
    height,
    values,
    fullWidth: math.max(reference.width, actual.width),
    fullHeight: math.max(reference.height, actual.height),
  );
}

class RegionElement {
  const RegionElement({
    required this.path,
    required this.tag,
    required this.iou,
    required this.sides,
  });
  final String path;
  final String tag;

  /// Best bbox IoU between the region and the element rect on either side.
  final double iou;

  /// `reference` and/or `actual`: the probe(s) whose rect intersects.
  final List<String> sides;

  Map<String, Object> toJson() => {
    'path': path,
    'tag': tag,
    'iou': _round(iou, 4),
    'sides': sides,
  };
}

class DiffRegion {
  DiffRegion({
    required this.id,
    required this.bbox,
    required this.pixels,
    required this.meanDeltaE,
    required this.maxDeltaE,
    this.components = 1,
    this.kind = 'pixels',
    this.elements = const [],
  });

  final int id;

  /// Integer pixel box `[x, y, w, h]`.
  final BoxRect bbox;
  final int pixels;
  final double meanDeltaE;
  final double maxDeltaE;

  /// Connected components merged into this region.
  final int components;

  /// `pixels` (ΔE mask) or `size` (area only one image covers).
  final String kind;
  final List<RegionElement> elements;

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind,
    'bbox': [
      bbox.x.toInt(),
      bbox.y.toInt(),
      bbox.width.toInt(),
      bbox.height.toInt(),
    ],
    'pixels': pixels,
    'meanDeltaE': _round(meanDeltaE, 2),
    'maxDeltaE': _round(maxDeltaE, 2),
    'components': components,
    'elements': [for (final e in elements) e.toJson()],
  };
}

class RegionReport {
  RegionReport({
    required this.width,
    required this.height,
    required this.threshold,
    required this.minArea,
    required this.mergeGap,
    required this.strongDeltaE,
    required this.maskPixels,
    required this.components,
    required this.regions,
    required this.keptPixels,
    required this.droppedComponents,
    required this.droppedPixels,
    required this.truncated,
  });

  final int width;
  final int height;
  final double threshold;
  final int minArea;
  final int mergeGap;
  final double strongDeltaE;

  /// Pixels with ΔE > [threshold].
  final int maskPixels;

  /// Connected components before the min-area filter.
  final int components;
  final List<DiffRegion> regions;

  /// Mask pixels inside components that pass the min-area filter.
  final int keptPixels;
  final int droppedComponents;
  final int droppedPixels;

  /// True when more than [defaultMaxRegions] regions passed the filter.
  final bool truncated;

  Map<String, Object> toJson() => {
    'schema': 'nativa_visual.regions/2',
    'width': width,
    'height': height,
    'mask': {
      'metric': 'CIE76 deltaE (sRGB -> Lab, D65)',
      'threshold': threshold,
      'rule': 'deltaE > threshold',
      'pixels': maskPixels,
    },
    'connectivity': 8,
    'minArea': minArea,
    'mergeGap': mergeGap,
    'grouping':
        'components whose boxes are at most mergeGap px apart are one region',
    'strongDeltaE': strongDeltaE,
    'filter':
        'groups with fewer than minArea pixels and max deltaE below strongDeltaE are dropped; size regions cover pixels only one image has',
    'components': components,
    'keptRegions': regions.length,
    'keptPixels': keptPixels,
    'droppedComponents': droppedComponents,
    'droppedPixels': droppedPixels,
    'truncated': truncated,
    'regions': [for (final r in regions) r.toJson()],
  };
}

/// Labels the ΔE > [threshold] mask with 8-neighbourhood connectivity, groups
/// components whose boxes are at most [mergeGap] px apart (one moved card or
/// changed word is one region, not one per fragment), drops groups smaller
/// than [minArea] unless their max ΔE reaches [strongDeltaE], adds the strips
/// that only one image covers, and attributes each kept region to the probe
/// elements whose rects intersect its bounding box.
RegionReport findRegions(
  DeltaMap map, {
  double threshold = defaultMaskThreshold,
  int minArea = defaultMinRegionArea,
  int mergeGap = defaultMergeGap,
  double strongDeltaE = defaultStrongDeltaE,
  List<ElementSnapshot> referenceElements = const [],
  List<ElementSnapshot> actualElements = const [],
  int maxRegions = defaultMaxRegions,
  int maxElementsPerRegion = defaultMaxElementsPerRegion,
}) {
  final w = map.width;
  final h = map.height;
  final n = w * h;
  final labels = Int32List(n); // 0 = unvisited/background.
  final queue = Int32List(n);
  final parts = <_Component>[];
  var maskPixels = 0;

  for (var start = 0; start < n; start++) {
    if (map.values[start] <= threshold) continue;
    maskPixels++;
    if (labels[start] != 0) continue;
    labels[start] = parts.length + 1;
    var head = 0, tail = 0;
    queue[tail++] = start;
    var minX = w, minY = h, maxX = -1, maxY = -1;
    var sum = 0.0, max = 0.0;
    while (head < tail) {
      final p = queue[head++];
      final px = p % w, py = p ~/ w;
      final de = map.values[p];
      sum += de;
      if (de > max) max = de;
      if (px < minX) minX = px;
      if (px > maxX) maxX = px;
      if (py < minY) minY = py;
      if (py > maxY) maxY = py;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = py + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = px + dx;
          if (nx < 0 || nx >= w) continue;
          final q = ny * w + nx;
          if (labels[q] != 0 || map.values[q] <= threshold) continue;
          labels[q] = parts.length + 1;
          queue[tail++] = q;
        }
      }
    }
    parts.add(_Component(minX, minY, maxX, maxY, tail, sum, max));
  }

  final groups = _group(parts, mergeGap);
  final found = <DiffRegion>[];
  var droppedComponents = 0;
  var droppedPixels = 0;
  var keptPixels = 0;
  for (final g in groups) {
    if (g.pixels < minArea && g.max < strongDeltaE) {
      droppedComponents += g.components;
      droppedPixels += g.pixels;
      continue;
    }
    keptPixels += g.pixels;
    found.add(
      DiffRegion(
        id: 0,
        bbox: BoxRect(
          g.minX.toDouble(),
          g.minY.toDouble(),
          (g.maxX - g.minX + 1).toDouble(),
          (g.maxY - g.minY + 1).toDouble(),
        ),
        pixels: g.pixels,
        meanDeltaE: g.sum / g.pixels,
        maxDeltaE: g.max,
        components: g.components,
      ),
    );
  }

  // Largest first; ties broken by position so the order is deterministic.
  found.sort((a, b) {
    final byPixels = b.pixels.compareTo(a.pixels);
    if (byPixels != 0) return byPixels;
    final byY = a.bbox.y.compareTo(b.bbox.y);
    return byY != 0 ? byY : a.bbox.x.compareTo(b.bbox.x);
  });
  // Pixels only one image has cannot be compared, but they differ.
  final strips = [
    if (map.fullWidth > w)
      BoxRect(
        w.toDouble(),
        0,
        (map.fullWidth - w).toDouble(),
        map.fullHeight.toDouble(),
      ),
    if (map.fullHeight > h)
      BoxRect(0, h.toDouble(), w.toDouble(), (map.fullHeight - h).toDouble()),
  ];
  final kept = [
    for (final s in strips)
      DiffRegion(
        id: 0,
        bbox: s,
        pixels: (s.width * s.height).toInt(),
        meanDeltaE: 0,
        maxDeltaE: 0,
        kind: 'size',
      ),
    ...found.take(maxRegions),
  ];
  final regions = <DiffRegion>[
    for (var i = 0; i < kept.length; i++)
      DiffRegion(
        id: i + 1,
        bbox: kept[i].bbox,
        pixels: kept[i].pixels,
        meanDeltaE: kept[i].meanDeltaE,
        maxDeltaE: kept[i].maxDeltaE,
        components: kept[i].components,
        kind: kept[i].kind,
        elements: _attribute(
          kept[i].bbox,
          referenceElements,
          actualElements,
          maxElementsPerRegion,
        ),
      ),
  ];

  return RegionReport(
    width: w,
    height: h,
    threshold: threshold,
    minArea: minArea,
    mergeGap: mergeGap,
    strongDeltaE: strongDeltaE,
    maskPixels: maskPixels,
    components: parts.length,
    regions: regions,
    keptPixels: keptPixels,
    droppedComponents: droppedComponents,
    droppedPixels: droppedPixels,
    truncated: found.length > maxRegions,
  );
}

class _Component {
  _Component(
    this.minX,
    this.minY,
    this.maxX,
    this.maxY,
    this.pixels,
    this.sum,
    this.max,
  );
  int minX, minY, maxX, maxY, pixels;
  double sum, max;
  int components = 1;

  void absorb(_Component o) {
    minX = math.min(minX, o.minX);
    minY = math.min(minY, o.minY);
    maxX = math.max(maxX, o.maxX);
    maxY = math.max(maxY, o.maxY);
    pixels += o.pixels;
    sum += o.sum;
    max = math.max(max, o.max);
    components += o.components;
  }
}

/// Union of components whose boxes are at most [gap] px apart (Chebyshev
/// distance between the boxes; chains are followed). Order of the result
/// follows the first component of each group, so it is deterministic.
List<_Component> _group(List<_Component> parts, int gap) {
  if (gap < 0 || parts.length < 2) return parts;
  final parent = List<int>.generate(parts.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  final order = List<int>.generate(parts.length, (i) => i)
    ..sort((a, b) => parts[a].minX.compareTo(parts[b].minX));
  for (var a = 0; a < order.length; a++) {
    final p = parts[order[a]];
    for (var b = a + 1; b < order.length; b++) {
      final q = parts[order[b]];
      if (q.minX - p.maxX - 1 > gap) break;
      final dy = math.max(q.minY - p.maxY - 1, p.minY - q.maxY - 1);
      if (dy > gap) continue;
      final ra = find(order[a]), rb = find(order[b]);
      if (ra != rb) parent[math.max(ra, rb)] = math.min(ra, rb);
    }
  }
  final byRoot = <int, _Component>{};
  for (var i = 0; i < parts.length; i++) {
    final r = find(i);
    final c = parts[i];
    final g = byRoot[r];
    if (g == null) {
      byRoot[r] = _Component(
        c.minX,
        c.minY,
        c.maxX,
        c.maxY,
        c.pixels,
        c.sum,
        c.max,
      );
    } else {
      g.absorb(c);
    }
  }
  return byRoot.values.toList();
}

List<RegionElement> _attribute(
  BoxRect bbox,
  List<ElementSnapshot> reference,
  List<ElementSnapshot> actual,
  int limit,
) {
  final byPath = <String, ({String tag, double iou, Set<String> sides})>{};
  void visit(List<ElementSnapshot> elements, String side) {
    for (final e in elements) {
      if (e.rect.isEmpty) continue;
      final overlap = e.rect.intersect(bbox);
      if (overlap.isEmpty) continue;
      final iou = e.rect.iou(bbox);
      final previous = byPath[e.path];
      byPath[e.path] = (
        tag: e.tag,
        iou: previous == null ? iou : math.max(previous.iou, iou),
        sides: {...?previous?.sides, side},
      );
    }
  }

  visit(reference, 'reference');
  visit(actual, 'actual');
  final entries = byPath.entries.toList()
    ..sort((a, b) {
      final byIou = b.value.iou.compareTo(a.value.iou);
      return byIou != 0 ? byIou : a.key.compareTo(b.key);
    });
  return [
    for (final entry in entries.take(limit))
      RegionElement(
        path: entry.key,
        tag: entry.value.tag,
        iou: entry.value.iou,
        sides: [
          for (final side in const ['reference', 'actual'])
            if (entry.value.sides.contains(side)) side,
        ],
      ),
  ];
}

/// Colour used to tint mask pixels in `overlay.png`.
const Rgb overlayTint = Rgb(255, 0, 128);

/// Share of [overlayTint] in a masked overlay pixel (the rest is the 50/50
/// blend of both screenshots).
const double overlayTintWeight = 0.6;

/// `overlay.png`: reference and actual blended 50/50 over their common area;
/// pixels with ΔE > [threshold] are mixed with [overlayTint].
RasterImage overlayImage(
  RasterImage reference,
  RasterImage actual,
  DeltaMap map, {
  double threshold = defaultMaskThreshold,
}) {
  final w = map.width;
  final h = map.height;
  final out = Uint8List(w * h * 4);
  final tint = [overlayTint.r, overlayTint.g, overlayTint.b];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * reference.width + x) * 4;
      final j = (y * actual.width + x) * 4;
      final o = (y * w + x) * 4;
      final masked = map.values[y * w + x] > threshold;
      for (var c = 0; c < 3; c++) {
        final blend = (reference.rgba[i + c] + actual.rgba[j + c]) / 2;
        out[o + c] = masked
            ? (blend * (1 - overlayTintWeight) + tint[c] * overlayTintWeight)
                  .round()
            : blend.round();
      }
      out[o + 3] = 255;
    }
  }
  return RasterImage(w, h, out);
}

double _round(double value, int digits) {
  if (!value.isFinite) return 0;
  final factor = math.pow(10, digits);
  return (value * factor).round() / factor;
}
