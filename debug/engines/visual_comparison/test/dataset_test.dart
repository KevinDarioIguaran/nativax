import 'dart:convert';
import 'dart:io';

import 'package:nativa_visual/src/audit/dataset.dart';
import 'package:nativa_visual/src/audit/evaluate.dart';
import 'package:nativa_visual/src/model.dart';
import 'package:nativa_visual/src/png.dart';
import 'package:test/test.dart';

const _dataset = '../../datasets/visual_comparison';

void main() {
  final cases = buildDataset();

  test('dataset covers every required case once, in a fixed order', () {
    expect(cases.map((c) => c.id), [
      'identical',
      'one-pixel',
      'small-block',
      'layout-shift',
      'missing-component',
      'extra-component',
      'text-change',
      'color-change',
      'opacity-change',
      'scaling',
      'viewport-size',
      'antialias-noise',
      'tiny-important',
      'unimportant-many',
      'nearby-edits',
    ]);
  });

  test('generator is deterministic', () {
    final again = buildDataset();
    for (var i = 0; i < cases.length; i++) {
      expect(again[i].actual.rgba, cases[i].actual.rgba, reason: cases[i].id);
    }
  });

  test('committed PNGs and manifest match the generator', () {
    final manifest =
        jsonDecode(File('$_dataset/manifest.json').readAsStringSync()) as Map;
    final committed = (manifest['cases'] as List).cast<Map>();
    expect(committed.map((c) => c['id']), cases.map((c) => c.id));
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      expect(
        jsonEncode(committed[i]),
        jsonEncode(c.toJson()),
        reason: '${c.id} manifest entry',
      );
      for (final (name, image) in [
        ('reference', c.reference),
        ('actual', c.actual),
      ]) {
        final decoded = decodePng(
          File('$_dataset/${c.id}/$name.png').readAsBytesSync(),
        );
        expect([decoded.width, decoded.height], [image.width, image.height]);
        expect(decoded.rgba, image.rgba, reason: '${c.id}/$name.png');
      }
    }
  });

  test('identical pair is a true negative at both levels', () {
    final r = evaluateCase(cases.first);
    expect(r.pixelOutcome, Outcome.tn);
    expect(r.regionOutcome, Outcome.tn);
    expect(r.maskPixels, 0);
  });

  test('a localized block is found with IoU 1 and no false pixels', () {
    final r = evaluateCase(cases.firstWhere((c) => c.id == 'small-block'));
    expect(r.pixelTp, 36);
    expect(r.pixelFp, 0);
    expect(r.matches.single.bestIou, 1);
    expect(r.matches.single.localized, isTrue);
    expect(r.falseRegions, 0);
  });

  test('a strong 1-pixel change survives the min-area filter', () {
    final c = cases.firstWhere((c) => c.id == 'one-pixel');
    final r = evaluateCase(c);
    expect(r.regionOutcome, Outcome.tp);
    expect(r.matches.single.localized, isTrue);
    // Without the strong-deltaE exception the filter hides it.
    final filtered = evaluateCase(c, strongDeltaE: double.infinity);
    expect(filtered.pixelOutcome, Outcome.tp);
    expect(filtered.regionOutcome, Outcome.fn);
    expect(filtered.droppedComponents, 1);
  });

  test('grouping joins a moved card but keeps nearby edits apart', () {
    final shift = evaluateCase(cases.firstWhere((c) => c.id == 'layout-shift'));
    expect(shift.matches.single.localized, isTrue);
    expect(
      evaluateCase(
        cases.firstWhere((c) => c.id == 'layout-shift'),
        mergeGap: -1,
      ).matches.single.localized,
      isFalse,
    );
    final nearby = evaluateCase(
      cases.firstWhere((c) => c.id == 'nearby-edits'),
    );
    expect(nearby.regions, 2);
    expect(nearby.matches.every((m) => m.localized), isTrue);
    final merged = evaluateCase(
      cases.firstWhere((c) => c.id == 'nearby-edits'),
      mergeGap: 7,
    );
    expect(merged.regions, 1);
  });

  test('the strip only one capture covers is a size region', () {
    final r = evaluateCase(cases.firstWhere((c) => c.id == 'viewport-size'));
    expect(r.regionOutcome, Outcome.tp);
    expect(r.matches.single.bestIou, 1);
  });

  test('truth outside the common area counts as a pixel false negative', () {
    final r = evaluateCase(cases.firstWhere((c) => c.id == 'viewport-size'));
    expect(r.sizeMismatch, isTrue);
    expect(r.truthPixels, 8 * 120);
    expect(r.pixelFn, 8 * 120);
    expect(r.pixelOutcome, Outcome.fn);
  });

  test('mask pixels with empty truth are false positives', () {
    final r = evaluatePair(
      id: 'x',
      kind: 'unimportant',
      reference: Canvas(4, 4).toImage(),
      actual: Canvas(4, 4, const [0, 0, 0]).toImage(),
      truth: const [],
    );
    expect(r.pixelFp, 16);
    expect(r.pixelOutcome, Outcome.fp);
    expect(r.regionOutcome, Outcome.fp);
    expect(r.falseRegions, 1);
  });

  test('merged IoU joins fragmented regions over one truth box', () {
    final reference = Canvas(20, 10).toImage();
    final canvas = Canvas(20, 10)
      ..fill(0, 0, 4, 10, const [0, 0, 0])
      ..fill(16, 0, 4, 10, const [0, 0, 0]);
    final r = evaluatePair(
      id: 'x',
      kind: 'important',
      reference: reference,
      actual: canvas.toImage(),
      truth: const [BoxRect(0, 0, 20, 10)],
    );
    expect(r.regions, 2);
    expect(r.matches.single.bestIou, closeTo(0.2, 1e-9));
    expect(r.matches.single.mergedIou, 1);
  });

  test('audit json has per-case results and both sweeps', () {
    final audit = auditDataset(cases.take(3).toList());
    expect(audit['cases'], hasLength(3));
    expect(audit['thresholdSweep'], hasLength(sweepThresholds.length));
    expect(audit['minAreaSweep'], hasLength(sweepMinAreas.length));
  });
}
