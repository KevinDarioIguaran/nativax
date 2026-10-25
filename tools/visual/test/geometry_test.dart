import 'dart:convert';

import 'package:nativa_visual/src/geometry.dart';
import 'package:nativa_visual/src/model.dart';
import 'package:test/test.dart';

ElementSnapshot element(
  String path,
  String tag,
  double x,
  double y,
  double w,
  double h,
) => ElementSnapshot(
  path: path,
  tag: tag,
  rect: BoxRect(x, y, w, h),
  styles: const {'color': 'rgb(0, 0, 0)'},
);

ProbeSnapshot probe(List<ElementSnapshot> elements, {int height = 600}) =>
    ProbeSnapshot(
      viewportWidth: 800,
      viewportHeight: height,
      dpr: 1,
      documentWidth: 800,
      documentHeight: height,
      elements: elements,
    );

void main() {
  group('geometry', () {
    test('identical layouts score 100', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 800, 600),
        element('html:1>body:1>div:1>span:1', 'span', 10, 20, 100, 40),
      ]);
      final comparison = compareGeometry(reference, reference);
      expect(comparison.positionScore, 1);
      expect(comparison.layoutScore, 1);
      expect(comparison.matched, 2);
      expect(comparison.missing, 0);
      expect(comparison.extra, 0);
      expect(comparison.rootCauses, isEmpty);
    });

    test('position deltas reduce the position score but not size', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 400, 300),
      ]);
      final moved = probe([
        element('html:1>body:1>div:1', 'div', 8, 0, 400, 300),
      ]);
      final comparison = compareGeometry(reference, moved);
      expect(comparison.positionScore, lessThan(1));
      expect(comparison.positionScore, greaterThan(0.4));
      expect(comparison.sizeMatchPct, 100);
      expect(comparison.deltas.single.positionDelta, 8);
    });

    test('size deltas reduce the layout score', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 400, 300),
      ]);
      final resized = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 430, 300),
      ]);
      final comparison = compareGeometry(reference, resized);
      expect(comparison.positionScore, 1);
      expect(comparison.layoutScore, lessThan(1));
      expect(comparison.sizeMatchPct, 0);
    });

    test('missing and extra elements are penalties', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 800, 600),
        element('html:1>body:1>div:1>p:1', 'p', 10, 10, 100, 20),
      ]);
      final other = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 800, 600),
        element('html:1>body:1>div:1>section:1', 'section', 10, 10, 100, 20),
      ]);
      final comparison = compareGeometry(reference, other);
      expect(comparison.missing, 1);
      expect(comparison.extra, 1);
      expect(comparison.positionScore, lessThan(1));
      expect(
        comparison.rootCauses.map((d) => d.path),
        contains('html:1>body:1>div:1>p:1'),
      );
    });

    test('root causes stop at the first wrong container', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 400, 300),
        element('html:1>body:1>div:1>span:1', 'span', 10, 10, 100, 40),
        element('html:1>body:1>footer:1', 'footer', 0, 400, 400, 100),
      ]);
      final other = probe([
        element('html:1>body:1>div:1', 'div', 30, 0, 400, 300),
        element('html:1>body:1>div:1>span:1', 'span', 40, 10, 100, 40),
        element('html:1>body:1>footer:1', 'footer', 0, 400, 400, 100),
      ]);
      final comparison = compareGeometry(reference, other);
      final roots = comparison.rootCauses.map((d) => d.path).toList();
      expect(roots, contains('html:1>body:1>div:1'));
      expect(roots, isNot(contains('html:1>body:1>div:1>span:1')));
    });

    test('detects swapped sibling order', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 400, 300),
        element('html:1>body:1>div:1>p:1', 'p', 0, 0, 100, 20),
        element('html:1>body:1>div:1>p:2', 'p', 0, 30, 100, 20),
      ]);
      final other = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 400, 300),
        element('html:1>body:1>div:1>p:1', 'p', 0, 40, 100, 20),
        element('html:1>body:1>div:1>p:2', 'p', 0, 10, 100, 20),
      ]);
      expect(compareGeometry(reference, other).orderViolations, greaterThan(0));
    });

    test('missing elements serialise without Infinity', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 100, 100),
      ]);
      final other = probe([]);
      final comparison = compareGeometry(reference, other);
      expect(
        () => jsonEncode([for (final d in comparison.deltas) d.toJson()]),
        returnsNormally,
      );
    });

    test('identical zero-area boxes are a perfect match', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 10, 10, 0, 4),
      ]);
      final comparison = compareGeometry(reference, reference);
      expect(comparison.layoutScore, 1);
      expect(comparison.deltas.single.iou, 1);
    });

    test('document height participates in flow', () {
      final reference = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 400, 600),
      ], height: 600);
      final shorter = probe([
        element('html:1>body:1>div:1', 'div', 0, 0, 400, 600),
      ], height: 300);
      final comparison = compareGeometry(reference, shorter);
      expect(comparison.flowScore, lessThan(1));
      expect(comparison.documentHeightDelta, 300);
    });
  });
}
