import 'model.dart';
import 'styles.dart';

const double positionTolerance = 2;
const double positionLimit = 16;
const double sizeTolerance = 2;
const double sizeLimit = 16;

double _falloff(double delta, double tolerance, double limit) {
  if (delta <= tolerance) return 1;
  if (delta >= limit) return 0;
  return 1 - (delta - tolerance) / (limit - tolerance);
}

class ElementDelta {
  ElementDelta({
    required this.path,
    required this.tag,
    required this.chromeRect,
    required this.nativaRect,
    required this.positionDelta,
    required this.sizeDelta,
    required this.iou,
    required this.missing,
    required this.extra,
    required this.rootCause,
  });

  /// Set during root-cause attribution; an element is reported when its parent
  /// already matches, so one wrong container does not flood the report.
  bool rootCause;

  final String path;
  final String tag;
  final BoxRect? chromeRect;
  final BoxRect? nativaRect;
  final double positionDelta;
  final double sizeDelta;
  final double iou;
  final bool missing;
  final bool extra;

  double get weight {
    final rect = chromeRect ?? nativaRect;
    return rect == null ? 1 : elementWeight(rect);
  }

  bool get positionMatch =>
      !missing && !extra && positionDelta <= positionTolerance;
  bool get sizeMatch => !missing && !extra && sizeDelta <= sizeTolerance;
  bool get layoutMatch => positionMatch && sizeMatch;

  Map<String, Object?> toJson() => {
    'path': path,
    'tag': tag,
    'chromeRect': chromeRect?.toJson(),
    'nativaRect': nativaRect?.toJson(),
    'positionDelta': positionDelta.isFinite ? _r(positionDelta) : null,
    'sizeDelta': sizeDelta.isFinite ? _r(sizeDelta) : null,
    'iou': iou.isFinite ? _r(iou) : null,
    'missing': missing,
    'extra': extra,
    'rootCause': rootCause,
    'positionMatch': positionMatch,
    'sizeMatch': sizeMatch,
  };
}

class GeometryComparison {
  const GeometryComparison({
    required this.positionScore,
    required this.layoutScore,
    required this.flowScore,
    required this.matched,
    required this.positionMatches,
    required this.sizeMatches,
    required this.missing,
    required this.extra,
    required this.deltas,
    required this.rootCauses,
    required this.orderViolations,
    required this.documentHeightDelta,
  });

  /// 0..1 weighted mean of the per-element position falloff.
  final double positionScore;

  /// 0..1: 90 % weighted size/IoU, 10 % document-height flow.
  final double layoutScore;
  final double flowScore;
  final int matched;
  final int positionMatches;
  final int sizeMatches;
  final int missing;
  final int extra;
  final List<ElementDelta> deltas;
  final List<ElementDelta> rootCauses;
  final int orderViolations;
  final int documentHeightDelta;

  int get total => deltas.length;
  double get positionMatchPct =>
      total == 0 ? 100 : 100 * positionMatches / total;
  double get sizeMatchPct => total == 0 ? 100 : 100 * sizeMatches / total;
  double get missingPct => total == 0 ? 0 : 100 * missing / total;
}

