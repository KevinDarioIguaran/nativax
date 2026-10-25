import 'model.dart';
import 'geometry.dart';
import 'pixels.dart';
import 'png.dart';
import 'styles.dart';

enum Verdict { pass, warn, fail, invalid }

extension VerdictLabel on Verdict {
  String get label => switch (this) {
    Verdict.pass => 'PASS',
    Verdict.warn => 'WARN',
    Verdict.fail => 'FAIL',
    Verdict.invalid => 'INVALID',
  };
}

class EnvCheck {
  const EnvCheck({
    required this.name,
    required this.ok,
    required this.detail,
    this.hard = false,
  });

  final String name;
  final bool ok;
  final String detail;

  /// A failed hard check makes the page INVALID: the comparison itself cannot
  /// be trusted, so a score would be misleading.
  final bool hard;

  Map<String, Object> toJson() => {
    'name': name,
    'ok': ok,
    'hard': hard,
    'detail': detail,
  };
}

class ElementReport {
  ElementReport({
    required this.delta,
    required this.style,
    required this.sample,
  });

  final ElementDelta delta;
  final StyleComparison? style;
  final ColorComparison? sample;

  double? get colorScore => sample?.score;
}

class Evaluation {
  Evaluation({
    required this.geometry,
    required this.pixels,
    required this.elements,
    required this.designFailures,
    required this.colorFailures,
    required this.position,
    required this.layout,
    required this.color,
    required this.design,
    required this.overall,
    required this.verdict,
    required this.reason,
    required this.checks,
    required this.colorComparable,
    required this.colorWithin2,
    required this.colorWithin5,
  });

  final GeometryComparison geometry;
  final PixelComparison pixels;
  final List<ElementReport> elements;
  final List<StyleComparison> designFailures;
  final List<ElementReport> colorFailures;

  /// All scores are 0..1; [color] is null when no element had matching
  /// geometry and pixel colour could not be isolated from layout error.
  final double? position;
  final double? layout;
  final double? color;
  final double? design;
  final double overall;
  final Verdict verdict;
  final String reason;
  final List<EnvCheck> checks;
  final int colorComparable;
  final int colorWithin2;
  final int colorWithin5;

  double get colorComparablePct =>
      geometry.total == 0 ? 0 : 100 * colorComparable / geometry.total;

  int get mismatchedPixels => pixels.totals.mismatched;
  double get mismatchedPixelPct => pixels.totals.mismatchedPct;
}

/// Fidelity target (strict judge): a page passes only when the overall score
/// and every measured sub-score (position, layout, colour, design) reach
/// 99.99 % and at most 0.01 % of the pixels differ from the reference.
const double passOverall = 0.9999;

/// Maximum share of differing pixels (percent) for a pass.
const double passPixelMismatchPct = 0.01;

/// Below this overall score a page fails; between it and [passOverall] it
/// warns.
const double failOverall = 0.99;

