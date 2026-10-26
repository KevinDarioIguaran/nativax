import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'result.dart';
import 'run_output.dart';
import 'suite_paths.dart';

class ReportFiles {
  const ReportFiles({
    required this.jsonl,
    required this.summary,
    required this.markdown,
  });
  final String jsonl;
  final String summary;
  final String markdown;
}

/// Writes raw JSONL, a machine-readable summary and a Markdown report.
class ConformanceReport {
  const ConformanceReport({
    this.maxFailures = 120,
    this.maxDetailChars = 1200,
  });

  final int maxFailures;
  final int maxDetailChars;

  ReportFiles write(
    RunSummary summary, {
    required String outputDir,
    required String markdownPath,
    RunSummary? baseline,
  }) {
    Directory(outputDir).createSync(recursive: true);
    final stamp = timestampForFile(summary.startedAt);
    final jsonlPath = p.join(outputDir, '${summary.suite}-$stamp.jsonl');
    final summaryPath = p.join(outputDir, '${summary.suite}-$stamp.summary.json');

    final jsonl = StringBuffer();
    for (final r in summary.results) {
      jsonl.writeln(jsonEncode(r.toJson()));
    }
    File(jsonlPath).writeAsStringSync(jsonl.toString());
    File(summaryPath).writeAsStringSync(summary.toJsonString());

    Directory(p.dirname(markdownPath)).createSync(recursive: true);
    File(markdownPath).writeAsStringSync(render(summary, baseline: baseline));

    return ReportFiles(
      jsonl: jsonlPath,
      summary: summaryPath,
      markdown: markdownPath,
    );
  }

  String render(RunSummary s, {RunSummary? baseline}) {
    final b = StringBuffer()
      ..writeln('# Conformance: ${s.suite}')
      ..writeln()
      ..writeln('- Started: ${isoWithOffset(s.startedAt)}')
      ..writeln('- Duration: ${(s.durationMs / 1000).toStringAsFixed(1)} s')
      ..writeln('- Runner version: $runnerVersion')
      ..writeln('- Suite revision: ${s.suiteCommit == null ? 'unknown (not a git checkout)' : '`${s.suiteCommit}`'}');
    if (s.suiteVersion != null) {
      b.writeln('- Suite version: ${s.suiteVersion}');
    }
    if (s.command != null) {
      b.writeln('- Command: `${s.command}`');
    }
    b
      ..writeln('- Total: **${s.total}** tests')
      ..writeln('- Pass rate (SKIP excluded): **${s.passRate.toStringAsFixed(2)} %**')
      ..writeln();

    b
      ..writeln('| Status | Tests |')
      ..writeln('|---|---:|')
      ..writeln('| PASS | ${s.passed} |')
      ..writeln('| FAIL | ${s.failed} |')
      ..writeln('| SKIP | ${s.skipped} |')
      ..writeln('| ERROR | ${s.errors} |')
      ..writeln();

    if (baseline != null) {
      b
        ..writeln('## Delta against the baseline')
        ..writeln()
        ..writeln(renderDelta(baseline, s))
        ..writeln();
    }

    void table(String title, Map<String, FeatureStats> stats) {
      if (stats.isEmpty) return;
      b
        ..writeln('## $title')
        ..writeln()
        ..writeln('| Group | PASS | FAIL | SKIP | ERROR | Pass rate |')
        ..writeln('|---|---:|---:|---:|---:|---:|');
      final entries = stats.entries.toList()
        ..sort((a, b) => b.value.total.compareTo(a.value.total));
      for (final e in entries.take(80)) {
        final v = e.value;
        b.writeln(
          '| `${_cell(e.key)}` | ${v.passed} | ${v.failed} | ${v.skipped} | '
          '${v.errored} | ${v.passRate.toStringAsFixed(1)} % |',
        );
      }
      if (entries.length > 80) {
        b.writeln('| _(+${entries.length - 80} groups)_ | | | | | |');
      }
      b.writeln();
    }

    table('By feature', s.byFeature);
    table('By directory', s.byDirectory);

    final failures =
        s.results.where((r) => r.status == ResultStatus.fail).toList();
    if (failures.isNotEmpty) {
      b
        ..writeln('## Failures (${failures.length})')
        ..writeln();
      for (final r in failures.take(maxFailures)) {
        b
          ..writeln('### `${r.id}`')
          ..writeln()
          ..writeln('- Features: ${r.features.isEmpty ? 'core' : r.features.join(', ')}')
          ..writeln('- Reason: ${_cell(r.reason ?? '(no reason)')}');
        if (r.detail != null && r.detail!.trim().isNotEmpty) {
          final detail = r.detail!.trim();
          b
            ..writeln()
            ..writeln('```text')
            ..writeln(detail.length <= maxDetailChars
                ? detail
                : '${detail.substring(0, maxDetailChars)}\n…')
            ..writeln('```');
        }
        b.writeln();
      }
      if (failures.length > maxFailures) {
        b.writeln('_… and ${failures.length - maxFailures} more failures '
            '(see the JSONL)._');
        b.writeln();
      }
    }

    if (s.skipped > 0) {
      final reasons = <String, int>{};
      for (final r in s.results.where((r) => r.status == ResultStatus.skip)) {
        final key = r.reason ?? '(no reason)';
        reasons[key] = (reasons[key] ?? 0) + 1;
      }
      b
        ..writeln('## SKIP grouped by reason')
        ..writeln()
        ..writeln('| Reason | Tests |')
        ..writeln('|---|---:|');
      final sorted = reasons.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        b.writeln('| ${_cell(e.key)} | ${e.value} |');
      }
      b.writeln();
    }

