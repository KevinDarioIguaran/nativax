import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'analysis.dart';
import 'classification.dart';
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
    ..writeln('- Date: ${run.metadata.timestamp.toIso8601String()}')
    ..writeln('- Profile: ${run.metadata.profile}')
    ..writeln('- Engine: ${run.metadata.engine} '
        '${run.metadata.engineVersion}')
    ..writeln('- Dart: ${run.metadata.dartVersion} (${run.metadata.mode})')
    ..writeln('- OS: ${run.metadata.os} ${run.metadata.osVersion} '
        '(${run.metadata.arch})')
    ..writeln('- Command: `${run.metadata.command}`')
    ..writeln()
    ..writeln('| Status | Cases |')
    ..writeln('|---|---:|');
  for (final status in LeakStatus.values) {
    b.writeln('| ${status.label} | ${counts[status]} |');
  }
  b
    ..writeln()
    ..writeln()
    ..writeln('| Class | Cases |')
    ..writeln('|---|---:|');
  for (final c in LeakClass.values) {
    b.writeln('| ${c.label} | '
        '${run.results.where((r) => r.classification?.leakClass == c).length} |');
  }
  b
    ..writeln()
    ..writeln('| Case | Subsystem | Status | Class | Scenario | Evidence |')
    ..writeln('|---|---|---|---|---|---|');
  for (final r in run.results) {
    final memory = r.samples.isEmpty
        ? '—'
        : '${_bytes(r.samples.first.rssBytes)} → '
            '${_bytes(r.samples.last.rssBytes)}';
    b.writeln('| `${r.id}` | ${r.subsystem} | ${r.status.label} | '
        '${r.classification?.leakClass.label ?? '—'} | '
        '${r.scenario} | ${memory}; ${r.reason} |');
  }
  b
    ..writeln()
    ..writeln('## Detail')
    ..writeln();
  for (final r in run.results) {
    b
      ..writeln('### `${r.id}` — ${r.status.label}')
      ..writeln()
      ..writeln('- Subsystem: ${r.subsystem}')
      ..writeln('- Scenario: ${r.scenario}')
      ..writeln('- Expectation: ${r.expectation}')
      ..writeln('- Reason: ${r.reason}')
      ..writeln('- Duration: ${r.durationMs} ms')
      ..writeln('- Reproduce: `${r.reproduce}`');
    final c = r.classification;
    if (c != null) {
      b.writeln('- Class: `${c.leakClass.label}` (${c.reason})');
    }
    if (r.truth != null) {
      b.writeln('- Ground truth: leaks=${r.truth!.leaks}, expected '
          '`${r.truth!.expected}` (${r.truth!.rationale})');
    }
    if (r.evidence.isNotEmpty) {
      for (final evidence in r.evidence) {
        b.writeln('- Evidence: $evidence');
      }
    }
    if (r.samples.isNotEmpty) {
      b
        ..writeln()
        ..writeln('| Batch | RSS | Max RSS | Engine heap | Nodes | Listeners | '
            'Timers | Targets |')
        ..writeln('|---:|---:|---:|---:|---:|---:|---:|---:|');
      for (final s in r.samples) {
        b.writeln('| ${s.release ? '${s.batch} (release)' : s.batch} | '
            '${_bytes(s.rssBytes)} | '
            '${_bytes(s.maxRssBytes)} | '
            '${s.engineBytes == null ? '—' : _bytes(s.engineBytes!)} | '
            '${s.nodes ?? '—'} | ${s.listeners ?? '—'} | '
            '${s.timers ?? '—'} | ${s.targets ?? '—'} |');
      }
    }
    b.writeln();
  }
  b
    ..writeln('## Limitations')
    ..writeln()
    ..writeln('- `ProcessInfo.currentRss` is process resident memory; it '
        'includes Dart, QuickJS, Flutter and the allocator. It is not '
        '"live heap".')
    ..writeln('- QuickJS exposes `JS_ComputeMemoryUsage`; it is used when the '
        'case provides it.')
    ..writeln('- An RSS increase is not a leak. `FAIL` requires a sustained '
        'trend and resource evidence; otherwise `INCONCLUSIVE`. RSS-only '
        'evidence is capped at `suspected_leak`.')
    ..writeln('- Dart GC and the allocator can keep memory after objects are '
        'freed; the operating system does not have to get it back.');
  return b.toString();
}

String _bytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '$value B';
}
