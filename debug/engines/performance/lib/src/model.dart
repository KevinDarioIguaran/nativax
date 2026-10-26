/// Data model for the performance suite.
library;

enum EngineKind { chromium, nativa }

extension EngineKindLabel on EngineKind {
  String get label => this == EngineKind.chromium ? 'chromium' : 'nativax';
}

enum RunStatus { ok, failed, skipped }

enum Verdict { pass, warn, fail, invalid }

extension VerdictLabel on Verdict {
  String get label => switch (this) {
    Verdict.pass => 'PASS',
    Verdict.warn => 'WARN',
    Verdict.fail => 'FAIL',
    Verdict.invalid => 'INVALID',
  };
}

class ProcSample {
  const ProcSample({
    required this.elapsedMs,
    required this.rssMb,
    required this.cpuPct,
    required this.processes,
  });

  final int elapsedMs;
  final double rssMb;
  final double cpuPct;
  final int processes;

  Map<String, Object> toJson() => {
    'elapsed_ms': elapsedMs,
    'rss_mb': _r(rssMb),
    'cpu_pct': _r(cpuPct),
    'processes': processes,
  };
}

class EngineRun {
  EngineRun({
    required this.engine,
    required this.status,
    this.error,
    this.scenarioMs = 0,
    this.loadMs = 0,
    this.evalMs = 0,
    this.renderMs = 0,
    this.frameTimes = const [],
    this.nodes = 0,
    this.nodesBefore = 0,
    this.scrollY = 0,
    this.documentHeight = 0,
    this.heapMb,
    this.layoutCount,
    this.styleCount,
    this.layoutMs,
    this.styleMs,
    this.scriptMs,
    this.nodeDelta,
    this.samples = const [],
    this.extra = const {},
  });

  final EngineKind engine;
  final RunStatus status;
  final String? error;

  /// Time spent inside the page workload (same JS in both engines).
  final double scenarioMs;

  /// Engine time from document start to a ready page, when measurable.
  final double loadMs;

  /// Wall time of the harness evaluating the JS (NativaX only).
  final double evalMs;

  /// Frame/style/layout work reported by the engine.
  final double renderMs;

  /// Per-step frame times. NativaX: 'tester.pump()' cost. Chromium: in-page
  /// scroll/layout time around each step.
  final List<double> frameTimes;
  final int nodes;
  final int nodesBefore;
  final int scrollY;
  final int documentHeight;
  final double? heapMb;
  final int? layoutCount;
  final int? styleCount;
  final double? layoutMs;
  final double? styleMs;
  final double? scriptMs;
  final int? nodeDelta;
  final List<ProcSample> samples;
  final Map<String, Object?> extra;

  bool get ok => status == RunStatus.ok;

  double get rssPeakMb => samples.isEmpty
      ? 0
      : samples.map((s) => s.rssMb).reduce((a, b) => a > b ? a : b);
  double get rssMedianMb => _median(samples.map((s) => s.rssMb).toList());
  double get cpuPeakPct => samples.isEmpty
      ? 0
      : samples.map((s) => s.cpuPct).reduce((a, b) => a > b ? a : b);
  double get cpuMedianPct => _median(samples.map((s) => s.cpuPct).toList());

  /// Median of the last three samples: the tail is the idle part of a run.
  double get rssTailMb => _tailMedian(
    samples.where((s) => s.rssMb > 0).map((s) => s.rssMb).toList(),
  );
  double get cpuTailPct => _tailMedian(
    samples.where((s) => s.rssMb > 0).map((s) => s.cpuPct).toList(),
  );

  double get frameP50 => _percentile(frameTimes, 50);
  double get frameP95 => _percentile(frameTimes, 95);
  double get frameMax =>
      frameTimes.isEmpty ? 0 : frameTimes.reduce((a, b) => a > b ? a : b);

  Map<String, Object?> toJson() => {
    'engine': engine.label,
    'status': status.name,
    if (error != null) 'error': error,
    'scenario_ms': _r(scenarioMs),
    'load_ms': _r(loadMs),
    'eval_ms': _r(evalMs),
    'render_ms': _r(renderMs),
    'frame_ms': {
      'p50': _r(frameP50),
      'p95': _r(frameP95),
      'max': _r(frameMax),
      if (frameTimes.isNotEmpty) 'samples': [for (final t in frameTimes) _r(t)],
    },
    'nodes': nodes,
    'nodes_before': nodesBefore,
    'node_delta': nodeDelta,
    'scroll_y': scrollY,
    'document_height': documentHeight,
    'heap_mb': heapMb == null ? null : _r(heapMb!),
    'layout_count': layoutCount,
    'style_count': styleCount,
    'layout_ms': layoutMs == null ? null : _r(layoutMs!),
    'style_ms': styleMs == null ? null : _r(styleMs!),
    'script_ms': scriptMs == null ? null : _r(scriptMs!),
    'rss_peak_mb': _r(rssPeakMb),
    'rss_median_mb': _r(rssMedianMb),
    'cpu_peak_pct': _r(cpuPeakPct),
    'cpu_median_pct': _r(cpuMedianPct),
    'rss_tail_mb': _r(rssTailMb),
    'cpu_tail_pct': _r(cpuTailPct),
    'samples': [for (final s in samples) s.toJson()],
    'extra': extra,
  };
}

