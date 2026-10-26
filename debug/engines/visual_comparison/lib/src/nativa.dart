import 'dart:convert';
import 'dart:io';

import 'chrome.dart';
import 'model.dart';
import 'png.dart';
import 'proc.dart';
import 'probe.dart';

class NativaOutcome {
  const NativaOutcome({
    required this.probe,
    required this.screenshot,
    required this.duration,
    required this.stdout,
    required this.stderr,
    required this.scriptErrors,
    required this.screenshotPath,
    required this.probeJsonPath,
    this.engine = 'unknown',
  });

  /// JavaScript engine the page ran on (`v8`, `quickjs`).
  final String engine;

  final ProbeSnapshot probe;
  final RasterImage screenshot;
  final Duration duration;
  final String stdout;
  final String stderr;
  final List<String> scriptErrors;
  final String screenshotPath;
  final String probeJsonPath;
}

/// Renders the staged page offscreen through the existing `flutter test`
/// screenshot harness. No window or display server is opened.
Future<NativaOutcome> renderWithNativa({
  required String repoRoot,
  required String pageDirectory,
  required String artifacts,
  required int width,
  required int height,
  String scheme = 'light',
  String setupJs = '',
  int waitMs = 900,
  Duration timeout = const Duration(seconds: 100),
}) async {
  final started = DateTime.now();
  final dir = Directory(artifacts)..createSync(recursive: true);
  final screenshot = File('${dir.path}/nativax.png');
  final probeJson = File('${dir.path}/nativax.json');
  final harnessDirectory = '$repoRoot/debug/harness';
  if (!Directory(harnessDirectory).existsSync()) {
    throw VisualException('harness not found: $harnessDirectory');
  }

  // Pages run on V8 by default on desktop: point the harness at the cdylib
  // built in tools/v8-spike unless the caller chose one.
  final v8 = '$repoRoot/tools/v8-spike/target/release/libnx_v8.so';
  final v8Env = Platform.environment['NATIVAX_V8_LIB'] == null &&
          File(v8).existsSync()
      ? {'NATIVAX_V8_LIB': v8}
      : const <String, String>{};

  Future<ProcResult> attempt() => runProcess(
    'flutter',
    ['test', 'test/screenshot_test.dart', '--reporter=compact', '--no-pub'],
    workingDirectory: harnessDirectory,
    timeout: timeout,
    environment: {
      'NATIVAX_SHOT': screenshot.path,
      'NATIVAX_SHOT_DIR': pageDirectory,
      'NATIVAX_SHOT_WIDTH': width.toString(),
      'NATIVAX_SHOT_HEIGHT': height.toString(),
      'NATIVAX_SHOT_SCHEME': scheme,
      'NATIVAX_SHOT_WAIT': waitMs.toString(),
      'NATIVAX_SHOT_JS': '$probeSource\n${setupJs.trim()}',
      'NATIVAX_SHOT_DUMP': '__visualProbe()',
      ...v8Env,
    },
  );

  // A page can occasionally deadlock inside `flutter test` (a stuck
  // `flutter_tester` after a large `toImage()`); one clean retry is cheaper
  // than dropping the page. The process group is killed on timeout.
  ProcResult? result;
  for (var attemptIndex = 0; attemptIndex < 2; attemptIndex++) {
    result = await attempt();
    final hasDump = RegExp(r'^DUMP: ', multiLine: true).hasMatch(result.stdout);
    if (hasDump && screenshot.existsSync()) break;
    if (screenshot.existsSync()) screenshot.deleteSync();
    if (attemptIndex == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  final finished = result!;
  if (finished.timedOut) {
    throw VisualException(
      'NativaX render timed out after ${timeout.inSeconds}s '
      '(two attempts, process group killed)',
    );
  }

  final dump = RegExp(
    r'^DUMP: (.+)$',
    multiLine: true,
  ).allMatches(finished.stdout).toList();
  final errors = RegExp(r'^SCRIPT ERROR: (.+)$', multiLine: true)
      .allMatches(finished.stdout)
      .map((m) => m.group(1)!.trim())
      .toList(growable: false);
  if (dump.isEmpty) {
    throw VisualException(
      'NativaX produced no probe dump (exit ${finished.exitCode}); '
      'stdout: ${_tail(finished.stdout)} stderr: ${_tail(finished.stderr)}',
    );
  }
  final engine = RegExp(r'^ENGINE: (\w+)', multiLine: true)
          .firstMatch(finished.stdout)
          ?.group(1) ??
      'unknown';
  final ProbeSnapshot probe;
  try {
    probe = ProbeSnapshot.fromJson(
      jsonDecode(dump.last.group(1)!) as Map<String, dynamic>,
    );
  } catch (error) {
    throw VisualException('invalid NativaX probe JSON: $error');
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

  if (!screenshot.existsSync()) {
    throw VisualException('NativaX test ran but wrote no screenshot');
  }
  final raw = decodePng(screenshot.readAsBytesSync());
  if (raw.width < probe.viewportWidth || raw.height < probe.viewportHeight) {
    throw VisualException(
      'NativaX screenshot is ${raw.width}x${raw.height}, probe viewport is '
      '${probe.viewportWidth}x${probe.viewportHeight}',
    );
  }
  return NativaOutcome(
    probe: probe,
    screenshot: raw.crop(probe.viewportWidth, probe.viewportHeight),
    duration: DateTime.now().difference(started),
    stdout: finished.stdout,
    stderr: finished.stderr,
    scriptErrors: errors,
    screenshotPath: screenshot.path,
    probeJsonPath: probeJson.path,
    engine: engine,
  );
}

String _tail(String value, {int lines = 6}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split('\n');
  return parts.length <= lines
      ? trimmed
      : parts.sublist(parts.length - lines).join('\n');
}
