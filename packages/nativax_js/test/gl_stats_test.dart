import 'package:nativax_js/nativax_js.dart' show GlSurfaces;
import 'package:test/test.dart';

void main() {
  test('presentation stats keep cadence, decode and size percentiles', () async {
    const surface = 0x7fffff00;

    GlSurfaces.markShown(
      surface,
      width: 1280,
      height: 720,
      decodeMicros: 1000,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    GlSurfaces.markShown(
      surface,
      width: 1280,
      height: 720,
      decodeMicros: 2000,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    GlSurfaces.markShown(
      surface,
      width: 1280,
      height: 720,
      decodeMicros: 3000,
    );

    expect(GlSurfaces.shown(surface), 3);
    expect(GlSurfaces.shownWidth(surface), 1280);
    expect(GlSurfaces.shownHeight(surface), 720);
    expect(GlSurfaces.presentSamples(surface), 2);
    expect(GlSurfaces.presentP50Micros(surface), greaterThan(0));
    expect(GlSurfaces.presentP95Micros(surface), greaterThan(0));
    expect(GlSurfaces.decodeP50Micros(surface), 2000);
    expect(GlSurfaces.decodeP95Micros(surface), 3000);
    expect(GlSurfaces.decodeP99Micros(surface), 3000);
  });
}
