import 'dart:io';

import '../lib/conformance.dart';

Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  final suite = wptDir(root);
  var dirs = <String>['dom/nodes', 'css/selectors'];
  int? limit = 400;
  var timeout = const Duration(seconds: 20);
  var verbose = false;
  String? grep;
  String? markdownPath;
  String? baselinePath;
  String? resultsDirectory;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dirs':
        dirs = args[++i].split(',').map((s) => s.trim()).toList();
      case '--grep':
        grep = args[++i];
      case '--limit':
        limit = int.parse(args[++i]);
      case '--timeout-ms':
        timeout = Duration(milliseconds: int.parse(args[++i]));
      case '--markdown':
        markdownPath = args[++i];
      case '--baseline':
        baselinePath = args[++i];
      case '--results-dir':
        resultsDirectory = args[++i];
      case '--verbose':
        verbose = true;
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/run_wpt.dart '
            '[--dirs dom/nodes,css/selectors] [--limit n] [--timeout-ms n] '
            '[--markdown path] [--baseline summary.json] [--results-dir DIR]');
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

  final summary = await WptRunner(WptRunOptions(
    suitePath: suite,
    directories: dirs,
    limit: limit,
    grep: grep,
    timeout: timeout,
    verbose: verbose,
  )).run();
  final output = RunOutput(root, resultsDirectory: resultsDirectory);
  final baseline = output.loadBaseline(summary.suite, explicit: baselinePath);
  final files = output.write(
    summary,
    markdownPath: markdownPath,
    baseline: baseline,
  );
  output.printSummary(summary, files);
}
