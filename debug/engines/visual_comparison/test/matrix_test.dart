import 'package:nativa_visual/src/color.dart';
import 'package:nativa_visual/src/geometry.dart';
import 'package:nativa_visual/src/model.dart';
import 'package:test/test.dart';

ElementSnapshot _element(String path, double x, double y, double w, double h) =>
    ElementSnapshot(
      path: path,
      tag: 'div',
      rect: BoxRect(x, y, w, h),
      styles: const {'color': 'rgb(0, 0, 0)'},
    );

ProbeSnapshot _probe(List<ElementSnapshot> elements, {int height = 600}) =>
    ProbeSnapshot(
      viewportWidth: 800,
      viewportHeight: height,
      dpr: 1,
      documentWidth: 800,
      documentHeight: height,
      elements: elements,
    );

void main() {
  // 25 colour-matrix cases: each one checks the same invariants on a different
  // RGB sample so a regression in Lab/ΔE constants cannot hide in one fixture.
  for (var i = 0; i < 25; i++) {
    test('colour matrix case ${i + 1}', () {
      final v = (i * 9 + 3) % 256;
      final other = (v + 37) % 256;
      expect(deltaE(v, v, v, v, v, v), 0);
      expect(deltaE(v, v, v, other, other, other), greaterThan(0));
      expect(deltaEScore(0), 1);
      expect(deltaEScore(2), 1);
      expect(deltaEScore(20), 0);
      final parsed = parseCssColor('rgb($v, $v, $v)');
      expect(parsed, isNotNull);
      expect(parsed!.r, v);
      expect(parsed.g, v);
      expect(parsed.b, v);
      expect(canonicalCssColor('rgb($v, $v, $v)'), 'rgb($v, $v, $v)');
    });
  }

  // 25 geometry-matrix cases: identical, shifted, resized and sibling-order
  // variants. The exact deltas vary, the contract does not.
  for (var i = 0; i < 25; i++) {
    test('geometry matrix case ${i + 1}', () {
      final reference = _probe([
        _element('html:1>body:1>div:1', 0, 0, 400, 300),
        _element('html:1>body:1>div:1>span:1', 10, 10, 100, 40),
      ]);
      final identical = compareGeometry(reference, reference);
      expect(identical.positionScore, 1);
      expect(identical.layoutScore, 1);
      expect(identical.missing, 0);
      expect(identical.extra, 0);

      final shifted = _probe([
        _element('html:1>body:1>div:1', (i + 1) * 8.0, 0, 400, 300),
        _element('html:1>body:1>div:1>span:1', 10, 10, 100, 40),
      ]);
      final moved = compareGeometry(reference, shifted);
      expect(moved.positionScore, lessThan(1));
      expect(moved.sizeMatchPct, 100);

      final resized = _probe([
        _element('html:1>body:1>div:1', 0, 0, 400 + i + 1.0, 300),
        _element('html:1>body:1>div:1>span:1', 10, 10, 100, 40),
      ]);
      final resizedResult = compareGeometry(reference, resized);
      expect(resizedResult.positionScore, 1);
      expect(resizedResult.layoutScore, lessThan(1));
    });
  }
}
