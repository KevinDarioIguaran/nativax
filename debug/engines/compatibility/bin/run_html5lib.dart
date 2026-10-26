import 'dart:io';

import '../lib/conformance.dart';

Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  final suite = html5libDir(root);
  int? limit;
  var verbose = false;
  String? markdownPath;
  String? baselinePath;
  String? resultsDirectory;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--limit':
        limit = int.parse(args[++i]);
      case '--markdown':
        markdownPath = args[++i];
      case '--baseline':
        baselinePath = args[++i];
      case '--results-dir':
        resultsDirectory = args[++i];
      case '--verbose':
        verbose = true;
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/run_html5lib.dart '
            '[--limit n] [--markdown path] [--baseline summary.json] [--results-dir DIR]');
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  if (!Directory(suite).existsSync()) {
    stderr.writeln('html5lib-tests not found at $suite.\n'
        'Run: dart run bin/fetch_suites.dart --suite html5lib');
    exitCode = 2;
    return;
  }

  final summary = await Html5libRunner(
    Html5libRunOptions(suitePath: suite, limit: limit, verbose: verbose),
  ).run();
  final output = RunOutput(root, resultsDirectory: resultsDirectory);
  final baseline = output.loadBaseline(summary.suite, explicit: baselinePath);
  final files = output.write(
    summary,
    markdownPath: markdownPath,
    baseline: baseline,
  );
  output.printSummary(summary, files);
}