Evaluation evaluate({
  required ProbeSnapshot chromeProbe,
  required RasterImage chromeImage,
  required ProbeSnapshot nativaProbe,
  required RasterImage nativaImage,
  required List<EnvCheck> checks,
}) {
  final geometry = compareGeometry(chromeProbe, nativaProbe);
  final pixels = comparePixels(chromeImage, nativaImage);

  final deltaByPath = {for (final d in geometry.deltas) d.path: d};
  final elements = <ElementReport>[];
  final designFailures = <StyleComparison>[];
  final colorFailures = <ElementReport>[];

  var designWeighted = 0.0;
  var designTotal = 0.0;
  var colorWeighted = 0.0;
  var colorTotal = 0.0;
  var colorComparable = 0;
  var colorWithin2 = 0;
  var colorWithin5 = 0;

  for (final chromeElement in chromeProbe.elements) {
    final nativaElement = nativaProbe.byPath[chromeElement.path];
    final delta = deltaByPath[chromeElement.path]!;
    StyleComparison? style;
    ColorComparison? sample;

    if (nativaElement != null) {
      style = compareStyles(chromeElement, nativaElement);
      final weight = elementWeight(chromeElement.rect);
      designWeighted += style.score * weight;
      designTotal += weight;
      if (style.score < 0.999) designFailures.add(style);

      // Each element is sampled inside its own box: a shifted element is a
      // layout error, not a colour error, so colour stays independent.
      sample = compareColors(
        chromeImage,
        nativaImage,
        chromeElement.rect,
        nativaElement.rect,
      );
      if (sample != null) {
        colorComparable++;
        final colorWeight = elementWeight(chromeElement.rect);
        colorWeighted += sample.score * colorWeight;
        colorTotal += colorWeight;
        if (sample.paletteDeltaE <= 2) colorWithin2++;
        if (sample.paletteDeltaE <= 5) colorWithin5++;
      }
    }

    final report = ElementReport(delta: delta, style: style, sample: sample);
    elements.add(report);
    if (sample != null && sample.score < 0.5) colorFailures.add(report);
  }

  // Elements that only exist in NativaX cannot be styled-compared; they are
  // already penalised by geometry and by the pixel comparison.
  for (final nativaElement in nativaProbe.elements) {
    if (chromeProbe.byPath.containsKey(nativaElement.path)) continue;
    final delta = deltaByPath[nativaElement.path]!;
    elements.add(ElementReport(delta: delta, style: null, sample: null));
  }

  designFailures.sort((a, b) {
    final left = (1 - a.score) * elementWeight(a.element.rect);
    final right = (1 - b.score) * elementWeight(b.element.rect);
    return right.compareTo(left);
  });
  colorFailures.sort(
    (a, b) => b.sample!.meanDeltaE.compareTo(a.sample!.meanDeltaE),
  );

  final position = geometry.positionScore;
  final layout = geometry.layoutScore;
  final color = colorTotal == 0 ? null : colorWeighted / colorTotal;
  final design = designTotal == 0 ? null : designWeighted / designTotal;

  // Weights: layout and position dominate, colour isolates paint, design
  // isolates computed-style contracts. Missing metrics are renormalised.
  final parts = <(double, double)>[
    (position, 0.30),
    (layout, 0.30),
    if (color != null) (color, 0.25),
    if (design != null) (design, 0.15),
  ];
  final weightSum = parts.fold<double>(0, (sum, p) => sum + p.$2);
  final overall =
      parts.fold<double>(0, (sum, p) => sum + p.$1 * p.$2) / weightSum;

  final hardFailure = checks.any((c) => c.hard && !c.ok);
  // Ink is the visible content once the page background is removed. A blank
  // or displaced render can be 99.8 % "identical" by area and still lose all
  // of its text, so a large ink mismatch overrides a good aggregate score.
  final inkPct = pixels.totals.inkMismatchPct;
  final visibleInk = pixels.totals.mismatchedPct >= 0.2;
  final severeInk = visibleInk && inkPct >= 80;
  final someInk = visibleInk && inkPct >= 50;

  final Verdict verdict;
  final String reason;
  if (hardFailure) {
    verdict = Verdict.invalid;
    reason = checks.firstWhere((c) => c.hard && !c.ok).detail;
  } else if (position < 0.50 || layout < 0.50) {
    verdict = Verdict.fail;
    reason =
        'position ${(position * 100).toStringAsFixed(1)} %, '
        'layout ${(layout * 100).toStringAsFixed(1)} %';
  } else if (severeInk) {
    verdict = Verdict.fail;
    reason =
        'ink mismatch ${inkPct.toStringAsFixed(1)} % of '
        '${pixels.totals.inkPixels} visible px';
  } else if (overall < failOverall) {
    verdict = Verdict.fail;
    reason = 'overall ${(overall * 100).toStringAsFixed(2)} % below '
        '${(failOverall * 100).toStringAsFixed(0)} %';
  } else if (overall < passOverall) {
    verdict = Verdict.warn;
    reason = 'overall ${(overall * 100).toStringAsFixed(3)} % below '
        '${(passOverall * 100).toStringAsFixed(2)} %';
  } else if ([position, layout, ?color, ?design].any((s) => s < passOverall)) {
    verdict = Verdict.warn;
    reason = 'a sub-score is below ${(passOverall * 100).toStringAsFixed(2)} %';
  } else if (pixels.totals.mismatchedPct > passPixelMismatchPct) {
    verdict = Verdict.warn;
    reason = '${pixels.totals.mismatchedPct.toStringAsFixed(3)} % of pixels '
        'differ (max $passPixelMismatchPct %)';
  } else if (someInk) {
    verdict = Verdict.warn;
    reason =
        'ink mismatch ${inkPct.toStringAsFixed(1)} % of '
        '${pixels.totals.inkPixels} visible px';
  } else {
    verdict = Verdict.pass;
    reason = 'overall ${(overall * 100).toStringAsFixed(1)} %';
  }

  return Evaluation(
    geometry: geometry,
    pixels: pixels,
    elements: elements,
    designFailures: designFailures,
    colorFailures: colorFailures,
    position: position,
    layout: layout,
    color: color,
    design: design,
    overall: overall,
    verdict: verdict,
    reason: reason,
    checks: checks,
    colorComparable: colorComparable,
    colorWithin2: colorWithin2,
    colorWithin5: colorWithin5,
  );
}
