import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'png.dart';
import 'proc.dart';
import 'probe.dart';
import 'staging.dart';

class ChromeOutcome {
  const ChromeOutcome({
    required this.probe,
    required this.screenshot,
    required this.rawScreenshot,
    required this.duration,
    required this.stderr,
    required this.screenshotPath,
    required this.probeJsonPath,
    required this.frameDelta,
  });

  final ProbeSnapshot probe;
  final RasterImage screenshot;
  final RasterImage rawScreenshot;
  final Duration duration;
  final String stderr;
  final String screenshotPath;
  final String probeJsonPath;

  /// Pixels that headless Chromium reserves above the layout viewport when
  /// dumping the DOM. Measurement runs add it back so the screenshot and the
  /// probe share exactly the same layout height.
  final int frameDelta;
}

class VisualException implements Exception {
  VisualException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Measures how much taller the window has to be for `--dump-dom` to report
/// the requested `innerHeight`.
///
/// Headless Chromium (152 on Linux) reports `innerHeight = window - 87` when
/// dumping the DOM, but `--screenshot` lays the page out at the full window
/// height. Without this correction, `100vh`, fixed centring and percentage
/// heights are measured against a different viewport than the one painted,
/// which silently invalidates the comparison.
Future<int> calibrateChromeFrame({
  required String executable,
  required int width,
  required int height,
  Duration timeout = const Duration(minutes: 1),
}) async {
  final temp = Directory.systemTemp.createTempSync('nativa-visual-cal-');
  try {
    final page = File('${temp.path}/calibrate.html')
      ..writeAsStringSync('''<!doctype html><html><head><meta charset="utf-8">
<title>calibration</title></head><body><pre id="__calib"></pre>
<script>
addEventListener('load', function () {
  document.getElementById('__calib').textContent = JSON.stringify({
    w: window.innerWidth, h: window.innerHeight, dpr: window.devicePixelRatio || 1
  });
});
</script></body></html>''');
    final result = await runProcess(executable, [
      ..._baseFlags,
      '--user-data-dir=${temp.path}/profile',
      '--window-size=$width,$height',
      '--virtual-time-budget=1000',
      '--dump-dom',
      Uri.file(page.path).toString(),
    ], timeout: timeout);
    if (!result.ok) {
      throw VisualException(
        'Chromium calibration failed (${result.exitCode}): ${_tail(result.stderr)}',
      );
    }
    final marker = RegExp(
      r'<pre[^>]*id="__calib"[^>]*>([\s\S]*?)</pre>',
    ).firstMatch(result.stdout);
    if (marker == null) {
      throw VisualException('Chromium calibration probe did not run');
    }
    final data =
        jsonDecode(htmlUnescape(marker.group(1)!)) as Map<String, dynamic>;
    final inner = (data['h'] as num).toInt();
    final innerWidth = (data['w'] as num).toInt();
    final delta = height - inner;
    if (innerWidth != width || delta < 0 || delta > 200) {
      throw VisualException(
        'unexpected Chromium calibration: window ${width}x$height, '
        'inner ${innerWidth}x$inner. Chromium enforces a minimum window size '
        '(500 px wide on Linux); use a larger --width.',
      );
    }
    return delta;
  } finally {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {
      // Best effort.
    }
  }
}

const List<String> _baseFlags = [
  '--headless=new',
  '--disable-gpu',
  '--hide-scrollbars',
  '--force-device-scale-factor=1',
  '--no-first-run',
  '--no-default-browser-check',
  '--disable-background-networking',
  '--disable-sync',
  '--disable-extensions',
  '--disable-dev-shm-usage',
  '--disable-lcd-text',
  '--host-resolver-rules=MAP * ~NOTFOUND',
];

/// Renders [pageDirectory] in headless Chromium, captures the probe JSON and
/// the screenshot in [artifacts].
Future<ChromeOutcome> renderWithChrome({
  required String executable,
  required String pageDirectory,
  required String artifacts,
  required int width,
  required int height,
  required int frameDelta,
  String scheme = 'light',
  String setupJs = '',
  Duration timeout = const Duration(minutes: 2),
}) async {
  final started = DateTime.now();
  final dir = Directory(artifacts)..createSync(recursive: true);
  final probeJson = File('${dir.path}/chrome.json');
  final screenshot = File('${dir.path}/chrome.png');

  final index = File('$pageDirectory/index.html');
  if (!index.readAsStringSync().contains('__visual_probe.js')) {
    injectBody(
      index,
      '<script src="__visual_probe.js"></script><script src="__visual_run.js"></script>',
    );
  }
  File('$pageDirectory/__visual_probe.js').writeAsStringSync(probeSource);
  File(
    '$pageDirectory/__visual_run.js',
  ).writeAsStringSync(chromeHarness(setupJs: setupJs));

  final profile = Directory('${dir.path}/.chrome-profile');
  List<String> flags(int windowHeight) => [
    ..._baseFlags,
    '--user-data-dir=${profile.path}',
    '--window-size=$width,$windowHeight',
    if (scheme == 'dark') '--blink-settings=preferredColorScheme=0',
  ];

  Future<ProbeSnapshot> measure(int windowHeight) async {
    final dom = await runProcess(executable, [
      ...flags(windowHeight),
      '--virtual-time-budget=2000',
      '--dump-dom',
      Uri.file(index.path).toString(),
    ], timeout: timeout);
    if (dom.timedOut) {
      throw VisualException(
        'Chromium measurement timed out after ${timeout.inSeconds}s',
      );
    }
    if (dom.exitCode != 0) {
      throw VisualException(
        'Chromium measurement failed (${dom.exitCode}): ${_tail(dom.stderr)}',
      );
    }
    final marker = RegExp(
      r'<pre[^>]*id="__visual"[^>]*>([\s\S]*?)</pre>',
    ).firstMatch(dom.stdout);
    if (marker == null) {
      throw VisualException(
        'Chromium probe did not run; stderr: ${_tail(dom.stderr)}',
      );
    }
    try {
      return ProbeSnapshot.fromJson(
        jsonDecode(htmlUnescape(marker.group(1)!)) as Map<String, dynamic>,
      );
    } catch (error) {
      throw VisualException('invalid Chromium probe JSON: $error');
    }
  }

  try {
    var probe = await measure(height + frameDelta);
    if ((probe.viewportHeight - height).abs() > 1) {
      // Calibration drifted (different Chrome build or platform): correct it
      // once from the observed viewport instead of failing the page.
      final corrected = height + frameDelta + (height - probe.viewportHeight);
      probe = await measure(corrected);
      if ((probe.viewportHeight - height).abs() > 1) {
        throw VisualException(
          'Chromium layout viewport ${probe.viewportWidth}x${probe.viewportHeight} '
          'does not match the requested ${width}x$height',
        );
      }
    }

    probeJson.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'title': probe.title,
        'externalResources': probe.externalResources,
        'viewport': {
          'width': probe.viewportWidth,
          'height': probe.viewportHeight,
          'dpr': probe.dpr,
        },
        'document': {
          'width': probe.documentWidth,
          'height': probe.documentHeight,
        },
        'elements': [
          for (final e in probe.elements)
            {
              'path': e.path,
              'tag': e.tag,
              'rect': e.rect.toJson(),
              'styles': e.styles,
              if (e.text != null) 'text': e.text,
            },
        ],
      }),
    );

    final shot = await runProcess(executable, [
      ...flags(height),
      '--virtual-time-budget=2000',
      '--screenshot=${screenshot.path}',
      Uri.file(index.path).toString(),
    ], timeout: timeout);
    if (shot.timedOut) {
      throw VisualException(
        'Chromium screenshot timed out after ${timeout.inSeconds}s',
      );
    }
    if (!screenshot.existsSync()) {
      throw VisualException(
        'Chromium produced no screenshot (${shot.exitCode}): ${_tail(shot.stderr)}',
      );
    }
    final raw = decodePng(screenshot.readAsBytesSync());
    if (raw.width < probe.viewportWidth || raw.height < probe.viewportHeight) {
      throw VisualException(
        'Chromium screenshot is ${raw.width}x${raw.height}, probe viewport is '
        '${probe.viewportWidth}x${probe.viewportHeight}',
      );
    }
    return ChromeOutcome(
      probe: probe,
      screenshot: raw.crop(probe.viewportWidth, probe.viewportHeight),
      rawScreenshot: raw,
      duration: DateTime.now().difference(started),
      stderr: _tail(shot.stderr),
      screenshotPath: screenshot.path,
      probeJsonPath: probeJson.path,
      frameDelta: frameDelta,
    );
  } finally {
    if (profile.existsSync()) {
      try {
        profile.deleteSync(recursive: true);
      } catch (_) {
        // Chromium may still hold a lock briefly; the temp dir is disposable.
      }
    }
  }
}

String _tail(String value, {int lines = 4}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split('\n');
  return parts.length <= lines
      ? trimmed
      : parts.sublist(parts.length - lines).join('\n');
}
