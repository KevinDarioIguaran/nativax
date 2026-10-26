import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/conformance.dart';

Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  final suite = wptDir(root);
  int? limit;
  String? baselinePath;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--limit':
        limit = int.parse(args[++i]);
      case '--baseline':
        baselinePath = args[++i];
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/run_url.dart '
            '[--limit n] [--baseline summary.json]');
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
  final baseline = _loadBaseline(root, baselinePath);
  final stamp = timestampForFile(summary.startedAt);
  final marked = p.join(resultsDir(root), 'wpt-url-$stamp.md');
  final files = const ConformanceReport().write(
    summary,
    outputDir: resultsDir(root),
    markdownPath: marked,
    baseline: baseline,
  );
  File(files.markdown).copySync(p.join(reportsDir(root), 'wpt-url-latest.md'));

  stdout
    ..writeln()
    ..writeln('PASS ${summary.passed}  FAIL ${summary.failed}  '
        'SKIP ${summary.skipped}  ERROR ${summary.errors}')
    ..writeln('rate  ${summary.passRate.toStringAsFixed(2)} % '
        '(${summary.total} tests)')
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
          p.basename(f.path).startsWith('wpt-url-') &&
          f.path.endsWith('.summary.json'))
      .toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  if (candidates.isEmpty) return null;
  return RunSummary.fromJson(
      (const JsonDecoder().convert(candidates.first.readAsStringSync())
              as Map)
          .cast<String, Object?>());
}