class ScenarioResult {
  ScenarioResult({
    required this.scenarioId,
    required this.title,
    required this.kind,
    required this.source,
    required this.chromium,
    required this.nativa,
    required this.verdict,
    required this.reasons,
  });

  final String scenarioId;
  final String title;
  final String kind;
  final String source;
  final EngineRun chromium;
  final EngineRun nativa;
  final Verdict verdict;
  final List<String> reasons;

  Map<String, Object?> toJson() => {
    'scenario': scenarioId,
    'title': title,
    'kind': kind,
    'source': source,
    'verdict': verdict.label,
    'reasons': reasons,
    'chromium': chromium.toJson(),
    'nativax': nativa.toJson(),
    'comparison': comparison(),
  };

  Map<String, Object?> comparison() {
    double? ratio(double a, double b) => b <= 0 ? null : _r(a / b);
    return {
      'scenario_ratio': ratio(nativa.scenarioMs, chromium.scenarioMs),
      'render_ratio': ratio(nativa.renderMs, chromium.renderMs),
      'nodes_ratio': ratio(nativa.nodes.toDouble(), chromium.nodes.toDouble()),
      'frame_p95_ms': _r(nativa.frameP95),
      'frame_budget_ms': 16.7,
      'work_ratio': ratio(
        nativa.scenarioMs + nativa.renderMs,
        chromium.scenarioMs + chromium.renderMs,
      ),
    };
  }
}

class PerfTargets {
  const PerfTargets({
    this.frameP95Ms = 16.7,
    this.frameMaxMs = 100,
    this.workRatio = 3.0,
    this.nodesTolerance = 0.05,
    this.idleRssMb = 250,
    this.idleCpuPct = 1.0,
  });

  final double frameP95Ms;
  final double frameMaxMs;
  final double workRatio;
  final double nodesTolerance;
  final double idleRssMb;
  final double idleCpuPct;

  Map<String, Object> toJson() => {
    'frame_p95_ms': frameP95Ms,
    'frame_max_ms': frameMaxMs,
    'work_ratio': workRatio,
    'nodes_tolerance': nodesTolerance,
    'idle_rss_mb': idleRssMb,
    'idle_cpu_pct': idleCpuPct,
  };
}

class PerfRun {
  PerfRun({
    required this.startedAt,
    required this.duration,
    required this.command,
    required this.chromeVersion,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.outDir,
    required this.targets,
    required this.results,
    required this.idle,
    this.notes = const [],
  });

  final DateTime startedAt;
  final Duration duration;
  final String command;
  final String chromeVersion;
  final int viewportWidth;
  final int viewportHeight;
  final String outDir;
  final PerfTargets targets;
  final List<ScenarioResult> results;

  /// Idle baseline per engine (scenario `idle.blank`).
  final ScenarioResult? idle;
  final List<String> notes;

  int count(Verdict verdict) =>
      results.where((r) => r.verdict == verdict).length;

  Map<String, Object?> toJson() => {
    'tool': 'nativa_perf',
    'version': '0.1.0',
    'started_at': startedAt.toIso8601String(),
    'duration_seconds': _r(duration.inMilliseconds / 1000),
    'command': command,
    'chrome': chromeVersion,
    'viewport': {'width': viewportWidth, 'height': viewportHeight},
    'targets': targets.toJson(),
    'summary': {
      'scenarios': results.length,
      'pass': count(Verdict.pass),
      'warn': count(Verdict.warn),
      'fail': count(Verdict.fail),
      'invalid': count(Verdict.invalid),
    },
    'idle': idle?.toJson(),
    'results': [for (final r in results) r.toJson()],
    'notes': notes,
  };
}

double _percentile(List<double> values, int pct) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((pct / 100) * (sorted.length - 1)).round().clamp(
    0,
    sorted.length - 1,
  );
  return sorted[index];
}

double _tailMedian(List<double> values) {
  if (values.isEmpty) return 0;
  final tail = values.length <= 3 ? values : values.sublist(values.length - 3);
  return _median(tail);
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _r(double value) => value.isFinite ? (value * 1000).round() / 1000 : 0;
