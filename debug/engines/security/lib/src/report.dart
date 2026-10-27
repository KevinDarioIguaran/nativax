import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'model.dart';

class SecurityReportFiles {
  const SecurityReportFiles({required this.json, required this.markdown});
  final String json;
  final String markdown;
}

SecurityReportFiles writeSecurityReport(
  SecurityRun run, {
  required String outputDir,
  String? jsonPath,
  String? markdownPath,
}) {
  Directory(outputDir).createSync(recursive: true);
  final stamp = run.metadata.timestamp.toIso8601String().replaceAll(':', '');
  final jsonFile = jsonPath ?? p.join(outputDir, 'security-$stamp.json');
  final mdFile = markdownPath ?? p.join(outputDir, 'security-$stamp.md');
  for (final path in [jsonFile, mdFile]) {
    Directory(p.dirname(path)).createSync(recursive: true);
  }
  File(
    jsonFile,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(run.toJson()));
  File(mdFile).writeAsStringSync(renderSecurityMarkdown(run));
  return SecurityReportFiles(json: jsonFile, markdown: mdFile);
}

SecurityRun loadSecurityRun(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map) throw FormatException('$path is not a security report');
  final map = decoded.cast<String, Object?>();
  final meta = (map['metadata'] as Map?)?.cast<String, Object?>() ?? const {};
  return SecurityRun(
    metadata: SecurityMetadata(
      engine: meta['engine'] as String? ?? '',
      engineVersion: meta['engineVersion'] as String? ?? '',
      dartVersion: meta['dartVersion'] as String? ?? '',
      mode: meta['mode'] as String? ?? '',
      os: meta['os'] as String? ?? '',
      osVersion: meta['osVersion'] as String? ?? '',
      arch: meta['arch'] as String? ?? '',
      timestamp:
          DateTime.tryParse(meta['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      command: meta['command'] as String? ?? '',
      limits: (meta['limits'] as Map?)?.cast<String, String>() ?? const {},
    ),
    results: [
      for (final e in (map['results'] as List? ?? const []))
        SecurityResult(
          id: (e as Map)['id'] as String? ?? '',
          category: e['category'] as String? ?? '',
          severity: e['severity'] as String? ?? '',
          description: e['description'] as String? ?? '',
          status: SecurityStatus.values.firstWhere(
            (s) => s.name == e['status'],
            orElse: () => SecurityStatus.error,
          ),
          expected: e['expected'] as String? ?? '',
          observed: e['observed'] as String? ?? '',
          durationMs: (e['durationMs'] as num?)?.toInt() ?? 0,
          evidence: (e['evidence'] as List?)?.cast<String>() ?? const [],
          remediation: e['remediation'] as String? ?? '',
        ),
    ],
  );
}

String renderSecurityMarkdown(SecurityRun run) {
  final b = StringBuffer()
    ..writeln('# NativaX security audit results')
    ..writeln()
    ..writeln('- Fecha: ${run.metadata.timestamp.toIso8601String()}')
    ..writeln(
      '- Motor: ${run.metadata.engine} '
      '${run.metadata.engineVersion}',
    )
    ..writeln('- Dart: ${run.metadata.dartVersion} (${run.metadata.mode})')
    ..writeln(
      '- OS: ${run.metadata.os} ${run.metadata.osVersion} '
      '(${run.metadata.arch})',
    )
    ..writeln('- Comando: `${run.metadata.command}`')
    ..writeln()
    ..writeln('| Caso | Categoría | Severidad | Estado | Observado |')
    ..writeln('|---|---|---|---|---|');
  for (final r in run.results) {
    b.writeln(
      '| `${r.id}` | ${r.category} | ${r.severity} | '
      '${r.status.label} | ${r.observed.replaceAll('|', '\\|')} |',
    );
  }
  b
    ..writeln()
    ..writeln('## Detalle')
    ..writeln();
  for (final r in run.results) {
    b
      ..writeln('### `${r.id}` — ${r.status.label}')
      ..writeln()
      ..writeln('- Severidad: ${r.severity}')
      ..writeln('- Descripción: ${r.description}')
      ..writeln('- Esperado: ${r.expected}')
      ..writeln('- Observado: ${r.observed}')
      ..writeln('- Duración: ${r.durationMs} ms');
    if (r.remediation.isNotEmpty) {
      b.writeln('- Remediation: ${r.remediation}');
    }
    if (r.evidence.isNotEmpty) {
      for (final evidence in r.evidence) {
        b.writeln('- Evidencia: $evidence');
      }
    }
    b.writeln();
  }
  b
    ..writeln('## Limitaciones')
    ..writeln()
    ..writeln(
      '- Esta suite cubre las fronteras verificables desde Dart/CLI. '
      'Flutter, Android, iOS, Windows y macOS requieren ejecución propia.',
    )
    ..writeln(
      '- `PASS` significa que el ataque probado no produjo el efecto '
      'no autorizado; no es una garantía de sandbox del sistema operativo.',
    )
    ..writeln('- Un `SKIP` no es una protección verificada.')
    ..writeln(
      '- No se declara NativaX “100 % seguro” ni “a prueba de '
      'exploits”.',
    );
  return b.toString();
}