GeometryComparison compareGeometry(ProbeSnapshot chrome, ProbeSnapshot nativa) {
  final deltas = <ElementDelta>[];
  final byPath = <String, ElementDelta>{};
  var weightedPosition = 0.0;
  var weightedLayout = 0.0;
  var totalWeight = 0.0;
  var matched = 0;
  var positionMatches = 0;
  var sizeMatches = 0;
  var missing = 0;
  var extra = 0;

  for (final element in chrome.elements) {
    final other = nativa.byPath[element.path];
    final BoxRect? otherRect = other?.rect;
    final posDelta = otherRect == null
        ? double.infinity
        : element.rect.maxPositionDelta(otherRect);
    final sizeDelta = otherRect == null
        ? double.infinity
        : element.rect.maxSizeDelta(otherRect);
    final iou = otherRect == null ? 0.0 : element.rect.iou(otherRect);
    final weight = elementWeight(element.rect);
    totalWeight += weight;
    if (otherRect == null) {
      missing++;
      final delta = ElementDelta(
        path: element.path,
        tag: element.tag,
        chromeRect: element.rect,
        nativaRect: null,
        positionDelta: posDelta,
        sizeDelta: sizeDelta,
        iou: 0,
        missing: true,
        extra: false,
        rootCause: false,
      );
      deltas.add(delta);
      byPath[element.path] = delta;
      continue;
    }
    matched++;
    final posScore = _falloff(posDelta, positionTolerance, positionLimit);
    final sizeScore = _falloff(sizeDelta, sizeTolerance, sizeLimit);
    weightedPosition += posScore * weight;
    weightedLayout += (0.7 * sizeScore + 0.3 * iou) * weight;
    if (posDelta <= positionTolerance) positionMatches++;
    if (sizeDelta <= sizeTolerance) sizeMatches++;
    final delta = ElementDelta(
      path: element.path,
      tag: element.tag,
      chromeRect: element.rect,
      nativaRect: otherRect,
      positionDelta: posDelta,
      sizeDelta: sizeDelta,
      iou: iou,
      missing: false,
      extra: false,
      rootCause: false,
    );
    deltas.add(delta);
    byPath[element.path] = delta;
  }

  for (final element in nativa.elements) {
    if (chrome.byPath.containsKey(element.path)) continue;
    extra++;
    final weight = elementWeight(element.rect);
    totalWeight += weight;
    final delta = ElementDelta(
      path: element.path,
      tag: element.tag,
      chromeRect: null,
      nativaRect: element.rect,
      positionDelta: double.infinity,
      sizeDelta: double.infinity,
      iou: 0,
      missing: false,
      extra: true,
      rootCause: true,
    );
    deltas.add(delta);
    byPath[element.path] = delta;
  }

  // Root-cause attribution: report an element only when its parent already
  // matches, so one wrong container does not flood the top offenders.
  for (final delta in deltas) {
    if (delta.missing || delta.extra) {
      delta.rootCause = true;
      continue;
    }
    if (delta.positionDelta <= positionTolerance &&
        delta.sizeDelta <= sizeTolerance)
      continue;
    final parent = _parentOf(delta.path);
    if (parent == null) {
      delta.rootCause = true;
      continue;
    }
    final parentDelta = byPath[parent];
    delta.rootCause =
        parentDelta == null ||
        parentDelta.missing ||
        parentDelta.extra ||
        (parentDelta.positionDelta <= positionTolerance &&
            parentDelta.sizeDelta <= sizeTolerance);
  }

  final positionScore = totalWeight == 0 ? 1.0 : weightedPosition / totalWeight;
  final elementLayout = totalWeight == 0 ? 1.0 : weightedLayout / totalWeight;
  final chromeHeight = chrome.documentHeight;
  final natHeight = nativa.documentHeight;
  final heightDelta = (chromeHeight - natHeight).abs();
  final flowScore = chromeHeight <= 0
      ? 1.0
      : (1 - (heightDelta / chromeHeight / 0.15).clamp(0.0, 1.0)).toDouble();

  final roots =
      deltas
          .where((d) => d.rootCause && (d.missing || d.extra || !d.layoutMatch))
          .toList()
        ..sort((a, b) {
          final byPos = b.positionDelta.compareTo(a.positionDelta);
          return byPos != 0 ? byPos : b.sizeDelta.compareTo(a.sizeDelta);
        });

  return GeometryComparison(
    positionScore: positionScore,
    layoutScore: elementLayout * 0.9 + flowScore * 0.1,
    flowScore: flowScore,
    matched: matched,
    positionMatches: positionMatches,
    sizeMatches: sizeMatches,
    missing: missing,
    extra: extra,
    deltas: deltas,
    rootCauses: roots.take(25).toList(growable: false),
    orderViolations: _countOrderViolations(chrome, nativa),
    documentHeightDelta: heightDelta,
  );
}

String? _parentOf(String path) {
  final i = path.lastIndexOf('>');
  return i < 0 ? null : path.substring(0, i);
}

/// Counts adjacent sibling pairs whose vertical order differs between both
/// renders. A high count means flow, not just offsets, differs.
int _countOrderViolations(ProbeSnapshot chrome, ProbeSnapshot nativa) {
  final groups = <String, List<ElementSnapshot>>{};
  for (final element in chrome.elements) {
    final parent = _parentOf(element.path);
    if (parent == null) continue;
    groups.putIfAbsent(parent, () => []).add(element);
  }
  var violations = 0;
  for (final siblings in groups.values) {
    if (siblings.length < 2) continue;
    siblings.sort((a, b) => a.rect.y.compareTo(b.rect.y));
    for (var i = 1; i < siblings.length; i++) {
      final a = siblings[i - 1];
      final b = siblings[i];
      final na = nativa.byPath[a.path];
      final nb = nativa.byPath[b.path];
      if (na == null || nb == null) continue;
      final chromeOrder = a.rect.y - b.rect.y;
      final nativeOrder = na.rect.y - nb.rect.y;
      if (chromeOrder.abs() < 1 || nativeOrder.abs() < 1) continue;
      if (chromeOrder.sign != nativeOrder.sign) violations++;
    }
  }
  return violations;
}

double _r(double value) =>
    value.isFinite ? (value * 100).round() / 100 : double.infinity;

/// Serialises a geometry comparison without the full delta list.
Map<String, Object> geometrySummary(GeometryComparison comparison) => {
  'positionScore': _r(comparison.positionScore),
  'layoutScore': _r(comparison.layoutScore),
  'flowScore': _r(comparison.flowScore),
  'matchedElements': comparison.matched,
  'positionMatches': comparison.positionMatches,
  'positionMatchPct': _r(comparison.positionMatchPct),
  'sizeMatches': comparison.sizeMatches,
  'sizeMatchPct': _r(comparison.sizeMatchPct),
  'missingElements': comparison.missing,
  'extraElements': comparison.extra,
  'orderViolations': comparison.orderViolations,
  'documentHeightDelta': comparison.documentHeightDelta,
};
