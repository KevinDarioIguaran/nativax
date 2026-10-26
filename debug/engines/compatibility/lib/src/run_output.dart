import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'report.dart';
import 'result.dart';
import 'suite_paths.dart';

/// Version of the runners and of the summary format. Bump it whenever a
/// change can move a verdict, so summaries from different runner versions
/// are never compared as if they were equal.
const runnerVersion = '0.2.0';

/// ISO 8601 with the local UTC offset, e.g. `2026-10-26T09:15:02.123-05:00`.
/// `DateTime.toIso8601String()` omits the offset for local times.
String isoWithOffset(DateTime time) {
  if (time.isUtc) return time.toIso8601String();
  final offset = time.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hh = (minutes ~/ 60).toString().padLeft(2, '0');
  final mm = (minutes % 60).toString().padLeft(2, '0');
  return '${time.toIso8601String()}$sign$hh:$mm';
}

/// Git revision of [suitePath] when it is the top of a git checkout.
///
/// Returns null for a directory that only lives *inside* a checkout (for
/// example the committed validation fixtures), so that the NativaX commit is
/// never recorded as if it were the suite revision.
String? suiteRevision(String suitePath) {
  try {
    final top = Process.runSync(
        'git', ['rev-parse', '--show-toplevel'],
        workingDirectory: suitePath);
    if (top.exitCode != 0) return null;
    final topLevel = p.canonicalize((top.stdout as String).trim());
    if (topLevel != p.canonicalize(suitePath)) return null;
    final head = Process.runSync('git', ['rev-parse', 'HEAD'],
        workingDirectory: suitePath);
    if (head.exitCode != 0) return null;
    return (head.stdout as String).trim();
  } on ProcessException {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// Where a runner writes its files.
///
/// By default results go to `.conformance/results` and the Markdown report
/// is also copied to the tracked `progress/reports/<suite>-latest.md`. With
/// `--results-dir DIR` every file goes to DIR and no tracked file is touched.
class RunOutput {
  RunOutput(this.repoRoot, {String? resultsDirectory})
      : _override =
            resultsDirectory == null ? null : p.absolute(resultsDirectory);

  final String repoRoot;
  final String? _override;

  String get directory => _override ?? resultsDir(repoRoot);
  bool get updatesTrackedLatest => _override == null;

  /// The newest `<suite>-<timestamp>.summary.json` in [directory], or the
  /// explicit file. The name must match exactly, so `wpt` never picks a
  /// `wpt-url` or `wpt-html-tree` summary.
  RunSummary? loadBaseline(String suite, {String? explicit}) {
    File? file;
    if (explicit != null) {
      file = File(explicit);
      if (!file.existsSync()) return null;
    } else {
      final dir = Directory(directory);
      if (!dir.existsSync()) return null;
      final pattern = RegExp('^${RegExp.escape(suite)}-'
          r'\d{4}-\d{2}-\d{2}T\d{6}\.summary\.json$');
      final candidates = dir
          .listSync()
          .whereType<File>()
          .where((f) => pattern.hasMatch(p.basename(f.path)))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (candidates.isEmpty) return null;
      file = candidates.first;
    }
    return RunSummary.fromJson(
        (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>());
  }

  ReportFiles write(
    RunSummary summary, {
    String? markdownPath,
    RunSummary? baseline,
  }) {
    final stamp = timestampForFile(summary.startedAt);
    final files = const ConformanceReport().write(
      summary,
      outputDir: directory,
      markdownPath:
          markdownPath ?? p.join(directory, '${summary.suite}-$stamp.md'),
      baseline: baseline,
    );
    if (updatesTrackedLatest) {
      final reports = reportsDir(repoRoot);
      Directory(reports).createSync(recursive: true);
      File(files.markdown)
          .copySync(p.join(reports, '${summary.suite}-latest.md'));
    }
    return files;
  }

  /// Prints the standard run footer.
  void printSummary(RunSummary summary, ReportFiles files) {
    stdout
      ..writeln()
      ..writeln('PASS ${summary.passed}  FAIL ${summary.failed}  '
          'SKIP ${summary.skipped}  ERROR ${summary.errors}')
      ..writeln('rate  ${summary.passRate.toStringAsFixed(2)} % '
          '(${summary.total} tests, '
          '${(summary.durationMs / 1000).toStringAsFixed(1)} s)')
      ..writeln('jsonl ${files.jsonl}')
      ..writeln('md    ${files.markdown}');
  }
}