    if (s.errors > 0) {
      b
        ..writeln('## Runner errors (${s.errors})')
        ..writeln();
      for (final r in s.results
          .where((r) => r.status == ResultStatus.error)
          .take(50)) {
        b.writeln('- `${r.id}`: ${_cell(r.reason ?? r.detail ?? '')}');
      }
      b.writeln();
    }

    b
      ..writeln('---')
      ..writeln()
      ..writeln('_Generated by `debug/engines/compatibility`. A SKIP never counts '
          'as compatibility; it only records that the runner could not execute '
          'the test or that the feature is out of scope._');
    return b.toString();
  }

  static String renderDelta(RunSummary baseline, RunSummary current) {
    Map<String, TestResult> index(RunSummary s) =>
        {for (final r in s.results) '${r.suite}/${r.id}': r};
    final old = index(baseline);
    final now = index(current);
    var fixed = 0, regressed = 0, stillFailing = 0, added = 0, removed = 0;
    for (final e in now.entries) {
      final before = old[e.key];
      if (before == null) {
        added++;
      } else if (before.status != ResultStatus.pass &&
          e.value.status == ResultStatus.pass) {
        fixed++;
      } else if (before.status == ResultStatus.pass &&
          e.value.status != ResultStatus.pass) {
        regressed++;
      } else if (before.status == ResultStatus.fail &&
          e.value.status == ResultStatus.fail) {
        stillFailing++;
      }
    }
    removed = old.keys.where((k) => !now.containsKey(k)).length;
    final warning = baseline.suiteCommit != current.suiteCommit
        ? '- **Not comparable:** suite revision '
            '`${baseline.suiteCommit ?? 'unknown'}` in the baseline, '
            '`${current.suiteCommit ?? 'unknown'}` now\n'
        : '';
    return '$warning'
        '- Fixed: **$fixed**\n'
        '- Regressions: **$regressed**\n'
        '- Still failing: **$stillFailing**\n'
        '- New in this run: **$added**\n'
        '- Missing compared with the baseline: **$removed**';
  }

  static String _cell(String value) => value
      .replaceAll('|', '\\|')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ');
}
