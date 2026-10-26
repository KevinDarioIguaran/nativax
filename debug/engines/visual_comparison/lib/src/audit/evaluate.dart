/// Scores the real pixel and region detectors against the ground truth of the
/// synthetic dataset. Pixel level and region level are reported separately.
library;

import 'dart:math' as math;

import '../model.dart';
import '../pixels.dart';
import '../png.dart';
import '../regions.dart';
import 'dataset.dart';

/// IoU at or above which a ground-truth box counts as localized.
const double localizationIou = 0.5;

/// Case-level outcome of a binary "is there a difference?" decision.
enum Outcome { tp, fp, fn, tn }

Outcome outcome({required bool expected, required bool detected}) =>
    switch ((expected, detected)) {
      (true, true) => Outcome.tp,
      (false, true) => Outcome.fp,
      (true, false) => Outcome.fn,
      (false, false) => Outcome.tn,
    };

class TruthMatch {
  const TruthMatch(this.truth, this.bestIou, this.mergedIou, this.regions);
  final BoxRect truth;

  /// Best IoU between [truth] and one detected region bbox.
  final double bestIou;

  /// IoU between [truth] and the bbox of all regions that intersect it.
  final double mergedIou;

  /// Regions that intersect [truth].
  final int regions;

  bool get localized => bestIou >= localizationIou;

  Map<String, Object> toJson() => {
    'truth': _box(truth),
    'bestIou': _r(bestIou),
    'mergedIou': _r(mergedIou),
    'intersectingRegions': regions,
    'localized': localized,
  };
}

class CaseResult {
  CaseResult({
    required this.id,
    required this.kind,
    required this.threshold,
    required this.minArea,
    required this.comparedPixels,
    required this.sizeMismatch,
    required this.maskPixels,
    required this.truthPixels,
    required this.pixelTp,
    required this.pixelFp,
    required this.pixelFn,
    required this.pixelOutcome,
    required this.regions,
    required this.falseRegions,
    required this.droppedComponents,
    required this.matches,
    required this.regionOutcome,
    required this.verdictMismatchPct,
  });

  final String id;
  final String kind;
  final double threshold;
  final int minArea;
  final int comparedPixels;
  final bool sizeMismatch;

  /// Pixels with ΔE > threshold in the common area.
  final int maskPixels;

  /// Ground-truth pixels: inside a truth box and different in raw RGB
  /// (pixels of a truth box outside the common area count as different).
  final int truthPixels;
  final int pixelTp;
  final int pixelFp;
  final int pixelFn;
  final Outcome pixelOutcome;

  /// Regions kept after the min-area filter.
  final int regions;

  /// Kept regions that intersect no truth box.
  final int falseRegions;
  final int droppedComponents;
  final List<TruthMatch> matches;
  final Outcome regionOutcome;

  /// `mismatchedPct` from the existing `comparePixels()` (threshold 2 only).
  final double verdictMismatchPct;

  double? get pixelPrecision =>
      pixelTp + pixelFp == 0 ? null : pixelTp / (pixelTp + pixelFp);
  double? get pixelRecall =>
      pixelTp + pixelFn == 0 ? null : pixelTp / (pixelTp + pixelFn);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'threshold': threshold,
    'minArea': minArea,
    'comparedPixels': comparedPixels,
    'sizeMismatch': sizeMismatch,
    'pixel': {
      'maskPixels': maskPixels,
      'truthPixels': truthPixels,
      'tp': pixelTp,
      'fp': pixelFp,
      'fn': pixelFn,
      'precision': pixelPrecision == null ? null : _r(pixelPrecision!),
      'recall': pixelRecall == null ? null : _r(pixelRecall!),
      'outcome': pixelOutcome.name.toUpperCase(),
      'mismatchedPctAtDefault': verdictMismatchPct,
    },
    'region': {
      'regions': regions,
      'falseRegions': falseRegions,
      'droppedComponents': droppedComponents,
      'outcome': regionOutcome.name.toUpperCase(),
      'truth': [for (final m in matches) m.toJson()],
    },
  };
}

CaseResult evaluateCase(
  DatasetCase c, {
  double threshold = defaultMaskThreshold,
  int minArea = defaultMinRegionArea,
}) => evaluatePair(
  id: c.id,
  kind: c.kind,
  reference: c.reference,
  actual: c.actual,
  truth: c.truth,
  threshold: threshold,
  minArea: minArea,
);

