import 'dart:convert';
import 'dart:io';

import 'chrome.dart';
import 'model.dart';
import 'nativa.dart';
import 'png.dart';
import 'report.dart';
import 'score.dart';
import 'staging.dart';

class JudgeOptions {
  const JudgeOptions({
    required this.repoRoot,
    required this.outputDir,
    this.width = 800,
    this.height = 900,
    this.scheme = 'light',
    this.setupJs = '',
    this.pixelCsv = false,
    this.pixelCsvAll = false,
    this.keepStaging = false,
    this.chromeExecutable = 'google-chrome',
    this.chromeTimeout = const Duration(minutes: 2),
    required this.frameDelta,
    this.nativaTimeout = const Duration(seconds: 100),
  });

  final String repoRoot;
  final String outputDir;
  final int width;
  final int height;
  final String scheme;
  final String setupJs;
  final bool pixelCsv;
  final bool pixelCsvAll;
  final bool keepStaging;
  final String chromeExecutable;

  /// Measured `window - innerHeight` offset of headless Chromium. See
  /// [calibrateChromeFrame].
  final int frameDelta;
  final Duration chromeTimeout;
  final Duration nativaTimeout;
}

class PageJudgeResult {
  const PageJudgeResult(this.report, this.duration);
  final PageReport report;
  final Duration duration;
}

String pageArtifactsDirectory(String outputDir, String pageId) =>
    '$outputDir/pages/$pageId';

