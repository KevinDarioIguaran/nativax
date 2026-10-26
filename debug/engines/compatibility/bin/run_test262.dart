import 'dart:io';

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
  String? resultsDirectory;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--suite':
        // Checkout override is intentionally unsupported here; use the
        // standard .conformance/suites location so reports stay comparable.
        stderr.writeln('--suite is not supported; suites live in '
            '.conformance/suites (see fetch_suites.dart)');
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
      case '--results-dir':
        resultsDirectory = args[++i];
      case '--verbose':
        verbose = true;
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/run_test262.dart '
            '[--dirs a,b] [--limit n] [--timeout-ms n] '
            '[--skip-features f1,f2] [--markdown path] [--baseline summary.json] [--results-dir DIR] '
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

  final output = RunOutput(root, resultsDirectory: resultsDirectory);
  final baseline = output.loadBaseline(summary.suite, explicit: baselinePath);
  final files = output.write(
    summary,
    markdownPath: markdownPath,
    baseline: baseline,
  );
  output.printSummary(summary, files);
}
