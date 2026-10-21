import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'model.dart';
import 'runner.dart';

class ReportFiles {
  const ReportFiles({required this.json, required this.markdown});
  final String json;
  final String markdown;
}

ReportFiles writeReport(
  RunReport report, {
  required String outputDir,
  String? jsonPath,
  String? markdownPath,
}) {
  Directory(outputDir).createSync(recursive: true);
  final stamp = report.metadata.timestamp
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '-');
  final jsonFile = jsonPath ?? p.join(outputDir, 'bench-$stamp.json');
  final mdFile = markdownPath ?? p.join(outputDir, 'bench-$stamp.md');
  Directory(p.dirname(jsonFile)).createSync(recursive: true);
  Directory(p.dirname(mdFile)).createSync(recursive: true);
  File(jsonFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report.toJson()));
  File(mdFile).writeAsStringSync(renderMarkdown(report));
  return ReportFiles(json: jsonFile, markdown: mdFile);
}

RunReport loadReport(String path) {
  final json = jsonDecode(File(path).readAsStringSync());
  if (json is! Map) throw FormatException('$path is not a benchmark report');
  return RunReport.fromJson(json.cast<String, Object?>());
}

String renderMarkdown(RunReport report) {
  final b = StringBuffer()
    ..writeln('# NativaX benchmark')
    ..writeln()
    ..writeln('- Fecha: ${report.metadata.timestamp.toIso8601String()}')
    ..writeln('- Comando: `${report.command}`')
    ..writeln('- Motor: ${report.metadata.engine} '
        '${report.metadata.engineVersion}')
    ..writeln('- Dart: ${report.metadata.dartVersion} '
        '(${report.metadata.mode})')
    ..writeln('- OS: ${report.metadata.os} ${report.metadata.osVersion} '
        '(${report.metadata.arch})')
    ..writeln('- Reloj: ${report.metadata.clock}; '
        '${report.metadata.clockFrequencyHz} Hz; '
        'resolución declarada ${report.metadata.clockResolutionMs} ms')
    ..writeln();

  if (report.notes.isNotEmpty) {
    for (final note in report.notes) {
      b.writeln('> $note');
    }
    b.writeln();
  }

  b
    ..writeln('| Benchmark | Cat. | Mediana | p90 | p95 | p99 | '
        'MAD | Ops/s | MB/s | Rondas | Checksum |')
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final r in report.results) {
    b.writeln(
      '| `${r.name}` | ${r.category} | ${formatMs(r.medianMs)} | '
      '${formatMs(r.p90Ms)} | ${formatMs(r.p95Ms)} | ${formatMs(r.p99Ms)} | '
      '${formatMs(r.madMs)} | ${formatOps(r.opsPerSecond)} | '
      '${r.mbPerSecond > 0 ? r.mbPerSecond.toStringAsFixed(2) : '—'} | '
      '${r.rounds} | `${r.checksum}` |',
    );
  }
  b.writeln();

  final speedups = _speedups(report);
  if (speedups.isNotEmpty) {
    b
      ..writeln('## JavaScript vs. Dart (mismo trabajo)')
      ..writeln()
      ..writeln('`speedup = mediana_Dart / mediana_JS`; >1 significa que JS '
          'fue más rápido. Solo se incluyen pares comparables.')
      ..writeln()
      ..writeln('| Benchmark | JS | Dart | Speedup | Cambio |')
      ..writeln('|---|---:|---:|---:|---:|');
    for (final entry in speedups) {
      b.writeln('| `${entry.suffix}` | ${formatMs(entry.jsMs)} | '
          '${formatMs(entry.dartMs)} | ${entry.speedup.toStringAsFixed(2)}× | '
          '${entry.changePct >= 0 ? '+' : ''}'
          '${entry.changePct.toStringAsFixed(1)} % |');
    }
    b.writeln();
  }
  b
    ..writeln('## Notas por benchmark')
    ..writeln();
  for (final r in report.results.where((r) => r.notes.isNotEmpty)) {
    b.writeln('- `${r.name}`: ${r.notes}');
  }
  b
    ..writeln()
    ..writeln('## Limitaciones')
    ..writeln()
    ..writeln('- `Stopwatch` es monotónico, pero su resolución efectiva depende '
        'del sistema; se declara 1 µs como cota inferior, no como precisión '
        'garantizada.')
    ..writeln('- Los benchmarks `dart.*` son una referencia del mismo proceso, '
        'no una comparación equivalente con QuickJS.')
    ..writeln('- Los benchmarks JS incluyen el coste de `engine.evaluate` y de '
        'serializar el checksum; con operaciones internas suficientes es '
        'despreciable, pero se documenta.')
    ..writeln('- No se miden frames de GPU; `dom.style_recompute` mide solo '
        'DOM → estilos, no la actualización visible.')
    ..writeln('- No se comparan motores distintos (V8/JavaScriptCore) como si '
        'fueran equivalentes.');
  return b.toString();
}

class Speedup {
  Speedup(this.suffix, this.jsMs, this.dartMs)
      : speedup = jsMs == 0 ? 0 : dartMs / jsMs,
        changePct = jsMs == 0 ? 0 : ((jsMs - dartMs) / jsMs) * 100;
  final String suffix;
  final double jsMs;
  final double dartMs;
  final double speedup;
  final double changePct;
}

List<Speedup> _speedups(RunReport report) {
  final out = <Speedup>[];
  for (final js in report.results) {
    if (!js.name.startsWith('js.')) continue;
    final suffix = js.name.substring(3);
    final dart = report.byName('dart.$suffix');
    if (dart == null) continue;
    out.add(Speedup(suffix, js.medianMs, dart.medianMs));
  }
  out.sort((a, b) => a.suffix.compareTo(b.suffix));
  return out;
}

String renderComparison(
  List<Comparison> comparisons, {
  required String baselinePath,
  required String currentPath,
  required double thresholdPct,
  required double noiseMultiplier,
}) {
  final b = StringBuffer()
    ..writeln('# Comparación de benchmarks')
    ..writeln()
    ..writeln('- Base: `$baselinePath`')
    ..writeln('- Actual: `$currentPath`')
    ..writeln('- Umbral: $thresholdPct %')
    ..writeln('- Ruido: MAD/mediana × $noiseMultiplier')
    ..writeln()
    ..writeln('| Benchmark | Base | Actual | Cambio | Ruido | Estado |')
    ..writeln('|---|---:|---:|---:|---:|---|');
  for (final c in comparisons) {
    final change = c.changePct.isFinite
        ? '${c.changePct >= 0 ? '+' : ''}${c.changePct.toStringAsFixed(1)} %'
        : 'n/a';
    b.writeln('| `${c.name}` | ${formatMs(c.baselineMedianMs)} | '
        '${formatMs(c.currentMedianMs)} | $change | '
        '${c.noisePct.toStringAsFixed(1)} % | ${c.status} |');
  }
  final regressions =
      comparisons.where((c) => c.status == 'regression').length;
  b
    ..writeln()
    ..writeln('Regresiones: **$regressions**');
  return b.toString();
}