/// Runs the reference and the runtime for one page and returns a complete
/// report with screenshot, probes, per-pixel metrics and CSV tables.
Future<PageJudgeResult> judgePage(
  PageSource source,
  JudgeOptions options,
) async {
  final started = DateTime.now();
  final artifacts = pageArtifactsDirectory(options.outputDir, source.id);
  Directory(artifacts).createSync(recursive: true);
  final checks = <EnvCheck>[];
  final notes = <String>[];
  final staging = Directory.systemTemp.createTempSync('nativa-visual-');

  try {
    final refDir = stagePage(
      source.directory,
      Directory('${staging.path}/ref'),
      entry: source.entry,
    );
    final nativaDir = stagePage(
      source.directory,
      Directory('${staging.path}/nativa'),
      entry: source.entry,
    );

    late final ChromeOutcome chrome;
    try {
      chrome = await renderWithChrome(
        executable: options.chromeExecutable,
        pageDirectory: refDir.path,
        artifacts: artifacts,
        width: options.width,
        height: options.height,
        frameDelta: options.frameDelta,
        scheme: options.scheme,
        setupJs: options.setupJs,
        timeout: options.chromeTimeout,
      );
      checks.add(
        EnvCheck(
          name: 'chromium',
          ok: true,
          hard: true,
          detail:
              '${options.chromeExecutable}; screenshot ${chrome.rawScreenshot.width}x'
              '${chrome.rawScreenshot.height}, viewport '
              '${chrome.probe.viewportWidth}x${chrome.probe.viewportHeight}',
        ),
      );
    } catch (error) {
      checks.add(
        EnvCheck(name: 'chromium', ok: false, hard: true, detail: '$error'),
      );
      final report = PageReport(
        page: source,
        viewportWidth: options.width,
        viewportHeight: options.height,
        scheme: options.scheme,
        artifactsDir: artifacts,
        checks: checks,
        failure: 'Chromium reference failed: $error',
      );
      report.writeArtifacts();
      return PageJudgeResult(report, DateTime.now().difference(started));
    }

    // NativaX must use exactly the reference viewport, not the requested
    // window size: headless Chromium reports a smaller innerHeight.
    final viewportWidth = chrome.probe.viewportWidth;
    final viewportHeight = chrome.probe.viewportHeight;

    late final NativaOutcome nativa;
    try {
      nativa = await renderWithNativa(
        repoRoot: options.repoRoot,
        pageDirectory: nativaDir.path,
        artifacts: artifacts,
        width: viewportWidth,
        height: viewportHeight,
        scheme: options.scheme,
        setupJs: options.setupJs,
        timeout: options.nativaTimeout,
      );
      checks.add(
        EnvCheck(
          name: 'nativa',
          ok: true,
          hard: true,
          detail:
              'flutter test screenshot ${nativa.screenshot.width}x'
              '${nativa.screenshot.height}',
        ),
      );
    } catch (error) {
      checks.add(
        EnvCheck(name: 'nativa', ok: false, hard: true, detail: '$error'),
      );
      final report = PageReport(
        page: source,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        scheme: options.scheme,
        artifactsDir: artifacts,
        checks: checks,
        chromeProbe: chrome.probe,
        chromeDuration: chrome.duration,
        failure: 'NativaX render failed: $error',
      );
      report.writeArtifacts(chromeImage: chrome.screenshot);
      return PageJudgeResult(report, DateTime.now().difference(started));
    }

    checks.add(
      EnvCheck(
        name: 'js-engine',
        ok: true,
        detail: 'NativaX ran on ${nativa.engine}',
      ),
    );
    checks.add(
      EnvCheck(
        name: 'viewport',
        ok:
            chrome.probe.viewportWidth == nativa.probe.viewportWidth &&
            chrome.probe.viewportHeight == nativa.probe.viewportHeight,
        hard: true,
        detail:
            'chromium ${chrome.probe.viewportWidth}x${chrome.probe.viewportHeight}, '
            'nativax ${nativa.probe.viewportWidth}x${nativa.probe.viewportHeight}',
      ),
    );
    checks.add(
      EnvCheck(
        name: 'device-pixel-ratio',
        ok: (chrome.probe.dpr - nativa.probe.dpr).abs() < 0.01,
        hard: true,
        detail: 'chromium ${chrome.probe.dpr}, nativax ${nativa.probe.dpr}',
      ),
    );
    checks.add(
      EnvCheck(
        name: 'elements',
        ok:
            chrome.probe.elements.isNotEmpty &&
            nativa.probe.elements.isNotEmpty,
        hard: true,
        detail:
            '${chrome.probe.elements.length} in Chromium, '
            '${nativa.probe.elements.length} in NativaX',
      ),
    );
    checks.add(
      EnvCheck(
        name: 'screenshot-size',
        ok:
            chrome.screenshot.width == nativa.screenshot.width &&
            chrome.screenshot.height == nativa.screenshot.height,
        hard: true,
        detail:
            'chromium ${chrome.screenshot.width}x${chrome.screenshot.height}, '
            'nativax ${nativa.screenshot.width}x${nativa.screenshot.height}',
      ),
    );
    checks.add(
      EnvCheck(
        name: 'javascript-errors',
        ok: nativa.scriptErrors.isEmpty,
        detail: nativa.scriptErrors.isEmpty
            ? 'none'
            : '${nativa.scriptErrors.length}: ${nativa.scriptErrors.take(3).join(' | ')}',
      ),
    );

    final captureHeight = chrome.screenshot.height;
    final documentHeight = chrome.probe.documentHeight;
    final coverage = documentHeight <= 0
        ? 1.0
        : (captureHeight / documentHeight).clamp(0.0, 1.0).toDouble();
    checks.add(
      EnvCheck(
        name: 'document-coverage',
        ok: coverage >= 0.999,
        detail:
            '${captureHeight}px captured of ${documentHeight}px document '
            '(${(coverage * 100).toStringAsFixed(1)} %)',
      ),
    );
    if (coverage < 0.999) {
      notes.add(
        'Only the top ${captureHeight}px of a ${documentHeight}px document '
        'were compared; raise --height to cover more.',
      );
    }

    checks.add(
      EnvCheck(
        name: 'external-resources',
        ok: true,
        detail: chrome.probe.externalResources == 0
            ? 'none'
            : '${chrome.probe.externalResources} external URL(s); network is '
                  'blocked for both engines, so the comparison covers local files only',
      ),
    );
    if (chrome.probe.externalResources > 0) {
      notes.add(
        '${chrome.probe.externalResources} external resource(s) were blocked '
        'in both engines (fonts, CDN, remote images).',
      );
    }
    checks.add(
      const EnvCheck(
        name: 'animations',
        ok: true,
        detail: 'animations and transitions frozen in both engines',
      ),
    );

    final evaluation = evaluate(
      chromeProbe: chrome.probe,
      chromeImage: chrome.screenshot,
      nativaProbe: nativa.probe,
      nativaImage: nativa.screenshot,
      checks: checks,
    );

    if (options.keepStaging) {
      final kept = Directory('$artifacts/staging');
      if (kept.existsSync()) kept.deleteSync(recursive: true);
      _copyTrees(staging, kept);
      notes.add('Staging copies kept in ${kept.path}');
    }

    final report = PageReport(
      page: source,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      scheme: options.scheme,
      artifactsDir: artifacts,
      checks: checks,
      chromeProbe: chrome.probe,
      nativaProbe: nativa.probe,
      evaluation: evaluation,
      chromeDuration: chrome.duration,
      nativaDuration: nativa.duration,
      notes: notes,
    );
    report.writeArtifacts(
      chromeImage: chrome.screenshot,
      nativaImage: nativa.screenshot,
      writePixelCsv: options.pixelCsv,
      writePixelCsvAll: options.pixelCsvAll,
    );
    return PageJudgeResult(report, DateTime.now().difference(started));
  } finally {
    if (!options.keepStaging && staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {
        // Best effort.
      }
    }
  }
}

