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

/// Regions kept in `regions.json`, largest first. Totals stay exact.
const int defaultMaxRegions = 500;

/// Elements listed per region, best IoU first.
const int defaultMaxElementsPerRegion = 8;

/// Per-pixel CIE76 ΔE over the common area of both images, row-major.
class DeltaMap {
  DeltaMap(this.width, this.height, this.values);
  final int width;
  final int height;
  final Float32List values;
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
  return DeltaMap(width, height, values);
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
    this.elements = const [],
  });

  final int id;

  /// Integer pixel box `[x, y, w, h]`.
  final BoxRect bbox;
  final int pixels;
  final double meanDeltaE;
  final double maxDeltaE;
  final List<RegionElement> elements;

  Map<String, Object> toJson() => {
    'id': id,
    'bbox': [
      bbox.x.toInt(),
      bbox.y.toInt(),
      bbox.width.toInt(),
      bbox.height.toInt(),
    ],
    'pixels': pixels,
    'meanDeltaE': _round(meanDeltaE, 2),
    'maxDeltaE': _round(maxDeltaE, 2),
    'elements': [for (final e in elements) e.toJson()],
  };
}

class RegionReport {
  RegionReport({
    required this.width,
    required this.height,
    required this.threshold,
    required this.minArea,
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
    'schema': 'nativa_visual.regions/1',
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
    'filter': 'components with fewer than minArea pixels are dropped',
    'components': components,
    'keptRegions': components - droppedComponents,
    'keptPixels': keptPixels,
    'droppedComponents': droppedComponents,
    'droppedPixels': droppedPixels,
    'truncated': truncated,
    'regions': [for (final r in regions) r.toJson()],
  };
}

/// Labels the ΔE > [threshold] mask with 8-neighbourhood connectivity, drops
/// components smaller than [minArea] and attributes each kept region to the
/// probe elements whose rects intersect its bounding box.
RegionReport findRegions(
  DeltaMap map, {
  double threshold = defaultMaskThreshold,
  int minArea = defaultMinRegionArea,
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
  final found = <DiffRegion>[];
  var maskPixels = 0;
  var components = 0;
  var droppedComponents = 0;
  var droppedPixels = 0;
  var keptPixels = 0;

  for (var start = 0; start < n; start++) {
    if (map.values[start] <= threshold) continue;
    maskPixels++;
    if (labels[start] != 0) continue;
    components++;
    labels[start] = components;
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
          labels[q] = components;
          queue[tail++] = q;
        }
      }
    }
    final count = tail;
    if (count < minArea) {
      droppedComponents++;
      droppedPixels += count;
      continue;
    }
    keptPixels += count;
    found.add(
      DiffRegion(
        id: 0,
        bbox: BoxRect(
          minX.toDouble(),
          minY.toDouble(),
          (maxX - minX + 1).toDouble(),
          (maxY - minY + 1).toDouble(),
        ),
        pixels: count,
        meanDeltaE: sum / count,
        maxDeltaE: max,
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
  final kept = found.take(maxRegions).toList();
  final regions = <DiffRegion>[
    for (var i = 0; i < kept.length; i++)
      DiffRegion(
        id: i + 1,
        bbox: kept[i].bbox,
        pixels: kept[i].pixels,
        meanDeltaE: kept[i].meanDeltaE,
        maxDeltaE: kept[i].maxDeltaE,
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
    maskPixels: maskPixels,
    components: components,
    regions: regions,
    keptPixels: keptPixels,
    droppedComponents: droppedComponents,
    droppedPixels: droppedPixels,
    truncated: found.length > maxRegions,
  );
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