CaseResult evaluatePair({
  required String id,
  required String kind,
  required RasterImage reference,
  required RasterImage actual,
  required List<BoxRect> truth,
  double threshold = defaultMaskThreshold,
  int minArea = defaultMinRegionArea,
}) {
  final map = deltaMap(reference, actual);
  final w = map.width, h = map.height;
  final sizeMismatch =
      reference.width != actual.width || reference.height != actual.height;

  bool inTruth(int x, int y) =>
      truth.any((t) => t.containsPoint(x + 0.5, y + 0.5));
  bool rawDiffers(int x, int y) {
    final i = (y * reference.width + x) * 4;
    final j = (y * actual.width + x) * 4;
    return reference.rgba[i] != actual.rgba[j] ||
        reference.rgba[i + 1] != actual.rgba[j + 1] ||
        reference.rgba[i + 2] != actual.rgba[j + 2];
  }

  var mask = 0, tp = 0, fp = 0, fn = 0, truthPixels = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final masked = map.values[y * w + x] > threshold;
      final isTruth = inTruth(x, y) && rawDiffers(x, y);
      if (masked) mask++;
      if (isTruth) truthPixels++;
      if (masked && isTruth) tp++;
      if (masked && !isTruth) fp++;
      if (!masked && isTruth) fn++;
    }
  }
  // Truth pixels outside the common area can never be detected by pixels.
  final fullW = math.max(reference.width, actual.width);
  final fullH = math.max(reference.height, actual.height);
  for (var y = 0; y < fullH; y++) {
    for (var x = 0; x < fullW; x++) {
      if (x < w && y < h) continue;
      if (inTruth(x, y)) {
        truthPixels++;
        fn++;
      }
    }
  }

  final report = findRegions(map, threshold: threshold, minArea: minArea);
  final matches = <TruthMatch>[];
  for (final t in truth) {
    var best = 0.0;
    BoxRect? merged;
    var count = 0;
    for (final r in report.regions) {
      if (r.bbox.intersect(t).isEmpty) continue;
      count++;
      best = math.max(best, r.bbox.iou(t));
      merged = merged == null ? r.bbox : _union(merged, r.bbox);
    }
    matches.add(TruthMatch(t, best, merged == null ? 0 : merged.iou(t), count));
  }
  final falseRegions = report.regions
      .where((r) => truth.every((t) => r.bbox.intersect(t).isEmpty))
      .length;
  final expected = truth.isNotEmpty;

  return CaseResult(
    id: id,
    kind: kind,
    threshold: threshold,
    minArea: minArea,
    comparedPixels: w * h,
    sizeMismatch: sizeMismatch,
    maskPixels: mask,
    truthPixels: truthPixels,
    pixelTp: tp,
    pixelFp: fp,
    pixelFn: fn,
    pixelOutcome: outcome(expected: expected, detected: mask > 0),
    regions: report.regions.length,
    falseRegions: falseRegions,
    droppedComponents: report.droppedComponents,
    matches: matches,
    regionOutcome: outcome(
      expected: expected,
      detected: report.regions.isNotEmpty,
    ),
    verdictMismatchPct:
        comparePixels(reference, actual).totals.toJson()['mismatchedPct']!
            as double,
  );
}

/// Aggregate of one parameter setting over every case.
class SweepRow {
  SweepRow(this.threshold, this.minArea, this.cases);
  final double threshold;
  final int minArea;
  final List<CaseResult> cases;

  int _count(Outcome Function(CaseResult) f, Outcome o) =>
      cases.where((c) => f(c) == o).length;

  Map<String, Object?> toJson() {
    final tp = cases.fold<int>(0, (s, c) => s + c.pixelTp);
    final fp = cases.fold<int>(0, (s, c) => s + c.pixelFp);
    final fn = cases.fold<int>(0, (s, c) => s + c.pixelFn);
    final truths = [for (final c in cases) ...c.matches];
    return {
      'threshold': threshold,
      'minArea': minArea,
      'pixel': {
        'caseTp': _count((c) => c.pixelOutcome, Outcome.tp),
        'caseFp': _count((c) => c.pixelOutcome, Outcome.fp),
        'caseFn': _count((c) => c.pixelOutcome, Outcome.fn),
        'caseTn': _count((c) => c.pixelOutcome, Outcome.tn),
        'tp': tp,
        'fp': fp,
        'fn': fn,
        'precision': tp + fp == 0 ? null : _r(tp / (tp + fp)),
        'recall': tp + fn == 0 ? null : _r(tp / (tp + fn)),
      },
      'region': {
        'caseTp': _count((c) => c.regionOutcome, Outcome.tp),
        'caseFp': _count((c) => c.regionOutcome, Outcome.fp),
        'caseFn': _count((c) => c.regionOutcome, Outcome.fn),
        'caseTn': _count((c) => c.regionOutcome, Outcome.tn),
        'truthBoxes': truths.length,
        'localized': truths.where((m) => m.localized).length,
        'meanBestIou': truths.isEmpty
            ? null
            : _r(
                truths.fold<double>(0, (s, m) => s + m.bestIou) / truths.length,
              ),
        'meanMergedIou': truths.isEmpty
            ? null
            : _r(
                truths.fold<double>(0, (s, m) => s + m.mergedIou) /
                    truths.length,
              ),
        'falseRegions': cases.fold<int>(0, (s, c) => s + c.falseRegions),
      },
    };
  }
}

const List<double> sweepThresholds = [0.5, 1, 2, 3, 5, 10, 20, 40];
const List<int> sweepMinAreas = [1, 4, 9, 16, 64];

Map<String, Object?> auditDataset(List<DatasetCase> cases) => {
  'schema': 'nativa_visual.audit/1',
  'defaults': {
    'threshold': defaultMaskThreshold,
    'minArea': defaultMinRegionArea,
    'connectivity': 8,
    'localizationIou': localizationIou,
  },
  'cases': [for (final c in cases) evaluateCase(c).toJson()],
  'thresholdSweep': [
    for (final t in sweepThresholds)
      SweepRow(t, defaultMinRegionArea, [
        for (final c in cases) evaluateCase(c, threshold: t),
      ]).toJson(),
  ],
  'minAreaSweep': [
    for (final m in sweepMinAreas)
      SweepRow(defaultMaskThreshold, m, [
        for (final c in cases) evaluateCase(c, minArea: m),
      ]).toJson(),
  ],
};

BoxRect _union(BoxRect a, BoxRect b) {
  final x = math.min(a.x, b.x), y = math.min(a.y, b.y);
  return BoxRect(
    x,
    y,
    math.max(a.right, b.right) - x,
    math.max(a.bottom, b.bottom) - y,
  );
}

List<int> _box(BoxRect b) => [
  b.x.toInt(),
  b.y.toInt(),
  b.width.toInt(),
  b.height.toInt(),
];

double _r(double v) => (v * 10000).round() / 10000;
