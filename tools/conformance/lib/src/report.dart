import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'result.dart';
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
      ..writeln('# Conformidad: ${s.suite}')
      ..writeln()
      ..writeln('- Fecha: ${s.startedAt.toUtc().toIso8601String()}')
      ..writeln('- Duración: ${(s.durationMs / 1000).toStringAsFixed(1)} s');
    if (s.suiteCommit != null) {
      b.writeln('- Commit de la suite: `${s.suiteCommit}`');
    }
    if (s.suiteVersion != null) {
      b.writeln('- Versión de la suite: ${s.suiteVersion}');
    }
    if (s.command != null) {
      b.writeln('- Comando: `${s.command}`');
    }
    b
      ..writeln('- Total: **${s.total}** tests')
      ..writeln('- Tasa de éxito (sin SKIP): **${s.passRate.toStringAsFixed(2)} %**')
      ..writeln();

    b
      ..writeln('| Estado | Tests |')
      ..writeln('|---|---:|')
      ..writeln('| PASS | ${s.passed} |')
      ..writeln('| FAIL | ${s.failed} |')
      ..writeln('| SKIP | ${s.skipped} |')
      ..writeln('| ERROR | ${s.errors} |')
      ..writeln();

    if (baseline != null) {
      b
        ..writeln('## Delta contra la línea base')
        ..writeln()
        ..writeln(renderDelta(baseline, s))
        ..writeln();
    }

    void table(String title, Map<String, FeatureStats> stats) {
      if (stats.isEmpty) return;
      b
        ..writeln('## $title')
        ..writeln()
        ..writeln('| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |')
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
        b.writeln('| _(+${entries.length - 80} grupos)_ | | | | | |');
      }
      b.writeln();
    }

    table('Por característica', s.byFeature);
    table('Por directorio', s.byDirectory);

    final failures =
        s.results.where((r) => r.status == ResultStatus.fail).toList();
    if (failures.isNotEmpty) {
      b
        ..writeln('## Fallos (${failures.length})')
        ..writeln();
      for (final r in failures.take(maxFailures)) {
        b
          ..writeln('### `${r.id}`')
          ..writeln()
          ..writeln('- Características: ${r.features.isEmpty ? 'core' : r.features.join(', ')}')
          ..writeln('- Motivo: ${_cell(r.reason ?? '(sin motivo)')}');
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
        b.writeln('_… y ${failures.length - maxFailures} fallos más '
            '(ver el JSONL)._');
        b.writeln();
      }
    }

    if (s.skipped > 0) {
      final reasons = <String, int>{};
      for (final r in s.results.where((r) => r.status == ResultStatus.skip)) {
        final key = r.reason ?? '(sin motivo)';
        reasons[key] = (reasons[key] ?? 0) + 1;
      }
      b
        ..writeln('## SKIP agrupados por motivo')
        ..writeln()
        ..writeln('| Motivo | Tests |')
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
        ..writeln('## Errores del runner (${s.errors})')
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
      ..writeln('_Generado por `tools/conformance`. Un SKIP no cuenta como '
          'compatibilidad; mide únicamente que el runner no pudo ejecutar el '
          'test o que la característica está fuera de alcance._');
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
    return '- Corregidos: **$fixed**\n'
        '- Regresiones: **$regressed**\n'
        '- Siguen fallando: **$stillFailing**\n'
        '- Nuevos en esta ejecución: **$added**\n'
        '- Ausentes respecto a la base: **$removed**';
  }

  static String _cell(String value) => value
      .replaceAll('|', '\\|')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ');
}
