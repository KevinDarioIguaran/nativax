import 'model.dart';
import 'scenarios.dart';

class _Check {
  _Check(this.name, this.ok, this.detail);
  final String name;
  final bool ok;
  final String detail;
}

ScenarioResult evaluateScenario(
  PerfScenario scenario,
  EngineRun chromium,
  EngineRun nativa,
  PerfTargets targets,
) {
  final reasons = <String>[];
  final checks = <_Check>[];

  if (!chromium.ok || !nativa.ok) {
    if (!chromium.ok)
      reasons.add('Chromium failed: ${chromium.error ?? 'unknown'}');
    if (!nativa.ok) reasons.add('NativaX failed: ${nativa.error ?? 'unknown'}');
    return ScenarioResult(
      scenarioId: scenario.id,
      title: scenario.title,
      kind: scenario.kind.name,
      source: scenario.source,
      chromium: chromium,
      nativa: nativa,
      verdict: Verdict.fail,
      reasons: reasons,
    );
  }

  if (scenario.kind == ScenarioKind.idle) {
    final rssOk = nativa.rssTailMb <= targets.idleRssMb;
    final cpuOk = nativa.cpuTailPct <= targets.idleCpuPct;
    checks.add(
      _Check(
        'idle-rss',
        rssOk,
        '${nativa.rssTailMb.toStringAsFixed(1)} MB tail vs ${targets.idleRssMb} MB target',
      ),
    );
    checks.add(
      _Check(
        'idle-cpu',
        cpuOk,
        '${nativa.cpuTailPct.toStringAsFixed(2)} % tail vs ${targets.idleCpuPct} % target',
      ),
    );
    for (final check in checks) {
      if (!check.ok) reasons.add('${check.name}: ${check.detail}');
    }
    final verdict = reasons.isEmpty ? Verdict.pass : Verdict.warn;
    return ScenarioResult(
      scenarioId: scenario.id,
      title: scenario.title,
      kind: scenario.kind.name,
      source: scenario.source,
      chromium: chromium,
      nativa: nativa,
      verdict: verdict,
      reasons: [
        ...reasons,
        'Offscreen harness baseline (includes flutter test + tester); '
            'not the desktop app process.',
      ],
    );
  }

  if (chromium.nodes > 0 && nativa.nodes > 0) {
    final relative = (nativa.nodes - chromium.nodes).abs() / chromium.nodes;
    checks.add(
      _Check(
        'nodes',
        relative <= targets.nodesTolerance,
        '${nativa.nodes} vs ${chromium.nodes} (${(relative * 100).toStringAsFixed(1)} % diff)',
      ),
    );
  }

  final chromeWork = chromium.scenarioMs + chromium.renderMs;
  final nativaWork = nativa.scenarioMs + nativa.renderMs;
  // Scroll cost in Chromium is compositor-driven and often sub-millisecond;
  // comparing it to a pump would produce a meaningless thousand-fold ratio.
  if (scenario.kind != ScenarioKind.scroll &&
      chromeWork > 0.05 &&
      nativaWork > 0.05) {
    final ratio = nativaWork / chromeWork;
    checks.add(
      _Check(
        'work-ratio',
        ratio <= targets.workRatio,
        '${ratio.toStringAsFixed(2)}x vs ${targets.workRatio}x target '
            '(${nativaWork.toStringAsFixed(1)} ms / ${chromeWork.toStringAsFixed(1)} ms)',
      ),
    );
  }

  final jank = nativa.frameMax;
  if (jank > 0) {
    checks.add(
      _Check(
        'no-long-frame',
        jank <= targets.frameMaxMs,
        '${jank.toStringAsFixed(1)} ms max vs ${targets.frameMaxMs} ms',
      ),
    );
  }
  if (scenario.kind == ScenarioKind.scroll && nativa.frameTimes.isNotEmpty) {
    checks.add(
      _Check(
        'frame-p95',
        nativa.frameP95 <= targets.frameP95Ms,
        '${nativa.frameP95.toStringAsFixed(1)} ms p95 vs ${targets.frameP95Ms} ms',
      ),
    );
  }

  for (final check in checks) {
    if (!check.ok) reasons.add('${check.name}: ${check.detail}');
  }
  final missed = checks.where((c) => !c.ok).length;
  final verdict = jank > targets.frameMaxMs
      ? Verdict.fail
      : missed == 0
      ? Verdict.pass
      : missed == 1
      ? Verdict.warn
      : Verdict.fail;
  return ScenarioResult(
    scenarioId: scenario.id,
    title: scenario.title,
    kind: scenario.kind.name,
    source: scenario.source,
    chromium: chromium,
    nativa: nativa,
    verdict: verdict,
    reasons: reasons,
  );
}
