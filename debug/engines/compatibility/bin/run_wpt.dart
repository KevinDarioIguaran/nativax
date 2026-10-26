import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
      case '--verbose':
        verbose = true;
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/run_wpt.dart '
            '[--dirs dom/nodes,css/selectors] [--limit n] [--timeout-ms n] '
            '[--markdown path] [--baseline summary.json]');
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
  final baseline = _loadBaseline(root, baselinePath);
  final stamp = timestampForFile(summary.startedAt);
  final marked =
      markdownPath ?? p.join(resultsDir(root), 'wpt-$stamp.md');
  final files = const ConformanceReport().write(
    summary,
    outputDir: resultsDir(root),
    markdownPath: marked,
    baseline: baseline,
  );
  File(files.markdown).copySync(p.join(reportsDir(root), 'wpt-latest.md'));

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
    return RunSummary.fromJson(
        (const JsonDecoder().convert(f.readAsStringSync()) as Map)
            .cast<String, Object?>());
  }
  final dir = Directory(resultsDir(root));
  if (!dir.existsSync()) return null;
  final candidates = dir
      .listSync()
      .whereType<File>()
      .where((f) =>
          p.basename(f.path).startsWith('wpt-') &&
          f.path.endsWith('.summary.json'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  if (candidates.isEmpty) return null;
  return RunSummary.fromJson(
      (const JsonDecoder().convert(candidates.first.readAsStringSync())
              as Map)
          .cast<String, Object?>());
}
