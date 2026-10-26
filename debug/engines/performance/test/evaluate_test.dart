import 'package:nativa_perf/src/evaluate.dart';
import 'package:nativa_perf/src/model.dart';
import 'package:nativa_perf/src/scenarios.dart';
import 'package:test/test.dart';

EngineRun run({
  EngineKind engine = EngineKind.nativa,
  double scenarioMs = 10,
  double renderMs = 5,
  int nodes = 100,
  List<double> frames = const [5, 6, 7],
  double rss = 120,
  double cpu = 0.5,
}) => EngineRun(
  engine: engine,
  status: RunStatus.ok,
  scenarioMs: scenarioMs,
  renderMs: renderMs,
  nodes: nodes,
  frameTimes: frames,
  samples: [
    ProcSample(elapsedMs: 0, rssMb: rss, cpuPct: cpu, processes: 1),
    ProcSample(elapsedMs: 250, rssMb: rss, cpuPct: cpu, processes: 1),
    ProcSample(elapsedMs: 500, rssMb: rss, cpuPct: cpu, processes: 1),
  ],
);

const scenario = PerfScenario(
  id: 'test.scenario',
  title: 'Test',
  kind: ScenarioKind.dom,
  source: 'unit',
  description: 'unit test',
);

void main() {
  group('metrics', () {
    test('percentiles and frame max', () {
      final value = run(frames: [1, 2, 3, 4, 100]);
      expect(value.frameP50, 3);
      expect(value.frameP95, 100);
      expect(value.frameMax, 100);
    });

    test('tail ignores phantom zero samples', () {
      final value = EngineRun(
        engine: EngineKind.nativa,
        status: RunStatus.ok,
        samples: const [
          ProcSample(elapsedMs: 0, rssMb: 300, cpuPct: 50, processes: 3),
          ProcSample(elapsedMs: 100, rssMb: 280, cpuPct: 10, processes: 3),
          ProcSample(elapsedMs: 200, rssMb: 200, cpuPct: 2, processes: 3),
          ProcSample(elapsedMs: 300, rssMb: 0, cpuPct: 0, processes: 0),
        ],
      );
      expect(value.rssTailMb, 280);
      expect(value.cpuTailPct, 10);
    });
  });

  group('verdicts', () {
    test('equal engines pass', () {
      final result = evaluateScenario(
        scenario,
        run(engine: EngineKind.chromium),
        run(),
        const PerfTargets(),
      );
      expect(result.verdict, Verdict.pass);
    });

    test('a work ratio over the target warns', () {
      final result = evaluateScenario(
        scenario,
        run(engine: EngineKind.chromium, scenarioMs: 10, renderMs: 5),
        run(scenarioMs: 60, renderMs: 15),
        const PerfTargets(),
      );
      expect(result.verdict, Verdict.warn);
      expect(result.reasons.first, contains('work-ratio'));
    });

    test('a long frame fails even with equal work', () {
      final result = evaluateScenario(
        scenario,
        run(engine: EngineKind.chromium),
        run(frames: [140]),
        const PerfTargets(),
      );
      expect(result.verdict, Verdict.fail);
      expect(result.reasons.join(' '), contains('no-long-frame'));
    });

    test('scroll scenarios use frame p95 and ignore the compositor ratio', () {
      const scroll = PerfScenario(
        id: 'scroll.test',
        title: 'Scroll',
        kind: ScenarioKind.scroll,
        source: 'unit',
        description: 'unit',
      );
      final result = evaluateScenario(
        scroll,
        run(engine: EngineKind.chromium, scenarioMs: 0.1, renderMs: 0),
        run(scenarioMs: 200, renderMs: 0, frames: [20, 21, 22]),
        const PerfTargets(),
      );
      expect(result.verdict, Verdict.warn);
      expect(result.reasons.join(' '), contains('frame-p95'));
      expect(result.reasons.join(' '), isNot(contains('work-ratio')));
    });

    test('node mismatch is reported', () {
      final result = evaluateScenario(
        scenario,
        run(engine: EngineKind.chromium, nodes: 1000),
        run(nodes: 500),
        const PerfTargets(),
      );
      expect(result.reasons.join(' '), contains('nodes'));
    });

    test('a failed harness fails the scenario', () {
      final failed = EngineRun(
        engine: EngineKind.nativa,
        status: RunStatus.failed,
        error: 'boom',
      );
      final result = evaluateScenario(
        scenario,
        run(engine: EngineKind.chromium),
        failed,
        const PerfTargets(),
      );
      expect(result.verdict, Verdict.fail);
      expect(result.reasons.join(' '), contains('boom'));
    });

    test('idle over the memory target warns, never fails', () {
      const idle = PerfScenario(
        id: 'idle.test',
        title: 'Idle',
        kind: ScenarioKind.idle,
        source: 'unit',
        description: 'unit',
      );
      final result = evaluateScenario(
        idle,
        run(engine: EngineKind.chromium),
        run(rss: 400, cpu: 2),
        const PerfTargets(),
      );
      expect(result.verdict, Verdict.warn);
      expect(result.reasons.join(' '), contains('idle-rss'));
    });
  });
}
