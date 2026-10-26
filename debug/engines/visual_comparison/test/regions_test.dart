import 'dart:typed_data';

import 'package:nativa_visual/src/model.dart';
import 'package:nativa_visual/src/png.dart';
import 'package:nativa_visual/src/regions.dart';
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

void paint(RasterImage image, int x, int y, int r, int g, int b) {
  final i = (y * image.width + x) * 4;
  image.rgba[i] = r;
  image.rgba[i + 1] = g;
  image.rgba[i + 2] = b;
}

void fill(RasterImage image, int x, int y, int w, int h, int r, int g, int b) {
  for (var yy = y; yy < y + h; yy++) {
    for (var xx = x; xx < x + w; xx++) {
      paint(image, xx, yy, r, g, b);
    }
  }
}

ElementSnapshot element(String path, BoxRect rect) =>
    ElementSnapshot(path: path, tag: 'div', rect: rect, styles: const {});

void main() {
  test('identical images produce no mask and no regions', () {
    final a = solid(10, 10, 255, 255, 255);
    final report = findRegions(deltaMap(a, solid(10, 10, 255, 255, 255)));
    expect(report.maskPixels, 0);
    expect(report.components, 0);
    expect(report.regions, isEmpty);
  });

  test('diagonal pixels join one 8-connected component', () {
    final a = solid(10, 10, 255, 255, 255);
    final b = solid(10, 10, 255, 255, 255);
    for (var i = 0; i < 5; i++) {
      paint(b, 2 + i, 2 + i, 0, 0, 0);
    }
    final report = findRegions(deltaMap(a, b), minArea: 1);
    expect(report.components, 1);
    final region = report.regions.single;
    expect(region.pixels, 5);
    expect(region.bbox.toJson(), [2, 2, 5, 5]);
  });

  test('min-area filter drops small components and counts them', () {
    final a = solid(20, 20, 255, 255, 255);
    final b = solid(20, 20, 255, 255, 255);
    paint(b, 0, 0, 230, 230, 230); // faint 1 px speckle (deltaE < strong)
    fill(b, 10, 10, 3, 3, 0, 0, 0); // 9 px block
    final report = findRegions(deltaMap(a, b), minArea: 4);
    expect(report.maskPixels, 10);
    expect(report.components, 2);
    expect(report.droppedComponents, 1);
    expect(report.droppedPixels, 1);
    expect(report.keptPixels, 9);
    expect(report.regions.single.bbox.toJson(), [10, 10, 3, 3]);
  });

  test('threshold is strict: deltaE equal to the threshold is not masked', () {
    final a = solid(4, 4, 255, 255, 255);
    final b = solid(4, 4, 250, 250, 250);
    final map = deltaMap(a, b);
    final de = map.values.first;
    expect(findRegions(map, threshold: de).maskPixels, 0);
    expect(findRegions(map, threshold: de - 0.01).maskPixels, 16);
  });

  test('regions report mean and max deltaE and sort largest first', () {
    final a = solid(30, 10, 255, 255, 255);
    final b = solid(30, 10, 255, 255, 255);
    fill(b, 0, 0, 2, 2, 0, 0, 0);
    fill(b, 10, 0, 4, 4, 200, 200, 200);
    final report = findRegions(deltaMap(a, b), minArea: 1);
    expect(report.regions.map((r) => r.pixels), [16, 4]);
    expect(report.regions.map((r) => r.id), [1, 2]);
    expect(report.regions.last.maxDeltaE, closeTo(100, 0.5));
    expect(
      report.regions.first.meanDeltaE,
      closeTo(report.regions.first.maxDeltaE, 1e-6),
    );
  });

  test('regions name intersecting elements with IoU and side', () {
    final a = solid(40, 40, 255, 255, 255);
    final b = solid(40, 40, 255, 255, 255);
    fill(b, 10, 10, 10, 10, 0, 0, 0);
    final report = findRegions(
      deltaMap(a, b),
      referenceElements: [
        element('html:1', const BoxRect(0, 0, 40, 40)),
        element('html:1>div:1', const BoxRect(10, 10, 10, 10)),
        element('html:1>div:2', const BoxRect(30, 30, 5, 5)),
      ],
      actualElements: [element('html:1>div:1', const BoxRect(12, 10, 10, 10))],
    );
    final elements = report.regions.single.elements;
    expect(elements.map((e) => e.path), ['html:1>div:1', 'html:1']);
    expect(elements.first.iou, 1);
    expect(elements.first.sides, ['reference', 'actual']);
    expect(elements.last.iou, closeTo(100 / 1600, 1e-9));
    expect(elements.last.sides, ['reference']);
  });

  test('json records threshold, connectivity and min-area', () {
    final a = solid(4, 4, 255, 255, 255);
    final json = findRegions(deltaMap(a, a), threshold: 3, minArea: 7).toJson();
    expect(json['connectivity'], 8);
    expect(json['minArea'], 7);
    expect((json['mask'] as Map)['threshold'], 3);
    expect(json['regions'], isEmpty);
  });

  test('region list is truncated but totals stay exact', () {
    final a = solid(20, 20, 255, 255, 255);
    final b = solid(20, 20, 255, 255, 255);
    for (var i = 0; i < 10; i++) {
      paint(b, i * 2, 0, 0, 0, 0);
    }
    final report = findRegions(
      deltaMap(a, b),
      minArea: 1,
      mergeGap: -1,
      maxRegions: 3,
    );
    expect(report.regions, hasLength(3));
    expect(report.truncated, isTrue);
    expect(report.keptPixels, 10);
  });

  test('components closer than mergeGap form one region', () {
    final a = solid(30, 10, 255, 255, 255);
    final b = solid(30, 10, 255, 255, 255);
    fill(b, 0, 0, 2, 2, 0, 0, 0);
    fill(b, 6, 0, 2, 2, 0, 0, 0); // 4 px gap: grouped
    fill(b, 20, 0, 2, 2, 0, 0, 0); // 12 px gap: separate
    final report = findRegions(deltaMap(a, b), mergeGap: 4);
    expect(report.components, 3);
    expect(report.regions.map((r) => r.bbox.toJson()), [
      [0, 0, 8, 2],
      [20, 0, 2, 2],
    ]);
    expect(report.regions.first.components, 2);
    expect(findRegions(deltaMap(a, b), mergeGap: -1).regions, hasLength(3));
  });

  test('pixels only one image covers become size regions', () {
    final a = solid(12, 6, 255, 255, 255);
    final b = solid(10, 4, 255, 255, 255);
    final report = findRegions(deltaMap(a, b));
    expect(report.maskPixels, 0);
    expect(
      [
        for (final r in report.regions) [r.kind, ...r.bbox.toJson()],
      ],
      [
        ['size', 10, 0, 2, 6],
        ['size', 0, 4, 10, 2],
      ],
    );
  });

  test('overlay blends 50/50 and tints mask pixels', () {
    final a = solid(2, 1, 200, 100, 0);
    final b = solid(2, 1, 200, 100, 0);
    paint(b, 1, 0, 0, 100, 200);
    final overlay = overlayImage(a, b, deltaMap(a, b));
    expect(overlay.width, 2);
    expect(overlay.height, 1);
    expect(
      [overlay.red(0, 0), overlay.green(0, 0), overlay.blue(0, 0)],
      [200, 100, 0],
    );
    // blend (100, 100, 100) mixed 40/60 with the tint (255, 0, 128).
    expect(
      [overlay.red(1, 0), overlay.green(1, 0), overlay.blue(1, 0)],
      [193, 40, 117],
    );
    expect(overlay.alpha(1, 0), 255);
  });

  test('overlay and map use the common area of different sizes', () {
    final map = deltaMap(solid(5, 4, 0, 0, 0), solid(3, 6, 0, 0, 0));
    expect([map.width, map.height], [3, 4]);
    final overlay = overlayImage(
      solid(5, 4, 0, 0, 0),
      solid(3, 6, 0, 0, 0),
      map,
    );
    expect([overlay.width, overlay.height], [3, 4]);
  });
}
