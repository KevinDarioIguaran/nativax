import 'dart:convert';
import 'dart:io';

import 'app_idle.dart';
import 'chrome_engine.dart';
import 'evaluate.dart';
import 'externals.dart';
import 'model.dart';
import 'nativa_engine.dart';
import 'report.dart';
import 'scenarios.dart';

class PerfOptions {
  const PerfOptions({
    required this.repoRoot,
    required this.outDir,
    this.width = 800,
    this.height = 900,
    this.only,
    this.includeExternal = true,
    this.appIdle = false,
    this.chromeExecutable = 'google-chrome',
    this.cpuRate = 1,
    this.cpuCores,
    this.cpuQuotaPct,
    this.memoryLimitMb,
    this.matrix = false,
  });

  final String repoRoot;
  final String outDir;
  final int width;
  final int height;
  final String? only;
  final bool includeExternal;
  final bool appIdle;
  final String chromeExecutable;
  final double cpuRate;
  final int? cpuCores;
  final int? cpuQuotaPct;
  final int? memoryLimitMb;
  final bool matrix;
}

Future<PerfRun> runPerf(
  PerfOptions options, {
  void Function(String message)? log,
}) async {
  final started = DateTime.now();
  Directory(options.outDir).createSync(recursive: true);

  final resolvedSuites = <ExternalSuite>[
    if (options.includeExternal)
      for (final suite in externalSuites)
        if (resolveExternalPage(options.repoRoot, suite) != null) suite,
  ];
  var scenarios = allScenarios(resolvedSuites);
  if (options.only != null) {
    final pattern = RegExp(options.only!);
    scenarios = scenarios.where((s) => pattern.hasMatch(s.id)).toList();
  }
  if (scenarios.isEmpty) {
    throw StateError('no scenarios selected');
  }

  final chromeVersion = await _chromeVersion(options.chromeExecutable);
  final results = <ScenarioResult>[];
  ScenarioResult? idle;
  PerfRun liveRun() => PerfRun(
    startedAt: started,
    duration: DateTime.now().difference(started),
    command: 'dart run tools/perf/bin/perf.dart run --out ${options.outDir}',
    chromeVersion: chromeVersion,
    viewportWidth: options.width,
    viewportHeight: options.height,
    outDir: options.outDir,
    targets: const PerfTargets(),
    results: List<ScenarioResult>.of(results),
    idle: idle,
    notes: [
      'live snapshot',
      'External suites resolved: ${resolvedSuites.map((s) => s.id).join(', ')}',
    ],
  );

  for (var index = 0; index < scenarios.length; index++) {
    final scenario = scenarios[index];
    final prefix =
        '[${(index + 1).toString().padLeft(scenarios.length.toString().length)}/${scenarios.length}] ${scenario.id}';
    final artifacts = '${options.outDir}/pages/${scenario.id}';
    Directory(artifacts).createSync(recursive: true);
    log?.call('$prefix ...');

    String? sourceDir;
    if (scenario.pageBuilder != null) {
      final source = Directory('$artifacts/source')
        ..createSync(recursive: true);
      File(
        '${source.path}/index.html',
      ).writeAsStringSync(scenario.pageBuilder!());
      sourceDir = source.path;
    } else if (scenario.externalId != null) {
      final suite = externalSuiteById(scenario.externalId!);
      sourceDir = suite == null
          ? null
          : resolveExternalPage(options.repoRoot, suite);
    }
    if (sourceDir == null) {
      final missing = EngineRun(
        engine: EngineKind.nativa,
        status: RunStatus.skipped,
        error: 'external page not fetched',
      );
      results.add(
        ScenarioResult(
          scenarioId: scenario.id,
          title: scenario.title,
          kind: scenario.kind.name,
          source: scenario.source,
          chromium: missing,
          nativa: missing,
          verdict: Verdict.invalid,
          reasons: ['external page not available; run the fetch command'],
        ),
      );
      writeLivePerfResults(liveRun(), options.outDir);
      log?.call('$prefix SKIP (external page not fetched)');
      continue;
    }

    final pageDir = stageScenarioPage(sourceDir, Directory('$artifacts/page'));
    final chromium = await runChromeScenario(
      scenario: scenario,
      pageDirectory: pageDir.path,
      artifacts: artifacts,
      width: options.width,
      height: options.height,
      executable: options.chromeExecutable,
      cpuRate: options.cpuRate,
      cpuCores: options.cpuCores,
      cpuQuotaPct: options.cpuQuotaPct,
      memoryLimitMb: options.memoryLimitMb,
    );
    EngineRun nativa;
    try {
      nativa = await runNativaScenario(
        scenario: scenario,
        repoRoot: options.repoRoot,
        pageDirectory: pageDir.path,
        artifacts: artifacts,
        width: options.width,
        height: options.height,
      );
    } catch (error) {
      nativa = EngineRun(
        engine: EngineKind.nativa,
        status: RunStatus.failed,
        error: '$error',
      );
    }
    File('$artifacts/chromium.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(chromium.toJson()),
    );
    File('$artifacts/nativax.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(nativa.toJson()),
    );
    final result = evaluateScenario(
      scenario,
      chromium,
      nativa,
      const PerfTargets(),
    );
    results.add(result);
    if (scenario.kind == ScenarioKind.idle) idle = result;
    writeLivePerfResults(liveRun(), options.outDir);
    log?.call(
      '$prefix ${result.verdict.label}  '
      'chrome ${(chromium.scenarioMs + chromium.renderMs).toStringAsFixed(1)} ms  '
      'nativa ${(nativa.scenarioMs + nativa.renderMs).toStringAsFixed(1)} ms  '
      'nodes ${nativa.nodes}/${chromium.nodes}  '
      'rss ${nativa.rssPeakMb.toStringAsFixed(0)} MB',
    );
  }

  if (options.appIdle) {
    final idleApp = await measureAppIdle(
      repoRoot: options.repoRoot,
      build: false,
      log: log,
    );
    File('${options.outDir}/app-idle.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(idleApp.toJson()),
    );
  }

  final run = PerfRun(
    startedAt: started,
    duration: DateTime.now().difference(started),
    command: 'dart run tools/perf/bin/perf.dart run --out ${options.outDir}',
    chromeVersion: chromeVersion,
    viewportWidth: options.width,
    viewportHeight: options.height,
    outDir: options.outDir,
    targets: const PerfTargets(),
    results: results,
    idle: idle,
    notes: [
      'External suites resolved: ${resolvedSuites.map((s) => s.id).join(', ')}',
      'Network is blocked in both engines.',
      'NativaX runs offscreen through flutter test; frame times are pump costs.',
    ],
  );
  writePerfReports(run, options.outDir);
  return run;
}

Future<String> _chromeVersion(String executable) async {
  try {
    final result = await Process.run(executable, ['--version']);
    final text = '${result.stdout}${result.stderr}'.trim().split('\n').first;
    return text.isEmpty ? executable : text;
  } catch (_) {
    return executable;
  }
}
