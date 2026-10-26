import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'analysis.dart';
import 'model.dart';

class LeakReportFiles {
  const LeakReportFiles({
    required this.json,
    required this.jsonl,
    required this.markdown,
  });
  final String json;
  final String jsonl;
  final String markdown;
}

LeakReportFiles writeLeakReport(
  LeakRun run, {
  required String outputDir,
  String? jsonPath,
  String? jsonlPath,
  String? markdownPath,
}) {
  Directory(outputDir).createSync(recursive: true);
  final stamp = run.metadata.timestamp.toIso8601String().replaceAll(':', '');
  final jsonFile = jsonPath ?? p.join(outputDir, 'leaks-$stamp.json');
  final jsonlFile = jsonlPath ?? p.join(outputDir, 'leaks-$stamp.jsonl');
  final mdFile = markdownPath ?? p.join(outputDir, 'leaks-$stamp.md');
  for (final path in [jsonFile, jsonlFile, mdFile]) {
    Directory(p.dirname(path)).createSync(recursive: true);
  }
  File(jsonFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(run.toJson()));
  final lines = StringBuffer();
  for (final result in run.results) {
    for (final sample in result.samples) {
      lines.writeln(jsonEncode({
        'id': result.id,
        'batch': sample.batch,
        ...sample.toJson(),
      }));
    }
  }
  File(jsonlFile).writeAsStringSync(lines.toString());
  File(mdFile).writeAsStringSync(renderLeakMarkdown(run));
  return LeakReportFiles(
    json: jsonFile,
    jsonl: jsonlFile,
    markdown: mdFile,
  );
}

LeakRun loadLeakRun(String path) {
  final json = jsonDecode(File(path).readAsStringSync());
  if (json is! Map) throw FormatException('$path is not a leak report');
  return LeakRun.fromJson(json.cast<String, Object?>());
}

String renderLeakMarkdown(LeakRun run) {
  final counts = <LeakStatus, int>{
    for (final status in LeakStatus.values)
      status: run.results.where((r) => r.status == status).length,
  };
  final b = StringBuffer()
    ..writeln('# NativaX leak & lifecycle report')
    ..writeln()
    ..writeln('- Fecha: ${run.metadata.timestamp.toIso8601String()}')
    ..writeln('- Perfil: ${run.metadata.profile}')
    ..writeln('- Motor: ${run.metadata.engine} '
        '${run.metadata.engineVersion}')
    ..writeln('- Dart: ${run.metadata.dartVersion} (${run.metadata.mode})')
    ..writeln('- OS: ${run.metadata.os} ${run.metadata.osVersion} '
        '(${run.metadata.arch})')
    ..writeln('- Comando: `${run.metadata.command}`')
    ..writeln()
    ..writeln('| Estado | Casos |')
    ..writeln('|---|---:|');
  for (final status in LeakStatus.values) {
    b.writeln('| ${status.label} | ${counts[status]} |');
  }
  b
    ..writeln()
    ..writeln('| Caso | Subsistema | Estado | Escenario | Evidencia |')
    ..writeln('|---|---|---|---|---|');
  for (final r in run.results) {
    final memory = r.samples.isEmpty
        ? '—'
        : '${_bytes(r.samples.first.rssBytes)} → '
            '${_bytes(r.samples.last.rssBytes)}';
    b.writeln('| `${r.id}` | ${r.subsystem} | ${r.status.label} | '
        '${r.scenario} | ${memory}; ${r.reason} |');
  }
  b
    ..writeln()
    ..writeln('## Detalle')
    ..writeln();
  for (final r in run.results) {
    b
      ..writeln('### `${r.id}` — ${r.status.label}')
      ..writeln()
      ..writeln('- Subsistema: ${r.subsystem}')
      ..writeln('- Escenario: ${r.scenario}')
      ..writeln('- Expectativa: ${r.expectation}')
      ..writeln('- Motivo: ${r.reason}')
      ..writeln('- Duración: ${r.durationMs} ms')
      ..writeln('- Reproducir: `${r.reproduce}`');
    if (r.evidence.isNotEmpty) {
      for (final evidence in r.evidence) {
        b.writeln('- Evidencia: $evidence');
      }
    }
    if (r.samples.isNotEmpty) {
      b
        ..writeln()
        ..writeln('| Lote | RSS | Máx RSS | Heap motor | Nodos | Listeners | '
            'Timers | Targets |')
        ..writeln('|---:|---:|---:|---:|---:|---:|---:|---:|');
      for (final s in r.samples) {
        b.writeln('| ${s.batch} | ${_bytes(s.rssBytes)} | '
            '${_bytes(s.maxRssBytes)} | '
            '${s.engineBytes == null ? '—' : _bytes(s.engineBytes!)} | '
            '${s.nodes ?? '—'} | ${s.listeners ?? '—'} | '
            '${s.timers ?? '—'} | ${s.targets ?? '—'} |');
      }
    }
    b.writeln();
  }
  b
    ..writeln('## Limitaciones')
    ..writeln()
    ..writeln('- `ProcessInfo.currentRss` es memoria residente del proceso; '
        'incluye Dart, QuickJS, Flutter y el allocator. No es “heap vivo”.')
    ..writeln('- QuickJS expone `JS_ComputeMemoryUsage`; se usa cuando el caso '
        'lo proporciona.')
    ..writeln('- Una subida de RSS no es una fuga. `FAIL` exige tendencia '
        'sostenida y evidencia de recursos; si no, `INCONCLUSIVE`.')
    ..writeln('- El GC de Dart y el allocator pueden retener memoria después '
        'de liberar objetos; el sistema operativo no tiene que devolverla.');
  return b.toString();
}

String _bytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '$value B';
}
