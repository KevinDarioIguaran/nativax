import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/conformance.dart';

Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  final suite = test262Dir(root);

  var dirs = <String>[
    'test/language/expressions',
    'test/language/statements',
    'test/language/types',
    'test/language/literals',
  ];
  int? limit;
  var timeout = const Duration(seconds: 2);
  var verbose = false;
  var skipFeatures = <String>{};
  String? markdownPath;
  String? baselinePath;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--suite':
        // Checkout override is intentionally unsupported here; use the
        // standard debug/artifacts/conformance/suites location so reports stay
        // comparable.
        stderr.writeln('--suite is not supported; suites live in '
            'debug/artifacts/conformance/suites (see fetch_suites.dart)');
        exitCode = 64;
        return;
      case '--dirs':
        dirs = args[++i].split(',').map((s) => s.trim()).toList();
      case '--limit':
        limit = int.parse(args[++i]);
      case '--timeout-ms':
        timeout = Duration(milliseconds: int.parse(args[++i]));
      case '--skip-features':
        skipFeatures = args[++i].split(',').map((s) => s.trim()).toSet();
      case '--markdown':
        markdownPath = args[++i];
      case '--baseline':
        baselinePath = args[++i];
      case '--verbose':
        verbose = true;
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/run_test262.dart '
            '[--dirs a,b] [--limit n] [--timeout-ms n] '
            '[--skip-features f1,f2] [--markdown path] [--baseline summary.json] '
            '[--verbose]');
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  if (!Directory(suite).existsSync()) {
    stderr.writeln('Test262 not found at $suite.\n'
        'Run: dart run bin/fetch_suites.dart --suite test262');
    exitCode = 2;
    return;
  }

  final runner = Test262Runner(Test262RunOptions(
    suitePath: suite,
    directories: dirs,
    limit: limit,
    skipFeatures: skipFeatures,
    timeout: timeout,
    verbose: verbose,
  ));
  final summary = await runner.run();

  final baseline = _loadBaseline(root, baselinePath);
  final stamp = timestampForFile(summary.startedAt);
  final outputDir = resultsDir(root);
  final dated = markdownPath ??
      p.join(resultsDir(root), 'test262-$stamp.md');
  final files = const ConformanceReport().write(
    summary,
    outputDir: outputDir,
    markdownPath: dated,
    baseline: baseline,
  );
  // Keep a stable "latest" pointer for dashboards and humans.
  File(files.markdown).copySync(
      p.join(reportsDir(root), 'test262-latest.md'));

  stdout
    ..writeln()
    ..writeln('PASS ${summary.passed}  FAIL ${summary.failed}  '
        'SKIP ${summary.skipped}  ERROR ${summary.errors}')
    ..writeln('rate  ${summary.passRate.toStringAsFixed(2)} % '
        '(${summary.total} tests, ${(summary.durationMs / 1000).toStringAsFixed(1)} s)')
    ..writeln('jsonl ${files.jsonl}')
    ..writeln('md    ${files.markdown}');
}

RunSummary? _loadBaseline(String root, String? explicit) {
  if (explicit != null) {
    final f = File(explicit);
    if (!f.existsSync()) return null;
    return RunSummary.load(f);
  }
  final dir = Directory(resultsDir(root));
  if (!dir.existsSync()) return null;
  final candidates = dir
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('test262-') &&
          f.path.endsWith('.summary.json'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  if (candidates.isEmpty) return null;
  return RunSummary.load(candidates.first);
}
