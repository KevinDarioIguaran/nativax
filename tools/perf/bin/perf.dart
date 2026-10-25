import 'dart:convert';
import 'dart:io';

import 'package:nativa_perf/perf.dart';

const _usage = '''
NativaX performance suite — Chromium reference vs NativaX offscreen.

Usage:
  dart run tools/perf/bin/perf.dart list [--no-externals] [--json]
  dart run tools/perf/bin/perf.dart fetch [--source <id>]
  dart run tools/perf/bin/perf.dart run [options]
  dart run tools/perf/bin/perf.dart compare <baseline.json> <current.json>
  dart run tools/perf/bin/perf.dart idle-app [--build] [--seconds 5]

Run options:
  --out <dir>        output directory (default .perf/latest)
  --width/--height   layout viewport (default 800x900)
  --only <regex>     run scenarios whose id matches
  --no-externals     only built-in scenarios
  --app-idle         also launch the Linux app on a blank page and measure idle
  --chrome <exe>     Chromium binary
  --json             print the run JSON to stdout

Outputs: results.json, results.csv, report.md, timeline.csv, charts/*.svg,
and pages/<scenario>/{chromium,nativax}.json.
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  final repoRoot = _findRepoRoot();
  final command = args.first;
  final rest = args.sublist(1);
  switch (command) {
    case 'list':
      final withExternal = !rest.contains('--no-externals');
      final asJson = rest.contains('--json');
      final suites = [
        if (withExternal)
          for (final suite in externalSuites)
            if (suite.id != 'millionrows') suite,
      ];
      final scenarios = allScenarios(suites);
      if (asJson) {
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert([
            for (final scenario in scenarios)
              {
                'id': scenario.id,
                'title': scenario.title,
                'kind': scenario.kind.name,
                'source': scenario.source,
                'description': scenario.description,
                'external': scenario.isExternal,
              },
          ]),
        );
        return;
      }
      for (final scenario in scenarios) {
        stdout.writeln(
          '${scenario.id.padRight(38)} ${scenario.kind.name.padRight(9)} ${scenario.title}',
        );
      }
      return;
    case 'fetch':
      final sourceIndex = rest.indexOf('--source');
      final only = sourceIndex >= 0 && sourceIndex + 1 < rest.length
          ? [rest[sourceIndex + 1]]
          : null;
      final lines = await fetchExternalSuites(repoRoot, only: only);
      for (final line in lines) {
        stdout.writeln(line);
      }
      return;
    case 'run':
      await _run(repoRoot, rest);
      return;
    case 'idle-app':
      await _idleApp(repoRoot, rest);
      return;
    case 'compare':
      if (rest.length != 2) {
        stderr.writeln(
          'usage: perf.dart compare <baseline.json> <current.json>',
        );
        exit(64);
      }
      _compare(rest[0], rest[1]);
      return;
    default:
      stderr.writeln('unknown command: $command');
      stderr.writeln(_usage);
      exit(64);
  }
}

Future<void> _idleApp(String repoRoot, List<String> rest) async {
  var seconds = 5;
  var build = false;
  var out = '.perf/app-idle.json';
  for (var i = 0; i < rest.length; i++) {
    switch (rest[i]) {
      case '--seconds':
        seconds = int.parse(rest[++i]);
      case '--build':
        build = true;
      case '--out':
        out = rest[++i];
      default:
        stderr.writeln('unknown option: ${rest[i]}');
        exit(64);
    }
  }
  final result = await measureAppIdle(
    repoRoot: repoRoot,
    idleSeconds: seconds,
    build: build,
    log: stdout.writeln,
  );
  File(out).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(result.toJson()),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  stdout.writeln('written: ${File(out).absolute.path}');
  if (result.status != 'ok') exit(1);
}

Future<void> _run(String repoRoot, List<String> rest) async {
  var out = '.perf/latest';
  var width = 800;
  var height = 900;
  String? only;
  var includeExternal = true;
  var chrome = Platform.environment['CHROME'] ?? 'google-chrome';
  var json = false;
  var appIdle = false;
  var cpuRate = 1.0;
  for (var i = 0; i < rest.length; i++) {
    final arg = rest[i];
    switch (arg) {
      case '--out':
        out = rest[++i];
      case '--width':
        width = int.parse(rest[++i]);
      case '--height':
        height = int.parse(rest[++i]);
      case '--only':
        only = rest[++i];
      case '--no-externals':
        includeExternal = false;
      case '--chrome':
        chrome = rest[++i];
      case '--json':
        json = true;
      case '--app-idle':
        appIdle = true;
      case '--cpu-rate':
        cpuRate = double.parse(rest[++i]);
      default:
        stderr.writeln('unknown option: $arg');
        exit(64);
    }
  }
  final outDir = Directory(out).absolute.path;
  final run = await runPerf(
    PerfOptions(
      repoRoot: repoRoot,
      outDir: outDir,
      width: width,
      height: height,
      only: only,
      includeExternal: includeExternal,
      appIdle: appIdle,
      chromeExecutable: chrome,
      cpuRate: cpuRate,
    ),
    log: stdout.writeln,
  );
  stdout.writeln('');
  stdout.writeln(
    'Summary: ${run.count(Verdict.pass)} PASS, '
    '${run.count(Verdict.warn)} WARN, ${run.count(Verdict.fail)} FAIL, '
    '${run.count(Verdict.invalid)} INVALID (${run.results.length} scenarios)',
  );
  stdout.writeln('Report:  $outDir/report.md');
  stdout.writeln('JSON:    $outDir/results.json');
  stdout.writeln('Charts:  $outDir/charts/');
  if (json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(run.toJson()));
  }
  if (run.count(Verdict.fail) + run.count(Verdict.invalid) > 0) exit(1);
}

void _compare(String baselinePath, String currentPath) {
  final baseline =
      jsonDecode(File(baselinePath).readAsStringSync()) as Map<String, dynamic>;
  final current =
      jsonDecode(File(currentPath).readAsStringSync()) as Map<String, dynamic>;
  Map<String, double> work(Map<String, dynamic> run) {
    final out = <String, double>{};
    for (final result in (run['results'] as List? ?? const [])) {
      final map = result as Map<String, dynamic>;
      final nativa = map['nativax'] as Map<String, dynamic>? ?? const {};
      out[map['scenario'] as String] =
          ((nativa['scenario_ms'] as num? ?? 0) +
                  (nativa['render_ms'] as num? ?? 0))
              .toDouble();
    }
    return out;
  }

  final base = work(baseline);
  final next = work(current);
  stdout.writeln('scenario,baseline_ms,current_ms,delta_pct,status');
  for (final entry in next.entries) {
    final previous = base[entry.key];
    if (previous == null) continue;
    final delta = previous <= 0
        ? 0.0
        : (entry.value - previous) / previous * 100;
    final status = delta > 10
        ? 'regression'
        : delta < -10
        ? 'improvement'
        : 'noise';
    stdout.writeln(
      '${entry.key},${previous.toStringAsFixed(2)},'
      '${entry.value.toStringAsFixed(2)},${delta.toStringAsFixed(2)},$status',
    );
  }
}

String _findRepoRoot() {
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: nativa_workspace')) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return Directory.current.absolute.path;
}