void _copyTrees(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is Directory) {
      _copyTrees(entity, Directory('${target.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${target.path}/$name');
    }
  }
}

/// Judges the reference against a second reference render. Used by
/// `--self-check`: a correct judge must report 100 / PASS. Any deviation is a
/// bug in the judge, not in NativaX.
Future<PageJudgeResult> selfCheck(
  PageSource source,
  JudgeOptions options,
) async {
  final started = DateTime.now();
  final artifacts = pageArtifactsDirectory(options.outputDir, source.id);
  Directory(artifacts).createSync(recursive: true);
  final staging = Directory.systemTemp.createTempSync('nativa-visual-self-');
  final checks = <EnvCheck>[];
  try {
    final firstDir = stagePage(
      source.directory,
      Directory('${staging.path}/a'),
      entry: source.entry,
    );
    final secondDir = stagePage(
      source.directory,
      Directory('${staging.path}/b'),
      entry: source.entry,
    );
    final first = await renderWithChrome(
      executable: options.chromeExecutable,
      pageDirectory: firstDir.path,
      artifacts: '$artifacts/reference-a',
      width: options.width,
      height: options.height,
      frameDelta: options.frameDelta,
      scheme: options.scheme,
      setupJs: options.setupJs,
      timeout: options.chromeTimeout,
    );
    final second = await renderWithChrome(
      executable: options.chromeExecutable,
      pageDirectory: secondDir.path,
      artifacts: '$artifacts/reference-b',
      width: options.width,
      height: options.height,
      frameDelta: options.frameDelta,
      scheme: options.scheme,
      setupJs: options.setupJs,
      timeout: options.chromeTimeout,
    );
    File('${second.screenshotPath}').copySync('$artifacts/nativax.png');
    File('$artifacts/reference-a/chrome.png').copySync('$artifacts/chrome.png');
    checks.add(
      const EnvCheck(
        name: 'self-check',
        ok: true,
        hard: true,
        detail: 'reference compared against a second reference render',
      ),
    );
    final evaluation = evaluate(
      chromeProbe: first.probe,
      chromeImage: first.screenshot,
      nativaProbe: second.probe,
      nativaImage: second.screenshot,
      checks: checks,
    );
    final report = PageReport(
      page: source,
      viewportWidth: first.probe.viewportWidth,
      viewportHeight: first.probe.viewportHeight,
      scheme: options.scheme,
      artifactsDir: artifacts,
      checks: checks,
      chromeProbe: first.probe,
      nativaProbe: second.probe,
      evaluation: evaluation,
      chromeDuration: first.duration,
      nativaDuration: second.duration,
      notes: const ['Self-check: both sides are Chromium renders.'],
    );
    report.writeArtifacts(
      chromeImage: first.screenshot,
      nativaImage: second.screenshot,
    );
    return PageJudgeResult(report, DateTime.now().difference(started));
  } finally {
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

/// Rebuilds a report from artifacts written by a previous run. Used by
/// `--resume` so iterating on the report does not re-render every page.
Future<PageJudgeResult?> reusePage(
  PageSource source,
  JudgeOptions options,
) async {
  final dir = pageArtifactsDirectory(options.outputDir, source.id);
  final chromeJson = File('$dir/chrome.json');
  final nativaJson = File('$dir/nativax.json');
  final chromePng = File('$dir/chrome.png');
  final nativaPng = File('$dir/nativax.png');
  if (!chromeJson.existsSync() ||
      !nativaJson.existsSync() ||
      !chromePng.existsSync() ||
      !nativaPng.existsSync()) {
    return null;
  }
  try {
    final chromeProbe = ProbeSnapshot.fromJson(
      jsonDecode(chromeJson.readAsStringSync()) as Map<String, dynamic>,
    );
    final nativaProbe = ProbeSnapshot.fromJson(
      jsonDecode(nativaJson.readAsStringSync()) as Map<String, dynamic>,
    );
    final chromeImage = decodePng(
      chromePng.readAsBytesSync(),
    ).crop(chromeProbe.viewportWidth, chromeProbe.viewportHeight);
    final nativaImage = decodePng(
      nativaPng.readAsBytesSync(),
    ).crop(nativaProbe.viewportWidth, nativaProbe.viewportHeight);
    final checks = <EnvCheck>[
      const EnvCheck(
        name: 'reused-artifacts',
        ok: true,
        detail: 'chrome.json, nativax.json and both screenshots were reused',
      ),
      EnvCheck(
        name: 'viewport',
        ok:
            chromeProbe.viewportWidth == nativaProbe.viewportWidth &&
            chromeProbe.viewportHeight == nativaProbe.viewportHeight,
        hard: true,
        detail:
            'chromium ${chromeProbe.viewportWidth}x${chromeProbe.viewportHeight}, '
            'nativax ${nativaProbe.viewportWidth}x${nativaProbe.viewportHeight}',
      ),
      EnvCheck(
        name: 'elements',
        ok: chromeProbe.elements.isNotEmpty && nativaProbe.elements.isNotEmpty,
        hard: true,
        detail:
            '${chromeProbe.elements.length} in Chromium, '
            '${nativaProbe.elements.length} in NativaX',
      ),
      EnvCheck(
        name: 'device-pixel-ratio',
        ok: (chromeProbe.dpr - nativaProbe.dpr).abs() < 0.01,
        hard: true,
        detail: 'chromium ${chromeProbe.dpr}, nativax ${nativaProbe.dpr}',
      ),
      EnvCheck(
        name: 'screenshot-size',
        ok:
            chromeImage.width == nativaImage.width &&
            chromeImage.height == nativaImage.height,
        hard: true,
        detail:
            'chromium ${chromeImage.width}x${chromeImage.height}, '
            'nativax ${nativaImage.width}x${nativaImage.height}',
      ),
      EnvCheck(
        name: 'javascript-errors',
        ok: true,
        detail: 'not captured when reusing artifacts',
      ),
      EnvCheck(
        name: 'document-coverage',
        ok:
            chromeProbe.documentHeight <= 0 ||
            chromeImage.height >= chromeProbe.documentHeight,
        detail:
            '${chromeImage.height}px captured of '
            '${chromeProbe.documentHeight}px document',
      ),
      EnvCheck(
        name: 'external-resources',
        ok: true,
        detail: chromeProbe.externalResources == 0
            ? 'none'
            : '${chromeProbe.externalResources} external URL(s) were blocked',
      ),
      const EnvCheck(
        name: 'animations',
        ok: true,
        detail: 'animations and transitions were frozen in the cached run',
      ),
    ];
    final evaluation = evaluate(
      chromeProbe: chromeProbe,
      chromeImage: chromeImage,
      nativaProbe: nativaProbe,
      nativaImage: nativaImage,
      checks: checks,
    );
    final report = PageReport(
      page: source,
      viewportWidth: chromeProbe.viewportWidth,
      viewportHeight: chromeProbe.viewportHeight,
      scheme: options.scheme,
      artifactsDir: dir,
      checks: checks,
      chromeProbe: chromeProbe,
      nativaProbe: nativaProbe,
      evaluation: evaluation,
      notes: const [
        'Re-evaluated from cached probes and screenshots (--resume).',
      ],
    );
    report.writeArtifacts(
      chromeImage: chromeImage,
      nativaImage: nativaImage,
      writePixelCsv: options.pixelCsv,
      writePixelCsvAll: options.pixelCsvAll,
    );
    return PageJudgeResult(report, Duration.zero);
  } catch (_) {
    return null;
  }
}
