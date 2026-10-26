import 'dart:io';

import 'package:nativa_visual/src/chrome.dart';
import 'package:nativa_visual/src/png.dart';
import 'package:test/test.dart';

/// Chrome-only integration test. It proves that the probe viewport and the
/// screenshot share the same layout height, which is required for `100vh`,
/// fixed centring and percentage heights.
///
///   NATIVA_VISUAL_E2E=1 dart test test/chrome_e2e_test.dart
void main() {
  final enabled = Platform.environment['NATIVA_VISUAL_E2E'] == '1';
  final chrome = Platform.environment['CHROME'] ?? 'google-chrome';

  test(
    'probe viewport matches the rendered screenshot',
    () async {
      final root = Directory.systemTemp.createTempSync('nativa-visual-e2e-');
      addTearDown(() => root.deleteSync(recursive: true));
      final page = Directory('${root.path}/page')..createSync();
      File('${page.path}/index.html').writeAsStringSync('''<!doctype html>
<html><head><meta charset="utf-8"><style>
html, body { margin: 0; height: 100%; }
body { display: flex; align-items: center; justify-content: center; background: #fff; }
#box { width: 100px; height: 100px; background: #ff0000; }
</style></head><body><div id="box"></div></body></html>''');

      // Chromium enforces a minimum window size; use a realistic viewport.
      const width = 500;
      const height = 400;
      final delta = await calibrateChromeFrame(
        executable: chrome,
        width: width,
        height: height,
      );
      expect(delta, greaterThanOrEqualTo(0));
      final outcome = await renderWithChrome(
        executable: chrome,
        pageDirectory: page.path,
        artifacts: '${root.path}/artifacts',
        width: width,
        height: height,
        frameDelta: delta,
      );
      expect(outcome.probe.viewportWidth, width);
      expect(outcome.probe.viewportHeight, height);
      expect(outcome.probe.dpr, 1);
      expect(outcome.screenshot.width, width);
      expect(outcome.screenshot.height, height);
      final box = outcome.probe.byPath['#box'];
      expect(box, isNotNull);
      expect(box!.rect.x, closeTo(200, 1));
      expect(box.rect.y, closeTo(150, 1));
      expect(box.rect.width, closeTo(100, 1));

      // The screenshot must paint the box at the same coordinates the probe
      // reports; before the frame-offset calibration this was 37px off.
      RasterImage image = outcome.screenshot;
      expect(image.red(250, 200), greaterThan(200));
      expect(image.green(250, 200), lessThan(40));
      expect(image.red(250, 80), greaterThan(200));
      expect(image.green(250, 80), greaterThan(200));
    },
    skip: enabled
        ? false
        : 'set NATIVA_VISUAL_E2E=1 to run Chrome integration tests',
  );

  test(
    'a body with only text still reports a measurable element',
    () async {
      // mdn html-text-formatting has text directly in <body>; with no child
      // element both engines reported 0 elements and the page was INVALID.
      final root = Directory.systemTemp.createTempSync('nativa-visual-e2e-');
      addTearDown(() => root.deleteSync(recursive: true));
      final page = Directory('${root.path}/page')..createSync();
      File('${page.path}/index.html').writeAsStringSync(
        '<!doctype html><html><body>Quick hummus recipe</body></html>',
      );
      const width = 500;
      const height = 400;
      final delta = await calibrateChromeFrame(
        executable: chrome,
        width: width,
        height: height,
      );
      final outcome = await renderWithChrome(
        executable: chrome,
        pageDirectory: page.path,
        artifacts: '${root.path}/artifacts',
        width: width,
        height: height,
        frameDelta: delta,
      );
      expect(outcome.probe.elements.map((e) => e.tag), ['body']);
    },
    skip: enabled
        ? false
        : 'set NATIVA_VISUAL_E2E=1 to run Chrome integration tests',
  );
}
