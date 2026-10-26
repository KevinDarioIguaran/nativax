import 'dart:typed_data';

import 'package:nativa_visual/src/model.dart';
import 'package:nativa_visual/src/pixels.dart';
import 'package:nativa_visual/src/png.dart';
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

void main() {
  group('pixel comparison', () {
    test('identical screenshots have no mismatched pixels', () {
      final comparison = comparePixels(
        solid(20, 10, 200, 100, 50),
        solid(20, 10, 200, 100, 50),
      );
      expect(comparison.totals.pixels, 200);
      expect(comparison.totals.mismatched, 0);
      expect(comparison.totals.exact, 200);
      expect(comparison.totals.meanDeltaE, 0);
      expect(comparison.totals.maxDeltaE, 0);
    });

    test('one changed pixel is counted and gets a diff colour', () {
      final other = solid(20, 10, 200, 100, 50);
      other.rgba[0] = 0;
      other.rgba[1] = 0;
      other.rgba[2] = 0;
      final comparison = comparePixels(solid(20, 10, 200, 100, 50), other);
      expect(comparison.totals.mismatched, 1);
      expect(comparison.totals.exact, 199);
      expect(comparison.totals.maxDeltaE, greaterThan(20));
      expect(comparison.diff.red(0, 0), 255);
      expect(comparison.diff.red(1, 0), 245);
    });

    test('ink mismatch exposes missing content on an almost-white page', () {
      final chrome = solid(40, 40, 255, 255, 255);
      for (var y = 10; y < 14; y++) {
        for (var x = 10; x < 14; x++) {
          final i = (y * 40 + x) * 4;
          chrome.rgba[i] = 0;
          chrome.rgba[i + 1] = 0;
          chrome.rgba[i + 2] = 0;
        }
      }
      final nativa = solid(40, 40, 255, 255, 255);
      final comparison = comparePixels(chrome, nativa);
      expect(comparison.totals.pixels, 1600);
      expect(comparison.totals.mismatched, 16);
      expect(comparison.totals.inkPixels, 16);
      expect(comparison.totals.inkMismatched, 16);
      expect(comparison.totals.inkMismatchPct, 100);
      expect(comparison.totals.chromeInkPixels, 16);
      expect(comparison.totals.nativaInkPixels, 0);
    });

    test('buckets separate small and large differences', () {
      final other = solid(10, 10, 10, 10, 10);
      for (var i = 0; i < 10; i++) {
        other.rgba[i * 4] = 255;
      }
      final comparison = comparePixels(solid(10, 10, 10, 10, 10), other);
      expect(comparison.totals.buckets['de>20'], 10);
      expect(comparison.totals.pixels, 100);
    });

    test('worst tiles are reported in descending order', () {
      final a = solid(32, 32, 255, 255, 255);
      final b = solid(32, 32, 255, 255, 255);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final i = (y * 32 + x) * 4;
          b.rgba[i] = 0;
          b.rgba[i + 1] = 0;
          b.rgba[i + 2] = 0;
        }
      }
      final comparison = comparePixels(a, b);
      expect(comparison.worstTiles, isNotEmpty);
      expect(comparison.worstTiles.first.x, 0);
      expect(comparison.worstTiles.first.y, 0);
    });

    test('pixel CSV can include only mismatches', () {
      final other = solid(4, 4, 0, 0, 0);
      other.rgba[0] = 255;
      final csv = pixelCsv(solid(4, 4, 0, 0, 0), other);
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('x,y,chrome_r'));
      expect(lines.length, 2);
      expect(lines[1], startsWith('0,0,0,0,0,255,0,0,'));
    });
  });

  group('colour comparison', () {
    test('identical element boxes score 100', () {
      final comparison = compareColors(
        solid(20, 20, 30, 144, 255),
        solid(20, 20, 30, 144, 255),
        const BoxRect(0, 0, 20, 20),
        const BoxRect(0, 0, 20, 20),
      );
      expect(comparison, isNotNull);
      expect(comparison!.score, 1);
      expect(comparison.paletteDeltaE, 0);
    });

    test('different colours score low and report both palettes', () {
      final comparison = compareColors(
        solid(20, 20, 255, 0, 0),
        solid(20, 20, 0, 0, 255),
        const BoxRect(0, 0, 20, 20),
        const BoxRect(0, 0, 20, 20),
      )!;
      expect(comparison.score, lessThan(0.5));
      expect(comparison.paletteDeltaE, greaterThan(20));
      expect(comparison.chromePalette.first.color.toString(), 'rgb(255, 0, 0)');
      expect(comparison.nativaPalette.first.color.toString(), 'rgb(0, 0, 255)');
    });

    test('palette share changes count as colour differences', () {
      final mostlyWhite = solid(20, 20, 255, 255, 255);
      final mixed = solid(20, 20, 255, 255, 255);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 8; x++) {
          final i = (y * 20 + x) * 4;
          mixed.rgba[i] = 0;
          mixed.rgba[i + 1] = 0;
          mixed.rgba[i + 2] = 255;
        }
      }
      final comparison = compareColors(
        mostlyWhite,
        mixed,
        const BoxRect(0, 0, 20, 20),
        const BoxRect(0, 0, 20, 20),
      )!;
      expect(comparison.paletteDeltaE, greaterThan(5));
      expect(comparison.score, lessThan(0.5));
    });

    test('colour is independent of a shifted box', () {
      final image = solid(40, 40, 255, 255, 255);
      final comparison = compareColors(
        image,
        image,
        const BoxRect(0, 0, 20, 20),
        const BoxRect(20, 20, 20, 20),
      )!;
      expect(comparison.score, 1);
    });

    test('dominant colours recover a two-colour palette', () {
      final image = solid(20, 10, 255, 255, 255);
      for (var y = 0; y < 10; y++) {
        for (var x = 0; x < 10; x++) {
          final i = (y * 20 + x) * 4;
          image.rgba[i] = 0;
          image.rgba[i + 1] = 0;
          image.rgba[i + 2] = 0;
        }
      }
      final palette = dominantColors(image, const BoxRect(0, 0, 20, 10));
      expect(palette, hasLength(2));
      expect(palette.first.share, closeTo(0.5, 0.01));
    });

    test('boxes below the viewport are not sampled', () {
      expect(
        averageColor(
          solid(10, 10, 255, 255, 255),
          const BoxRect(0, 40, 10, 10),
        ),
        isNull,
      );
      expect(
        dominantColors(
          solid(10, 10, 255, 255, 255),
          const BoxRect(0, 40, 10, 10),
        ),
        isEmpty,
      );
    });

    test('partially visible boxes use the visible part', () {
      expect(
        averageColor(
          solid(10, 10, 255, 255, 255),
          const BoxRect(0, 5, 10, 40),
        )?.toString(),
        'rgb(255, 255, 255)',
      );
    });

    test('empty boxes are not compared', () {
      expect(
        compareColors(
          solid(10, 10, 0, 0, 0),
          solid(10, 10, 0, 0, 0),
          const BoxRect(0, 0, 0, 10),
          const BoxRect(0, 0, 10, 10),
        ),
        isNull,
      );
    });
  });

  group('region sampling', () {
    test('averages the same region in both images', () {
      final sample = sampleRegion(
        solid(40, 40, 255, 255, 255),
        solid(40, 40, 255, 0, 0),
        const BoxRect(10, 10, 20, 20),
      );
      expect(sample, isNotNull);
      expect(sample!.chrome.toString(), 'rgb(255, 255, 255)');
      expect(sample.nativa.toString(), 'rgb(255, 0, 0)');
      expect(sample.meanDeltaE, greaterThan(20));
    });

    test('refuses boxes outside the screenshot', () {
      expect(
        sampleRegion(
          solid(10, 10, 0, 0, 0),
          solid(10, 10, 0, 0, 0),
          const BoxRect(5, 5, 20, 20),
        ),
        isNull,
      );
    });

    test('one-pixel boxes are not sampled', () {
      expect(
        sampleRegion(
          solid(10, 10, 0, 0, 0),
          solid(10, 10, 0, 0, 0),
          const BoxRect(2, 2, 2, 2),
        ),
        isNull,
      );
    });
  });

  test('images of different widths compare the common area pixel by pixel', () {
    // Same gradient content; the actual capture is 3 px narrower. A stride
    // error would compare shifted rows and report false mismatches.
    RasterImage gradient(int width, int height) {
      final rgba = Uint8List(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          rgba[i] = x * 20;
          rgba[i + 1] = y * 20;
          rgba[i + 2] = 128;
          rgba[i + 3] = 255;
        }
      }
      return RasterImage(width, height, rgba);
    }

    final wide = gradient(10, 6);
    final narrow = gradient(7, 6);
    for (final (a, b) in [(wide, narrow), (narrow, wide)]) {
      final result = comparePixels(a, b);
      expect(result.totals.width, 7);
      expect(result.totals.mismatched, 0);
      expect(result.totals.maxDeltaE, 0);
      expect(pixelCsv(a, b).trim().split('\n'), hasLength(1));
    }
  });
}
