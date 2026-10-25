import 'dart:convert';
import 'dart:io';

import 'model.dart';

String _r(double value) => value.isFinite ? value.toStringAsFixed(2) : '—';

double _work(EngineRun run) => run.scenarioMs + run.renderMs;

String _pct(double value) => '${(value).toStringAsFixed(2)} %';

/// Writes only results.json after each scenario so the dashboard can follow a run.
void writeLivePerfResults(PerfRun run, String directory) {
  final dir = Directory(directory)..createSync(recursive: true);
  final tmp = File('${dir.path}/.results.json.tmp');
  tmp.writeAsStringSync(jsonEncode(run.toJson()));
  tmp.renameSync('${dir.path}/results.json');
}

void writePerfReports(PerfRun run, String directory) {
  final dir = Directory(directory)..createSync(recursive: true);
  final results = File('${dir.path}/.results.json.tmp')
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(run.toJson()),
    );
  results.renameSync('${dir.path}/results.json');
  File('${dir.path}/results.csv').writeAsStringSync(_csv(run));
  File('${dir.path}/report.md').writeAsStringSync(_markdown(run));
  File('${dir.path}/timeline.csv').writeAsStringSync(_timeline(run));
  final charts = Directory('${dir.path}/charts')..createSync(recursive: true);
  File('${charts.path}/work-ratio.svg').writeAsStringSync(
    _bars(
      title: 'NativaX / Chromium work ratio (lower is better)',
      rows: [
        for (final r in run.results)
          if (r.chromium.ok && r.nativa.ok)
            (
              label: r.scenarioId,
              value: _ratio(_work(r.nativa), _work(r.chromium)),
              color:
                  _ratio(_work(r.nativa), _work(r.chromium)) <=
                      run.targets.workRatio
                  ? '#3fb950'
                  : '#f85149',
            ),
      ],
      target: run.targets.workRatio,
      targetLabel: '${run.targets.workRatio}x target',
      maxValue: 8,
    ),
  );
  File('${charts.path}/frame-p95.svg').writeAsStringSync(
    _bars(
      title: 'NativaX frame p95 during scroll (ms)',
      rows: [
        for (final r in run.results)
          if (r.kind == 'scroll' && r.nativa.frameTimes.isNotEmpty)
            (
              label: r.scenarioId,
              value: r.nativa.frameP95,
              color: r.nativa.frameP95 <= run.targets.frameP95Ms
                  ? '#3fb950'
                  : '#f85149',
            ),
      ],
      target: run.targets.frameP95Ms,
      targetLabel: '16.7 ms budget',
      maxValue: 50,
    ),
  );
  File('${charts.path}/rss.svg').writeAsStringSync(
    _bars(
      title: 'NativaX resident memory peak (MB)',
      rows: [
        for (final r in run.results)
          if (r.nativa.samples.isNotEmpty)
            (
              label: r.scenarioId,
              value: r.nativa.rssPeakMb,
              color: r.nativa.rssPeakMb <= run.targets.idleRssMb
                  ? '#3fb950'
                  : '#d29922',
            ),
      ],
      target: run.targets.idleRssMb,
      targetLabel: '250 MB idle target',
      maxValue: 1200,
    ),
  );
}

