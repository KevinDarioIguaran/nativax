import 'dart:typed_data';

import 'package:nativa_visual/src/png.dart';
import 'package:test/test.dart';

RasterImage _checkerboard(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      rgba[i] = (x * 7) & 0xff;
      rgba[i + 1] = (y * 5) & 0xff;
      rgba[i + 2] = (x + y) & 0xff;
      rgba[i + 3] = 255;
    }
  }
  return RasterImage(width, height, rgba);
}

void main() {
  group('PNG codec', () {
    test('roundtrips RGBA pixels', () {
      final source = _checkerboard(37, 19);
      final decoded = decodePng(encodePng(source));
      expect(decoded.width, 37);
      expect(decoded.height, 19);
      expect(decoded.rgba, equals(source.rgba));
    });

    test('rejects a non-PNG file', () {
      expect(
        () => decodePng(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
        throwsA(isA<PngException>()),
      );
    });

    test('rejects a truncated PNG', () {
      final png = encodePng(_checkerboard(8, 8));
      expect(
        () => decodePng(Uint8List.sublistView(png, 0, png.length - 20)),
        throwsA(isA<PngException>()),
      );
    });

    test('crop keeps the top-left region', () {
      final source = _checkerboard(10, 10);
      final cropped = source.crop(5, 4);
      expect(cropped.width, 5);
      expect(cropped.height, 4);
      expect(cropped.red(3, 2), source.red(3, 2));
      expect(cropped.width, 5);
      expect(cropped.crop(100, 100).width, 5);
    });

    test('nearest resize preserves solid colours', () {
      final source = RasterImage(
        2,
        2,
        Uint8List.fromList([
          255,
          0,
          0,
          255,
          255,
          0,
          0,
          255,
          255,
          0,
          0,
          255,
          255,
          0,
          0,
          255,
        ]),
      );
      final scaled = source.nearest(8, 8);
      expect(scaled.width, 8);
      expect(scaled.red(7, 7), 255);
      expect(scaled.green(7, 7), 0);
    });
  });
}
