import 'dart:typed_data';

import 'package:nativa_visual/src/model.dart';
import 'package:nativa_visual/src/png.dart';
import 'package:nativa_visual/src/score.dart';
import 'package:test/test.dart';

RasterImage solid(int width, int height, int r, int g, int b) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = 255;
  }
  return RasterImage(width, height, rgba);
}

ElementSnapshot element(
  String path,
  double x,
  double y,
  double w,
  double h, {
  String size = '16px',
  String color = 'rgb(0, 0, 0)',
}) => ElementSnapshot(
  path: path,
  tag: 'div',
  rect: BoxRect(x, y, w, h),
  styles: {
    'display': 'block',
    'color': color,
    'background-color': 'rgb(255, 255, 255)',
    'font-size': size,
    'font-weight': '400',
    'font-family': 'sans-serif',
    'line-height': 'normal',
    'border-top-style': 'none',
    'border-top-width': '0px',
    'opacity': '1',
    'position': 'static',
    'visibility': 'visible',
    'overflow-x': 'visible',
    'overflow-y': 'visible',
  },
);

ProbeSnapshot snapshot(List<ElementSnapshot> elements, {int height = 40}) =>
    ProbeSnapshot(
      viewportWidth: 40,
      viewportHeight: height,
      dpr: 1,
      documentWidth: 40,
      documentHeight: height,
      elements: elements,
    );

List<ElementSnapshot> page({double dx = 0}) => [
  element('html:1>body:1>div:1', 0 + dx, 0 + dx, 40, 40),
  element('html:1>body:1>div:1>span:1', 5 + dx, 5 + dx, 20, 20),
];

void main() {
  group('evaluation', () {
    test('a perfect match scores 100 and passes', () {
      final reference = snapshot(page());
      final evaluation = evaluate(
        chromeProbe: reference,
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [
          EnvCheck(name: 'chromium', ok: true, hard: true, detail: 'ok'),
          EnvCheck(name: 'nativa', ok: true, hard: true, detail: 'ok'),
        ],
      );
      expect(evaluation.position, 1);
      expect(evaluation.layout, 1);
      expect(evaluation.color, 1);
      expect(evaluation.design, 1);
      expect(evaluation.overall, 1);
      expect(evaluation.verdict, Verdict.pass);
      expect(evaluation.mismatchedPixels, 0);
    });

    test('a global shift fails position while colour stays independent', () {
      final evaluation = evaluate(
        chromeProbe: snapshot(page()),
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page(dx: 20)),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(evaluation.position, 0);
      expect(evaluation.color, 1);
      expect(evaluation.colorComparable, greaterThan(0));
      expect(evaluation.verdict, Verdict.fail);
    });

    test('a colour difference lowers colour and overrides nothing else', () {
      final evaluation = evaluate(
        chromeProbe: snapshot(page()),
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 0, 0),
        checks: const [],
      );
      expect(evaluation.color, lessThan(1));
      expect(evaluation.colorFailures, isNotEmpty);
      expect(evaluation.position, 1);
      expect(evaluation.verdict, isNot(Verdict.pass));
    });

    test('a style difference lowers design but keeps layout', () {
      final nativaPage = page();
      nativaPage[1] = element(
        'html:1>body:1>div:1>span:1',
        5,
        5,
        20,
        20,
        size: '12px',
      );
      final evaluation = evaluate(
        chromeProbe: snapshot(page()),
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(nativaPage),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(evaluation.design, lessThan(1));
      expect(evaluation.layout, 1);
      expect(
        evaluation.designFailures.first.mismatches.map((m) => m.property),
        contains('font-size'),
      );
    });

    test('a failed hard environment check makes the page invalid', () {
      final reference = snapshot(page());
      final evaluation = evaluate(
        chromeProbe: reference,
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [
          EnvCheck(name: 'viewport', ok: false, hard: true, detail: 'mismatch'),
        ],
      );
      expect(evaluation.verdict, Verdict.invalid);
    });

    test('a large ink mismatch fails an otherwise perfect page', () {
      final chrome = solid(40, 40, 255, 255, 255);
      for (var y = 10; y < 14; y++) {
        for (var x = 10; x < 14; x++) {
          final i = (y * 40 + x) * 4;
          chrome.rgba[i] = 0;
          chrome.rgba[i + 1] = 0;
          chrome.rgba[i + 2] = 0;
        }
      }
      final evaluation = evaluate(
        chromeProbe: snapshot(page()),
        chromeImage: chrome,
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(evaluation.overall, greaterThan(0.9));
      expect(evaluation.verdict, Verdict.fail);
      expect(evaluation.reason, contains('ink mismatch'));
    });

    test('strict judge: a single-pixel ink mismatch is not a pass', () {
      final chrome = solid(40, 40, 255, 255, 255);
      chrome.rgba[0] = 0;
      chrome.rgba[1] = 0;
      chrome.rgba[2] = 0;
      final evaluation = evaluate(
        chromeProbe: snapshot(page()),
        chromeImage: chrome,
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(evaluation.verdict, Verdict.warn);
    });

    test('soft environment warnings do not invalidate', () {
      final reference = snapshot(page());
      final evaluation = evaluate(
        chromeProbe: reference,
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [
          EnvCheck(name: 'document-coverage', ok: false, detail: 'partial'),
        ],
      );
      expect(evaluation.verdict, Verdict.pass);
    });

    test('strict judge: one differing pixel in 1600 is not a pass', () {
      // 1/1600 = 0.0625 % of pixels: above the 0.01 % pixel margin.
      final nativa = solid(40, 40, 255, 255, 255);
      nativa.rgba[0] = 0;
      nativa.rgba[1] = 0;
      nativa.rgba[2] = 0;
      final evaluation = evaluate(
        chromeProbe: snapshot(page()),
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: nativa,
        checks: const [],
      );
      expect(evaluation.verdict, isNot(Verdict.pass));
    });

    test('strict judge: below 99 % overall fails', () {
      expect(failOverall, 0.99);
      expect(passPixelMismatchPct, 0.01);
      final evaluation = evaluate(
        chromeProbe: snapshot(page(dx: 3)),
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(evaluation.overall, lessThan(failOverall));
      expect(evaluation.verdict, Verdict.fail);
    });

    test('the pass target is 99.99 %: a near match only warns', () {
      final evaluation = evaluate(
        chromeProbe: snapshot(page(dx: 1)),
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(passOverall, 0.9999);
      expect(evaluation.overall, lessThan(passOverall));
      expect(evaluation.verdict, isNot(Verdict.pass));
    });

    test('small shifts keep colour measurable on the overlap', () {
      final evaluation = evaluate(
        chromeProbe: snapshot(page(dx: 3)),
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: snapshot(page()),
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(evaluation.color, 1);
      expect(evaluation.colorComparable, greaterThan(0));
      expect(evaluation.overall, inInclusiveRange(0, 1));
    });

    test('overall is renormalised when colour cannot be measured', () {
      final left = snapshot([element('html:1>body:1>div:1', 0, 0, 10, 10)]);
      final right = snapshot([element('html:1>body:1>span:1', 0, 0, 10, 10)]);
      final evaluation = evaluate(
        chromeProbe: left,
        chromeImage: solid(40, 40, 255, 255, 255),
        nativaProbe: right,
        nativaImage: solid(40, 40, 255, 255, 255),
        checks: const [],
      );
      expect(evaluation.color, isNull);
      expect(evaluation.overall, inInclusiveRange(0, 1));
    });
  });
}