String _markdown(PerfRun run) {
  final buffer = StringBuffer()
    ..writeln('# NativaX performance suite')
    ..writeln()
    ..writeln(
      '- Reference: ${run.chromeVersion} headless, ${run.viewportWidth}x${run.viewportHeight}',
    )
    ..writeln('- Date: ${run.startedAt.toIso8601String()}')
    ..writeln(
      '- Duration: ${(run.duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
    )
    ..writeln('- Command: `${run.command}`')
    ..writeln(
      '- Targets: frame p95 ≤ ${run.targets.frameP95Ms} ms, max frame ≤ '
      '${run.targets.frameMaxMs} ms, work ratio ≤ ${run.targets.workRatio}x, '
      'idle RSS ≤ ${run.targets.idleRssMb} MB, idle CPU ≤ ${run.targets.idleCpuPct} %',
    )
    ..writeln()
    ..writeln('| Verdict | Scenarios |')
    ..writeln('|---|---:|')
    ..writeln('| PASS | ${run.count(Verdict.pass)} |')
    ..writeln('| WARN | ${run.count(Verdict.warn)} |')
    ..writeln('| FAIL | ${run.count(Verdict.fail)} |')
    ..writeln('| INVALID | ${run.count(Verdict.invalid)} |')
    ..writeln()
    ..writeln('## Scenarios')
    ..writeln()
    ..writeln(
      '| Scenario | Verdict | NativaX work | Chromium work | Ratio | '
      'Nodes N/C | Frame p95 | RSS peak | CPU peak |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final result in run.results) {
    final n = result.nativa;
    final c = result.chromium;
    final ratio = _ratio(_work(n), _work(c));
    buffer.writeln(
      '| `${result.scenarioId}` | ${result.verdict.label} | '
      '${_r(_work(n))} ms | ${_r(_work(c))} ms | ${ratio.toStringAsFixed(2)}x | '
      '${n.nodes}/${c.nodes} | '
      '${n.frameTimes.isEmpty ? '—' : '${_r(n.frameP95)} ms'} | '
      '${_r(n.rssPeakMb)} MB | ${_pct(n.cpuPeakPct)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'Work = scenario JS time + measured frame/style/layout time. '
      'Chromium frame time is `LayoutDuration + RecalcStyleDuration`; NativaX '
      'frame time is the offscreen `tester.pump()` cost. They are related but '
      'not the same clock: use the ratio as a regression signal, not as FPS.',
    )
    ..writeln()
    ..writeln('## Idle baseline');
  final idle = run.idle;
  if (idle == null) {
    buffer.writeln('Not measured.');
  } else {
    buffer
      ..writeln()
      ..writeln('| Engine | RSS tail | RSS peak | CPU tail | CPU peak |')
      ..writeln('|---|---:|---:|---:|---:|')
      ..writeln(
        '| NativaX | ${_r(idle.nativa.rssTailMb)} MB | '
        '${_r(idle.nativa.rssPeakMb)} MB | ${_pct(idle.nativa.cpuTailPct)} | '
        '${_pct(idle.nativa.cpuPeakPct)} |',
      )
      ..writeln(
        '| Chromium | ${_r(idle.chromium.rssTailMb)} MB | '
        '${_r(idle.chromium.rssPeakMb)} MB | ${_pct(idle.chromium.cpuTailPct)} | '
        '${_pct(idle.chromium.cpuPeakPct)} |',
      )
      ..writeln()
      ..writeln(
        '> The NativaX idle number is the **offscreen `flutter test` '
        'harness**, not the desktop app. It includes the test runner, the '
        'Flutter engine and the fonts. The 250 MB target is defined for the '
        'desktop app process; the harness number is an upper bound and its '
        'own comparison baseline.',
      );
  }
  final appIdleFile = File('${run.outDir}/app-idle.json');
  if (appIdleFile.existsSync()) {
    try {
      final app =
          jsonDecode(appIdleFile.readAsStringSync()) as Map<String, dynamic>;
      final rssOk = (app['rss_tail_mb'] as num? ?? 0) <= run.targets.idleRssMb;
      final cpuOk =
          (app['cpu_tail_pct'] as num? ?? 0) <= run.targets.idleCpuPct;
      buffer
        ..writeln()
        ..writeln('## App idle (desktop, blank page)')
        ..writeln()
        ..writeln(
          '| Status | RSS tail | RSS peak | CPU tail | CPU peak | GPU |',
        )
        ..writeln('|---|---:|---:|---:|---:|---:|')
        ..writeln(
          '| ${app['status']} | ${_r((app['rss_tail_mb'] as num? ?? 0).toDouble())} MB | '
          '${_r((app['rss_peak_mb'] as num? ?? 0).toDouble())} MB | '
          '${_r((app['cpu_tail_pct'] as num? ?? 0).toDouble())} % | '
          '${_r((app['cpu_peak_pct'] as num? ?? 0).toDouble())} % | '
          '${app['gpu_busy_pct'] == null ? 'not exposed' : '${_r((app['gpu_busy_pct'] as num).toDouble())} %'} |',
        )
        ..writeln()
        ..writeln(
          'Targets: RSS ≤ ${run.targets.idleRssMb} MB (${rssOk ? 'OK' : 'over'}), '
          'CPU ≤ ${run.targets.idleCpuPct} % (${cpuOk ? 'OK' : 'over'}). '
          'This is the real Flutter Linux app, not the offscreen harness.',
        );
    } catch (_) {}
  }
  buffer
    ..writeln()
    ..writeln('## Details');
  for (final result in run.results) {
    buffer
      ..writeln()
      ..writeln('### `${result.scenarioId}` — ${result.verdict.label}')
      ..writeln()
      ..writeln(result.title)
      ..writeln()
      ..writeln('Source: ${result.source}')
      ..writeln();
    if (result.reasons.isNotEmpty) {
      for (final reason in result.reasons) {
        buffer.writeln('- $reason');
      }
      buffer.writeln();
    }
    buffer
      ..writeln('| Metric | NativaX | Chromium |')
      ..writeln('|---|---:|---:|')
      ..writeln(
        '| Load (engine) | ${_r(result.nativa.loadMs)} ms | '
        '${_r(result.chromium.loadMs)} ms |',
      )
      ..writeln(
        '| Scenario | ${_r(result.nativa.scenarioMs)} ms | '
        '${_r(result.chromium.scenarioMs)} ms |',
      )
      ..writeln(
        '| Render/layout | ${_r(result.nativa.renderMs)} ms | '
        '${_r(result.chromium.renderMs)} ms |',
      )
      ..writeln('| Nodes | ${result.nativa.nodes} | ${result.chromium.nodes} |')
      ..writeln(
        '| Frame p95 | ${result.nativa.frameTimes.isEmpty ? '—' : '${_r(result.nativa.frameP95)} ms'} | '
        '${result.chromium.frameTimes.isEmpty ? '—' : '${_r(result.chromium.frameP95)} ms'} |',
      )
      ..writeln(
        '| Heap | ${result.nativa.heapMb == null ? '—' : '${_r(result.nativa.heapMb!)} MB'} | '
        '${result.chromium.heapMb == null ? '—' : '${_r(result.chromium.heapMb!)} MB'} |',
      )
      ..writeln(
        '| RSS peak | ${_r(result.nativa.rssPeakMb)} MB | '
        '${_r(result.chromium.rssPeakMb)} MB |',
      )
      ..writeln(
        '| CPU peak | ${_pct(result.nativa.cpuPeakPct)} | '
        '${_pct(result.chromium.cpuPeakPct)} |',
      )
      ..writeln();
    final read = result.nativa.extra['read'] ?? result.chromium.extra['read'];
    if (read != null) {
      buffer
        ..writeln('Page-reported result:')
        ..writeln()
        ..writeln('```json')
        ..writeln(const JsonEncoder.withIndent('  ').convert(read))
        ..writeln('```')
        ..writeln();
    }
  }
  if (run.notes.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Notes');
    for (final note in run.notes) {
      buffer.writeln('- $note');
    }
  }
  buffer
    ..writeln()
    ..writeln('## Limits')
    ..writeln()
    ..writeln(
      '- Offscreen frames are `tester.pump()` work: CPU build/layout/paint, '
      'not GPU rasterisation or display refresh.',
    )
    ..writeln(
      '- Chromium and NativaX block external network, matching the '
      'offline contract of the runtime.',
    )
    ..writeln(
      '- RSS/CPU are sampled from `/proc`; the NativaX harness includes '
      'the Flutter test runner.',
    )
    ..writeln(
      '- Heap is only reported by Chromium (`Performance.getMetrics`).',
    );
  return buffer.toString();
}

String _csv(PerfRun run) {
  final out = StringBuffer()
    ..writeln(
      'scenario,kind,verdict,nativa_work_ms,chromium_work_ms,ratio,'
      'nativa_nodes,chromium_nodes,nativa_frame_p95_ms,nativa_frame_max_ms,'
      'nativa_rss_peak_mb,nativa_cpu_peak_pct,chromium_rss_peak_mb,'
      'chromium_cpu_peak_pct,reasons',
    );
  for (final r in run.results) {
    out.writeln(
      [
        r.scenarioId,
        r.kind,
        r.verdict.label,
        _r(_work(r.nativa)),
        _r(_work(r.chromium)),
        _ratio(_work(r.nativa), _work(r.chromium)).toStringAsFixed(3),
        r.nativa.nodes,
        r.chromium.nodes,
        _r(r.nativa.frameP95),
        _r(r.nativa.frameMax),
        _r(r.nativa.rssPeakMb),
        _r(r.nativa.cpuPeakPct),
        _r(r.chromium.rssPeakMb),
        _r(r.chromium.cpuPeakPct),
        '"${r.reasons.join('; ').replaceAll('"', '""')}"',
      ].join(','),
    );
  }
  return out.toString();
}

String _timeline(PerfRun run) {
  final out = StringBuffer()
    ..writeln('scenario,engine,elapsed_ms,rss_mb,cpu_pct,processes');
  for (final result in run.results) {
    for (final sample in result.nativa.samples) {
      out.writeln(
        '${result.scenarioId},nativax,${sample.elapsedMs},'
        '${sample.rssMb.toStringAsFixed(2)},${sample.cpuPct.toStringAsFixed(2)},'
        '${sample.processes}',
      );
    }
    for (final sample in result.chromium.samples) {
      out.writeln(
        '${result.scenarioId},chromium,${sample.elapsedMs},'
        '${sample.rssMb.toStringAsFixed(2)},${sample.cpuPct.toStringAsFixed(2)},'
        '${sample.processes}',
      );
    }
  }
  return out.toString();
}

double _ratio(double a, double b) => b <= 0.0001 ? 0 : a / b;

String _bars({
  required String title,
  required List<({String label, double value, String color})> rows,
  double? target,
  String? targetLabel,
  required double maxValue,
}) {
  final width = 980;
  final rowHeight = 26;
  final top = 54;
  final height = top + rows.length * rowHeight + 40;
  final labelWidth = 300.0;
  final chartWidth = width - labelWidth - 140;
  final max = [
    maxValue,
    ...rows.map((r) => r.value),
    if (target != null) target,
  ].reduce((a, b) => a > b ? a : b);
  final buffer = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" '
      'viewBox="0 0 $width $height" font-family="sans-serif">',
    )
    ..writeln('<rect width="$width" height="$height" fill="#0d1117"/>')
    ..writeln(
      '<text x="16" y="30" fill="#e6edf3" font-size="18" font-weight="700">'
      '${_escape(title)}</text>',
    );
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final y = top + i * rowHeight;
    final barWidth = (row.value.clamp(0, max) / max) * chartWidth;
    buffer
      ..writeln(
        '<text x="16" y="${y + 16}" fill="#9fb3c8" font-size="12">'
        '${_escape(row.label)}</text>',
      )
      ..writeln(
        '<rect x="$labelWidth" y="${y + 4}" width="${chartWidth.toInt()}" '
        'height="16" fill="#161b22" rx="3"/>',
      )
      ..writeln(
        '<rect x="$labelWidth" y="${y + 4}" width="${barWidth.toStringAsFixed(1)}" '
        'height="16" fill="${row.color}" rx="3"/>',
      )
      ..writeln(
        '<text x="${labelWidth + chartWidth + 8}" y="${y + 16}" '
        'fill="#e6edf3" font-size="12">${row.value.toStringAsFixed(2)}</text>',
      );
  }
  if (target != null) {
    final x = labelWidth + (target.clamp(0, max) / max) * chartWidth;
    buffer
      ..writeln(
        '<line x1="${x.toStringAsFixed(1)}" y1="${top - 10}" '
        'x2="${x.toStringAsFixed(1)}" y2="${height - 30}" stroke="#f0b72f" '
        'stroke-width="2" stroke-dasharray="5,4"/>',
      )
      ..writeln(
        '<text x="${x.toStringAsFixed(1)}" y="${height - 12}" fill="#f0b72f" '
        'font-size="12" text-anchor="middle">${_escape(targetLabel ?? '')}</text>',
      );
  }
  buffer.writeln('</svg>');
  return buffer.toString();
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
