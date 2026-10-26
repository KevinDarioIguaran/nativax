import 'dart:io';

import '../lib/conformance.dart';

Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  final suite = wptDir(root);
  int? limit;
  String? baselinePath;
  String? resultsDirectory;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--limit':
        limit = int.parse(args[++i]);
      case '--baseline':
        baselinePath = args[++i];
      case '--results-dir':
        resultsDirectory = args[++i];
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/run_url.dart '
            '[--limit n] [--baseline summary.json] [--results-dir DIR]');
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  if (!Directory(suite).existsSync()) {
    stderr.writeln('WPT not found at $suite.\n'
        'Run: dart run bin/fetch_suites.dart --suite wpt');
    exitCode = 2;
    return;
  }

  final summary = await UrlRunner(
    UrlRunOptions(suitePath: suite, limit: limit),
  ).run();
  final output = RunOutput(root, resultsDirectory: resultsDirectory);
  final baseline = output.loadBaseline(summary.suite, explicit: baselinePath);
  final files = output.write(
    summary,
    baseline: baseline,
  );
  output.printSummary(summary, files);
}
